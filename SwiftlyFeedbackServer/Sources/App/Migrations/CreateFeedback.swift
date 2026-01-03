import Fluent

struct CreateFeedback: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("feedbacks")
            .id()
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("status", .string, .required, .sql(.default("pending")))
            .field("category", .string, .required)
            .field("user_id", .string, .required)
            .field("user_email", .string)
            .field("vote_count", .int, .required, .sql(.default(0)))
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("feedbacks").delete()
    }
}
