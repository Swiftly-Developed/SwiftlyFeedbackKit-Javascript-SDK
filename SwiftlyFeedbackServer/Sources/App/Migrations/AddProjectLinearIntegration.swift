import Fluent

struct AddProjectLinearIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Linear fields to projects table
        try await database.schema("projects")
            .field("linear_token", .string)
            .field("linear_team_id", .string)
            .field("linear_team_name", .string)
            .field("linear_project_id", .string)
            .field("linear_project_name", .string)
            .field("linear_default_label_ids", .array(of: .string))
            .field("linear_sync_status", .bool, .required, .sql(.default(false)))
            .field("linear_sync_comments", .bool, .required, .sql(.default(false)))
            .update()

        // Add Linear fields to feedbacks table
        try await database.schema("feedbacks")
            .field("linear_issue_url", .string)
            .field("linear_issue_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("linear_token")
            .deleteField("linear_team_id")
            .deleteField("linear_team_name")
            .deleteField("linear_project_id")
            .deleteField("linear_project_name")
            .deleteField("linear_default_label_ids")
            .deleteField("linear_sync_status")
            .deleteField("linear_sync_comments")
            .update()

        try await database.schema("feedbacks")
            .deleteField("linear_issue_url")
            .deleteField("linear_issue_id")
            .update()
    }
}
