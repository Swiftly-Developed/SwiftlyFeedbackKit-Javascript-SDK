import Fluent

struct AddVoteEmailNotification: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("votes")
            .field("email", .string)
            .field("notify_status_change", .bool, .required, .sql(.default(false)))
            .field("permission_key", .uuid)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("votes")
            .deleteField("email")
            .deleteField("notify_status_change")
            .deleteField("permission_key")
            .update()
    }
}
