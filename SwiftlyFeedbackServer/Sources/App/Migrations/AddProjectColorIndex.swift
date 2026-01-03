import Fluent

struct AddProjectColorIndex: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .field("color_index", .int, .required, .sql(.default(0)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("color_index")
            .update()
    }
}
