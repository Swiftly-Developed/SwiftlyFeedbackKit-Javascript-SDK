//
//  OnboardingWelcomeView.swift
//  SwiftlyFeedbackAdmin
//
//  Welcome Step 1: Introduction to Feedback Kit
//

import SwiftUI

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void
    let onLogin: () -> Void

    @State private var animateContent = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: contentSpacing) {
                    Spacer(minLength: 16)

                    // App Logo and Title
                    VStack(spacing: 12) {
                        Image("FeedbackKit")
                            .resizable()
                            .scaledToFit()
                            .frame(width: logoSize, height: logoSize)
                            .clipShape(RoundedRectangle(cornerRadius: logoCornerRadius))
                            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
                            .scaleEffect(animateContent ? 1 : 0.8)
                            .opacity(animateContent ? 1 : 0)

                        VStack(spacing: 6) {
                            Text("Feedback Kit")
                                .font(titleFont)
                                .fontWeight(.bold)

                            Text("The feedback platform for modern apps")
                                .font(subtitleFont)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                    }

                    // Feature highlights
                    VStack(spacing: isCompactWidth ? 10 : 12) {
                        ForEach(Array(highlights.enumerated()), id: \.offset) { index, highlight in
                            HighlightRow(icon: highlight.icon, text: highlight.text)
                                .opacity(animateContent ? 1 : 0)
                                .offset(x: animateContent ? 0 : -20)
                                .animation(
                                    .easeOut(duration: 0.4).delay(Double(index) * 0.08),
                                    value: animateContent
                                )
                        }
                    }
                    .padding(.horizontal, horizontalPadding)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom buttons
            VStack(spacing: 12) {
                Button {
                    onContinue()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: buttonMaxWidth)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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

    private var highlights: [(icon: String, text: String)] {
        [
            ("bubble.left.and.bubble.right.fill", "Collect feature requests and bug reports"),
            ("chart.bar.xaxis", "Track analytics and prioritize by impact"),
            ("person.3.fill", "Collaborate with your team"),
            ("arrow.triangle.branch", "Sync with GitHub, Linear, Notion & more")
        ]
    }

    // MARK: - Platform-Adaptive Properties

    private var isCompactWidth: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var logoSize: CGFloat {
        #if os(macOS)
        return 80
        #else
        return isCompactWidth ? 80 : 100
        #endif
    }

    private var logoCornerRadius: CGFloat {
        logoSize * 0.22
    }

    private var titleFont: Font {
        #if os(macOS)
        return .title
        #else
        return isCompactWidth ? .title2 : .title
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
        return 480
        #else
        return isCompactWidth ? .infinity : 520
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

// MARK: - Highlight Row

private struct HighlightRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

#Preview("iPhone") {
    OnboardingWelcomeView(
        onContinue: {},
        onLogin: {}
    )
}

#Preview("iPad") {
    OnboardingWelcomeView(
        onContinue: {},
        onLogin: {}
    )
}
