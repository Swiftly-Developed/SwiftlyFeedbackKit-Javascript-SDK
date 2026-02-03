import Vapor

enum EnvironmentType: String {
    case development
    case staging
    case production
    case local

    var name: String { rawValue }
}

final class AppEnvironment: Sendable {
    static let shared = AppEnvironment()

    let type: EnvironmentType
    let serverURL: String

    private init() {
        // Read APP_ENV from environment variable
        if let appEnv = Environment.get("APP_ENV") {
            switch appEnv.lowercased() {
            case "development":
                self.type = .development
                self.serverURL = "https://api.feedbackkit.dev.swiftly-developed.com"
            case "staging":
                self.type = .staging
                self.serverURL = "https://api.feedbackkit.testflight.swiftly-developed.com"
            case "production":
                self.type = .production
                self.serverURL = "https://feedbackkit.swiftly-workspace.com"
            default:
                self.type = .local
                self.serverURL = "http://localhost:8080"
            }
        } else {
            // Default to local for development
            self.type = .local
            self.serverURL = "http://localhost:8080"
        }
    }

    var isDevelopment: Bool { type == .development }
    var isStaging: Bool { type == .staging }
    var isProduction: Bool { type == .production }
    var isLocal: Bool { type == .local }

    /// Environment badge text for non-production
    var environmentBadge: String? {
        switch type {
        case .local: return "Local"
        case .development: return "Development"
        case .staging: return "TestFlight"
        case .production: return nil
        }
    }

    /// FeedbackKit API key for the dog-fooding project (collecting feedback about FeedbackKit itself)
    var feedbackKitAPIKey: String {
        switch type {
        case .local:
            return "sf_8iJjRNZof9tRrrybkxViu1ZF8Jgxs7Ad"
        case .development:
            return "sf_67xRwr4qxTwaIQOFyXq9uyuSOrtS2uvy"
        case .staging:
            return "sf_Gw8ZKcjCEtxHUNCKjpusOkFvlNbQ2Pxf"
        case .production:
            return "sf_Tt5Oc4SFNhNgGUb9Ga7Y7AMwF9cGj571"
        }
    }
}
