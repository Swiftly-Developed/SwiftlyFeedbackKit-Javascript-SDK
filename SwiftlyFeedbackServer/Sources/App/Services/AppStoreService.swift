import Vapor
import Foundation

/// Service for verifying App Store transactions and notifications
final class AppStoreService: Sendable {

    // Product ID to tier mapping (must match App Store Connect)
    private let productToTier: [String: SubscriptionTier] = [
        // Monthly
        "swiftlyfeedback.pro.monthly": .pro,
        "swiftlyfeedback.team.monthly": .team,
        // Yearly
        "swiftlyfeedback.pro.yearly": .pro,
        "swiftlyfeedback.team.yearly": .team,
    ]

    init() {}

    // MARK: - Transaction Verification

    /// Verify a StoreKit 2 transaction JWS and extract transaction info
    /// In production, you should verify the JWS signature using Apple's public keys
    func verifyTransaction(_ signedTransaction: String) async throws -> DecodedAppStoreTransaction {
        // StoreKit 2 transactions are JWS (JSON Web Signature) tokens
        // Format: header.payload.signature (base64url encoded)

        let parts = signedTransaction.split(separator: ".")
        guard parts.count == 3 else {
            throw Abort(.badRequest, reason: "Invalid transaction format")
        }

        // Decode the payload (middle part)
        let payloadPart = String(parts[1])

        // Convert base64url to base64
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let payloadData = Data(base64Encoded: base64) else {
            throw Abort(.badRequest, reason: "Failed to decode transaction payload")
        }

        // Parse the JSON payload
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let payload = try decoder.decode(AppStoreTransactionPayload.self, from: payloadData)

        // Convert milliseconds to Date
        let expiresDate = payload.expiresDate.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        let purchaseDate = payload.purchaseDate.map { Date(timeIntervalSince1970: Double($0) / 1000) }

        return DecodedAppStoreTransaction(
            originalTransactionId: payload.originalTransactionId,
            productId: payload.productId,
            expiresDate: expiresDate,
            purchaseDate: purchaseDate
        )
    }

    // MARK: - Server Notification Verification

    /// Verify and decode an App Store Server Notification v2
    func verifyNotification(_ signedPayload: String) async throws -> DecodedAppStoreNotification {
        // App Store Server Notifications v2 are also JWS tokens
        let parts = signedPayload.split(separator: ".")
        guard parts.count == 3 else {
            throw Abort(.badRequest, reason: "Invalid notification format")
        }

        // Decode the payload
        let payloadPart = String(parts[1])

        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let payloadData = Data(base64Encoded: base64) else {
            throw Abort(.badRequest, reason: "Failed to decode notification payload")
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(AppStoreNotificationJWSPayload.self, from: payloadData)

        return DecodedAppStoreNotification(
            notificationType: payload.notificationType,
            subtype: payload.subtype,
            notificationUUID: payload.notificationUUID,
            data: DecodedAppStoreNotification.AppStoreNotificationData(
                bundleId: payload.data.bundleId,
                environment: payload.data.environment,
                signedTransactionInfo: payload.data.signedTransactionInfo,
                signedRenewalInfo: payload.data.signedRenewalInfo
            )
        )
    }

    // MARK: - Tier Mapping

    /// Map an App Store product ID to a subscription tier
    func tierFromProductId(_ productId: String) -> SubscriptionTier {
        // Check exact match first
        if let tier = productToTier[productId] {
            return tier
        }

        // Fallback to string matching
        let lowercased = productId.lowercased()
        if lowercased.contains("team") {
            return .team
        } else if lowercased.contains("pro") {
            return .pro
        }

        return .free
    }

    /// Map notification type to subscription status
    func statusFromNotificationType(_ type: String, subtype: String?) -> SubscriptionStatus? {
        switch type {
        case "SUBSCRIBED", "DID_RENEW":
            return .active
        case "EXPIRED", "GRACE_PERIOD_EXPIRED":
            return .expired
        case "DID_CHANGE_RENEWAL_STATUS":
            // Check subtype to determine if auto-renew was turned off
            if subtype == "AUTO_RENEW_DISABLED" {
                return .cancelled
            }
            return .active
        case "DID_FAIL_TO_RENEW":
            return .gracePeriod
        case "REFUND":
            return .expired
        default:
            return nil
        }
    }
}

// MARK: - Internal Payload Types

/// Internal payload structure for App Store transaction JWS
private struct AppStoreTransactionPayload: Codable {
    let originalTransactionId: String
    let productId: String
    let expiresDate: Int64?
    let purchaseDate: Int64?

    enum CodingKeys: String, CodingKey {
        case originalTransactionId = "originalTransactionId"
        case productId = "productId"
        case expiresDate = "expiresDate"
        case purchaseDate = "purchaseDate"
    }
}

/// Internal payload structure for App Store Server Notification JWS
private struct AppStoreNotificationJWSPayload: Codable {
    let notificationType: String
    let subtype: String?
    let notificationUUID: String
    let data: NotificationData

    struct NotificationData: Codable {
        let bundleId: String
        let environment: String
        let signedTransactionInfo: String?
        let signedRenewalInfo: String?
    }
}

// MARK: - Request Extension

extension Request {
    var appStoreService: AppStoreService {
        return AppStoreService()
    }
}
