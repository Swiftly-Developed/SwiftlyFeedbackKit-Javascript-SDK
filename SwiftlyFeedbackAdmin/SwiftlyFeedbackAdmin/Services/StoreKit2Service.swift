//
//  StoreKit2Service.swift
//  SwiftlyFeedbackAdmin
//
//  StoreKit 2 integration for in-app purchases.
//

import Foundation
import StoreKit

/// Service for managing StoreKit 2 product loading and purchases
@MainActor
@Observable
final class StoreKit2Service: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = StoreKit2Service()

    // MARK: - Product Identifiers

    /// Product identifiers matching App Store Connect configuration
    enum ProductID: String, CaseIterable {
        case proMonthly = "swiftlyfeedback.pro.monthly"
        case proYearly = "swiftlyfeedback.pro.yearly"
        case teamMonthly = "swiftlyfeedback.team.monthly"
        case teamYearly = "swiftlyfeedback.team.yearly"

        var tier: SubscriptionTier {
            switch self {
            case .proMonthly, .proYearly: return .pro
            case .teamMonthly, .teamYearly: return .team
            }
        }

        var isYearly: Bool {
            switch self {
            case .proYearly, .teamYearly: return true
            case .proMonthly, .teamMonthly: return false
            }
        }

        static func productID(for tier: SubscriptionTier, yearly: Bool) -> ProductID? {
            switch (tier, yearly) {
            case (.pro, false): return .proMonthly
            case (.pro, true): return .proYearly
            case (.team, false): return .teamMonthly
            case (.team, true): return .teamYearly
            case (.free, _): return nil
            }
        }
    }

    // MARK: - State

    /// Whether the service is currently loading products
    private(set) var isLoading = false

    /// Error message if an operation failed
    private(set) var errorMessage: String?

    /// Whether an error should be shown
    var showError = false

    /// Available products from StoreKit
    private(set) var products: [Product] = []

    /// Current active subscription transaction
    private(set) var currentTransaction: Transaction?

    /// Transaction listener task
    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        AppLogger.subscription.info("StoreKit2Service initialized")
    }

    // MARK: - Lifecycle

    /// Start listening for transaction updates
    func startListening() {
        updateListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if case .verified(let transaction) = result {
                    await MainActor.run {
                        self.currentTransaction = transaction
                    }
                    await transaction.finish()
                    AppLogger.subscription.info("Transaction updated: \(transaction.productID)")
                }
            }
        }
        AppLogger.subscription.info("StoreKit2Service started listening for transactions")
    }

    /// Stop listening for transaction updates
    func stopListening() {
        updateListenerTask?.cancel()
        updateListenerTask = nil
        AppLogger.subscription.info("StoreKit2Service stopped listening for transactions")
    }

    // MARK: - Product Loading

    /// Load products from App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let productIds = ProductID.allCases.map(\.rawValue)
            products = try await Product.products(for: productIds)
            AppLogger.subscription.info("Loaded \(products.count) products from StoreKit")
        } catch {
            AppLogger.subscription.error("Failed to load products: \(error)")
            showError(message: error.localizedDescription)
        }
    }

    /// Get product for a specific tier and billing period
    func product(for tier: SubscriptionTier, yearly: Bool) -> Product? {
        guard let productId = ProductID.productID(for: tier, yearly: yearly) else { return nil }
        return products.first { $0.id == productId.rawValue }
    }

    // MARK: - Purchase

    /// Purchase a product
    func purchase(_ product: Product) async throws -> Transaction {
        isLoading = true
        defer { isLoading = false }

        AppLogger.subscription.info("Starting purchase for product: \(product.id)")

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                AppLogger.subscription.info("Purchase successful: \(transaction.productID)")
                currentTransaction = transaction
                await transaction.finish()
                return transaction
            case .unverified(let transaction, let error):
                AppLogger.subscription.error("Purchase unverified: \(error)")
                await transaction.finish()
                throw StoreKit2Error.verificationFailed(error)
            }

        case .userCancelled:
            AppLogger.subscription.info("Purchase cancelled by user")
            throw StoreKit2Error.purchaseCancelled

        case .pending:
            AppLogger.subscription.info("Purchase pending approval")
            throw StoreKit2Error.purchasePending

        @unknown default:
            throw StoreKit2Error.unknown
        }
    }

    // MARK: - Restore Purchases

    /// Restore previous purchases
    func restorePurchases() async throws -> Transaction? {
        isLoading = true
        defer { isLoading = false }

        AppLogger.subscription.info("Restoring purchases")

        // Sync with App Store
        try await AppStore.sync()

        // Check for current entitlements
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable {
                    currentTransaction = transaction
                    AppLogger.subscription.info("Restored subscription: \(transaction.productID)")
                    return transaction
                }
            }
        }

        AppLogger.subscription.info("No active subscriptions found")
        return nil
    }

    // MARK: - Current Subscription

    /// Check current subscription status from StoreKit
    func checkCurrentSubscription() async -> Transaction? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable {
                    currentTransaction = transaction
                    return transaction
                }
            }
        }
        currentTransaction = nil
        return nil
    }

    /// Get the original transaction ID for server sync
    var originalTransactionId: String? {
        currentTransaction?.originalID.description
    }

    /// Get the current product ID
    var currentProductId: String? {
        currentTransaction?.productID
    }

    /// Get the subscription expiration date
    var expirationDate: Date? {
        currentTransaction?.expirationDate
    }

    /// Determine tier from current transaction
    var currentTier: SubscriptionTier {
        guard let productId = currentTransaction?.productID,
              let pid = ProductID(rawValue: productId) else {
            return .free
        }
        return pid.tier
    }

    // MARK: - Error Handling

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }
}

// MARK: - Errors

enum StoreKit2Error: LocalizedError {
    case purchaseCancelled
    case purchasePending
    case verificationFailed(Error)
    case noProductsAvailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .purchaseCancelled:
            return "Purchase was cancelled"
        case .purchasePending:
            return "Purchase is pending approval"
        case .verificationFailed(let error):
            return "Purchase verification failed: \(error.localizedDescription)"
        case .noProductsAvailable:
            return "No subscription products are available"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
