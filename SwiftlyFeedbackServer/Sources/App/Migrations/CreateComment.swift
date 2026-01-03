import Fluent

struct CreateComment: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("comments")
            .id()
            .field("content", .string, .required)
            .field("user_id", .string, .required)
            .field("is_admin", .bool, .required, .sql(.default(false)))
            .field("feedback_id", .uuid, .required, .references("feedbacks", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("comments").delete()
    }
}
