import Fluent

struct AddProjectMondayIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Monday.com fields to projects table
        try await database.schema("projects")
            .field("monday_token", .string)
            .field("monday_board_id", .string)
            .field("monday_board_name", .string)
            .field("monday_group_id", .string)
            .field("monday_group_name", .string)
            .field("monday_sync_status", .bool, .required, .sql(.default(false)))
            .field("monday_sync_comments", .bool, .required, .sql(.default(false)))
            .field("monday_status_column_id", .string)
            .field("monday_votes_column_id", .string)
            .update()

        // Add Monday.com fields to feedbacks table
        try await database.schema("feedbacks")
            .field("monday_item_url", .string)
            .field("monday_item_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("monday_token")
            .deleteField("monday_board_id")
            .deleteField("monday_board_name")
            .deleteField("monday_group_id")
            .deleteField("monday_group_name")
            .deleteField("monday_sync_status")
            .deleteField("monday_sync_comments")
            .deleteField("monday_status_column_id")
            .deleteField("monday_votes_column_id")
            .update()

        try await database.schema("feedbacks")
            .deleteField("monday_item_url")
            .deleteField("monday_item_id")
            .update()
    }
}
