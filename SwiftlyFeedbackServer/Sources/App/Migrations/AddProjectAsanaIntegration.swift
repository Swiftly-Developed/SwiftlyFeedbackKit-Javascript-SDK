import Fluent

struct AddProjectAsanaIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Asana fields to projects table
        try await database.schema("projects")
            .field("asana_token", .string)
            .field("asana_workspace_id", .string)
            .field("asana_workspace_name", .string)
            .field("asana_project_id", .string)
            .field("asana_project_name", .string)
            .field("asana_section_id", .string)
            .field("asana_section_name", .string)
            .field("asana_sync_status", .bool, .required, .sql(.default(false)))
            .field("asana_sync_comments", .bool, .required, .sql(.default(false)))
            .field("asana_status_field_id", .string)
            .field("asana_votes_field_id", .string)
            .field("asana_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Add Asana fields to feedbacks table
        try await database.schema("feedbacks")
            .field("asana_task_url", .string)
            .field("asana_task_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("asana_token")
            .deleteField("asana_workspace_id")
            .deleteField("asana_workspace_name")
            .deleteField("asana_project_id")
            .deleteField("asana_project_name")
            .deleteField("asana_section_id")
            .deleteField("asana_section_name")
            .deleteField("asana_sync_status")
            .deleteField("asana_sync_comments")
            .deleteField("asana_status_field_id")
            .deleteField("asana_votes_field_id")
            .deleteField("asana_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("asana_task_url")
            .deleteField("asana_task_id")
            .update()
    }
}
