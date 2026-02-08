# SwiftlyFeedbackAdmin Web Version - Technical Plan

## Overview

Build a full-featured web admin dashboard using **Vapor + Leaf** (server-side rendering) that replicates all functionality of the SwiftlyFeedbackAdmin iOS/macOS app. The web version will run on the existing SwiftlyFeedbackServer, sharing models, services, and database.

---

## Architecture Decision

### Approach: Server-Side Rendering with Leaf + HTMX

| Option | Pros | Cons |
|--------|------|------|
| **Leaf + HTMX** (Recommended) | Single codebase, shared models, no API versioning, fast initial load, SEO-friendly | Less interactive than SPA, learning curve for HTMX |
| SPA (React/Vue) | Rich interactivity, familiar to web devs | Separate codebase, API maintenance, CORS complexity |
| Full Leaf (no JS) | Simplest, most maintainable | Page reloads for every action, poor UX |

**Recommendation**: Leaf templates with **HTMX** for dynamic updates and **Tailwind CSS** for styling. This keeps everything in Swift, shares models with the API, and provides modern UX without a separate frontend codebase.

---

## Project Structure

```
SwiftlyFeedbackServer/
├── Sources/App/
│   ├── Controllers/
│   │   ├── API/                    # Existing API controllers (keep as-is)
│   │   │   ├── AuthController.swift
│   │   │   ├── ProjectController.swift
│   │   │   └── ...
│   │   └── Web/                    # NEW: Web controllers for Leaf pages
│   │       ├── WebAuthController.swift
│   │       ├── WebDashboardController.swift
│   │       ├── WebProjectController.swift
│   │       ├── WebFeedbackController.swift
│   │       ├── WebAnalyticsController.swift
│   │       ├── WebSettingsController.swift
│   │       └── WebIntegrationController.swift
│   ├── Middleware/
│   │   └── WebSessionAuthMiddleware.swift  # NEW: Cookie-based auth
│   ├── ViewContexts/               # NEW: Leaf view models
│   │   ├── DashboardContext.swift
│   │   ├── ProjectContext.swift
│   │   ├── FeedbackContext.swift
│   │   └── ...
│   └── routes.swift                # Add web routes
├── Resources/
│   └── Views/                      # NEW: Leaf templates
│       ├── layouts/
│       │   ├── base.leaf           # Base HTML structure
│       │   ├── auth.leaf           # Auth pages layout
│       │   └── dashboard.leaf      # Dashboard layout with sidebar
│       ├── partials/
│       │   ├── navbar.leaf
│       │   ├── sidebar.leaf
│       │   ├── flash-messages.leaf
│       │   ├── pagination.leaf
│       │   └── modals/
│       │       ├── confirm-delete.leaf
│       │       └── create-project.leaf
│       ├── auth/
│       │   ├── login.leaf
│       │   ├── signup.leaf
│       │   ├── verify-email.leaf
│       │   ├── forgot-password.leaf
│       │   └── reset-password.leaf
│       ├── dashboard/
│       │   └── index.leaf
│       ├── projects/
│       │   ├── index.leaf
│       │   ├── show.leaf
│       │   ├── settings.leaf
│       │   ├── members.leaf
│       │   └── integrations/
│       │       ├── slack.leaf
│       │       ├── github.leaf
│       │       └── ... (10 total)
│       ├── feedback/
│       │   ├── index.leaf
│       │   ├── show.leaf
│       │   └── kanban.leaf
│       ├── analytics/
│       │   ├── users.leaf
│       │   └── events.leaf
│       └── settings/
│           ├── account.leaf
│           ├── subscription.leaf
│           └── notifications.leaf
└── Public/                         # Static assets
    ├── css/
    │   └── app.css                 # Tailwind output
    ├── js/
    │   ├── htmx.min.js
    │   ├── alpine.min.js           # Optional: for complex UI state
    │   └── app.js
    └── images/
```

---

## Phase 1: Foundation (Week 1-2)

### 1.1 Leaf Setup & Configuration

```swift
// configure.swift additions
import Leaf

app.views.use(.leaf)
app.leaf.tags["formatDate"] = FormatDateTag()
app.leaf.tags["statusBadge"] = StatusBadgeTag()
app.leaf.tags["roleLabel"] = RoleLabelTag()

// Session configuration for web auth
app.sessions.use(.fluent)
app.middleware.use(app.sessions.middleware)
```

### 1.2 Session-Based Authentication

Create `WebSession` model for cookie-based auth:

```swift
// Models/WebSession.swift
final class WebSession: Model, Content, @unchecked Sendable {
    static let schema = "web_sessions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "session_token") var sessionToken: String
    @Field(key: "expires_at") var expiresAt: Date
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
}
```

### 1.3 Web Session Middleware

```swift
// Middleware/WebSessionAuthMiddleware.swift
struct WebSessionAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let sessionToken = request.session.data["auth_token"],
              let session = try await WebSession.query(on: request.db)
                  .filter(\.$sessionToken == sessionToken)
                  .filter(\.$expiresAt > Date())
                  .with(\.$user)
                  .first() else {
            return request.redirect(to: "/admin/login")
        }
        request.auth.login(session.user)
        return try await next.respond(to: request)
    }
}
```

### 1.4 Base Layout Template

```leaf
<!-- Resources/Views/layouts/base.leaf -->
<!DOCTYPE html>
<html lang="en" class="h-full">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>#(title) - Feedback Kit Admin</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="/js/htmx.min.js"></script>
    <script src="/js/alpine.min.js" defer></script>
</head>
<body class="h-full bg-gray-50">
    #import("content")
</body>
</html>
```

### 1.5 Route Registration

```swift
// routes.swift additions
func routes(_ app: Application) throws {
    // Existing API routes
    try app.group("api", "v1") { api in
        try api.register(collection: AuthController())
        // ... existing controllers
    }

    // NEW: Web admin routes
    try app.group("admin") { admin in
        // Public auth routes
        try admin.register(collection: WebAuthController())

        // Protected routes
        let protected = admin.grouped(WebSessionAuthMiddleware())
        try protected.register(collection: WebDashboardController())
        try protected.register(collection: WebProjectController())
        try protected.register(collection: WebFeedbackController())
        try protected.register(collection: WebAnalyticsController())
        try protected.register(collection: WebSettingsController())
        try protected.register(collection: WebIntegrationController())
    }
}
```

---

## Phase 2: Authentication Pages (Week 2-3)

### 2.1 Pages to Build

| Page | Route | Features |
|------|-------|----------|
| Login | `GET/POST /admin/login` | Email/password, "Keep me signed in", error handling |
| Signup | `GET/POST /admin/signup` | Name, email, password, password confirmation |
| Email Verification | `GET/POST /admin/verify-email` | 8-character code input, resend button |
| Forgot Password | `GET/POST /admin/forgot-password` | Email input, success message |
| Reset Password | `GET/POST /admin/reset-password` | New password form (from email link) |
| Logout | `POST /admin/logout` | Clear session, redirect to login |

### 2.2 WebAuthController

```swift
struct WebAuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("login", use: loginPage)
        routes.post("login", use: login)
        routes.get("signup", use: signupPage)
        routes.post("signup", use: signup)
        routes.get("verify-email", use: verifyEmailPage)
        routes.post("verify-email", use: verifyEmail)
        routes.post("resend-verification", use: resendVerification)
        routes.get("forgot-password", use: forgotPasswordPage)
        routes.post("forgot-password", use: forgotPassword)
        routes.get("reset-password", use: resetPasswordPage)
        routes.post("reset-password", use: resetPassword)
        routes.post("logout", use: logout)
    }

    func login(req: Request) async throws -> Response {
        // Validate credentials
        // Create WebSession
        // Set session cookie
        // Redirect to dashboard
    }
}
```

---

## Phase 3: Dashboard (Week 3-4)

### 3.1 Home Dashboard

| Component | Data Source | Features |
|-----------|-------------|----------|
| Stats Cards | `/dashboard/home` | Total projects, feedback, votes, completion rate |
| Project Quick Stats | Per-project aggregates | Feedback by status chart |
| Recent Activity | Latest feedback/comments | Links to items |
| Quick Actions | - | Create project, view all feedback |

### 3.2 Dashboard Layout with Sidebar

```leaf
<!-- Resources/Views/layouts/dashboard.leaf -->
#extend("layouts/base"):
    #export("content"):
    <div class="flex h-screen">
        <!-- Sidebar -->
        <aside class="w-64 bg-gray-900 text-white">
            #embed("partials/sidebar")
        </aside>

        <!-- Main content -->
        <main class="flex-1 overflow-auto">
            <nav class="bg-white shadow px-6 py-4">
                #embed("partials/navbar")
            </nav>
            <div class="p-6">
                #import("main")
            </div>
        </main>
    </div>
    #endexport
#endextend
```

### 3.3 Sidebar Navigation

```
📊 Dashboard
📁 Projects
💬 Feedback
👥 Users (Analytics)
📈 Events (Analytics)
⚙️ Settings
```

---

## Phase 4: Projects (Week 4-5)

### 4.1 Project Pages

| Page | Route | Features |
|------|-------|----------|
| Project List | `GET /admin/projects` | Grid/list view, archived toggle, search |
| Create Project | `POST /admin/projects` | Modal form (HTMX) |
| Project Detail | `GET /admin/projects/:id` | Overview, quick stats, API key display |
| Project Settings | `GET /admin/projects/:id/settings` | Name, description, color, danger zone |
| Project Members | `GET /admin/projects/:id/members` | Member list, invite form, role management |
| Project Integrations | `GET /admin/projects/:id/integrations` | 10 integration configuration pages |

### 4.2 HTMX Interactions

```html
<!-- Create project modal trigger -->
<button hx-get="/admin/projects/new"
        hx-target="#modal-container"
        hx-trigger="click">
    Create Project
</button>

<!-- Inline project deletion with confirmation -->
<button hx-delete="/admin/projects/#(project.id)"
        hx-confirm="Are you sure you want to delete this project?"
        hx-target="closest .project-card"
        hx-swap="outerHTML swap:1s">
    Delete
</button>

<!-- Live API key regeneration -->
<button hx-post="/admin/projects/#(project.id)/regenerate-key"
        hx-target="#api-key-display"
        hx-swap="innerHTML">
    Regenerate API Key
</button>
```

### 4.3 Integration Configuration Pages

Each of the 10 integrations needs a configuration page:

1. **Slack** - Webhook URL, channel, notifications toggle
2. **GitHub** - Token, owner/repo, labels, status mapping
3. **ClickUp** - Token, workspace/space/list selection, status mapping
4. **Notion** - Token, database selection, property mapping
5. **Monday.com** - Token, board/group selection, column mapping
6. **Linear** - API key, team/project selection, state mapping
7. **Trello** - Token/key, board/list selection, label mapping
8. **Airtable** - Token, base/table selection, field mapping
9. **Asana** - Token, workspace/project selection, section mapping
10. **Basecamp** - Auth, account/project/todolist selection

---

## Phase 5: Feedback Management (Week 5-6)

### 5.1 Feedback Pages

| Page | Route | Features |
|------|-------|----------|
| Feedback List | `GET /admin/feedback` | Filterable table, project selector, status/category filters |
| Feedback Kanban | `GET /admin/feedback/kanban` | Drag-drop status columns (SortableJS) |
| Feedback Detail | `GET /admin/feedback/:id` | Full details, comments, status updates, merge UI |

### 5.2 Feedback List with Filters

```html
<!-- Filter bar with HTMX -->
<form hx-get="/admin/feedback"
      hx-target="#feedback-list"
      hx-trigger="change">
    <select name="project_id">...</select>
    <select name="status">...</select>
    <select name="category">...</select>
    <input type="search" name="q" hx-trigger="keyup changed delay:300ms">
</form>

<div id="feedback-list">
    #embed("feedback/_list")
</div>
```

### 5.3 Kanban Board

```html
<!-- Kanban with drag-drop -->
<div class="flex gap-4" x-data="kanban()">
    #for(status in statuses):
    <div class="w-72 bg-gray-100 rounded-lg p-4"
         data-status="#(status.rawValue)">
        <h3>#(status.displayName)</h3>
        <div class="space-y-2 sortable-list">
            #for(feedback in feedbackByStatus[status]):
            <div class="bg-white p-3 rounded shadow cursor-move"
                 data-feedback-id="#(feedback.id)"
                 draggable="true">
                #(feedback.title)
            </div>
            #endfor
        </div>
    </div>
    #endfor
</div>
```

### 5.4 Feedback Actions

- **Update Status** - Dropdown with HTMX PATCH
- **Update Category** - Dropdown with HTMX PATCH
- **Add Comment** - Form with HTMX POST
- **Delete Feedback** - Confirmation modal
- **Merge Feedback** - Multi-select + merge modal
- **Create Integration Task** - GitHub issue, ClickUp task, etc.

---

## Phase 6: Analytics (Week 6-7)

### 6.1 SDK Users Analytics

| Component | Features |
|-----------|----------|
| User Table | Searchable, sortable list of SDK users |
| User Stats | Total users, active users, MRR breakdown |
| User Detail | Session history, feedback submitted, votes |

### 6.2 Events Analytics

| Component | Features |
|-----------|----------|
| Event Timeline | Time-period selector (day/week/month) |
| Event Chart | Chart.js line/bar chart |
| Event Table | Searchable event list |

```html
<!-- Time period selector with HTMX -->
<div class="flex gap-2">
    <button hx-get="/admin/analytics/events?period=day"
            hx-target="#events-chart"
            class="btn">Day</button>
    <button hx-get="/admin/analytics/events?period=week"
            hx-target="#events-chart"
            class="btn">Week</button>
    <button hx-get="/admin/analytics/events?period=month"
            hx-target="#events-chart"
            class="btn">Month</button>
</div>
```

---

## Phase 7: Settings (Week 7-8)

### 7.1 Account Settings

| Section | Features |
|---------|----------|
| Profile | Name, email (read-only) |
| Password | Change password form |
| Notifications | Email/push notification toggles |
| Danger Zone | Delete account with confirmation |

### 7.2 Subscription Management

| Component | Features |
|-----------|----------|
| Current Plan | Tier display, usage stats |
| Upgrade Options | Tier comparison, Stripe checkout link |
| Billing Portal | Link to Stripe customer portal |

---

## Phase 8: Polish & Production (Week 8-9)

### 8.1 UI/UX Enhancements

- **Loading States** - HTMX loading indicators
- **Toast Notifications** - Success/error messages
- **Form Validation** - Client-side + server-side
- **Responsive Design** - Mobile-friendly sidebar collapse
- **Dark Mode** - Tailwind dark mode classes
- **Keyboard Shortcuts** - Navigate with keys

### 8.2 Security

- **CSRF Protection** - Vapor's CSRF middleware
- **Rate Limiting** - Login attempt limits
- **Session Expiry** - Configurable timeout
- **Secure Cookies** - HttpOnly, Secure, SameSite

### 8.3 Performance

- **Caching** - Redis for session storage
- **Pagination** - All list views paginated
- **Lazy Loading** - HTMX for deferred content
- **Asset Bundling** - Minified CSS/JS

---

## Technology Stack Summary

| Layer | Technology |
|-------|------------|
| **Backend** | Vapor 4 (existing) |
| **Templating** | Leaf |
| **Database** | PostgreSQL + Fluent (existing) |
| **Styling** | Tailwind CSS |
| **Interactivity** | HTMX + Alpine.js |
| **Charts** | Chart.js |
| **Drag & Drop** | SortableJS |
| **Sessions** | Fluent Sessions |

---

## Database Migrations

New migration for web sessions:

```swift
struct CreateWebSession: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("web_sessions")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("session_token", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .unique(on: "session_token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("web_sessions").delete()
    }
}
```

---

## Route Summary

| Route Group | Routes | Auth |
|-------------|--------|------|
| `/admin/login`, `/signup`, etc. | 6 | Public |
| `/admin/dashboard` | 1 | Session |
| `/admin/projects/*` | ~15 | Session |
| `/admin/feedback/*` | ~8 | Session |
| `/admin/analytics/*` | 4 | Session |
| `/admin/settings/*` | 5 | Session |
| **Total** | **~40 routes** | |

---

## Estimated Timeline

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| 1. Foundation | 2 weeks | Leaf setup, auth middleware, base templates |
| 2. Authentication | 1 week | All auth pages functional |
| 3. Dashboard | 1 week | Home dashboard with stats |
| 4. Projects | 2 weeks | Full project CRUD + integrations |
| 5. Feedback | 2 weeks | List, Kanban, detail, merge |
| 6. Analytics | 1 week | Users + Events pages |
| 7. Settings | 1 week | Account + subscription |
| 8. Polish | 1 week | Testing, responsive, dark mode |
| **Total** | **~11 weeks** | |

---

## Key Benefits of This Approach

1. **Single Codebase** - All Swift, shared models with API
2. **No API Versioning** - Web controllers call services directly
3. **Consistent Auth** - Shared User model, different auth mechanism
4. **Fast Development** - Leaf templates are simple to build
5. **Modern UX** - HTMX provides SPA-like interactions
6. **SEO Friendly** - Server-rendered HTML
7. **Low Maintenance** - No separate frontend deployment

---

## Next Steps

1. **Approve this plan** - Confirm approach and timeline
2. **Create feature branch** - `feature/web-admin`
3. **Phase 1 implementation** - Start with Leaf setup and auth
4. **Iterative development** - Build and test each phase
5. **User testing** - Get feedback on UX
6. **Production deployment** - Deploy alongside existing server

---

## Files to Create (Summary)

### Controllers (7 new files)
- `WebAuthController.swift`
- `WebDashboardController.swift`
- `WebProjectController.swift`
- `WebFeedbackController.swift`
- `WebAnalyticsController.swift`
- `WebSettingsController.swift`
- `WebIntegrationController.swift`

### Middleware (1 new file)
- `WebSessionAuthMiddleware.swift`

### Models (1 new file)
- `WebSession.swift`

### Migrations (1 new file)
- `CreateWebSession.swift`

### View Contexts (6+ new files)
- `DashboardContext.swift`
- `ProjectContext.swift`
- `FeedbackContext.swift`
- `AnalyticsContext.swift`
- `SettingsContext.swift`
- `AuthContext.swift`

### Leaf Templates (~40 new files)
- 3 layouts
- 10+ partials
- 5 auth pages
- 1 dashboard page
- 6+ project pages
- 4 feedback pages
- 2 analytics pages
- 3 settings pages
- 10 integration pages

### Static Assets (4+ new files)
- `app.css` (Tailwind output)
- `app.js` (custom scripts)
- `htmx.min.js`
- `alpine.min.js`
