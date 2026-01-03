import Fluent

struct CreateVote: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("votes")
            .id()
            .field("user_id", .string, .required)
            .field("feedback_id", .uuid, .required, .references("feedbacks", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "user_id", "feedback_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("votes").delete()
    }
}
