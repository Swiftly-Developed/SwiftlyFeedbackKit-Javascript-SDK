import Fluent

struct CreatePushNotificationLog: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("push_notification_logs")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("device_token_id", .uuid, .references("device_tokens", "id", onDelete: .setNull))
            .field("notification_type", .string, .required)
            .field("status", .string, .required)
            .field("feedback_id", .uuid, .references("feedbacks", "id", onDelete: .setNull))
            .field("project_id", .uuid, .references("projects", "id", onDelete: .setNull))
            .field("payload", .json)
            .field("error_message", .string)
            .field("apns_id", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("push_notification_logs").delete()
    }
}
