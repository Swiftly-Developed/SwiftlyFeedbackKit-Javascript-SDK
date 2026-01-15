import Fluent
import SQLKit

struct AddProjectEmailNotifyStatuses: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            fatalError("Database must support SQL")
        }

        try await sql.raw("""
            ALTER TABLE projects
            ADD COLUMN email_notify_statuses TEXT[] NOT NULL DEFAULT ARRAY['approved','in_progress','completed','rejected']
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("email_notify_statuses")
            .update()
    }
}
