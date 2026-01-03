import Fluent
import Vapor

final class EmailVerification: Model, Content, @unchecked Sendable {
    static let schema = "email_verifications"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token")
    var token: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "verified_at")
    var verifiedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userId: UUID,
        expiresInHours: Int = 24
    ) {
        self.id = id
        self.$user.id = userId
        self.token = Self.generateVerificationCode()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresInHours * 60 * 60))
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isVerified: Bool {
        verifiedAt != nil
    }

    /// Generates a user-friendly 8-character verification code (uppercase letters and numbers, no ambiguous chars)
    static func generateVerificationCode() -> String {
        // Exclude ambiguous characters: 0, O, I, 1, L
        let chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}
