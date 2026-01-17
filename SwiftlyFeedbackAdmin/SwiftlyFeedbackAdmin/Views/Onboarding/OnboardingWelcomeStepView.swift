//
//  OnboardingWelcomeStepView.swift
//  SwiftlyFeedbackAdmin
//
//  Reusable component for welcome onboarding steps.
//

import SwiftUI

/// Shared view for welcome steps with consistent styling
struct OnboardingWelcomeStepView: View {
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String
    let features: [(icon: String, title: String, description: String)]
    let primaryButtonTitle: String
    let onContinue: () -> Void
    var onBack: (() -> Void)?
    var onLogin: (() -> Void)?

    @State private var animateContent = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: contentSpacing) {
                    Spacer(minLength: 16)

                    // Icon and Title
                    VStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: iconSize))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: iconColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(animateContent ? 1 : 0.8)
                            .opacity(animateContent ? 1 : 0)

                        VStack(spacing: 6) {
                            Text(title)
                                .font(titleFont)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)

                            Text(subtitle)
                                .font(subtitleFont)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                    }
                    .padding(.horizontal, horizontalPadding)

                    // Features
                    if isCompactWidth {
                        VStack(spacing: 12) {
                            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                                WelcomeFeatureRow(
                                    icon: feature.icon,
                                    title: feature.title,
                                    description: feature.description,
                                    iconColors: iconColors
                                )
                                .opacity(animateContent ? 1 : 0)
                                .offset(x: animateContent ? 0 : -20)
                                .animation(
                                    .easeOut(duration: 0.4).delay(Double(index) * 0.08),
                                    value: animateContent
                                )
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                                WelcomeFeatureCard(
                                    icon: feature.icon,
                                    title: feature.title,
                                    description: feature.description,
                                    iconColors: iconColors
                                )
                                .opacity(animateContent ? 1 : 0)
                                .scaleEffect(animateContent ? 1 : 0.95)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.08),
                                    value: animateContent
                                )
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom buttons
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if let onBack {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        onContinue()
                    } label: {
                        Text(primaryButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: buttonMaxWidth)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if let onLogin {
                    Button {
                        onLogin()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundStyle(.secondary)
                            Text("Log In")
                                .fontWeight(.medium)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(bottomBackground)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }

    // MARK: - Platform-Adaptive Properties

    private var isCompactWidth: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        return 48
        #else
        return isCompactWidth ? 44 : 52
        #endif
    }

    private var titleFont: Font {
        #if os(macOS)
        return .title2
        #else
        return isCompactWidth ? .title3 : .title2
        #endif
    }

    private var subtitleFont: Font {
        #if os(macOS)
        return .body
        #else
        return isCompactWidth ? .subheadline : .body
        #endif
    }

    private var contentSpacing: CGFloat {
        #if os(macOS)
        return 20
        #else
        return isCompactWidth ? 18 : 24
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 32
        #else
        return isCompactWidth ? 20 : 32
        #endif
    }

    private var maxContentWidth: CGFloat {
        #if os(macOS)
        return 560
        #else
        return isCompactWidth ? .infinity : 640
        #endif
    }

    private var buttonMaxWidth: CGFloat {
        #if os(macOS)
        return 240
        #else
        return isCompactWidth ? .infinity : 280
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(macOS)
        return 24
        #else
        return isCompactWidth ? 16 : 24
        #endif
    }

    private var bottomBackground: some ShapeStyle {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

// MARK: - Feature Row (Compact)

private struct WelcomeFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let iconColors: [Color]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: iconColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

// MARK: - Feature Card (Regular)

private struct WelcomeFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let iconColors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: iconColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private var cardBackground: some ShapeStyle {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

#Preview {
    OnboardingWelcomeStepView(
        icon: "bubble.left.and.bubble.right.fill",
        iconColors: [.blue, .purple],
        title: "Collect Feedback",
        subtitle: "Gather valuable insights from your users",
        features: [
            ("star.fill", "Feature Requests", "Collect ideas from users"),
            ("ladybug.fill", "Bug Reports", "Track issues efficiently")
        ],
        primaryButtonTitle: "Continue",
        onContinue: {},
        onBack: {},
        onLogin: {}
    )
}
