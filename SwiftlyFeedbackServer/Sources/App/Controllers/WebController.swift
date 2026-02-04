import Vapor
import Fluent

/// Controller for serving web pages (subscription, etc.)
struct WebController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Public web routes (no /api/v1 prefix)
        routes.get("subscribe", use: subscribePage)
        routes.get("subscribe", "success", use: successPage)
        routes.get("subscribe", "cancel", use: cancelPage)

        // Web-based checkout (accepts token in query param for cross-platform auth)
        routes.post("subscribe", "checkout", use: webCheckout)

        // Customer portal (manage subscription via Stripe)
        routes.get("portal", use: portalRedirect)

        // Legal pages
        routes.get("privacy", use: privacyPage)
        routes.get("terms", use: termsPage)
    }

    // MARK: - Subscribe Page

    /// GET /subscribe?token=xxx
    /// Shows pricing page. Token is optional - if provided, enables direct checkout.
    @Sendable
    func subscribePage(req: Request) async throws -> Response {
        // Get optional auth token from query
        let token = try? req.query.get(String.self, at: "token")

        // Get price IDs from environment
        let proMonthlyPrice = Environment.get("STRIPE_PRICE_PRO_MONTHLY") ?? ""
        let proYearlyPrice = Environment.get("STRIPE_PRICE_PRO_YEARLY") ?? ""
        let teamMonthlyPrice = Environment.get("STRIPE_PRICE_TEAM_MONTHLY") ?? ""
        let teamYearlyPrice = Environment.get("STRIPE_PRICE_TEAM_YEARLY") ?? ""

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Subscribe - FeedbackKit</title>
            <script src="https://cdn.tailwindcss.com"></script>
            <style>
                .gradient-bg {
                    background: linear-gradient(135deg, #FFB830 0%, #F7A50D 50%, #E85D04 100%);
                }
            </style>
        </head>
        <body class="bg-gray-900 text-white min-h-screen">
            <!-- Header -->
            <header class="gradient-bg py-10">
                <div class="max-w-4xl mx-auto px-4 flex flex-col items-center justify-center text-center">
                    <img src="https://images.squarespace-cdn.com/content/v1/63f9f1a6a9df014beaf6bdf3/f35f5f49-7d3c-4a8a-89b4-35bb1629de83/Swiftly+FeedbackKit+%281024+x+1024+px%29+%282%29.jpeg"
                         alt="FeedbackKit"
                         class="h-24 w-auto object-contain rounded-2xl shadow-xl mb-5">
                </div>
            </header>

            <!-- Auth Status -->
            <div id="auth-status" class="max-w-4xl mx-auto px-4 mt-4">
                <div id="auth-message" class="bg-yellow-500/20 border border-yellow-500 rounded-lg p-4 hidden">
                    <p class="text-yellow-400">Please log in to subscribe</p>
                </div>
            </div>
            <h1 class="text-3xl font-bold text-white text-center mt-8 mb-2">Choose your plan</h1>
            <!-- Billing Toggle -->
            <div class="max-w-4xl mx-auto px-4 mt-8">
                <div class="flex justify-center items-center gap-4">
                    <span id="monthly-label" class="text-white font-medium">Monthly</span>
                    <button id="billing-toggle" class="relative w-14 h-7 bg-gray-700 rounded-full transition-colors" onclick="toggleBilling()">
                        <span id="toggle-dot" class="absolute left-1 top-1 w-5 h-5 bg-white rounded-full transition-transform"></span>
                    </button>
                    <span id="yearly-label" class="text-gray-400">Yearly <span class="text-green-400 text-sm">(Save 17%)</span></span>
                </div>
            </div>

            <!-- Pricing Cards -->
            <div class="max-w-4xl mx-auto px-4 py-12">
                <div class="grid md:grid-cols-3 gap-6">
                    <!-- Free -->
                    <div class="bg-gray-800 rounded-2xl p-6 border border-gray-700">
                        <h2 class="text-xl font-bold">Free</h2>
                        <p class="text-gray-400 mt-2">For trying out FeedbackKit</p>
                        <div class="mt-4">
                            <span class="text-4xl font-bold">€0</span>
                            <span class="text-gray-400">/month</span>
                        </div>
                        <ul class="mt-6 space-y-3">
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>1 Project</span>
                            </li>
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>10 Feedback items</span>
                            </li>
                            <li class="flex items-center gap-2 text-gray-500">
                                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                                <span>No integrations</span>
                            </li>
                        </ul>
                        <button class="w-full mt-6 py-3 px-4 bg-gray-700 rounded-lg text-gray-400 cursor-not-allowed">
                            Current Plan
                        </button>
                    </div>

                    <!-- Pro -->
                    <div class="bg-gray-800 rounded-2xl p-6 border-2 border-orange-500 relative">
                        <div class="absolute -top-3 left-1/2 -translate-x-1/2 bg-orange-500 text-white text-sm font-bold px-3 py-1 rounded-full">
                            Popular
                        </div>
                        <h2 class="text-xl font-bold">Pro</h2>
                        <p class="text-gray-400 mt-2">For indie developers</p>
                        <div class="mt-4">
                            <span id="pro-price" class="text-4xl font-bold">€9.99</span>
                            <span id="pro-period" class="text-gray-400">/month</span>
                        </div>
                        <ul class="mt-6 space-y-3">
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>2 Projects</span>
                            </li>
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>Unlimited Feedback</span>
                            </li>
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>All Integrations</span>
                            </li>
                        </ul>
                        <button id="pro-button" onclick="subscribe('pro')" class="w-full mt-6 py-3 px-4 bg-orange-500 hover:bg-orange-600 rounded-lg font-semibold transition-colors">
                            Subscribe to Pro
                        </button>
                    </div>

                    <!-- Team -->
                    <div class="bg-gray-800 rounded-2xl p-6 border border-gray-700">
                        <h2 class="text-xl font-bold">Team</h2>
                        <p class="text-gray-400 mt-2">For teams & agencies</p>
                        <div class="mt-4">
                            <span id="team-price" class="text-4xl font-bold">€99.99</span>
                            <span id="team-period" class="text-gray-400">/month</span>
                        </div>
                        <ul class="mt-6 space-y-3">
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>Unlimited Projects</span>
                            </li>
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>Unlimited Feedback</span>
                            </li>
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>Team Members</span>
                            </li>
                            <li class="flex items-center gap-2">
                                <svg class="w-5 h-5 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                                <span>All Integrations</span>
                            </li>
                        </ul>
                        <button id="team-button" onclick="subscribe('team')" class="w-full mt-6 py-3 px-4 bg-gray-700 hover:bg-gray-600 rounded-lg font-semibold transition-colors">
                            Subscribe to Team
                        </button>
                    </div>
                </div>
            </div>

            <!-- Loading Overlay -->
            <div id="loading" class="fixed inset-0 bg-black/50 flex items-center justify-center hidden">
                <div class="bg-gray-800 rounded-xl p-8 text-center">
                    <div class="animate-spin w-8 h-8 border-4 border-orange-500 border-t-transparent rounded-full mx-auto"></div>
                    <p class="mt-4">Redirecting to checkout...</p>
                </div>
            </div>

            <script>
                // Configuration
                const AUTH_TOKEN = '\(token ?? "")';
                const PRICES = {
                    pro: { monthly: '\(proMonthlyPrice)', yearly: '\(proYearlyPrice)' },
                    team: { monthly: '\(teamMonthlyPrice)', yearly: '\(teamYearlyPrice)' }
                };

                let isYearly = false;

                // Check auth on load
                document.addEventListener('DOMContentLoaded', function() {
                    console.log('AUTH_TOKEN length:', AUTH_TOKEN ? AUTH_TOKEN.length : 0);
                    console.log('AUTH_TOKEN preview:', AUTH_TOKEN ? AUTH_TOKEN.substring(0, 20) + '...' : 'empty');

                    if (!AUTH_TOKEN) {
                        document.getElementById('auth-message').classList.remove('hidden');
                        document.getElementById('pro-button').disabled = true;
                        document.getElementById('team-button').disabled = true;
                        document.getElementById('pro-button').classList.add('opacity-50', 'cursor-not-allowed');
                        document.getElementById('team-button').classList.add('opacity-50', 'cursor-not-allowed');
                    }
                });

                function toggleBilling() {
                    isYearly = !isYearly;
                    const toggle = document.getElementById('toggle-dot');
                    const monthlyLabel = document.getElementById('monthly-label');
                    const yearlyLabel = document.getElementById('yearly-label');

                    if (isYearly) {
                        toggle.style.transform = 'translateX(28px)';
                        monthlyLabel.classList.remove('text-white');
                        monthlyLabel.classList.add('text-gray-400');
                        yearlyLabel.classList.remove('text-gray-400');
                        yearlyLabel.classList.add('text-white');

                        document.getElementById('pro-price').textContent = '€99.99';
                        document.getElementById('pro-period').textContent = '/year';
                        document.getElementById('team-price').textContent = '€999.99';
                        document.getElementById('team-period').textContent = '/year';
                    } else {
                        toggle.style.transform = 'translateX(0)';
                        monthlyLabel.classList.add('text-white');
                        monthlyLabel.classList.remove('text-gray-400');
                        yearlyLabel.classList.add('text-gray-400');
                        yearlyLabel.classList.remove('text-white');

                        document.getElementById('pro-price').textContent = '€9.99';
                        document.getElementById('pro-period').textContent = '/month';
                        document.getElementById('team-price').textContent = '€99.99';
                        document.getElementById('team-period').textContent = '/month';
                    }
                }

                async function subscribe(plan) {
                    if (!AUTH_TOKEN) {
                        alert('Please log in to subscribe. Open the subscribe page from the FeedbackKit app.');
                        return;
                    }

                    const priceId = PRICES[plan][isYearly ? 'yearly' : 'monthly'];
                    if (!priceId) {
                        alert('Price not configured. Please contact support.');
                        return;
                    }

                    document.getElementById('loading').classList.remove('hidden');

                    try {
                        // Decode the token if it was URL-encoded
                        const decodedToken = decodeURIComponent(AUTH_TOKEN);

                        const response = await fetch('/api/v1/subscriptions/checkout', {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                                'Authorization': 'Bearer ' + decodedToken
                            },
                            body: JSON.stringify({
                                price_id: priceId,
                                success_url: window.location.origin + '/subscribe/success',
                                cancel_url: window.location.origin + '/subscribe/cancel'
                            })
                        });

                        if (!response.ok) {
                            const error = await response.json();
                            throw new Error(error.reason || 'Failed to create checkout session');
                        }

                        const data = await response.json();
                        window.location.href = data.checkout_url;
                    } catch (error) {
                        document.getElementById('loading').classList.add('hidden');
                        alert('Error: ' + error.message);
                    }
                }
            </script>
        </body>
        </html>
        """

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html"],
            body: .init(string: html)
        )
    }

    // MARK: - Success Page

    /// GET /subscribe/success
    @Sendable
    func successPage(req: Request) async throws -> Response {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Success - FeedbackKit</title>
            <script src="https://cdn.tailwindcss.com"></script>
        </head>
        <body class="bg-gray-900 text-white min-h-screen flex items-center justify-center">
            <div class="text-center max-w-md mx-auto px-4">
                <div class="w-20 h-20 bg-green-500 rounded-full flex items-center justify-center mx-auto">
                    <svg class="w-10 h-10 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                    </svg>
                </div>
                <h1 class="text-3xl font-bold mt-6">Thank You!</h1>
                <p class="text-gray-400 mt-4">Your subscription is now active. You can close this window and return to the app.</p>
                <div class="mt-8 space-y-3">
                    <a href="feedbackkit://subscription/success" class="block w-full py-3 px-4 bg-orange-500 hover:bg-orange-600 rounded-lg font-semibold transition-colors">
                        Open FeedbackKit App
                    </a>
                    <p class="text-gray-500 text-sm">Or close this tab to return to your app</p>
                </div>
            </div>
        </body>
        </html>
        """

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html"],
            body: .init(string: html)
        )
    }

    // MARK: - Cancel Page

    /// GET /subscribe/cancel
    @Sendable
    func cancelPage(req: Request) async throws -> Response {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Cancelled - FeedbackKit</title>
            <script src="https://cdn.tailwindcss.com"></script>
        </head>
        <body class="bg-gray-900 text-white min-h-screen flex items-center justify-center">
            <div class="text-center max-w-md mx-auto px-4">
                <div class="w-20 h-20 bg-gray-700 rounded-full flex items-center justify-center mx-auto">
                    <svg class="w-10 h-10 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                    </svg>
                </div>
                <h1 class="text-3xl font-bold mt-6">Checkout Cancelled</h1>
                <p class="text-gray-400 mt-4">No worries! You can subscribe anytime when you're ready.</p>
                <div class="mt-8 space-y-3">
                    <a href="/subscribe" class="block w-full py-3 px-4 bg-orange-500 hover:bg-orange-600 rounded-lg font-semibold transition-colors">
                        Try Again
                    </a>
                    <a href="feedbackkit://home" class="block w-full py-3 px-4 bg-gray-700 hover:bg-gray-600 rounded-lg font-semibold transition-colors">
                        Return to App
                    </a>
                </div>
            </div>
        </body>
        </html>
        """

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html"],
            body: .init(string: html)
        )
    }

    // MARK: - Web Checkout

    /// POST /subscribe/checkout
    /// Alternative checkout endpoint that accepts token in body (for web form submission)
    @Sendable
    func webCheckout(req: Request) async throws -> Response {
        struct WebCheckoutRequest: Content {
            let token: String
            let priceId: String
        }

        let dto = try req.content.decode(WebCheckoutRequest.self)

        // Validate token and get user
        guard let userToken = try await UserToken.query(on: req.db)
            .filter(\.$value == dto.token)
            .with(\.$user)
            .first() else {
            throw Abort(.unauthorized, reason: "Invalid token")
        }

        let user = userToken.user
        let userId = try user.requireID()

        let stripeService = req.stripeService
        let customerId = try await stripeService.getOrCreateCustomer(for: user, on: req.db)

        let baseUrl = Environment.get("WEB_APP_URL") ?? req.application.http.server.configuration.hostname
        let successUrl = "\(baseUrl)/subscribe/success"
        let cancelUrl = "\(baseUrl)/subscribe/cancel"

        let checkoutUrl = try await stripeService.createCheckoutSession(
            customerId: customerId,
            priceId: dto.priceId,
            userId: userId,
            successUrl: successUrl,
            cancelUrl: cancelUrl
        )

        // Redirect to Stripe
        return req.redirect(to: checkoutUrl)
    }

    // MARK: - Customer Portal

    /// GET /portal?token=xxx
    /// Redirects to Stripe Customer Portal for subscription management
    @Sendable
    func portalRedirect(req: Request) async throws -> Response {
        // Get auth token from query
        guard let token = try? req.query.get(String.self, at: "token") else {
            throw Abort(.badRequest, reason: "Missing authentication token")
        }

        // Validate token and get user
        guard let userToken = try await UserToken.query(on: req.db)
            .filter(\.$value == token)
            .with(\.$user)
            .first() else {
            throw Abort(.unauthorized, reason: "Invalid token")
        }

        let user = userToken.user

        // User must have a Stripe customer ID to access portal
        guard let customerId = user.stripeCustomerId else {
            throw Abort(.badRequest, reason: "No subscription found. Please subscribe first.")
        }

        // Create portal session
        let stripeService = req.stripeService
        let baseUrl = Environment.get("WEB_APP_URL") ?? "http://localhost:8080"
        let returnUrl = "\(baseUrl)/subscribe"

        let portalUrl = try await stripeService.createPortalSession(
            customerId: customerId,
            returnUrl: returnUrl
        )

        // Redirect to Stripe portal
        return req.redirect(to: portalUrl)
    }

    // MARK: - Legal Pages

    /// GET /privacy
    @Sendable
    func privacyPage(req: Request) async throws -> View {
        return try await req.view.render("privacy")
    }

    /// GET /terms
    @Sendable
    func termsPage(req: Request) async throws -> View {
        return try await req.view.render("terms")
    }
}
