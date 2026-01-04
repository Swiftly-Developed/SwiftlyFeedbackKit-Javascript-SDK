import Fluent

struct AddProjectGitHubIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add GitHub fields to projects table
        try await database.schema("projects")
            .field("github_owner", .string)
            .field("github_repo", .string)
            .field("github_token", .string)
            .field("github_default_labels", .array(of: .string))
            .field("github_sync_status", .bool, .required, .sql(.default(false)))
            .update()

        // Add GitHub fields to feedbacks table
        try await database.schema("feedbacks")
            .field("github_issue_url", .string)
            .field("github_issue_number", .int)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("github_owner")
            .deleteField("github_repo")
            .deleteField("github_token")
            .deleteField("github_default_labels")
            .deleteField("github_sync_status")
            .update()

        try await database.schema("feedbacks")
            .deleteField("github_issue_url")
            .deleteField("github_issue_number")
            .update()
    }
}
