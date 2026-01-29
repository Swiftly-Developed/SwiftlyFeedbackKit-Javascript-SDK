import Vapor
import Fluent
import FluentPostgresDriver

@main
struct SwiftlyFeedbackServer {
    static func main() async throws {
        // Load .env file for local development (before Environment.detect)
        // This does NOT overwrite existing env vars, so Heroku config vars take precedence
        if let count = DotEnvLoader.load() {
            print("Loaded \(count) environment variables from .env")
        }

        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        defer { Task { try await app.asyncShutdown() } }

        try await configure(app)
        try await app.execute()
    }
}
