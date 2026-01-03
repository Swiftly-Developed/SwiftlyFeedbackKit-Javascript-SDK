import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "name")
    var name: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "is_admin")
    var isAdmin: Bool

    @Field(key: "is_email_verified")
    var isEmailVerified: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$owner)
    var ownedProjects: [Project]

    @Siblings(through: ProjectMember.self, from: \.$user, to: \.$project)
    var memberProjects: [Project]

    init() {}

    init(id: UUID? = nil, email: String, name: String, passwordHash: String, isAdmin: Bool = false, isEmailVerified: Bool = false) {
        self.id = id
        self.email = email
        self.name = name
        self.passwordHash = passwordHash
        self.isAdmin = isAdmin
        self.isEmailVerified = isEmailVerified
    }
}

extension User: ModelAuthenticatable {
    static var usernameKey: KeyPath<User, Field<String>> {
        \User.$email
    }
    static var passwordHashKey: KeyPath<User, Field<String>> {
        \User.$passwordHash
    }

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}

extension User {
    func generateToken() throws -> UserToken {
        try UserToken(
            value: [UInt8].random(count: 32).base64,
            userID: self.requireID()
        )
    }
}

extension User {
    struct Public: Content {
        let id: UUID
        let email: String
        let name: String
        let isAdmin: Bool
        let isEmailVerified: Bool
        let createdAt: Date?
    }

    func asPublic() throws -> Public {
        Public(
            id: try requireID(),
            email: email,
            name: name,
            isAdmin: isAdmin,
            isEmailVerified: isEmailVerified,
            createdAt: createdAt
        )
    }
}
