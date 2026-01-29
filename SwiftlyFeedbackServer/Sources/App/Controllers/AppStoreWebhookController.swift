import Vapor
import Fluent

struct AppStoreWebhookController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let webhooks = routes.grouped("webhooks")
        webhooks.post("appstore", use: handleWebhook)
    }

    /// POST /api/v1/webhooks/appstore
    /// Handles incoming App Store Server Notifications v2
    @Sendable
    func handleWebhook(req: Request) async throws -> HTTPStatus {
        // Decode the notification payload
        let payload: AppStoreNotificationPayload
        do {
            payload = try req.content.decode(AppStoreNotificationPayload.self)
        } catch {
            req.logger.error("App Store webhook: Failed to decode payload: \(error)")
            return .badRequest
        }

        let appStoreService = req.appStoreService

        // Verify and decode the notification
        let notification: DecodedAppStoreNotification
        do {
            notification = try await appStoreService.verifyNotification(payload.signedPayload)
        } catch {
            req.logger.error("App Store webhook: Failed to verify notification: \(error)")
            return .badRequest
        }

        req.logger.info("App Store webhook received: \(notification.notificationType) (subtype: \(notification.subtype ?? "none")) [env: \(AppEnvironment.shared.type.name)]")

        // Get transaction info if available
        guard let signedTransactionInfo = notification.data.signedTransactionInfo else {
            req.logger.warning("App Store webhook: No transaction info in notification")
            return .ok
        }

        // Decode the transaction
        let transaction: DecodedAppStoreTransaction
        do {
            transaction = try await appStoreService.verifyTransaction(signedTransactionInfo)
        } catch {
            req.logger.error("App Store webhook: Failed to decode transaction: \(error)")
            return .ok // Still acknowledge
        }

        // Find user by original transaction ID
        guard let user = try await User.query(on: req.db)
            .filter(\.$appleOriginalTransactionId == transaction.originalTransactionId)
            .first() else {
            req.logger.warning("App Store webhook: No user found for transaction \(transaction.originalTransactionId)")
            // This might happen if the user hasn't synced their first purchase yet
            // Store the event for later processing or just acknowledge it
            return .ok
        }

        // Process the notification
        do {
            try await processNotification(
                notification: notification,
                transaction: transaction,
                user: user,
                appStoreService: appStoreService,
                req: req
            )
        } catch {
            req.logger.error("App Store webhook: Error processing notification: \(error)")
        }

        return .ok
    }

    // MARK: - Notification Processing

    private func processNotification(
        notification: DecodedAppStoreNotification,
        transaction: DecodedAppStoreTransaction,
        user: User,
        appStoreService: AppStoreService,
        req: Request
    ) async throws {
        switch notification.notificationType {
        case "SUBSCRIBED", "DID_RENEW":
            // New subscription or renewal
            user.subscriptionTier = appStoreService.tierFromProductId(transaction.productId)
            user.subscriptionStatus = .active
            user.subscriptionProductId = transaction.productId
            user.subscriptionExpiresAt = transaction.expiresDate
            user.subscriptionUpdatedAt = Date()

            req.logger.info("App Store subscription active for user \(user.id?.uuidString ?? "unknown"): tier=\(user.subscriptionTier.rawValue)")

        case "EXPIRED", "GRACE_PERIOD_EXPIRED":
            // Subscription expired
            user.subscriptionTier = .free
            user.subscriptionStatus = .expired
            user.subscriptionUpdatedAt = Date()

            req.logger.info("App Store subscription expired for user \(user.id?.uuidString ?? "unknown"): downgraded to free")

        case "DID_CHANGE_RENEWAL_STATUS":
            // User turned auto-renew on or off
            if notification.subtype == "AUTO_RENEW_DISABLED" {
                // User cancelled but still has access until expiration
                user.subscriptionStatus = .cancelled
                req.logger.info("App Store subscription cancelled for user \(user.id?.uuidString ?? "unknown"): will expire at \(user.subscriptionExpiresAt?.description ?? "unknown")")
            } else if notification.subtype == "AUTO_RENEW_ENABLED" {
                // User re-enabled auto-renew
                user.subscriptionStatus = .active
                req.logger.info("App Store subscription reactivated for user \(user.id?.uuidString ?? "unknown")")
            }
            user.subscriptionUpdatedAt = Date()

        case "DID_FAIL_TO_RENEW":
            // Payment failed, enter grace period
            user.subscriptionStatus = .gracePeriod
            user.subscriptionUpdatedAt = Date()

            req.logger.info("App Store renewal failed for user \(user.id?.uuidString ?? "unknown"): entering grace period")

        case "REFUND":
            // User got a refund
            user.subscriptionTier = .free
            user.subscriptionStatus = .expired
            user.subscriptionUpdatedAt = Date()

            req.logger.info("App Store refund for user \(user.id?.uuidString ?? "unknown"): downgraded to free")

        case "DID_CHANGE_RENEWAL_INFO":
            // Upgrade or downgrade scheduled
            // The actual change happens on renewal, so just log for now
            req.logger.info("App Store renewal info changed for user \(user.id?.uuidString ?? "unknown")")

        case "OFFER_REDEEMED":
            // Promotional offer redeemed
            user.subscriptionTier = appStoreService.tierFromProductId(transaction.productId)
            user.subscriptionStatus = .active
            user.subscriptionProductId = transaction.productId
            user.subscriptionExpiresAt = transaction.expiresDate
            user.subscriptionUpdatedAt = Date()

            req.logger.info("App Store offer redeemed for user \(user.id?.uuidString ?? "unknown"): tier=\(user.subscriptionTier.rawValue)")

        default:
            req.logger.debug("App Store webhook: Unhandled notification type: \(notification.notificationType)")
            return
        }

        try await user.save(on: req.db)
    }
}
