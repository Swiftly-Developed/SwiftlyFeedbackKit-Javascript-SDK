import Fluent
import Vapor

struct WebSessionAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Check for session token in cookie
        guard let sessionToken = request.cookies["feedbackkit_session"]?.string else {
            return request.redirect(to: "/admin/login")
        }

        // Look up the session
        guard let session = try await WebSession.query(on: request.db)
            .filter(\.$sessionToken == sessionToken)
            .with(\.$user)
            .first() else {
            // Invalid session - clear cookie and redirect
            let response = request.redirect(to: "/admin/login")
            response.cookies["feedbackkit_session"] = .expired
            return response
        }

        // Check if session is expired
        if session.isExpired {
            // Delete expired session
            try await session.delete(on: request.db)
            let response = request.redirect(to: "/admin/login")
            response.cookies["feedbackkit_session"] = .expired
            return response
        }

        // Check if user needs email verification
        if !session.user.isEmailVerified {
            // Allow access to verify-email page
            if request.url.path.contains("verify-email") || request.url.path.contains("resend-verification") {
                request.auth.login(session.user)
                return try await next.respond(to: request)
            }
            return request.redirect(to: "/admin/verify-email")
        }

        // Update last accessed time (don't wait for it)
        session.lastAccessedAt = Date()
        try? await session.save(on: request.db)

        // Log in the user
        request.auth.login(session.user)

        return try await next.respond(to: request)
    }
}

extension HTTPCookies.Value {
    static var expired: HTTPCookies.Value {
        var cookie = HTTPCookies.Value(string: "")
        cookie.expires = Date(timeIntervalSince1970: 0)
        cookie.path = "/"
        return cookie
    }
}
