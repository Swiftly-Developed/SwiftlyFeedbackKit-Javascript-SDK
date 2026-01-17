import SwiftUI

struct OnboardingProjectChoiceView: View {
    @Bindable var viewModel: OnboardingViewModel
    let userName: String?

    @State private var animateCards = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: platformSpacing) {
                    Spacer(minLength: 16)

                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.green.opacity(0.2), .blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: iconBackgroundSize, height: iconBackgroundSize)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: iconSize))
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                        }

                        VStack(spacing: 4) {
                            if let name = userName {
                                Text("Welcome, \(name)!")
                                    .font(titleFont)
                                    .fontWeight(.bold)
                                    .accessibilityAddTraits(.isHeader)
                            } else {
                                Text("Welcome!")
                                    .font(titleFont)
                                    .fontWeight(.bold)
                                    .accessibilityAddTraits(.isHeader)
                            }

                            Text("Your account is ready. Now let's set up your first project.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 8)

                    // Choice Cards
                    VStack(spacing: 16) {
                        Text("How would you like to get started?")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        // Adaptive layout for cards
                        if isCompactWidth {
                            // iPhone: Vertical stack
                            VStack(spacing: 16) {
                                projectChoiceCards
                            }
                        } else {
                            // iPad/Mac: Horizontal layout
                            HStack(spacing: 20) {
                                projectChoiceCards
                            }
                            .frame(maxWidth: 700)
                        }
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom buttons
            VStack(spacing: 8) {
                Text("Not sure yet?")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.skipProjectSetup()
                } label: {
                    Text("Skip for now")
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
                .font(.subheadline)
                .accessibilityLabel("Skip project setup for now")
                .accessibilityHint("You can create or join a project later from the Projects tab")
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
                animateCards = true
            }
        }
    }

    // MARK: - Choice Cards

    @ViewBuilder
    private var projectChoiceCards: some View {
        // Create Project Card
        ProjectChoiceCard(
            icon: "plus.rectangle.fill",
            iconColor: .blue,
            title: "Create a New Project",
            description: "Start fresh and set up a project for your app or product",
            isCompact: isCompactWidth,
            action: {
                viewModel.selectProjectChoice(.create)
            }
        )
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .accessibilityLabel("Create a new project")
        .accessibilityHint("Start fresh and set up a project for your app or product")

        // Join Project Card
        ProjectChoiceCard(
            icon: "person.badge.plus.fill",
            iconColor: .purple,
            title: "Join an Existing Project",
            description: "Have an invite code? Join a team's project",
            isCompact: isCompactWidth,
            action: {
                viewModel.selectProjectChoice(.join)
            }
        )
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateCards)
        .accessibilityLabel("Join an existing project")
        .accessibilityHint("Enter an invite code to join a team's project")
    }

    // MARK: - Platform-Adaptive Properties

    private var isCompactWidth: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var iconBackgroundSize: CGFloat {
        #if os(macOS)
        return 60
        #else
        return isCompactWidth ? 60 : 72
        #endif
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        return 28
        #else
        return isCompactWidth ? 28 : 32
        #endif
    }

    private var titleFont: Font {
        #if os(macOS)
        return .title2
        #else
        return isCompactWidth ? .title3 : .title2
        #endif
    }

    private var platformSpacing: CGFloat {
        #if os(macOS)
        return 18
        #else
        return isCompactWidth ? 18 : 24
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 40
        #else
        return isCompactWidth ? 24 : 40
        #endif
    }

    private var maxContentWidth: CGFloat {
        #if os(macOS)
        return 700
        #else
        return isCompactWidth ? .infinity : 800
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(macOS)
        return 20
        #else
        return isCompactWidth ? 12 : 20
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

// MARK: - Choice Card Component

private struct ProjectChoiceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isCompact: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if isCompact {
                // iPhone: Horizontal layout
                HStack(spacing: 16) {
                    iconView
                    textContent
                    Spacer()
                    chevron
                }
                .padding(16)
                .frame(minHeight: 88) // Ensure comfortable touch area
            } else {
                // iPad/Mac: Vertical card layout
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        iconView
                        Spacer()
                        chevron
                    }
                    textContent
                }
                .padding(20)
                .frame(minHeight: 140)
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHovered ? iconColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: isCompact ? 28 : 32))
            .foregroundStyle(iconColor)
            .frame(width: isCompact ? 56 : 64, height: isCompact ? 56 : 64)
            .background(iconColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var backgroundFill: some ShapeStyle {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

#Preview("iPhone") {
    OnboardingProjectChoiceView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        userName: "John"
    )
}

#Preview("iPad") {
    OnboardingProjectChoiceView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        userName: "John"
    )
}
