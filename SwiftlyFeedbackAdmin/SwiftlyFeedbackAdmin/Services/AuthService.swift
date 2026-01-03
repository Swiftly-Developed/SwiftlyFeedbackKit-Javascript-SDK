import Foundation
import OSLog

private let logger = Logger(subsystem: "com.swiftlyfeedback.admin", category: "AuthService")

actor AuthService {
    static let shared = AuthService()

    private init() {
        logger.info("AuthService initialized")
    }

    func signup(email: String, name: String, password: String) async throws -> AuthResponse {
        logger.info("📝 Starting signup for email: \(email)")
        let request = SignupRequest(email: email, name: name, password: password)
        do {
            let response: AuthResponse = try await AdminAPIClient.shared.post(
                path: "auth/signup",
                body: request,
                requiresAuth: false
            )
            logger.info("✅ Signup successful for user: \(response.user.id)")

            // Save token
            try KeychainService.saveToken(response.token)
            logger.info("🔑 Token saved to keychain")

            return response
        } catch {
            logger.error("❌ Signup failed: \(error.localizedDescription)")
            throw error
        }
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        logger.info("🔐 Starting login for email: \(email)")
        let request = LoginRequest(email: email, password: password)
        do {
            let response: AuthResponse = try await AdminAPIClient.shared.post(
                path: "auth/login",
                body: request,
                requiresAuth: false
            )
            logger.info("✅ Login successful for user: \(response.user.id), isEmailVerified: \(response.user.isEmailVerified)")

            // Save token
            try KeychainService.saveToken(response.token)
            logger.info("🔑 Token saved to keychain")

            return response
        } catch {
            logger.error("❌ Login failed: \(error.localizedDescription)")
            throw error
        }
    }

    func logout() async throws {
        logger.info("🚪 Starting logout")
        do {
            try await AdminAPIClient.shared.post(path: "auth/logout", requiresAuth: true)
            logger.info("✅ Server logout successful")
        } catch {
            logger.warning("⚠️ Server logout failed (will clear token anyway): \(error.localizedDescription)")
            // Even if server logout fails, clear local token
        }
        // Run on main thread to ensure Keychain access is reliable
        await MainActor.run {
            KeychainService.deleteToken()
            logger.info("🔑 Token deleted from keychain")
        }
    }

    func getCurrentUser() async throws -> User {
        logger.info("👤 Fetching current user")
        do {
            let user: User = try await AdminAPIClient.shared.get(path: "auth/me")
            logger.info("✅ Got current user: \(user.id), isEmailVerified: \(user.isEmailVerified)")
            return user
        } catch {
            logger.error("❌ Failed to get current user: \(error.localizedDescription)")
            throw error
        }
    }

    func isLoggedIn() -> Bool {
        let hasToken = KeychainService.getToken() != nil
        logger.debug("🔍 isLoggedIn check: \(hasToken)")
        return hasToken
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        logger.info("🔄 Starting password change")
        let request = ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)
        do {
            try await AdminAPIClient.shared.put(path: "auth/password", body: request, requiresAuth: true)
            logger.info("✅ Password changed successfully")
            // Password changed successfully, token is invalidated - clear local token
            // Run on main thread to ensure Keychain access is reliable
            await MainActor.run {
                KeychainService.deleteToken()
                logger.info("🔑 Token deleted from keychain after password change")
            }
        } catch {
            logger.error("❌ Password change failed: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteAccount(password: String) async throws {
        logger.info("🗑️ Starting account deletion")
        let request = DeleteAccountRequest(password: password)
        do {
            try await AdminAPIClient.shared.delete(path: "auth/account", body: request, requiresAuth: true)
            logger.info("✅ Account deleted successfully")
            // Run on main thread to ensure Keychain access is reliable
            await MainActor.run {
                KeychainService.deleteToken()
                logger.info("🔑 Token deleted from keychain after account deletion")
            }
        } catch {
            logger.error("❌ Account deletion failed: \(error.localizedDescription)")
            throw error
        }
    }

    func verifyEmail(code: String) async throws -> VerifyEmailResponse {
        logger.info("✉️ Starting email verification with code: \(code)")
        let request = VerifyEmailRequest(code: code)
        do {
            let response: VerifyEmailResponse = try await AdminAPIClient.shared.post(
                path: "auth/verify-email",
                body: request,
                requiresAuth: false
            )
            logger.info("✅ Email verified successfully for user: \(response.user.id)")
            return response
        } catch {
            logger.error("❌ Email verification failed: \(error.localizedDescription)")
            throw error
        }
    }

    func resendVerification() async throws -> MessageResponse {
        logger.info("📧 Requesting verification email resend")
        do {
            let response: MessageResponse = try await AdminAPIClient.shared.post(path: "auth/resend-verification", requiresAuth: true)
            logger.info("✅ Verification email resent: \(response.message)")
            return response
        } catch {
            logger.error("❌ Resend verification failed: \(error.localizedDescription)")
            throw error
        }
    }
}
