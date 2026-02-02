import Vapor
import Fluent
import Leaf

struct WebAuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.get("signup", use: signupPage)
        routes.post("signup", use: signup)
        routes.get("forgot-password", use: forgotPasswordPage)
        routes.post("forgot-password", use: forgotPassword)
        routes.get("reset-password", use: resetPasswordPage)
        routes.post("reset-password", use: resetPassword)

        // Routes that need session (for verify-email and logout)
        let sessionProtected = routes.grouped(WebSessionAuthMiddleware())
        sessionProtected.get("verify-email", use: verifyEmailPage)
        sessionProtected.post("verify-email", use: verifyEmail)
        sessionProtected.post("resend-verification", use: resendVerification)
        sessionProtected.post("logout", use: logout)
    }

    // MARK: - Login

    @Sendable
    func loginPage(req: Request) async throws -> View {
        // If already logged in, redirect to dashboard
        if let sessionToken = req.cookies["feedbackkit_session"]?.string,
           let session = try await WebSession.query(on: req.db)
               .filter(\.$sessionToken == sessionToken)
               .with(\.$user)
               .first(),
           !session.isExpired {
            throw Abort.redirect(to: "/admin/dashboard")
        }

        let (envName, envColor) = getEnvironmentDisplay()
        return try await req.view.render("auth/login", LoginContext(
            title: "Sign In",
            error: nil,
            formData: LoginFormData(),
            environment: envName,
            environmentColor: envColor
        ))
    }

    private func getEnvironmentDisplay() -> (name: String, color: String) {
        let env = AppEnvironment.shared
        switch env.type {
        case .local:
            return ("Local", "bg-gray-500")
        case .development:
            return ("Development", "bg-blue-500")
        case .staging:
            return ("TestFlight", "bg-orange-500")
        case .production:
            return ("Production", "bg-green-500")
        }
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        let form = try req.content.decode(WebLoginRequest.self)

        // Find user
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == form.email.lowercased())
            .first() else {
            return try await renderLoginError(req: req, error: "Invalid email or password", email: form.email)
        }

        // Verify password
        guard try user.verify(password: form.password) else {
            return try await renderLoginError(req: req, error: "Invalid email or password", email: form.email)
        }

        // Create web session
        let session = try WebSession.generate(
            for: user,
            expiresIn: form.remember ? 60 * 60 * 24 * 30 : 60 * 60 * 24 // 30 days or 1 day
        )
        session.userAgent = req.headers.first(name: .userAgent)
        session.ipAddress = req.remoteAddress?.ipAddress

        try await session.save(on: req.db)

        // Set session cookie
        var response = req.redirect(to: user.isEmailVerified ? "/admin/dashboard" : "/admin/verify-email")
        response.cookies["feedbackkit_session"] = HTTPCookies.Value(
            string: session.sessionToken,
            expires: session.expiresAt,
            maxAge: nil,
            domain: nil,
            path: "/",
            isSecure: req.application.environment != .development,
            isHTTPOnly: true,
            sameSite: .lax
        )

        return response
    }

    private func renderLoginError(req: Request, error: String, email: String) async throws -> Response {
        let (envName, envColor) = getEnvironmentDisplay()
        let view = try await req.view.render("auth/login", LoginContext(
            title: "Sign In",
            error: error,
            formData: LoginFormData(email: email),
            environment: envName,
            environmentColor: envColor
        ))
        var response = try await view.encodeResponse(for: req).get()
        response.status = .unauthorized
        return response
    }

    // MARK: - Signup

    @Sendable
    func signupPage(req: Request) async throws -> View {
        return try await req.view.render("auth/signup", SignupContext(
            title: "Create Account",
            error: nil,
            formData: SignupFormData()
        ))
    }

    @Sendable
    func signup(req: Request) async throws -> Response {
        let form = try req.content.decode(WebSignupRequest.self)

        // Validate
        if form.name.trimmingCharacters(in: .whitespaces).count < 2 {
            return try await renderSignupError(req: req, error: "Name must be at least 2 characters", form: form)
        }

        if form.password.count < 8 {
            return try await renderSignupError(req: req, error: "Password must be at least 8 characters", form: form)
        }

        if form.password != form.confirmPassword {
            return try await renderSignupError(req: req, error: "Passwords do not match", form: form)
        }

        // Check if email already exists
        let existingUser = try await User.query(on: req.db)
            .filter(\.$email == form.email.lowercased())
            .first()

        if existingUser != nil {
            return try await renderSignupError(req: req, error: "An account with this email already exists", form: form)
        }

        // Create user
        let passwordHash = try Bcrypt.hash(form.password)
        let user = User(
            email: form.email.lowercased(),
            name: form.name.trimmingCharacters(in: .whitespaces),
            passwordHash: passwordHash
        )

        try await user.save(on: req.db)

        // Create email verification
        let verification = EmailVerification(userId: try user.requireID())
        try await verification.save(on: req.db)

        // Send verification email
        try await req.emailService.sendEmailVerification(
            to: user.email,
            userName: user.name,
            verificationCode: verification.token
        )

        // Create web session
        let session = try WebSession.generate(for: user)
        session.userAgent = req.headers.first(name: .userAgent)
        session.ipAddress = req.remoteAddress?.ipAddress

        try await session.save(on: req.db)

        // Set session cookie and redirect to verify email
        var response = req.redirect(to: "/admin/verify-email")
        response.cookies["feedbackkit_session"] = HTTPCookies.Value(
            string: session.sessionToken,
            expires: session.expiresAt,
            path: "/",
            isSecure: req.application.environment != .development,
            isHTTPOnly: true,
            sameSite: .lax
        )

        return response
    }

    private func renderSignupError(req: Request, error: String, form: WebSignupRequest) async throws -> Response {
        let view = try await req.view.render("auth/signup", SignupContext(
            title: "Create Account",
            error: error,
            formData: SignupFormData(name: form.name, email: form.email)
        ))
        var response = try await view.encodeResponse(for: req).get()
        response.status = .badRequest
        return response
    }

    // MARK: - Email Verification

    @Sendable
    func verifyEmailPage(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)

        if user.isEmailVerified {
            throw Abort.redirect(to: "/admin/dashboard")
        }

        return try await req.view.render("auth/verify-email", VerifyEmailContext(
            title: "Verify Email",
            email: user.email,
            error: nil
        ))
    }

    @Sendable
    func verifyEmail(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(WebVerifyEmailRequest.self)

        // Find the verification record
        guard let verification = try await EmailVerification.query(on: req.db)
            .filter(\.$token == form.code.uppercased())
            .filter(\.$user.$id == user.requireID())
            .first() else {
            let view = try await req.view.render("auth/verify-email", VerifyEmailContext(
                title: "Verify Email",
                email: user.email,
                error: "Invalid verification code"
            ))
            var response = try await view.encodeResponse(for: req).get()
            response.status = .badRequest
            return response
        }

        // Check if expired
        if verification.isExpired {
            let view = try await req.view.render("auth/verify-email", VerifyEmailContext(
                title: "Verify Email",
                email: user.email,
                error: "Verification code has expired. Please request a new one."
            ))
            var response = try await view.encodeResponse(for: req).get()
            response.status = .badRequest
            return response
        }

        // Mark as verified
        verification.verifiedAt = Date()
        try await verification.save(on: req.db)

        // Update user
        user.isEmailVerified = true
        try await user.save(on: req.db)

        return req.redirect(to: "/admin/dashboard")
    }

    @Sendable
    func resendVerification(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        if user.isEmailVerified {
            return req.redirect(to: "/admin/dashboard")
        }

        // Delete any existing verification tokens for this user
        try await EmailVerification.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .delete()

        // Create new verification
        let verification = EmailVerification(userId: try user.requireID())
        try await verification.save(on: req.db)

        // Send verification email
        try await req.emailService.sendEmailVerification(
            to: user.email,
            userName: user.name,
            verificationCode: verification.token
        )

        // Redirect back with success message (using flash)
        return req.redirect(to: "/admin/verify-email")
    }

    // MARK: - Forgot Password

    @Sendable
    func forgotPasswordPage(req: Request) async throws -> View {
        return try await req.view.render("auth/forgot-password", ForgotPasswordContext(
            title: "Forgot Password",
            success: false,
            email: nil,
            error: nil,
            formData: ForgotPasswordFormData()
        ))
    }

    @Sendable
    func forgotPassword(req: Request) async throws -> View {
        let form = try req.content.decode(WebForgotPasswordRequest.self)

        // Find user by email
        if let user = try await User.query(on: req.db)
            .filter(\.$email == form.email.lowercased())
            .first() {

            // Delete any existing password reset tokens for this user
            try await PasswordReset.query(on: req.db)
                .filter(\.$user.$id == user.requireID())
                .delete()

            // Create new password reset token
            let passwordReset = PasswordReset(userId: try user.requireID())
            try await passwordReset.save(on: req.db)

            // Send password reset email
            try await req.emailService.sendPasswordResetEmail(
                to: user.email,
                userName: user.name,
                resetCode: passwordReset.token
            )
        }

        // Always show success to prevent email enumeration
        return try await req.view.render("auth/forgot-password", ForgotPasswordContext(
            title: "Forgot Password",
            success: true,
            email: form.email,
            error: nil,
            formData: ForgotPasswordFormData(email: form.email)
        ))
    }

    // MARK: - Reset Password

    @Sendable
    func resetPasswordPage(req: Request) async throws -> View {
        return try await req.view.render("auth/reset-password", ResetPasswordContext(
            title: "Reset Password",
            error: nil,
            formData: ResetPasswordFormData()
        ))
    }

    @Sendable
    func resetPassword(req: Request) async throws -> Response {
        let form = try req.content.decode(WebResetPasswordRequest.self)

        // Validate
        if form.code.count != 8 {
            return try await renderResetPasswordError(req: req, error: "Code must be exactly 8 characters", form: form)
        }

        if form.password.count < 8 {
            return try await renderResetPasswordError(req: req, error: "Password must be at least 8 characters", form: form)
        }

        if form.password != form.confirmPassword {
            return try await renderResetPasswordError(req: req, error: "Passwords do not match", form: form)
        }

        // Find the password reset record
        guard let passwordReset = try await PasswordReset.query(on: req.db)
            .filter(\.$token == form.code.uppercased())
            .with(\.$user)
            .first() else {
            return try await renderResetPasswordError(req: req, error: "Invalid reset code", form: form)
        }

        // Check if already used
        if passwordReset.isUsed {
            return try await renderResetPasswordError(req: req, error: "This reset code has already been used", form: form)
        }

        // Check if expired
        if passwordReset.isExpired {
            return try await renderResetPasswordError(req: req, error: "Reset code has expired. Please request a new one.", form: form)
        }

        // Hash new password and update user
        passwordReset.user.passwordHash = try Bcrypt.hash(form.password)
        try await passwordReset.user.save(on: req.db)

        // Mark token as used
        passwordReset.usedAt = Date()
        try await passwordReset.save(on: req.db)

        // Delete all user tokens and web sessions
        try await UserToken.query(on: req.db)
            .filter(\.$user.$id == passwordReset.$user.id)
            .delete()

        try await WebSession.query(on: req.db)
            .filter(\.$user.$id == passwordReset.$user.id)
            .delete()

        // Redirect to login with success message
        return req.redirect(to: "/admin/login")
    }

    private func renderResetPasswordError(req: Request, error: String, form: WebResetPasswordRequest) async throws -> Response {
        let view = try await req.view.render("auth/reset-password", ResetPasswordContext(
            title: "Reset Password",
            error: error,
            formData: ResetPasswordFormData(email: form.email, code: form.code)
        ))
        var response = try await view.encodeResponse(for: req).get()
        response.status = .badRequest
        return response
    }

    // MARK: - Logout

    @Sendable
    func logout(req: Request) async throws -> Response {
        // Delete web session from database
        if let sessionToken = req.cookies["feedbackkit_session"]?.string {
            try await WebSession.query(on: req.db)
                .filter(\.$sessionToken == sessionToken)
                .delete()
        }

        // Clear cookie
        var response = req.redirect(to: "/admin/login")
        response.cookies["feedbackkit_session"] = .expired

        return response
    }
}

// MARK: - Request DTOs

struct WebLoginRequest: Content {
    let email: String
    let password: String
    let remember: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        password = try container.decode(String.self, forKey: .password)
        // Checkbox sends "on" if checked, nothing if not
        remember = (try? container.decode(String.self, forKey: .remember)) == "on"
    }

    enum CodingKeys: String, CodingKey {
        case email, password, remember
    }
}

struct WebSignupRequest: Content {
    let name: String
    let email: String
    let password: String
    let confirmPassword: String
}

struct WebVerifyEmailRequest: Content {
    let code: String
}

struct WebForgotPasswordRequest: Content {
    let email: String
}

struct WebResetPasswordRequest: Content {
    let email: String
    let code: String
    let password: String
    let confirmPassword: String
}

// MARK: - View Contexts

struct LoginContext: Encodable {
    let title: String
    let error: String?
    let formData: LoginFormData
    let environment: String
    let environmentColor: String
}

struct LoginFormData: Encodable {
    let email: String

    init(email: String = "") {
        self.email = email
    }
}

struct SignupContext: Encodable {
    let title: String
    let error: String?
    let formData: SignupFormData
}

struct SignupFormData: Encodable {
    let name: String
    let email: String

    init(name: String = "", email: String = "") {
        self.name = name
        self.email = email
    }
}

struct VerifyEmailContext: Encodable {
    let title: String
    let email: String
    let error: String?
}

struct ForgotPasswordContext: Encodable {
    let title: String
    let success: Bool
    let email: String?
    let error: String?
    let formData: ForgotPasswordFormData
}

struct ForgotPasswordFormData: Encodable {
    let email: String

    init(email: String = "") {
        self.email = email
    }
}

struct ResetPasswordContext: Encodable {
    let title: String
    let error: String?
    let formData: ResetPasswordFormData
}

struct ResetPasswordFormData: Encodable {
    let email: String
    let code: String

    init(email: String = "", code: String = "") {
        self.email = email
        self.code = code
    }
}
