import Vapor
import Fluent
import Leaf

struct WebSettingsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let settings = routes.grouped("settings")

        settings.get(use: index)
        settings.post("profile", use: updateProfile)
        settings.post("password", use: changePassword)
        settings.post("notifications", use: updateNotifications)
        settings.get("subscription", use: subscription)
        settings.post("subscription", "checkout", use: webCheckout)
        settings.post("delete-account", use: deleteAccount)
    }

    // MARK: - Settings Index

    @Sendable
    func index(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)

        return try await req.view.render("settings/index", SettingsContext(
            title: "Settings",
            pageTitle: "Account Settings",
            currentPage: "settings",
            user: UserContext(from: user),
            profile: ProfileSettings(
                name: user.name,
                email: user.email
            ),
            notifications: NotificationSettings(
                notifyNewFeedback: user.notifyNewFeedback,
                notifyNewComments: user.notifyNewComments,
                pushNotificationsEnabled: user.pushNotificationsEnabled,
                pushNotifyNewFeedback: user.pushNotifyNewFeedback,
                pushNotifyNewComments: user.pushNotifyNewComments,
                pushNotifyVotes: user.pushNotifyVotes,
                pushNotifyStatusChanges: user.pushNotifyStatusChanges
            ),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    // MARK: - Update Profile

    @Sendable
    func updateProfile(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(UpdateProfileForm.self)

        user.name = form.name.trimmingCharacters(in: .whitespaces)
        try await user.save(on: req.db)

        return req.redirect(to: "/admin/settings?success=profile_updated")
    }

    // MARK: - Change Password

    @Sendable
    func changePassword(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(ChangePasswordForm.self)

        // Verify current password
        guard try user.verify(password: form.currentPassword) else {
            return req.redirect(to: "/admin/settings?error=invalid_password")
        }

        // Validate new password
        guard form.newPassword.count >= 8 else {
            return req.redirect(to: "/admin/settings?error=password_too_short")
        }

        guard form.newPassword == form.confirmPassword else {
            return req.redirect(to: "/admin/settings?error=passwords_dont_match")
        }

        // Update password
        user.passwordHash = try Bcrypt.hash(form.newPassword)
        try await user.save(on: req.db)

        // Invalidate other sessions
        if let sessionToken = req.cookies["feedbackkit_session"]?.string {
            try await WebSession.query(on: req.db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$sessionToken != sessionToken)
                .delete()
        }

        return req.redirect(to: "/admin/settings?success=password_changed")
    }

    // MARK: - Update Notifications

    @Sendable
    func updateNotifications(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(UpdateNotificationsForm.self)

        user.notifyNewFeedback = form.notifyNewFeedback
        user.notifyNewComments = form.notifyNewComments
        user.pushNotificationsEnabled = form.pushNotificationsEnabled
        user.pushNotifyNewFeedback = form.pushNotifyNewFeedback
        user.pushNotifyNewComments = form.pushNotifyNewComments
        user.pushNotifyVotes = form.pushNotifyVotes
        user.pushNotifyStatusChanges = form.pushNotifyStatusChanges

        try await user.save(on: req.db)

        return req.redirect(to: "/admin/settings?success=notifications_updated")
    }

    // MARK: - Subscription

    @Sendable
    func subscription(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)

        // Get project count
        let projectCount = try await Project.query(on: req.db)
            .filter(\.$owner.$id == user.requireID())
            .count()

        // Get Stripe portal URL if user has Stripe subscription
        var portalUrl: String?
        if let stripeCustomerId = user.stripeCustomerId {
            // Get or create a user token for portal authentication
            let userId = try user.requireID()
            let userToken: UserToken

            if let existingToken = try await UserToken.query(on: req.db)
                .filter(\.$user.$id == userId)
                .first() {
                userToken = existingToken
                req.logger.info("🔑 Portal: Using existing token for user \(userId)")
            } else {
                // Create a new token if none exists
                userToken = try user.generateToken()
                try await userToken.save(on: req.db)
                req.logger.info("🔑 Portal: Created new token for user \(userId)")
            }

            // Debug: Log token info
            req.logger.info("🔑 Portal URL Debug:")
            req.logger.info("   - User ID: \(userId)")
            req.logger.info("   - Stripe Customer ID: \(stripeCustomerId)")
            req.logger.info("   - Token value (first 20 chars): \(String(userToken.value.prefix(20)))...")
            req.logger.info("   - Token created at: \(userToken.createdAt ?? Date())")

            // Build portal URL with auth token
            let baseUrl = AppEnvironment.shared.serverURL
            portalUrl = "\(baseUrl)/portal?token=\(userToken.value)"
            req.logger.info("   - Portal URL: \(portalUrl ?? "nil")")
        }

        // Get Stripe price IDs from environment
        let priceProMonthly = Environment.get("STRIPE_PRICE_PRO_MONTHLY") ?? ""
        let priceProYearly = Environment.get("STRIPE_PRICE_PRO_YEARLY") ?? ""
        let priceTeamMonthly = Environment.get("STRIPE_PRICE_TEAM_MONTHLY") ?? ""
        let priceTeamYearly = Environment.get("STRIPE_PRICE_TEAM_YEARLY") ?? ""

        return try await req.view.render("settings/subscription", SubscriptionContext(
            title: "Subscription",
            pageTitle: "Subscription",
            currentPage: "settings",
            user: UserContext(from: user),
            subscription: SubscriptionInfo(
                tier: user.subscriptionTier.rawValue,
                tierDisplay: user.subscriptionTier.displayName,
                status: user.subscriptionStatus?.rawValue,
                statusDisplay: user.subscriptionStatus?.displayName,
                expiresAt: formatDate(user.subscriptionExpiresAt),
                source: user.subscriptionSource?.rawValue
            ),
            usage: UsageInfo(
                projectCount: projectCount,
                maxProjects: user.subscriptionTier.maxProjects,
                maxFeedbackPerProject: user.subscriptionTier.maxFeedbackPerProject
            ),
            portalUrl: portalUrl,
            checkoutUrl: "\(AppEnvironment.shared.serverURL)/subscribe",
            priceProMonthly: priceProMonthly,
            priceProYearly: priceProYearly,
            priceTeamMonthly: priceTeamMonthly,
            priceTeamYearly: priceTeamYearly
        ))
    }

    // MARK: - Web Checkout

    struct WebCheckoutForm: Content {
        let priceId: String
    }

    @Sendable
    func webCheckout(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()
        let form = try req.content.decode(WebCheckoutForm.self)

        let stripeService = req.stripeService

        // Get or create Stripe customer
        let customerId = try await stripeService.getOrCreateCustomer(for: user, on: req.db)

        // Build URLs
        let baseUrl = AppEnvironment.shared.serverURL
        let successUrl = "\(baseUrl)/admin/settings/subscription?success=subscribed"
        let cancelUrl = "\(baseUrl)/admin/settings/subscription?cancelled=true"

        // Create checkout session
        let checkoutUrl = try await stripeService.createCheckoutSession(
            customerId: customerId,
            priceId: form.priceId,
            userId: userId,
            successUrl: successUrl,
            cancelUrl: cancelUrl
        )

        // Return JSON response with checkout URL
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(string: "{\"checkout_url\": \"\(checkoutUrl)\"}")
        )
    }

    // MARK: - Delete Account

    @Sendable
    func deleteAccount(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(DeleteAccountForm.self)

        // Verify password
        guard try user.verify(password: form.password) else {
            return req.redirect(to: "/admin/settings?error=invalid_password")
        }

        let userId = try user.requireID()

        // Transfer or archive owned projects
        let ownedProjects = try await Project.query(on: req.db)
            .filter(\.$owner.$id == userId)
            .all()

        for project in ownedProjects {
            let members = try await ProjectMember.query(on: req.db)
                .filter(\.$project.$id == project.requireID())
                .filter(\.$user.$id != userId)
                .all()

            if let newOwnerMember = members.first(where: { $0.role == .admin }) ?? members.first {
                project.$owner.id = newOwnerMember.$user.id
                try await project.save(on: req.db)
                try await newOwnerMember.delete(on: req.db)
            } else {
                project.isArchived = true
                project.archivedAt = Date()
                try await project.save(on: req.db)
            }
        }

        // Remove from project memberships
        try await ProjectMember.query(on: req.db)
            .filter(\.$user.$id == userId)
            .delete()

        // Delete tokens and sessions
        try await UserToken.query(on: req.db)
            .filter(\.$user.$id == userId)
            .delete()

        try await WebSession.query(on: req.db)
            .filter(\.$user.$id == userId)
            .delete()

        // Delete user
        try await user.delete(on: req.db)

        // Clear cookie and redirect to login
        let response = req.redirect(to: "/admin/login")
        response.cookies["feedbackkit_session"] = .expired

        return response
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Form DTOs

struct UpdateProfileForm: Content {
    let name: String
}

struct ChangePasswordForm: Content {
    let currentPassword: String
    let newPassword: String
    let confirmPassword: String
}

struct UpdateNotificationsForm: Content {
    let notifyNewFeedback: Bool
    let notifyNewComments: Bool
    let pushNotificationsEnabled: Bool
    let pushNotifyNewFeedback: Bool
    let pushNotifyNewComments: Bool
    let pushNotifyVotes: Bool
    let pushNotifyStatusChanges: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Checkboxes send "on" if checked, nothing if not
        notifyNewFeedback = (try? container.decode(String.self, forKey: .notifyNewFeedback)) == "on"
        notifyNewComments = (try? container.decode(String.self, forKey: .notifyNewComments)) == "on"
        pushNotificationsEnabled = (try? container.decode(String.self, forKey: .pushNotificationsEnabled)) == "on"
        pushNotifyNewFeedback = (try? container.decode(String.self, forKey: .pushNotifyNewFeedback)) == "on"
        pushNotifyNewComments = (try? container.decode(String.self, forKey: .pushNotifyNewComments)) == "on"
        pushNotifyVotes = (try? container.decode(String.self, forKey: .pushNotifyVotes)) == "on"
        pushNotifyStatusChanges = (try? container.decode(String.self, forKey: .pushNotifyStatusChanges)) == "on"
    }

    enum CodingKeys: String, CodingKey {
        case notifyNewFeedback
        case notifyNewComments
        case pushNotificationsEnabled
        case pushNotifyNewFeedback
        case pushNotifyNewComments
        case pushNotifyVotes
        case pushNotifyStatusChanges
    }
}

struct DeleteAccountForm: Content {
    let password: String
}

// MARK: - View Contexts

struct SettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let profile: ProfileSettings
    let notifications: NotificationSettings
    let success: String?
    let error: String?
}

struct ProfileSettings: Encodable {
    let name: String
    let email: String
}

struct NotificationSettings: Encodable {
    let notifyNewFeedback: Bool
    let notifyNewComments: Bool
    let pushNotificationsEnabled: Bool
    let pushNotifyNewFeedback: Bool
    let pushNotifyNewComments: Bool
    let pushNotifyVotes: Bool
    let pushNotifyStatusChanges: Bool
}

struct SubscriptionContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let subscription: SubscriptionInfo
    let usage: UsageInfo
    let portalUrl: String?
    let checkoutUrl: String
    let priceProMonthly: String
    let priceProYearly: String
    let priceTeamMonthly: String
    let priceTeamYearly: String
}

struct SubscriptionInfo: Encodable {
    let tier: String
    let tierDisplay: String
    let status: String?
    let statusDisplay: String?
    let expiresAt: String?
    let source: String?
}

struct UsageInfo: Encodable {
    let projectCount: Int
    let maxProjects: Int?
    let maxFeedbackPerProject: Int?
}

extension SubscriptionStatus {
    var displayName: String {
        switch self {
        case .active: return "Active"
        case .expired: return "Expired"
        case .cancelled: return "Cancelled"
        case .gracePeriod: return "Grace Period"
        case .paused: return "Paused"
        }
    }
}
