import Fluent

struct AddUserEmailVerified: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("is_email_verified", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("is_email_verified")
            .update()
    }
}
