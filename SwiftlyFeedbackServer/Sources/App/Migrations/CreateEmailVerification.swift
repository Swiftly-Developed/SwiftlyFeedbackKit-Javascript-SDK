import Fluent

struct CreateEmailVerification: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("email_verifications")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("verified_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("email_verifications").delete()
    }
}
