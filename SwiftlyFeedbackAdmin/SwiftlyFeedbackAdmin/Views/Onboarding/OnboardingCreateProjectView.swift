import SwiftUI

struct OnboardingCreateProjectView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onBack: () -> Void

    private enum Field: Hashable {
        case name, description
    }

    @FocusState private var focusedField: Field?
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
                                        colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: iconBackgroundSize, height: iconBackgroundSize)

                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: iconSize))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .accessibilityHidden(true)
                        }

                        VStack(spacing: 4) {
                            Text("Create Your Project")
                                .font(titleFont)
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)

                            Text("Set up a project to start collecting feedback from your users")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 8)

                    // Form Fields
                    #if os(macOS)
                    macOSFormFields
                    #else
                    iOSFormFields
                    #endif

                    // Info Card
                    OnboardingInfoCard(
                        icon: "key.fill",
                        iconColor: .orange,
                        title: "API Key",
                        description: "After creating your project, you'll receive an API key to integrate the SDK into your app."
                    )

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom buttons
            VStack(spacing: 16) {
                Button {
                    Task {
                        await viewModel.createProject()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: buttonMaxWidth)
                            .frame(minHeight: 44)
                    } else {
                        Text("Create Project")
                            .font(.headline)
                            .frame(maxWidth: buttonMaxWidth)
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isProjectNameValid || viewModel.isLoading)
                .accessibilityHint(viewModel.isProjectNameValid ? "Create your new project" : "Enter a project name to continue")

                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .accessibilityLabel("Go back to project choice")
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(bottomBackground)
        }
        .onAppear {
            #if os(iOS)
            focusedField = .name
            #endif
        }
    }

    // MARK: - iOS Form Fields

    #if os(iOS)
    private var iOSFormFields: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Project Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextField("My Awesome App", text: $viewModel.newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .description
                    }
                    .accessibilityLabel("Project name")
                    .accessibilityHint("Enter the name for your new project")

                Text("This is how your project will appear to your team")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("(Optional)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                TextField("A brief description of your project", text: $viewModel.newProjectDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .description)
                    .lineLimit(3...6)
                    .submitLabel(.done)
                    .onSubmit {
                        if viewModel.isProjectNameValid {
                            Task { await viewModel.createProject() }
                        }
                    }
                    .accessibilityLabel("Project description, optional")
                    .accessibilityHint("Enter a brief description to help your team understand what this project is for")

                Text("Help your team understand what this project is for")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    #endif

    // MARK: - macOS Form Fields

    #if os(macOS)
    private var macOSFormFields: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Project Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextField("My Awesome App", text: $viewModel.newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
                    .onSubmit {
                        focusedField = .description
                    }

                Text("This is how your project will appear to your team")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("(Optional)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                TextField("A brief description of your project", text: $viewModel.newProjectDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .description)
                    .lineLimit(3...6)

                Text("Help your team understand what this project is for")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    #endif

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
        return 16
        #else
        return isCompactWidth ? 16 : 20
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
        return 420
        #else
        return isCompactWidth ? .infinity : 480
        #endif
    }

    private var buttonMaxWidth: CGFloat {
        #if os(macOS)
        return 280
        #else
        return isCompactWidth ? .infinity : 320
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

// MARK: - Info Card Component

private struct OnboardingInfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

#Preview("iPhone") {
    OnboardingCreateProjectView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        onBack: {}
    )
}

#Preview("iPad") {
    OnboardingCreateProjectView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        onBack: {}
    )
}
