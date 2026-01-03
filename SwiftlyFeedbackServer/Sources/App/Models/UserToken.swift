import Fluent
import Vapor

final class UserToken: Model, Content, @unchecked Sendable {
    static let schema = "user_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "value")
    var value: String

    @Parent(key: "user_id")
    var user: User

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Field(key: "expires_at")
    var expiresAt: Date?

    init() {}

    init(id: UUID? = nil, value: String, userID: UUID) {
        self.id = id
        self.value = value
        self.$user.id = userID
        // Token expires in 30 days
        self.expiresAt = Date().addingTimeInterval(60 * 60 * 24 * 30)
    }
}

extension UserToken: ModelTokenAuthenticatable {
    static var valueKey: KeyPath<UserToken, Field<String>> {
        \UserToken.$value
    }
    static var userKey: KeyPath<UserToken, Parent<User>> {
        \UserToken.$user
    }

    var isValid: Bool {
        guard let expiresAt = expiresAt else { return true }
        return expiresAt > Date()
    }
}
