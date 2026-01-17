import Fluent

struct CreateProjectMemberPreference: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("project_member_preferences")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            // Push notification overrides (null = use personal preference)
            .field("push_notify_new_feedback", .bool)
            .field("push_notify_new_comments", .bool)
            .field("push_notify_votes", .bool)
            .field("push_notify_status_changes", .bool)
            .field("push_muted", .bool, .required, .sql(.default(false)))
            // Email notification overrides (future expansion)
            .field("email_notify_new_feedback", .bool)
            .field("email_notify_new_comments", .bool)
            .field("email_muted", .bool, .required, .sql(.default(false)))
            // Timestamps
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // Unique constraint
            .unique(on: "user_id", "project_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("project_member_preferences").delete()
    }
}
