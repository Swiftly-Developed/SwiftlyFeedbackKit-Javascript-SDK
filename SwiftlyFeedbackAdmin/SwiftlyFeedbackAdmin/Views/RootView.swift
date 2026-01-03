import SwiftUI

struct RootView: View {
    @State private var authViewModel = AuthViewModel()

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                if authViewModel.needsEmailVerification {
                    EmailVerificationView(viewModel: authViewModel)
                } else {
                    MainTabView(authViewModel: authViewModel)
                }
            } else {
                AuthContainerView(viewModel: authViewModel)
            }
        }
        .animation(.default, value: authViewModel.isAuthenticated)
        .animation(.default, value: authViewModel.needsEmailVerification)
    }
}

#Preview {
    RootView()
}
