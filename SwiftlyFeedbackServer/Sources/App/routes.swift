import Vapor

func routes(_ app: Application) throws {
    // Redirect root to admin login
    app.get { req -> Response in
        req.redirect(to: "/admin/login")
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
