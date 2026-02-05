//
//  OnboardingPaywallView.swift
//  SwiftlyFeedbackAdmin
//
//  Paywall step during onboarding - opens web browser for Stripe checkout.
//

import SwiftUI

struct OnboardingPaywallView: View {
    let onContinue: () -> Void

    @Environment(\.appConfiguration) private var appConfiguration
    @Environment(\.openURL) private var openURL
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var isYearly = true
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        paywallContent
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Paywall Content

    @ViewBuilder
    private var paywallContent: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: contentSpacing) {
                    Spacer(minLength: 16)

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: iconSize))
                            .foregroundStyle(.linearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))

                        Text("Unlock More Features")
                            .font(titleFont)
                            .fontWeight(.bold)

                        Text("Choose a plan that works for you")
                            .font(subtitleFont)
                            .foregroundStyle(.secondary)
                    }

                    // Billing toggle
                    billingPeriodToggle
                        .padding(.horizontal, horizontalPadding)

                    // Feature comparison (compact)
                    compactFeatureComparison
                        .padding(.horizontal, horizontalPadding)

                    // Tier selection + pricing
                    tierSelectionSection
                        .padding(.horizontal, horizontalPadding)

                    // Subscribe button
                    subscribeSection
                        .padding(.horizontal, horizontalPadding)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom buttons
            VStack(spacing: 8) {
                // Continue Free button
                Button {
                    onContinue()
                } label: {
                    Text("Continue with Free")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        #if os(iOS)
                        .background(Color(UIColor.secondarySystemBackground))
                        #else
                        .background(Color(NSColor.controlBackgroundColor))
                        #endif
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(OnboardingTierCardButtonStyle())

                // Footer
                footerSection
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(bottomBackground)
        }
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
                    .frame(minHeight: 40)
                    .background(isYearly ? Color.clear : Color.accentColor)
                    .foregroundStyle(isYearly ? Color.secondary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(OnboardingBillingToggleButtonStyle())

            // Yearly button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isYearly = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Yearly")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("-17%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isYearly ? Color.white.opacity(0.25) : Color.green.opacity(0.2))
                        .foregroundStyle(isYearly ? .white : .green)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .background(isYearly ? Color.accentColor : Color.clear)
                .foregroundStyle(isYearly ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(OnboardingBillingToggleButtonStyle())
        }
        .padding(4)
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Compact Feature Comparison

    @ViewBuilder
    private var compactFeatureComparison: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("FREE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                Text("PRO")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.purple)
                    .frame(width: 44)
                Text("TEAM")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .frame(width: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            CompactFeatureRow(feature: "Projects", free: "1", pro: "2", team: "∞")
            CompactFeatureRow(feature: "Feedback", free: "10", pro: "∞", team: "∞")
            CompactFeatureRow(feature: "Integrations", freeOK: false, proOK: true, teamOK: true)
            CompactFeatureRow(feature: "Team Members", freeOK: false, proOK: false, teamOK: true, isLast: true)
        }
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Tier Selection Section

    @ViewBuilder
    private var tierSelectionSection: some View {
        HStack(spacing: 10) {
            OnboardingTierCard(
                tier: .pro,
                isYearly: isYearly,
                isSelected: selectedTier == .pro,
                isRecommended: true
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTier = .pro
                }
            }

            OnboardingTierCard(
                tier: .team,
                isYearly: isYearly,
                isSelected: selectedTier == .team,
                isRecommended: false
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTier = .team
                }
            }
        }
    }

    // MARK: - Subscribe Section

    @ViewBuilder
    private var subscribeSection: some View {
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
            .frame(minHeight: 50)
            .background(tierColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(OnboardingTierCardButtonStyle())
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Secure checkout powered by Stripe")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Link("Terms", destination: URL(string: "https://swiftly-developed.com/feedback-kit-termsofservice")!)
                Link("Privacy", destination: URL(string: "https://swiftly-developed.com/feedbackkit-privacypolicy")!)
            }
            .font(.caption2)
        }
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
            // Continue after opening web
            onContinue()
        }
    }

    // MARK: - Adaptive Layout

    private var contentSpacing: CGFloat {
        horizontalSizeClass == .compact ? 16 : 20
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 20 : 32
    }

    private var iconSize: CGFloat {
        horizontalSizeClass == .compact ? 44 : 52
    }

    private var titleFont: Font {
        horizontalSizeClass == .compact ? .title2 : .title
    }

    private var subtitleFont: Font {
        horizontalSizeClass == .compact ? .subheadline : .body
    }

    private var maxContentWidth: CGFloat {
        500
    }

    private var bottomPadding: CGFloat {
        #if os(iOS)
        return 8
        #else
        return 16
        #endif
    }

    @ViewBuilder
    private var bottomBackground: some View {
        #if os(iOS)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}

// MARK: - Onboarding Tier Card

struct OnboardingTierCard: View {
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
        case (.pro, false): return "$15/mo"
        case (.pro, true): return "$150/yr"
        case (.team, false): return "$39/mo"
        case (.team, true): return "$390/yr"
        default: return ""
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                if isRecommended {
                    Text("Popular")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tierColor.opacity(0.2))
                        .foregroundStyle(tierColor)
                        .clipShape(Capsule())
                } else {
                    Text(" ")
                        .font(.caption2)
                        .padding(.vertical, 2)
                }

                Image(systemName: tierIcon)
                    .font(.title2)
                    .foregroundStyle(tierColor)

                Text(tier.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(priceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? tierColor : .secondary.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 130)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            #if os(iOS)
            .background(isSelected ? tierColor.opacity(0.12) : Color(UIColor.secondarySystemBackground))
            #else
            .background(isSelected ? tierColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? tierColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(OnboardingTierCardButtonStyle())
    }
}

// MARK: - Compact Feature Row

struct CompactFeatureRow: View {
    let feature: String
    var free: String? = nil
    var pro: String? = nil
    var team: String? = nil
    var freeOK: Bool? = nil
    var proOK: Bool? = nil
    var teamOK: Bool? = nil
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(feature)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)

                cellView(text: free, ok: freeOK, color: .secondary)
                    .frame(width: 44)
                cellView(text: pro, ok: proOK, color: .purple)
                    .frame(width: 44)
                cellView(text: team, ok: teamOK, color: .blue)
                    .frame(width: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !isLast {
                Divider()
                    .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private func cellView(text: String?, ok: Bool?, color: Color) -> some View {
        if let text = text {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        } else if let ok = ok {
            Image(systemName: ok ? "checkmark" : "xmark")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(ok ? color : .secondary.opacity(0.4))
        }
    }
}

// MARK: - Button Styles

struct OnboardingTierCardButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct OnboardingBillingToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingPaywallView {
        print("Continue tapped")
    }
}
