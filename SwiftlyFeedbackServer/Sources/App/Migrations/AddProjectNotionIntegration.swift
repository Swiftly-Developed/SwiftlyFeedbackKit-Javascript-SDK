import Fluent

struct AddProjectNotionIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Notion fields to projects table
        try await database.schema("projects")
            .field("notion_token", .string)
            .field("notion_database_id", .string)
            .field("notion_database_name", .string)
            .field("notion_sync_status", .bool, .required, .sql(.default(false)))
            .field("notion_sync_comments", .bool, .required, .sql(.default(false)))
            .field("notion_status_property", .string)
            .field("notion_votes_property", .string)
            .update()

        // Add Notion fields to feedbacks table
        try await database.schema("feedbacks")
            .field("notion_page_url", .string)
            .field("notion_page_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("notion_token")
            .deleteField("notion_database_id")
            .deleteField("notion_database_name")
            .deleteField("notion_sync_status")
            .deleteField("notion_sync_comments")
            .deleteField("notion_status_property")
            .deleteField("notion_votes_property")
            .update()

        try await database.schema("feedbacks")
            .deleteField("notion_page_url")
            .deleteField("notion_page_id")
            .update()
    }
}
