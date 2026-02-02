import Fluent
import Vapor

final class WebSession: Model, Content, @unchecked Sendable {
    static let schema = "web_sessions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "session_token")
    var sessionToken: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "user_agent")
    var userAgent: String?

    @Field(key: "ip_address")
    var ipAddress: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "last_accessed_at", on: .update)
    var lastAccessedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        sessionToken: String,
        expiresAt: Date,
        userAgent: String? = nil,
        ipAddress: String? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.sessionToken = sessionToken
        self.expiresAt = expiresAt
        self.userAgent = userAgent
        self.ipAddress = ipAddress
    }

    var isExpired: Bool {
        expiresAt < Date()
    }
}

extension WebSession {
    static func generate(for user: User, expiresIn: TimeInterval = 60 * 60 * 24 * 30) throws -> WebSession {
        let token = [UInt8].random(count: 32).base64
        return WebSession(
            userID: try user.requireID(),
            sessionToken: token,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }
}
