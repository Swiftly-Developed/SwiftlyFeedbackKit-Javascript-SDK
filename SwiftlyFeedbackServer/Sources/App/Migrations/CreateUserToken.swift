import Fluent

struct CreateUserToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_tokens")
            .id()
            .field("value", .string, .required)
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .field("expires_at", .datetime)
            .unique(on: "value")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_tokens").delete()
    }
}
