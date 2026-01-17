import Fluent

struct AddProjectBasecampIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Basecamp fields to projects table
        try await database.schema("projects")
            .field("basecamp_access_token", .string)
            .field("basecamp_account_id", .string)
            .field("basecamp_account_name", .string)
            .field("basecamp_project_id", .string)
            .field("basecamp_project_name", .string)
            .field("basecamp_todoset_id", .string)
            .field("basecamp_todolist_id", .string)
            .field("basecamp_todolist_name", .string)
            .field("basecamp_sync_status", .bool, .required, .sql(.default(false)))
            .field("basecamp_sync_comments", .bool, .required, .sql(.default(false)))
            .field("basecamp_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Add Basecamp fields to feedbacks table
        try await database.schema("feedbacks")
            .field("basecamp_todo_url", .string)
            .field("basecamp_todo_id", .string)
            .field("basecamp_bucket_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("basecamp_access_token")
            .deleteField("basecamp_account_id")
            .deleteField("basecamp_account_name")
            .deleteField("basecamp_project_id")
            .deleteField("basecamp_project_name")
            .deleteField("basecamp_todoset_id")
            .deleteField("basecamp_todolist_id")
            .deleteField("basecamp_todolist_name")
            .deleteField("basecamp_sync_status")
            .deleteField("basecamp_sync_comments")
            .deleteField("basecamp_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("basecamp_todo_url")
            .deleteField("basecamp_todo_id")
            .deleteField("basecamp_bucket_id")
            .update()
    }
}
