import Vapor
import Fluent

struct StripeWebhookController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let webhooks = routes.grouped("webhooks")
        webhooks.post("stripe", use: handleWebhook)
    }

    /// POST /api/v1/webhooks/stripe
    /// Handles incoming Stripe webhook events
    @Sendable
    func handleWebhook(req: Request) async throws -> HTTPStatus {
        // Get raw body for signature verification
        guard let rawBody = req.body.data else {
            req.logger.error("Stripe webhook: No body data")
            return .badRequest
        }

        // Get signature header
        guard let signature = req.headers.first(name: "Stripe-Signature") else {
            req.logger.error("Stripe webhook: Missing Stripe-Signature header")
            return .badRequest
        }

        let stripeService = req.stripeService
        let payload = Data(buffer: rawBody)

        // Verify signature
        do {
            try stripeService.verifyWebhookSignature(payload: payload, signature: signature)
        } catch {
            req.logger.error("Stripe webhook: Signature verification failed: \(error)")
            return .badRequest
        }

        // Parse event
        let event: StripeWebhookEvent
        do {
            event = try stripeService.parseWebhookEvent(from: payload)
        } catch {
            req.logger.error("Stripe webhook: Failed to parse event: \(error)")
            return .badRequest
        }

        req.logger.info("Stripe webhook received: \(event.type) [env: \(AppEnvironment.shared.type.name)]")

        // Handle the event
        do {
            switch event.type {
            case "checkout.session.completed":
                try await handleCheckoutCompleted(event: event, req: req)

            case "customer.subscription.updated":
                try await handleSubscriptionUpdated(event: event, req: req)

            case "customer.subscription.deleted":
                try await handleSubscriptionDeleted(event: event, req: req)

            case "invoice.payment_failed":
                try await handlePaymentFailed(event: event, req: req)

            default:
                req.logger.debug("Stripe webhook: Unhandled event type: \(event.type)")
            }
        } catch {
            req.logger.error("Stripe webhook: Error processing event: \(error)")
            // Still return 200 to acknowledge receipt
        }

        return .ok
    }

    // MARK: - Event Handlers

    /// Handle checkout.session.completed - User completed checkout
    private func handleCheckoutCompleted(event: StripeWebhookEvent, req: Request) async throws {
        let object = event.data.object

        // Get user ID from metadata
        guard let userIdString = object.metadata?["user_id"],
              let userId = UUID(uuidString: userIdString) else {
            req.logger.error("Stripe webhook: Missing user_id in checkout session metadata")
            return
        }

        // Find user
        guard let user = try await User.find(userId, on: req.db) else {
            req.logger.error("Stripe webhook: User not found: \(userId)")
            return
        }

        // Get subscription details
        guard let subscriptionId = object.subscription else {
            req.logger.error("Stripe webhook: No subscription in checkout session")
            return
        }

        let stripeService = req.stripeService
        let subscription = try await stripeService.getSubscription(subscriptionId: subscriptionId)

        // Update user
        user.stripeCustomerId = object.customer
        user.stripeSubscriptionId = subscriptionId

        // Get price ID from subscription items
        if let priceId = subscription.items?.data?.first?.price?.id {
            user.subscriptionTier = stripeService.tierFromPriceId(priceId)
            user.subscriptionProductId = priceId
        }

        user.subscriptionStatus = stripeService.subscriptionStatus(from: subscription.status)
        user.subscriptionExpiresAt = subscription.currentPeriodEnd
        user.subscriptionSource = .stripe
        user.subscriptionUpdatedAt = Date()

        try await user.save(on: req.db)

        req.logger.info("Stripe checkout completed for user \(userId): tier=\(user.subscriptionTier.rawValue)")
    }

    /// Handle customer.subscription.updated - Subscription changed (upgrade, downgrade, renewal)
    private func handleSubscriptionUpdated(event: StripeWebhookEvent, req: Request) async throws {
        let object = event.data.object

        // Find user by Stripe customer ID
        guard let customerId = object.customer,
              let user = try await User.query(on: req.db)
                .filter(\.$stripeCustomerId == customerId)
                .first() else {
            req.logger.warning("Stripe webhook: No user found for customer \(object.customer ?? "unknown")")
            return
        }

        let stripeService = req.stripeService

        // Update subscription details
        user.stripeSubscriptionId = object.id

        if let priceId = object.items?.data?.first?.price?.id {
            user.subscriptionTier = stripeService.tierFromPriceId(priceId)
            user.subscriptionProductId = priceId
        }

        if let status = object.status {
            user.subscriptionStatus = stripeService.subscriptionStatus(from: status)
        }

        user.subscriptionExpiresAt = object.currentPeriodEnd
        user.subscriptionUpdatedAt = Date()

        try await user.save(on: req.db)

        req.logger.info("Stripe subscription updated for user \(user.id?.uuidString ?? "unknown"): tier=\(user.subscriptionTier.rawValue), status=\(user.subscriptionStatus?.rawValue ?? "nil")")
    }

    /// Handle customer.subscription.deleted - Subscription cancelled and expired
    private func handleSubscriptionDeleted(event: StripeWebhookEvent, req: Request) async throws {
        let object = event.data.object

        guard let subscriptionId = object.id else {
            req.logger.error("Stripe webhook: No subscription ID in deleted event")
            return
        }

        // Find user by Stripe subscription ID
        guard let user = try await User.query(on: req.db)
            .filter(\.$stripeSubscriptionId == subscriptionId)
            .first() else {
            req.logger.warning("Stripe webhook: No user found for subscription \(subscriptionId)")
            return
        }

        // Downgrade to free tier
        user.subscriptionTier = .free
        user.subscriptionStatus = .expired
        user.stripeSubscriptionId = nil
        user.subscriptionUpdatedAt = Date()

        try await user.save(on: req.db)

        req.logger.info("Stripe subscription deleted for user \(user.id?.uuidString ?? "unknown"): downgraded to free")
    }

    /// Handle invoice.payment_failed - Payment failed
    private func handlePaymentFailed(event: StripeWebhookEvent, req: Request) async throws {
        let object = event.data.object

        // Find user by Stripe customer ID
        guard let customerId = object.customer,
              let user = try await User.query(on: req.db)
                .filter(\.$stripeCustomerId == customerId)
                .first() else {
            req.logger.warning("Stripe webhook: No user found for customer \(object.customer ?? "unknown")")
            return
        }

        // Set grace period status
        user.subscriptionStatus = .gracePeriod
        user.subscriptionUpdatedAt = Date()

        try await user.save(on: req.db)

        req.logger.info("Stripe payment failed for user \(user.id?.uuidString ?? "unknown"): set to grace period")
    }
}
