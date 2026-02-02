import Fluent

struct CreateWebSession: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("web_sessions")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("session_token", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("user_agent", .string)
            .field("ip_address", .string)
            .field("created_at", .datetime)
            .field("last_accessed_at", .datetime)
            .unique(on: "session_token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("web_sessions").delete()
    }
}
