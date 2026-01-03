import Fluent

struct CreateProject: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .id()
            .field("name", .string, .required)
            .field("api_key", .string, .required)
            .field("description", .string)
            .field("owner_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("is_archived", .bool, .required, .sql(.default(false)))
            .field("archived_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "api_key")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects").delete()
    }
}
