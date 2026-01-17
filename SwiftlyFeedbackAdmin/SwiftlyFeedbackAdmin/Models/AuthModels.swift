import Foundation

// MARK: - Auth Models
//
// All models are marked `nonisolated` to opt out of the project's default MainActor isolation.
// This allows their Codable conformances to be used from any actor context (e.g., AdminAPIClient).

nonisolated
struct User: Sendable, Identifiable {
    let id: UUID
    let email: String
    let name: String
    let isAdmin: Bool
    let isEmailVerified: Bool
    let notifyNewFeedback: Bool
    let notifyNewComments: Bool
    let pushNotificationsEnabled: Bool
    let pushNotifyNewFeedback: Bool
    let pushNotifyNewComments: Bool
    let pushNotifyVotes: Bool
    let pushNotifyStatusChanges: Bool
    let createdAt: Date?
}

extension User: Decodable {
    // Custom decoder to handle optional push notification fields with defaults
    // Note: AdminAPIClient uses .convertFromSnakeCase, so we don't need explicit CodingKeys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        name = try container.decode(String.self, forKey: .name)
        isAdmin = try container.decode(Bool.self, forKey: .isAdmin)
        isEmailVerified = try container.decode(Bool.self, forKey: .isEmailVerified)
        notifyNewFeedback = try container.decode(Bool.self, forKey: .notifyNewFeedback)
        notifyNewComments = try container.decode(Bool.self, forKey: .notifyNewComments)
        // Push notification fields with defaults for backward compatibility
        pushNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushNotificationsEnabled) ?? true
        pushNotifyNewFeedback = try container.decodeIfPresent(Bool.self, forKey: .pushNotifyNewFeedback) ?? true
        pushNotifyNewComments = try container.decodeIfPresent(Bool.self, forKey: .pushNotifyNewComments) ?? true
        pushNotifyVotes = try container.decodeIfPresent(Bool.self, forKey: .pushNotifyVotes) ?? true
        pushNotifyStatusChanges = try container.decodeIfPresent(Bool.self, forKey: .pushNotifyStatusChanges) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, email, name, isAdmin, isEmailVerified
        case notifyNewFeedback, notifyNewComments
        case pushNotificationsEnabled, pushNotifyNewFeedback, pushNotifyNewComments
        case pushNotifyVotes, pushNotifyStatusChanges
        case createdAt
    }
}

extension User: Encodable {}

nonisolated
struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated
struct SignupRequest: Encodable, Sendable {
    let email: String
    let name: String
    let password: String
}

nonisolated
struct AuthResponse: Decodable, Sendable {
    let token: String
    let user: User
}

nonisolated
struct ChangePasswordRequest: Encodable, Sendable {
    let currentPassword: String
    let newPassword: String
}

nonisolated
struct DeleteAccountRequest: Encodable, Sendable {
    let password: String
}

nonisolated
struct VerifyEmailRequest: Encodable, Sendable {
    let code: String
}

nonisolated
struct VerifyEmailResponse: Decodable, Sendable {
    let message: String
    let user: User
}

nonisolated
struct MessageResponse: Decodable, Sendable {
    let message: String
}

nonisolated
struct UpdateNotificationSettingsRequest: Encodable, Sendable {
    let notifyNewFeedback: Bool?
    let notifyNewComments: Bool?
    let pushNotificationsEnabled: Bool?
    let pushNotifyNewFeedback: Bool?
    let pushNotifyNewComments: Bool?
    let pushNotifyVotes: Bool?
    let pushNotifyStatusChanges: Bool?
}

nonisolated
struct ForgotPasswordRequest: Encodable, Sendable {
    let email: String
}

nonisolated
struct ResetPasswordRequest: Encodable, Sendable {
    let code: String
    let newPassword: String
}

nonisolated
struct OverrideSubscriptionTierRequest: Encodable, Sendable {
    let tier: String
}

nonisolated
struct SubscriptionInfoDTO: Decodable, Sendable {
    let tier: SubscriptionTier
    let status: String?
    let productId: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case tier, status
        case productId = "product_id"
        case expiresAt = "expires_at"
    }
}
