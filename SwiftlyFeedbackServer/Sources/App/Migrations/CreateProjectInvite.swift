import Fluent

struct CreateProjectInvite: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("project_invites")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("invited_by_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("email", .string, .required)
            .field("role", .string, .required)
            .field("token", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("accepted_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token")
            .unique(on: "project_id", "email")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("project_invites").delete()
    }
}
