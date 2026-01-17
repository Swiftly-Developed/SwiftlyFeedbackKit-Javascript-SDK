import Fluent

struct AddFeedbackRejectionReason: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("feedbacks")
            .field("rejection_reason", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("feedbacks")
            .deleteField("rejection_reason")
            .update()
    }
}
