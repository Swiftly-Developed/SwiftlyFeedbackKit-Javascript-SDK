import SwiftUI

struct AuthContainerView: View {
    @Bindable var viewModel: AuthViewModel
    @State private var showingSignup = false

    var body: some View {
        ScrollView {
            VStack {
                Spacer(minLength: 40)

                if showingSignup {
                    SignupView(viewModel: viewModel) {
                        withAnimation {
                            showingSignup = false
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    LoginView(viewModel: viewModel) {
                        withAnimation {
                            showingSignup = true
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.secondary.opacity(0.1))
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }
}

#Preview {
    AuthContainerView(viewModel: AuthViewModel())
}
