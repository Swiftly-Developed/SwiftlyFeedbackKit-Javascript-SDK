//
//  PaywallView.swift
//  SwiftlyFeedbackAdmin
//
//  Subscription paywall - opens web browser for Stripe checkout.
//

import SwiftUI

struct PaywallView: View {
    /// The minimum tier required for the feature that triggered the paywall
    let requiredTier: SubscriptionTier

    @Environment(\.appConfiguration) private var appConfiguration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var isYearly = true
    @State private var showError = false
    @State private var errorMessage = ""

    /// Initialize with a required tier (defaults to .pro for backwards compatibility)
    init(requiredTier: SubscriptionTier = .pro) {
        self.requiredTier = requiredTier
    }

    /// Available tiers to show based on requiredTier
    private var availableTiers: [SubscriptionTier] {
        switch requiredTier {
        case .free, .pro:
            return [.pro, .team]
        case .team:
            return [.team]
        }
    }

    var body: some View {
        NavigationStack {
            paywallContent
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                // Pre-select required tier if it's Team
                if requiredTier == .team {
                    selectedTier = .team
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Paywall Content

    @ViewBuilder
    private var paywallContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Logo with blur background
                logoSection

                // Billing period toggle
                billingPeriodToggle

                // Feature comparison table
                featureComparisonTable

                // Tier selection cards (with pricing)
                tierSelectionSection

                // Subscribe button (opens web)
                subscribeButton

                // Footer
                footerSection
            }
            .padding()
        }
    }

    // MARK: - Logo Section

    @ViewBuilder
    private var logoSection: some View {
        ZStack {
            // Dynamic blur background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.1), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .blur(radius: 20)

            VStack(spacing: 8) {
                Image(.feedbackKit)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("PREMIUM")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Billing Period Toggle

    @ViewBuilder
    private var billingPeriodToggle: some View {
        HStack(spacing: 4) {
            // Monthly button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isYearly = false
                }
            } label: {
                Text("Monthly")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(isYearly ? Color.clear : Color.accentColor)
                    .foregroundStyle(isYearly ? Color.secondary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(BillingToggleButtonStyle())

            // Yearly button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isYearly = true
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Yearly")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("-17%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isYearly ? Color.white.opacity(0.25) : Color.green.opacity(0.2))
                        .foregroundStyle(isYearly ? .white : .green)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(isYearly ? Color.accentColor : Color.clear)
                .foregroundStyle(isYearly ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(BillingToggleButtonStyle())
        }
        .padding(4)
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Feature Comparison Table

    @ViewBuilder
    private var featureComparisonTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("FREE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(width: 50)

                Text("PRO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.purple)
                    .frame(width: 50)

                Text("TEAM")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .frame(width: 50)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Feature rows
            FeatureComparisonRow(
                feature: "Projects",
                freeValue: .text("1"),
                proValue: .text("2"),
                teamValue: .text("∞")
            )

            FeatureComparisonRow(
                feature: "Feedback Requests",
                freeValue: .text("10"),
                proValue: .text("∞"),
                teamValue: .text("∞")
            )

            FeatureComparisonRow(
                feature: "Integrations",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available
            )

            FeatureComparisonRow(
                feature: "Advanced Analytics",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available
            )

            FeatureComparisonRow(
                feature: "Custom Statuses",
                freeValue: .unavailable,
                proValue: .available,
                teamValue: .available
            )

            FeatureComparisonRow(
                feature: "Team Members",
                freeValue: .unavailable,
                proValue: .unavailable,
                teamValue: .available
            )

            FeatureComparisonRow(
                feature: "Voter Notifications",
                freeValue: .unavailable,
                proValue: .unavailable,
                teamValue: .available,
                isLast: true
            )
        }
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tier Selection Section

    @ViewBuilder
    private var tierSelectionSection: some View {
        HStack(spacing: 12) {
            ForEach(availableTiers, id: \.self) { tier in
                WebTierSelectionCard(
                    tier: tier,
                    isYearly: isYearly,
                    isSelected: selectedTier == tier,
                    isRecommended: tier == .pro && availableTiers.count > 1
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTier = tier
                    }
                }
            }
        }
    }

    // MARK: - Subscribe Button

    @ViewBuilder
    private var subscribeButton: some View {
        let tierColor: Color = selectedTier == .team ? .blue : .purple

        Button {
            openWebSubscription()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text("Subscribe to \(selectedTier.displayName)")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(tierColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Footer Section

    @ViewBuilder
    private var footerSection: some View {
        VStack(spacing: 12) {
            Text("You'll be redirected to our secure checkout page powered by Stripe.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://swiftly-developed.com/feedback-kit-termsofservice")!)
                Link("Privacy Policy", destination: URL(string: "https://swiftly-developed.com/feedbackkit-privacypolicy")!)
            }
            .font(.caption)
        }
        .padding(.top, 8)
    }

    // MARK: - Web Subscription

    private func openWebSubscription() {
        // Get the auth token from secure storage
        guard let token = SecureStorageManager.shared.authToken else {
            errorMessage = "Please log in to subscribe"
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

        // Build the subscribe URL with auth token
        let baseURL = appConfiguration.baseURL.replacingOccurrences(of: "/api/v1", with: "")
        let subscribeURL = "\(baseURL)/subscribe?token=\(encodedToken)"

        if let url = URL(string: subscribeURL) {
            openURL(url)
            dismiss()
        }
    }
}

// MARK: - Web Tier Selection Card

struct WebTierSelectionCard: View {
    let tier: SubscriptionTier
    let isYearly: Bool
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    private var tierColor: Color {
        tier == .team ? .blue : .purple
    }

    private var tierIcon: String {
        tier == .team ? "person.3.fill" : "crown.fill"
    }

    private var priceText: String {
        switch (tier, isYearly) {
        case (.pro, false): return "$4.99/month"
        case (.pro, true): return "$49.99/year"
        case (.team, false): return "$9.99/month"
        case (.team, true): return "$99.99/year"
        default: return ""
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Recommended badge or spacer
                if isRecommended {
                    Text("Popular")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tierColor.opacity(0.2))
                        .foregroundStyle(tierColor)
                        .clipShape(Capsule())
                } else {
                    Text(" ")
                        .font(.caption2)
                        .padding(.vertical, 3)
                }

                Image(systemName: tierIcon)
                    .font(.title)
                    .foregroundStyle(tierColor)

                Text(tier.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(priceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? tierColor : .secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 160)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            #if os(iOS)
            .background(isSelected ? tierColor.opacity(0.12) : Color(UIColor.secondarySystemBackground))
            #else
            .background(isSelected ? tierColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? tierColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(TierCardButtonStyle())
    }
}

// MARK: - Feature Comparison Row

enum FeatureValue {
    case available
    case unavailable
    case text(String)
}

struct FeatureComparisonRow: View {
    let feature: String
    let freeValue: FeatureValue
    let proValue: FeatureValue
    let teamValue: FeatureValue
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(feature)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                featureCell(freeValue, color: .secondary)
                    .frame(width: 50)

                featureCell(proValue, color: .purple)
                    .frame(width: 50)

                featureCell(teamValue, color: .blue)
                    .frame(width: 50)
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
    private func featureCell(_ value: FeatureValue, color: Color) -> some View {
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
}

// MARK: - Tier Card Button Style

struct TierCardButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Billing Toggle Button Style

struct BillingToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("Pro Required") {
    PaywallView(requiredTier: .pro)
}

#Preview("Team Required") {
    PaywallView(requiredTier: .team)
}
