import Vapor
import Fluent

/// Service for interacting with Stripe API
/// Uses direct HTTP calls for better control and compatibility
struct StripeService {
    private let apiKey: String
    private let webhookSecret: String?
    private let httpClient: Client
    private let priceToTier: [String: SubscriptionTier]

    init(apiKey: String, webhookSecret: String?, httpClient: Client, priceToTier: [String: SubscriptionTier]) {
        self.apiKey = apiKey
        self.webhookSecret = webhookSecret
        self.httpClient = httpClient
        self.priceToTier = priceToTier
    }

    // MARK: - Customer Management

    /// Create or retrieve a Stripe customer for a user
    func getOrCreateCustomer(for user: User, on db: any Database) async throws -> String {
        // Return existing customer ID if available
        if let customerId = user.stripeCustomerId {
            return customerId
        }

        // Create new customer via Stripe API
        let response = try await httpClient.post(URI(string: "https://api.stripe.com/v1/customers")) { req in
            req.headers.add(name: .authorization, value: "Bearer \(apiKey)")
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")

            var body = "email=\(user.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user.email)"
            body += "&name=\(user.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user.name)"
            if let userId = user.id?.uuidString {
                body += "&metadata[user_id]=\(userId)"
            }
            req.body = ByteBuffer(string: body)
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to create Stripe customer: \(response.status)")
        }

        let customer = try response.content.decode(StripeCustomerResponse.self)

        // Save customer ID to user
        user.stripeCustomerId = customer.id
        try await user.save(on: db)

        return customer.id
    }

    // MARK: - Checkout Sessions

    /// Create a checkout session for subscription purchase
    func createCheckoutSession(
        customerId: String,
        priceId: String,
        userId: UUID,
        successUrl: String,
        cancelUrl: String
    ) async throws -> String {
        let response = try await httpClient.post(URI(string: "https://api.stripe.com/v1/checkout/sessions")) { req in
            req.headers.add(name: .authorization, value: "Bearer \(apiKey)")
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")

            var body = "mode=subscription"
            body += "&customer=\(customerId)"
            body += "&success_url=\(successUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? successUrl)"
            body += "&cancel_url=\(cancelUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cancelUrl)"
            body += "&line_items[0][price]=\(priceId)"
            body += "&line_items[0][quantity]=1"
            body += "&metadata[user_id]=\(userId.uuidString)"
            body += "&client_reference_id=\(userId.uuidString)"
            req.body = ByteBuffer(string: body)
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to create checkout session: \(response.status)")
        }

        let session = try response.content.decode(StripeCheckoutSessionResponse.self)

        guard let url = session.url else {
            throw Abort(.internalServerError, reason: "Checkout session created but URL is missing")
        }

        return url
    }

    // MARK: - Customer Portal

    /// Create a portal session for subscription management
    func createPortalSession(customerId: String, returnUrl: String) async throws -> String {
        let response = try await httpClient.post(URI(string: "https://api.stripe.com/v1/billing_portal/sessions")) { req in
            req.headers.add(name: .authorization, value: "Bearer \(apiKey)")
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")

            var body = "customer=\(customerId)"
            body += "&return_url=\(returnUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? returnUrl)"
            req.body = ByteBuffer(string: body)
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to create portal session: \(response.status)")
        }

        let session = try response.content.decode(StripeBillingPortalSessionResponse.self)
        return session.url
    }

    // MARK: - Subscription Management

    /// Get subscription details
    func getSubscription(subscriptionId: String) async throws -> StripeSubscriptionResponse {
        let response = try await httpClient.get(URI(string: "https://api.stripe.com/v1/subscriptions/\(subscriptionId)")) { req in
            req.headers.add(name: .authorization, value: "Bearer \(apiKey)")
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to get subscription: \(response.status)")
        }

        return try response.content.decode(StripeSubscriptionResponse.self)
    }

    // MARK: - Webhook Handling

    /// Verify webhook signature using HMAC-SHA256
    func verifyWebhookSignature(payload: Data, signature: String) throws {
        guard let secret = webhookSecret, !secret.isEmpty else {
            // Skip verification in development if no secret is configured
            return
        }

        // Parse the signature header (format: t=timestamp,v1=signature)
        let parts = signature.split(separator: ",")
        var timestamp: String?
        var v1Signature: String?

        for part in parts {
            let keyValue = part.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                let key = String(keyValue[0])
                let value = String(keyValue[1])
                if key == "t" {
                    timestamp = value
                } else if key == "v1" {
                    v1Signature = value
                }
            }
        }

        guard let ts = timestamp, let sig = v1Signature else {
            throw Abort(.badRequest, reason: "Invalid webhook signature format")
        }

        // Create the signed payload string
        let signedPayload = "\(ts).\(String(data: payload, encoding: .utf8) ?? "")"

        // Compute expected signature
        let key = SymmetricKey(data: Data(secret.utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(
            for: Data(signedPayload.utf8),
            using: key
        )
        let expectedSignatureHex = expectedSignature.map { String(format: "%02x", $0) }.joined()

        // Compare signatures
        guard expectedSignatureHex == sig else {
            throw Abort(.unauthorized, reason: "Invalid webhook signature")
        }
    }

    /// Parse webhook event from JSON payload
    func parseWebhookEvent(from payload: Data) throws -> StripeWebhookEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(StripeWebhookEvent.self, from: payload)
    }

    // MARK: - Tier Mapping

    /// Map a Stripe price ID to a subscription tier
    func tierFromPriceId(_ priceId: String) -> SubscriptionTier {
        // Check exact match first
        if let tier = priceToTier[priceId] {
            return tier
        }

        // Fallback to string matching
        let lowercased = priceId.lowercased()
        if lowercased.contains("team") {
            return .team
        } else if lowercased.contains("pro") {
            return .pro
        }

        return .free
    }

    /// Determine subscription status from Stripe subscription status string
    func subscriptionStatus(from stripeStatus: String) -> SubscriptionStatus {
        switch stripeStatus {
        case "active", "trialing":
            return .active
        case "past_due":
            return .gracePeriod
        case "canceled", "unpaid":
            return .expired
        case "paused":
            return .paused
        case "incomplete", "incomplete_expired":
            return .expired
        default:
            return .active
        }
    }
}

// MARK: - Stripe API Response Types

struct StripeCustomerResponse: Content {
    let id: String
    let email: String?
}

struct StripeCheckoutSessionResponse: Content {
    let id: String
    let url: String?
    let customer: String?
    let subscription: String?
}

struct StripeBillingPortalSessionResponse: Content {
    let id: String
    let url: String
}

struct StripeSubscriptionResponse: Content {
    let id: String
    let status: String
    let customer: String
    let currentPeriodEnd: Date?
    let items: StripeSubscriptionItems?

    struct StripeSubscriptionItems: Content {
        let data: [StripeSubscriptionItem]?
    }

    struct StripeSubscriptionItem: Content {
        let price: StripePrice?
    }

    struct StripePrice: Content {
        let id: String
    }
}

struct StripeWebhookEvent: Content {
    let id: String
    let type: String
    let data: StripeEventData

    struct StripeEventData: Content {
        let object: StripeEventObject
    }

    struct StripeEventObject: Content {
        // Common fields
        let id: String?
        let customer: String?
        let subscription: String?
        let status: String?
        let metadata: [String: String]?

        // Checkout session fields
        let url: String?

        // Subscription fields
        let currentPeriodEnd: Date?
        let items: StripeSubscriptionResponse.StripeSubscriptionItems?
    }
}

// MARK: - Crypto imports for HMAC
import Crypto

// MARK: - Request Extension

extension Request {
    var stripeService: StripeService {
        guard let apiKey = Environment.get("STRIPE_SECRET_KEY") else {
            fatalError("STRIPE_SECRET_KEY environment variable not set")
        }
        let webhookSecret = Environment.get("STRIPE_WEBHOOK_SECRET")

        // Build price-to-tier mapping from environment variables
        var priceToTier: [String: SubscriptionTier] = [:]

        // Pro tier prices
        if let priceId = Environment.get("STRIPE_PRICE_PRO_MONTHLY") {
            priceToTier[priceId] = .pro
        }
        if let priceId = Environment.get("STRIPE_PRICE_PRO_YEARLY") {
            priceToTier[priceId] = .pro
        }

        // Team tier prices
        if let priceId = Environment.get("STRIPE_PRICE_TEAM_MONTHLY") {
            priceToTier[priceId] = .team
        }
        if let priceId = Environment.get("STRIPE_PRICE_TEAM_YEARLY") {
            priceToTier[priceId] = .team
        }

        return StripeService(
            apiKey: apiKey,
            webhookSecret: webhookSecret,
            httpClient: self.client,
            priceToTier: priceToTier
        )
    }
}
