import Fluent

struct AddProjectSlackWebhook: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .field("slack_webhook_url", .string)
            .field("slack_notify_new_feedback", .bool, .required, .sql(.default(true)))
            .field("slack_notify_new_comments", .bool, .required, .sql(.default(true)))
            .field("slack_notify_status_changes", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("slack_webhook_url")
            .deleteField("slack_notify_new_feedback")
            .deleteField("slack_notify_new_comments")
            .deleteField("slack_notify_status_changes")
            .update()
    }
}
