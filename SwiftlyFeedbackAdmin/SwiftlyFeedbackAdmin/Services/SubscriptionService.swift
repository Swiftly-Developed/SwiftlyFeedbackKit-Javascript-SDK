//
//  SubscriptionService.swift
//  SwiftlyFeedbackAdmin
//
//  Subscription management using server sync (web-based Stripe subscriptions).
//

import Foundation

// MARK: - Subscription Tier

/// Represents the user's subscription tier
enum SubscriptionTier: String, Codable, Sendable, CaseIterable {
    case free = "free"
    case pro = "pro"
    case team = "team"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .team: return "Team"
        }
    }

    /// Maximum number of projects allowed (nil = unlimited)
    var maxProjects: Int? {
        switch self {
        case .free: return 1
        case .pro: return 2
        case .team: return nil
        }
    }

    /// Maximum feedback items per project (nil = unlimited)
    var maxFeedbackPerProject: Int? {
        switch self {
        case .free: return 10
        case .pro: return nil
        case .team: return nil
        }
    }

    /// Whether the tier allows inviting team members
    var canInviteMembers: Bool {
        self == .team
    }

    /// Whether the tier has access to integrations (Slack, GitHub, Email)
    var hasIntegrations: Bool {
        self != .free
    }

    /// Whether the tier has advanced analytics (MRR, detailed insights)
    var hasAdvancedAnalytics: Bool {
        self != .free
    }

    /// Whether the tier has configurable statuses
    var hasConfigurableStatuses: Bool {
        self != .free
    }

    /// Check if this tier meets the requirement of another tier
    func meetsRequirement(_ required: SubscriptionTier) -> Bool {
        switch required {
        case .free: return true
        case .pro: return self == .pro || self == .team
        case .team: return self == .team
        }
    }
}

// MARK: - Subscription Service

/// Service responsible for managing subscriptions via server sync (web-based Stripe).
@MainActor
@Observable
final class SubscriptionService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SubscriptionService()

    // MARK: - State

    /// Whether the service is currently loading data
    private(set) var isLoading = false

    /// Error message if an operation failed
    private(set) var errorMessage: String?

    /// Whether an error should be shown
    var showError = false

    // MARK: - DEBUG Tier Simulation

    #if DEBUG
    /// DEBUG only: Simulated tier for testing specific tier behaviors
    /// Set via Developer Center. nil = use environment override or actual tier
    /// Stored in SecureStorageManager with "debug" scope.

    /// Backing storage for simulatedTier - @Observable tracks this property
    private var _simulatedTier: SubscriptionTier? = {
        guard let raw: String = SecureStorageManager.shared.get(.simulatedSubscriptionTier) else { return nil }
        return SubscriptionTier(rawValue: raw)
    }()

    var simulatedTier: SubscriptionTier? {
        get { _simulatedTier }
        set {
            _simulatedTier = newValue
            if let tier = newValue {
                SecureStorageManager.shared.set(tier.rawValue, for: .simulatedSubscriptionTier)
            } else {
                SecureStorageManager.shared.remove(.simulatedSubscriptionTier)
            }
            AppLogger.storage.debug("Simulated tier set to: \(newValue?.rawValue ?? "nil")")
        }
    }

    func clearSimulatedTier() {
        simulatedTier = nil
        AppLogger.storage.debug("Simulated tier cleared")
    }
    #endif

    /// Clears the cached server tier (used when resetting purchases in Developer Center)
    func clearServerTier() {
        serverTier = nil
        AppLogger.subscription.debug("Server tier cleared")
    }

    /// Server-side tier (authoritative source of truth)
    /// This is populated from the /subscriptions endpoint
    private(set) var serverTier: SubscriptionTier?

    /// Server-side subscription status
    private(set) var serverStatus: SubscriptionStatus?

    /// Server-side expiration date
    private(set) var serverExpiresAt: Date?

    // MARK: - Computed Properties - Tier

    /// The user's current subscription tier from the server
    var currentTier: SubscriptionTier {
        // Server is the source of truth
        return serverTier ?? .free
    }

    /// Effective tier considering simulation (DEBUG only)
    /// Priority: 1. Simulated tier (DEBUG only), 2. Server tier
    var effectiveTier: SubscriptionTier {
        #if DEBUG
        // If a specific tier is being simulated, use it
        if let simulated = simulatedTier {
            return simulated
        }
        #endif
        // Otherwise use actual tier
        return currentTier
    }

    /// Check if user meets tier requirement (considering environment override)
    func meetsRequirement(_ required: SubscriptionTier) -> Bool {
        effectiveTier.meetsRequirement(required)
    }

    /// Whether the user has an active Team subscription
    var isTeamSubscriber: Bool {
        effectiveTier == .team
    }

    /// Whether the user has an active Pro subscription (or higher)
    var isProSubscriber: Bool {
        effectiveTier == .pro || effectiveTier == .team
    }

    /// Whether the user has any paid subscription
    var isPaidSubscriber: Bool {
        isProSubscriber || isTeamSubscriber
    }

    /// The expiration date of the active subscription
    var subscriptionExpirationDate: Date? {
        serverExpiresAt
    }

    /// Whether the subscription will renew
    var willRenew: Bool {
        serverStatus == .active
    }

    /// Display name for the current subscription status
    var subscriptionStatusText: String {
        currentTier.displayName
    }

    // MARK: - Initialization

    private init() {
        AppLogger.subscription.info("SubscriptionService initialized")
    }

    // MARK: - Configuration

    /// Configure the subscription service. Call this once at app launch.
    func configure(userId: UUID? = nil) {
        AppLogger.subscription.info("SubscriptionService configured")

        if userId != nil {
            Task {
                await syncWithServer()
            }
        }
    }

    // MARK: - Authentication

    /// Login with a user ID (call after user authentication)
    func login(userId: UUID) async {
        AppLogger.subscription.info("SubscriptionService login for user: \(userId)")

        // Sync with server
        await syncWithServer()
    }

    /// Logout (call after user logout)
    func logout() async {
        AppLogger.subscription.info("SubscriptionService logout")

        // Clear server tier on logout
        serverTier = nil
        serverStatus = nil
        serverExpiresAt = nil
    }

    // MARK: - Server Sync

    /// Response from the subscription endpoint
    private struct SubscriptionResponse: Codable {
        let tier: SubscriptionTier
        let status: SubscriptionStatus?
        let expiresAt: Date?
        let source: String?
    }

    /// Sync subscription status with the server (get current status)
    func syncWithServer() async {
        AppLogger.subscription.info("Syncing subscription with server")
        isLoading = true

        do {
            let response: SubscriptionResponse = try await AdminAPIClient.shared.get(
                path: "subscriptions",
                requiresAuth: true
            )

            serverTier = response.tier
            serverStatus = response.status
            serverExpiresAt = response.expiresAt

            AppLogger.subscription.info("Subscription synced: tier=\(response.tier.displayName), status=\(response.status?.rawValue ?? "nil")")
        } catch {
            AppLogger.subscription.error("Failed to sync subscription: \(error)")
            // Don't throw - this is a best-effort sync
        }

        isLoading = false
    }

    // MARK: - Entitlement Checking

    /// Check if the user has pro access (Pro or Team tier)
    func hasProAccess() -> Bool {
        isProSubscriber
    }

    /// Check if the user has team access
    func hasTeamAccess() -> Bool {
        isTeamSubscriber
    }

    /// Check if the user's tier meets the required tier
    func hasTierAccess(_ requiredTier: SubscriptionTier) -> Bool {
        currentTier.meetsRequirement(requiredTier)
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: String, Codable, Sendable {
    case active
    case gracePeriod = "grace_period"
    case expired
    case cancelled
    case paused
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .syncFailed(let message):
            return "Failed to sync subscription: \(message)"
        }
    }
}
