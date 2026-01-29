import Vapor
import Fluent

struct SubscriptionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let subscriptions = routes.grouped("subscriptions")

        // Protected routes (require authentication)
        let protected = subscriptions.grouped(UserToken.authenticator(), User.guardMiddleware())

        // Stripe checkout and portal
        protected.post("checkout", use: createCheckoutSession)
        protected.get("portal", use: getPortalUrl)

        // Apple transaction sync
        protected.post("sync-apple", use: syncAppleTransaction)

        // Get current subscription
        protected.get(use: getSubscription)
    }

    // MARK: - Get Subscription

    /// GET /api/v1/subscriptions
    /// Returns current subscription info
    @Sendable
    func getSubscription(req: Request) async throws -> SubscriptionInfoDTO {
        let user = try req.auth.require(User.self)

        // Count user's owned projects
        let projectCount = try await Project.query(on: req.db)
            .filter(\.$owner.$id == user.requireID())
            .count()

        let tier = user.subscriptionTier
        let canCreateProject: Bool
        if let maxProjects = tier.maxProjects {
            canCreateProject = projectCount < maxProjects
        } else {
            canCreateProject = true
        }

        return SubscriptionInfoDTO(
            tier: tier,
            status: user.subscriptionStatus,
            productId: user.subscriptionProductId,
            expiresAt: user.subscriptionExpiresAt,
            source: user.subscriptionSource,
            limits: SubscriptionLimitsDTO(
                maxProjects: tier.maxProjects,
                maxFeedbackPerProject: tier.maxFeedbackPerProject,
                currentProjectCount: projectCount,
                canCreateProject: canCreateProject
            )
        )
    }

    // MARK: - Stripe Checkout

    /// POST /api/v1/subscriptions/checkout
    /// Creates a Stripe Checkout session for web subscription
    @Sendable
    func createCheckoutSession(req: Request) async throws -> CheckoutSessionResponseDTO {
        // Debug: Log the authorization header
        if let authHeader = req.headers.bearerAuthorization {
            req.logger.info("🔑 Bearer token received: \(authHeader.token.prefix(20))...")
        } else {
            req.logger.warning("⚠️ No Bearer authorization header found")
        }

        let user = try req.auth.require(User.self)
        let userId = try user.requireID()
        let dto = try req.content.decode(CreateCheckoutSessionDTO.self)

        let stripeService = req.stripeService

        // Get or create Stripe customer (lazy creation)
        let customerId = try await stripeService.getOrCreateCustomer(for: user, on: req.db)

        // Default URLs if not provided
        let baseUrl = Environment.get("WEB_APP_URL") ?? "https://app.swiftlyfeedback.com"
        let successUrl = dto.successUrl ?? "\(baseUrl)/subscription/success"
        let cancelUrl = dto.cancelUrl ?? "\(baseUrl)/subscription/cancel"

        // Create checkout session
        let checkoutUrl = try await stripeService.createCheckoutSession(
            customerId: customerId,
            priceId: dto.priceId,
            userId: userId,
            successUrl: successUrl,
            cancelUrl: cancelUrl
        )

        return CheckoutSessionResponseDTO(checkoutUrl: checkoutUrl)
    }

    // MARK: - Stripe Portal

    /// GET /api/v1/subscriptions/portal
    /// Returns Stripe Customer Portal URL for subscription management
    @Sendable
    func getPortalUrl(req: Request) async throws -> PortalSessionResponseDTO {
        let user = try req.auth.require(User.self)

        guard let customerId = user.stripeCustomerId else {
            throw Abort(.badRequest, reason: "No Stripe customer found. Subscribe first to manage your subscription.")
        }

        let dto = try? req.query.decode(CreatePortalSessionDTO.self)
        let baseUrl = Environment.get("WEB_APP_URL") ?? "https://app.swiftlyfeedback.com"
        let returnUrl = dto?.returnUrl ?? baseUrl

        let stripeService = req.stripeService
        let portalUrl = try await stripeService.createPortalSession(
            customerId: customerId,
            returnUrl: returnUrl
        )

        return PortalSessionResponseDTO(portalUrl: portalUrl)
    }

    // MARK: - Apple Transaction Sync

    /// POST /api/v1/subscriptions/sync-apple
    /// Syncs an App Store transaction with the server
    @Sendable
    func syncAppleTransaction(req: Request) async throws -> SubscriptionInfoDTO {
        let user = try req.auth.require(User.self)

        // Log raw request body for debugging
        if let bodyData = req.body.data {
            let bodyString = String(buffer: bodyData)
            req.logger.info("🔍 Raw request body: \(bodyString)")
        } else {
            req.logger.warning("⚠️ No request body received")
        }

        let dto = try req.content.decode(SyncAppleTransactionDTO.self)

        let appStoreService = req.appStoreService

        // Update user subscription fields from the transaction info
        user.appleOriginalTransactionId = dto.originalTransactionId
        user.subscriptionProductId = dto.productId
        user.subscriptionTier = appStoreService.tierFromProductId(dto.productId)
        user.subscriptionStatus = .active
        user.subscriptionSource = .appStore
        user.subscriptionUpdatedAt = Date()

        try await user.save(on: req.db)

        req.logger.info("✅ Synced Apple transaction for user \(user.id?.uuidString ?? "unknown"): tier=\(user.subscriptionTier.rawValue), productId=\(dto.productId)")

        return try await getSubscription(req: req)
    }
}
