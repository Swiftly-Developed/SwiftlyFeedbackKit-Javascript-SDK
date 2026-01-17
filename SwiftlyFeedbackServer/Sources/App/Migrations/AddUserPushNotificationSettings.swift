import Fluent

struct AddUserPushNotificationSettings: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("push_notifications_enabled", .bool, .required, .sql(.default(true)))
            .field("push_notify_new_feedback", .bool, .required, .sql(.default(true)))
            .field("push_notify_new_comments", .bool, .required, .sql(.default(true)))
            .field("push_notify_votes", .bool, .required, .sql(.default(true)))
            .field("push_notify_status_changes", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("push_notifications_enabled")
            .deleteField("push_notify_new_feedback")
            .deleteField("push_notify_new_comments")
            .deleteField("push_notify_votes")
            .deleteField("push_notify_status_changes")
            .update()
    }
}
