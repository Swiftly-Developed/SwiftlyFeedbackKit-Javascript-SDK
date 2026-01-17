import Fluent

struct AddProjectAirtableIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Airtable fields to projects table
        try await database.schema("projects")
            .field("airtable_token", .string)
            .field("airtable_base_id", .string)
            .field("airtable_base_name", .string)
            .field("airtable_table_id", .string)
            .field("airtable_table_name", .string)
            .field("airtable_sync_status", .bool, .required, .sql(.default(false)))
            .field("airtable_sync_comments", .bool, .required, .sql(.default(false)))
            .field("airtable_status_field_id", .string)
            .field("airtable_votes_field_id", .string)
            .field("airtable_title_field_id", .string)
            .field("airtable_description_field_id", .string)
            .field("airtable_category_field_id", .string)
            .field("airtable_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Add Airtable fields to feedbacks table
        try await database.schema("feedbacks")
            .field("airtable_record_url", .string)
            .field("airtable_record_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("airtable_token")
            .deleteField("airtable_base_id")
            .deleteField("airtable_base_name")
            .deleteField("airtable_table_id")
            .deleteField("airtable_table_name")
            .deleteField("airtable_sync_status")
            .deleteField("airtable_sync_comments")
            .deleteField("airtable_status_field_id")
            .deleteField("airtable_votes_field_id")
            .deleteField("airtable_title_field_id")
            .deleteField("airtable_description_field_id")
            .deleteField("airtable_category_field_id")
            .deleteField("airtable_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("airtable_record_url")
            .deleteField("airtable_record_id")
            .update()
    }
}
