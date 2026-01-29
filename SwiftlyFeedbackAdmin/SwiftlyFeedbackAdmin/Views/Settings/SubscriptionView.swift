//
//  SubscriptionView.swift
//  SwiftlyFeedbackAdmin
//
//  Subscription management view - uses web-based Stripe subscriptions.
//

import SwiftUI

struct SubscriptionView: View {
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.appConfiguration) private var appConfiguration
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var paywallRequiredTier: SubscriptionTier = .pro
    @State private var isLoadingPortal = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            // Current Plan Section
            currentPlanSection

            // Upgrade Section (for users who can upgrade)
            if canShowUpgradeSection {
                upgradeSection
            }

            // Feature Comparison Table
            featureComparisonSection

            // Manage Subscription Section (for paid subscribers)
            if subscriptionService.isPaidSubscriber {
                manageSubscriptionSection
            }

            // Refresh Subscription Section
            refreshSection
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(requiredTier: paywallRequiredTier)
        }
        .navigationTitle("Subscription")
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    /// Whether to show the upgrade section
    /// Shows for free users, and Pro users who might want Team
    private var canShowUpgradeSection: Bool {
        // Show if user is not at max tier (Team)
        displayTier != .team
    }

    // MARK: - Current Plan Section

    /// The tier to display (uses effectiveTier to respect environment override)
    private var displayTier: SubscriptionTier {
        subscriptionService.effectiveTier
    }

    @ViewBuilder
    private var currentPlanSection: some View {
        Section {
            HStack(spacing: 16) {
                // Plan Icon
                ZStack {
                    tierGradient(for: displayTier)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    Image(systemName: tierIcon(for: displayTier))
                        .font(.title2)
                        .foregroundStyle(displayTier != .free ? .white : .gray)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTier.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if subscriptionService.isPaidSubscriber {
                        if let expirationDate = subscriptionService.subscriptionExpirationDate {
                            if subscriptionService.willRenew {
                                Text("Renews \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Expires \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("Upgrade to unlock all features")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if displayTier != .free {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Current Plan")
        }
    }

    // MARK: - Feature Comparison Section

    @ViewBuilder
    private var featureComparisonSection: some View {
        Section {
            featureComparisonTable
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            Text("Compare Plans")
        } footer: {
            Text("Upgrade anytime to unlock more features. All plans include core feedback collection.")
        }
    }

    @ViewBuilder
    private var featureComparisonTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)

                tierHeaderCell(tier: .free, label: "FREE")
                tierHeaderCell(tier: .pro, label: "PRO")
                tierHeaderCell(tier: .team, label: "TEAM")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Feature rows
            SubscriptionFeatureRow(
                feature: "Projects",
                freeValue: .text("1"),
                proValue: .text("2"),
                teamValue: .text("∞"),
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Feedback per Project",
                freeValue: .text("10"),
                proValue: .text("∞"),
                teamValue: .text("∞"),
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Integrations",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available,
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Advanced Analytics",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available,
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Custom Statuses",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available,
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Comment Notifications",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available,
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Team Members",
                freeValue: .unavailable,
                proValue: .unavailable,
                teamValue: .available,
                currentTier: displayTier
            )

            SubscriptionFeatureRow(
                feature: "Voter Notifications",
                freeValue: .unavailable,
                proValue: .unavailable,
                teamValue: .available,
                currentTier: displayTier,
                isLast: true
            )
        }
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tierHeaderCell(tier: SubscriptionTier, label: String) -> some View {
        let isCurrentTier = displayTier == tier
        let color: Color = {
            switch tier {
            case .free: return .secondary
            case .pro: return .purple
            case .team: return .blue
            }
        }()

        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)

            if isCurrentTier {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 55)
    }

    // MARK: - Upgrade Section

    /// Available tiers to upgrade to based on current tier
    private var availableUpgradeTiers: [SubscriptionTier] {
        switch displayTier {
        case .free:
            return [.pro, .team]
        case .pro:
            return [.team]
        case .team:
            return []
        }
    }

    @ViewBuilder
    private var upgradeSection: some View {
        Section {
            VStack(spacing: 12) {
                ForEach(availableUpgradeTiers, id: \.self) { tier in
                    UpgradeButton(tier: tier) {
                        paywallRequiredTier = tier
                        showPaywall = true
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Manage Subscription Section

    @ViewBuilder
    private var manageSubscriptionSection: some View {
        Section {
            Button {
                openStripePortal()
            } label: {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage Subscription")
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text("Change plan, update payment, or cancel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isLoadingPortal {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isLoadingPortal)
        } header: {
            Text("Subscription Management")
        } footer: {
            Text("You'll be redirected to Stripe to manage your subscription, update payment method, or cancel.")
        }
    }

    // MARK: - Refresh Section

    @ViewBuilder
    private var refreshSection: some View {
        Section {
            Button {
                Task {
                    await refreshSubscription()
                }
            } label: {
                HStack {
                    Spacer()
                    if subscriptionService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Refresh Subscription Status")
                    }
                    Spacer()
                }
            }
            .disabled(subscriptionService.isLoading)
        } footer: {
            Text("Refresh to sync your subscription status with the server.")
        }
    }

    // MARK: - Helpers

    private func tierGradient(for tier: SubscriptionTier) -> some View {
        Group {
            switch tier {
            case .free:
                Color.gray.opacity(0.3)
            case .pro:
                LinearGradient(
                    colors: [.purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .team:
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func tierIcon(for tier: SubscriptionTier) -> String {
        switch tier {
        case .free: return "person.fill"
        case .pro: return "crown.fill"
        case .team: return "person.3.fill"
        }
    }

    // MARK: - Actions

    private func openStripePortal() {
        // Get the auth token from secure storage
        guard let token = SecureStorageManager.shared.authToken else {
            errorMessage = "Please log in to manage your subscription"
            showError = true
            return
        }

        // URL encode the token to handle special characters
        // Note: .urlQueryAllowed doesn't encode +, /, = which are common in base64 tokens
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            errorMessage = "Invalid authentication token"
            showError = true
            return
        }

        // Build the portal URL with auth token
        let baseURL = appConfiguration.baseURL.replacingOccurrences(of: "/api/v1", with: "")
        let portalURL = "\(baseURL)/portal?token=\(encodedToken)"

        if let url = URL(string: portalURL) {
            openURL(url)
        }
    }

    private func refreshSubscription() async {
        await subscriptionService.syncWithServer()
    }
}

// MARK: - Subscription Feature Row

/// A row in the feature comparison table that highlights the current tier
struct SubscriptionFeatureRow: View {
    let feature: String
    let freeValue: FeatureValue
    let proValue: FeatureValue
    let teamValue: FeatureValue
    let currentTier: SubscriptionTier
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(feature)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                featureCell(freeValue, tier: .free)
                    .frame(width: 55)

                featureCell(proValue, tier: .pro)
                    .frame(width: 55)

                featureCell(teamValue, tier: .team)
                    .frame(width: 55)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if !isLast {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func featureCell(_ value: FeatureValue, tier: SubscriptionTier) -> some View {
        let isCurrentTier = currentTier == tier
        let color: Color = {
            switch tier {
            case .free: return .secondary
            case .pro: return .purple
            case .team: return .blue
            }
        }()

        Group {
            switch value {
            case .available:
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            case .unavailable:
                Image(systemName: "xmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary.opacity(0.4))
            case .text(let text):
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isCurrentTier ? color.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

// MARK: - Upgrade Button

/// A styled button for upgrading to a specific subscription tier
private struct UpgradeButton: View {
    let tier: SubscriptionTier
    let action: () -> Void

    private var icon: String {
        tier == .team ? "person.3.fill" : "crown.fill"
    }

    private var title: String {
        "Upgrade to \(tier.displayName)"
    }

    private var subtitle: String {
        switch tier {
        case .pro:
            return "2 projects, unlimited feedback, integrations"
        case .team:
            return "Unlimited projects, team collaboration"
        case .free:
            return ""
        }
    }

    private var backgroundColors: [Color] {
        tier == .team ? [.blue, .cyan] : [.purple, .pink]
    }

    private var iconBackgroundColor: Color {
        tier == .team ? .white.opacity(0.25) : .white.opacity(0.25)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon with contrasting background
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(iconBackgroundColor, in: RoundedRectangle(cornerRadius: 10))

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(UpgradeButtonStyle())
    }
}

// MARK: - Upgrade Button Style

private struct UpgradeButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Free User") {
    NavigationStack {
        SubscriptionView()
    }
}
