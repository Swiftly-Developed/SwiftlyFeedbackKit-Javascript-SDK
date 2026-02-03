import Vapor

// MARK: - Landing Page Context

struct IndexContext: Encodable {
    let loginURL: String
    let signupURL: String
    let environment: String
    let environmentBadge: String?
    let isProduction: Bool
}

func routes(_ app: Application) throws {
    // Landing page
    app.get { req async throws -> View in
        let env = AppEnvironment.shared
        let context = IndexContext(
            loginURL: "/admin/login",
            signupURL: "/admin/signup",
            environment: env.type.rawValue,
            environmentBadge: env.environmentBadge,
            isProduction: env.isProduction
        )
        return try await req.view.render("index", context)
    }

    app.get("health") { req in
        ["status": "ok"]
    }

    // Web pages (subscription, etc.) - no prefix
    try app.register(collection: WebController())

    // Web Admin routes
    let admin = app.grouped("admin")

    // Public auth routes (login, signup, forgot password)
    try admin.register(collection: WebAuthController())

    // Protected admin routes (require session authentication)
    let protectedAdmin = admin.grouped(WebSessionAuthMiddleware())
    try protectedAdmin.register(collection: WebDashboardController())
    try protectedAdmin.register(collection: WebProjectController())
    try protectedAdmin.register(collection: WebFeedbackController())
    try protectedAdmin.register(collection: WebSettingsController())
    try protectedAdmin.register(collection: WebAnalyticsController())
    try protectedAdmin.register(collection: WebIntegrationsController())
    try protectedAdmin.register(collection: WebFeatureRequestsController())

    // API v1 routes
    let api = app.grouped("api", "v1")

    // Auth routes (signup, login, etc.)
    try api.register(collection: AuthController())

    // Project management routes (requires authentication)
    try api.register(collection: ProjectController())

    // Feedback routes (public API with API key + admin routes with auth)
    try api.register(collection: FeedbackController())
    try api.register(collection: VoteController())
    try api.register(collection: CommentController())

    // SDK User routes (for MRR tracking)
    try api.register(collection: SDKUserController())

    // View event tracking routes
    try api.register(collection: ViewEventController())

    // Dashboard routes (home KPIs)
    try api.register(collection: DashboardController())

    // Subscription management routes (checkout, portal, sync)
    try api.register(collection: SubscriptionController())

    // Webhook routes (Stripe, App Store)
    try api.register(collection: StripeWebhookController())
    try api.register(collection: AppStoreWebhookController())

    // Device management routes (push notifications)
    try api.register(collection: DeviceController())
}
