import Fluent

struct CreateViewEvent: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("view_events")
            .id()
            .field("event_name", .string, .required)
            .field("user_id", .string, .required)
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("properties", .json)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("view_events").delete()
    }
}
