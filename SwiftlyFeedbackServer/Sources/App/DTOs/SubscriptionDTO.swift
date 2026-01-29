import Vapor

// MARK: - Subscription Info Response

struct SubscriptionInfoDTO: Content {
    let tier: SubscriptionTier
    let status: SubscriptionStatus?
    let productId: String?
    let expiresAt: Date?
    let source: SubscriptionSource?
    let limits: SubscriptionLimitsDTO
    // Note: No CodingKeys needed - global encoder/decoder uses snake_case conversion
}

struct SubscriptionLimitsDTO: Content {
    let maxProjects: Int?
    let maxFeedbackPerProject: Int?
    let currentProjectCount: Int
    let canCreateProject: Bool
    // Note: No CodingKeys needed - global encoder/decoder uses snake_case conversion
}

// MARK: - Payment Required Error Response

struct PaymentRequiredDTO: Content {
    let reason: String
    let currentTier: SubscriptionTier
    let requiredTier: SubscriptionTier
    let limit: Int?
    let current: Int?
    // Note: No CodingKeys needed - global encoder/decoder uses snake_case conversion
}

// MARK: - Apple Transaction Sync Request

struct SyncAppleTransactionDTO: Content {
    /// Original transaction ID from StoreKit 2
    let originalTransactionId: String
    /// Product ID of the purchased subscription
    let productId: String
    // Note: No CodingKeys needed - global decoder uses convertFromSnakeCase
}

// MARK: - Stripe Checkout Request/Response

struct CreateCheckoutSessionDTO: Content {
    let priceId: String
    let successUrl: String?
    let cancelUrl: String?
    // Note: No CodingKeys needed - global decoder uses convertFromSnakeCase
}

struct CheckoutSessionResponseDTO: Content {
    let checkoutUrl: String
    // Note: No CodingKeys needed - global encoder uses convertToSnakeCase
}

// MARK: - Stripe Portal Request/Response

struct CreatePortalSessionDTO: Content {
    let returnUrl: String?
    // Note: No CodingKeys needed - global decoder uses convertFromSnakeCase
}

struct PortalSessionResponseDTO: Content {
    let portalUrl: String
    // Note: No CodingKeys needed - global encoder uses convertToSnakeCase
}

// MARK: - Override Tier Request (Dev/Testing only)

struct OverrideSubscriptionTierDTO: Content {
    let tier: SubscriptionTier
}

// MARK: - App Store Server Notification Payload

struct AppStoreNotificationPayload: Content {
    let signedPayload: String
    // Note: Apple uses camelCase, but signedPayload matches so no issue
}

// MARK: - Decoded App Store Transaction (from JWS)
// Note: Apple's JWS payloads use camelCase, which matches Swift naming

struct DecodedAppStoreTransaction: Content, Sendable {
    let originalTransactionId: String
    let productId: String
    let expiresDate: Date?
    let purchaseDate: Date?
}

// MARK: - App Store Server Notification (decoded)
// Note: Apple's notification payloads use camelCase

struct DecodedAppStoreNotification: Content, Sendable {
    let notificationType: String
    let subtype: String?
    let notificationUUID: String
    let data: AppStoreNotificationData

    struct AppStoreNotificationData: Content, Sendable {
        let bundleId: String
        let environment: String
        let signedTransactionInfo: String?
        let signedRenewalInfo: String?
    }
}
