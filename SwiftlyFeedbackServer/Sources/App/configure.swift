import Vapor
import Fluent
import FluentPostgresDriver
import NIOSSL
import Leaf
import LeafKit

func configure(_ app: Application) async throws {
    // Configure JSON encoding/decoding to use snake_case
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Database configuration - PostgreSQL
    // Try to use DATABASE_URL first (Heroku standard), then fall back to individual vars
    if let databaseURL = Environment.get("DATABASE_URL") {
        // Parse DATABASE_URL (format: postgres://username:password@hostname:port/database)
        guard let url = URL(string: databaseURL),
              let host = url.host,
              let user = url.user,
              let pass = url.password,
              let port = url.port else {
            fatalError("Invalid DATABASE_URL format")
        }
        let dbName = String(url.path.dropFirst()) // Remove leading "/"

        // Configure TLS for Heroku Postgres (requires SSL but without certificate verification)
        var tlsConfig: TLSConfiguration = .makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        let sslContext = try NIOSSLContext(configuration: tlsConfig)

        let config = SQLPostgresConfiguration(
            hostname: host,
            port: port,
            username: user,
            password: pass,
            database: dbName,
            tls: .require(sslContext)
        )

        app.databases.use(.postgres(configuration: config), as: .psql)
        app.logger.info("Using DATABASE_URL: \(host):\(port)/\(dbName)")
    } else {
        // Fall back to individual environment variables (for local development)
        let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
        let port = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432
        let username = Environment.get("DATABASE_USERNAME") ?? "postgres"
        let password = Environment.get("DATABASE_PASSWORD") ?? "postgres"
        let database = Environment.get("DATABASE_NAME") ?? "swiftly_feedback"

        let config = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        app.databases.use(.postgres(configuration: config), as: .psql)
        app.logger.info("Using individual DB vars: \(hostname):\(port)/\(database)")
    }

    // Log detected environment
    let appEnv = AppEnvironment.shared
    app.logger.info("Environment detected: \(appEnv.type.name)")
    app.logger.info("Server URL: \(appEnv.serverURL)")

    // Configure Leaf templating engine
    app.views.use(.leaf)

    // Use VIEWS_PATH env var if set, otherwise use default
    // Default works on deployed servers; VIEWS_PATH can be set for local Xcode development
    if let customPath = Environment.get("VIEWS_PATH") {
        app.leaf.sources = LeafSources.singleSource(
            NIOLeafFiles(fileio: app.fileio,
                         limits: .default,
                         sandboxDirectory: customPath,
                         viewDirectory: customPath)
        )
        app.logger.info("Using custom views directory: \(customPath)")
    }

    // Serve static files from Public directory
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Migrations - order matters!
    app.migrations.add(CreateUser())
    app.migrations.add(CreateUserToken())
    app.migrations.add(CreateProject())
    app.migrations.add(CreateProjectMember())
    app.migrations.add(CreateFeedback())
    app.migrations.add(CreateVote())
    app.migrations.add(CreateComment())
    app.migrations.add(CreateProjectInvite())
    app.migrations.add(AddUserEmailVerified())
    app.migrations.add(CreateEmailVerification())
    app.migrations.add(CreateSDKUser())
    app.migrations.add(CreateViewEvent())
    app.migrations.add(AddProjectColorIndex())
    app.migrations.add(AddUserNotificationSettings())
    app.migrations.add(AddProjectSlackWebhook())
    app.migrations.add(AddFeedbackMergeFields())
    app.migrations.add(AddProjectAllowedStatuses())
    app.migrations.add(AddProjectGitHubIntegration())
    app.migrations.add(AddProjectClickUpIntegration())
    app.migrations.add(AddProjectNotionIntegration())
    app.migrations.add(AddProjectMondayIntegration())
    app.migrations.add(AddProjectLinearIntegration())
    app.migrations.add(AddIntegrationActiveToggles())
    app.migrations.add(CreatePasswordReset())
    app.migrations.add(AddUserSubscriptionFields())
    app.migrations.add(AddVoteEmailNotification())
    app.migrations.add(AddProjectTrelloIntegration())
    app.migrations.add(AddProjectAirtableIntegration())
    app.migrations.add(AddProjectAsanaIntegration())
    app.migrations.add(AddProjectBasecampIntegration())
    app.migrations.add(AddProjectEmailNotifyStatuses())
    app.migrations.add(AddFeedbackRejectionReason())
    app.migrations.add(CreateDeviceToken())
    app.migrations.add(CreateProjectMemberPreference())
    app.migrations.add(CreatePushNotificationLog())
    app.migrations.add(AddUserPushNotificationSettings())
    app.migrations.add(AddStripeSubscriptionFields())
    app.migrations.add(CreateWebSession())

    try await app.autoMigrate()

    // Configure APNs (optional - only if environment variables are set)
    try? app.apns.configure()

    // CORS middleware
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .PATCH, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .init("X-API-Key"), .init("X-User-Id")]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration))

    // Schedule feedback cleanup (runs daily at startup and every 24 hours)
    // Only runs on non-production environments (dev, testflight)
    FeedbackCleanupScheduler.start(app: app)

    // Routes
    try routes(app)
}
