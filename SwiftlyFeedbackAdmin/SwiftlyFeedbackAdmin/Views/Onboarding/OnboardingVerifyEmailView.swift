import SwiftUI

struct OnboardingVerifyEmailView: View {
    @Bindable var viewModel: OnboardingViewModel
    let userEmail: String?
    let onLogout: () -> Void

    @FocusState private var isCodeFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: platformSpacing) {
                    Spacer(minLength: 16)

                    // Header with Animation
                    VStack(spacing: 12) {
                        ZStack {
                            // Animated circles
                            ForEach(0..<2, id: \.self) { index in
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                                    .frame(
                                        width: iconBackgroundSize + CGFloat(index * 16),
                                        height: iconBackgroundSize + CGFloat(index * 16)
                                    )
                                    .opacity(0.5 - Double(index) * 0.2)
                            }

                            Image(systemName: "envelope.badge.fill")
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
                        .frame(height: iconBackgroundSize + 24)

                        VStack(spacing: 8) {
                            Text("Verify Your Email")
                                .font(titleFont)
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)

                            Text("We sent a verification code to")
                                .foregroundStyle(.secondary)

                            if let email = userEmail {
                                Text(email)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .multilineTextAlignment(.center)
                    }

                    // Code Input Section
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Verification Code")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            TextField("Enter 8-character code", text: $viewModel.verificationCode)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.oneTimeCode)
                                .autocorrectionDisabled()
                                .focused($isCodeFocused)
                                .multilineTextAlignment(.center)
                                .font(.system(.title2, design: .monospaced))
                                #if os(iOS)
                                .textInputAutocapitalization(.characters)
                                .keyboardType(.asciiCapable)
                                #endif
                                .onChange(of: viewModel.verificationCode) { _, newValue in
                                    let filtered = String(newValue.uppercased().prefix(8))
                                    if filtered != newValue {
                                        viewModel.verificationCode = filtered
                                    }
                                }
                                .onSubmit {
                                    if viewModel.isVerificationCodeValid {
                                        Task { await viewModel.verifyEmail() }
                                    }
                                }
                                .submitLabel(.go)
                                .accessibilityLabel("Verification code input")
                                .accessibilityHint("Enter the 8-character code from your email")

                            // Code format helper
                            HStack {
                                Spacer()
                                Text("\(viewModel.verificationCode.count)/8 characters")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.verificationCode.count == 8 ? .green : .secondary)
                                Spacer()
                            }
                            .accessibilityHidden(true)
                        }
                    }

                    // Resend Section
                    VStack(spacing: 12) {
                        Divider()
                            .padding(.vertical, 8)

                        Text("Didn't receive the code?")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)

                        resendButtons
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom buttons
            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.verifyEmail()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: buttonMaxWidth)
                            .frame(minHeight: 44)
                    } else {
                        Text("Verify Email")
                            .font(.headline)
                            .frame(maxWidth: buttonMaxWidth)
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isVerificationCodeValid || viewModel.isLoading)
                .accessibilityHint(viewModel.isVerificationCodeValid ? "Verify your email address" : "Enter the complete verification code first")

                // Sign Out Option
                Button {
                    onLogout()
                } label: {
                    HStack(spacing: 4) {
                        Text("Wrong email?")
                            .foregroundStyle(.secondary)
                        Text("Sign Out")
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .accessibilityLabel("Sign out and go back to registration")
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
            isCodeFocused = true
            #endif
        }
    }

    // MARK: - Resend Buttons

    @ViewBuilder
    private var resendButtons: some View {
        #if os(macOS)
        // macOS: Horizontal layout with proper spacing
        HStack(spacing: 24) {
            Button {
                Task {
                    await viewModel.resendVerificationCode()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    if viewModel.resendCooldown > 0 {
                        Text("Resend in \(viewModel.resendCooldown)s")
                    } else {
                        Text("Resend Code")
                    }
                }
            }
            .disabled(viewModel.isLoading || viewModel.resendCooldown > 0)

            Text("or check your spam folder")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        #else
        // iOS: Stack vertically on compact, horizontal on regular
        if isCompactWidth {
            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.resendVerificationCode()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        if viewModel.resendCooldown > 0 {
                            Text("Resend in \(viewModel.resendCooldown)s")
                        } else {
                            Text("Resend Code")
                        }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(viewModel.isLoading || viewModel.resendCooldown > 0)

                Text("Also check your spam folder")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .font(.subheadline)
        } else {
            HStack(spacing: 24) {
                Button {
                    Task {
                        await viewModel.resendVerificationCode()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        if viewModel.resendCooldown > 0 {
                            Text("Resend in \(viewModel.resendCooldown)s")
                        } else {
                            Text("Resend Code")
                        }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(viewModel.isLoading || viewModel.resendCooldown > 0)

                Text("or check your spam folder")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        #endif
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

#Preview("iPhone") {
    OnboardingVerifyEmailView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        userEmail: "user@example.com",
        onLogout: {}
    )
}

#Preview("iPad") {
    OnboardingVerifyEmailView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        userEmail: "user@example.com",
        onLogout: {}
    )
}
