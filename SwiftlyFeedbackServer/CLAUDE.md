# CLAUDE.md - Feedback Kit Server

Vapor 4 backend API server with PostgreSQL.

## Build & Run

```bash
swift build
swift run                    # http://localhost:8080
swift test
swift test --filter TestClassName/testMethodName  # Single test
```

**Environment Variables:**
- `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `DATABASE_NAME`
- `RESEND_API_KEY` - Email service
- `TRELLO_API_KEY` - Trello integration

## Directory Structure

```
Sources/App/
├── Controllers/     # Route handlers
├── Models/          # Fluent models
├── Migrations/      # Database migrations
├── DTOs/            # Request/response types
├── Services/        # Email, integrations
├── Jobs/            # Background tasks (cleanup scheduler)
├── configure.swift  # App configuration
├── routes.swift     # Route registration
└── entrypoint.swift # Server entry point
```

## API Endpoints

All endpoints prefixed with `/api/v1`.

### Authentication (No auth / Bearer)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | /auth/signup | - | Create account |
| POST | /auth/login | - | Login (returns token) |
| GET | /auth/me | Bearer | Current user |
| POST | /auth/logout | Bearer | Logout |
| POST | /auth/verify-email | - | Verify with 8-char code |
| POST | /auth/resend-verification | Bearer | Resend code |
| PUT | /auth/password | Bearer | Change password |
| DELETE | /auth/account | Bearer | Delete account |
| POST | /auth/forgot-password | - | Request reset email |
| POST | /auth/reset-password | - | Reset with code |

### Projects (Bearer auth)

| Method | Path | Role | Description |
|--------|------|------|-------------|
| GET | /projects | - | List user's projects |
| POST | /projects | - | Create project |
| GET | /projects/:id | - | Get details |
| PATCH | /projects/:id | Owner/Admin | Update |
| DELETE | /projects/:id | Owner | Delete |
| POST | /projects/:id/archive | Owner | Archive |
| POST | /projects/:id/unarchive | Owner | Unarchive |
| POST | /projects/:id/regenerate-key | Owner | New API key |
| PATCH | /projects/:id/statuses | Owner/Admin | Update allowed statuses |
| PATCH | /projects/:id/email-notify-statuses | Owner/Admin | Configure email notifications |
| POST | /projects/:id/transfer-ownership | Owner | Transfer to another user |

### Project Members (Bearer auth)

| Method | Path | Role | Description |
|--------|------|------|-------------|
| GET | /projects/:id/members | - | List members |
| POST | /projects/:id/members | Owner/Admin | Add by email |
| PATCH | /projects/:id/members/:memberId | Owner/Admin | Update role |
| DELETE | /projects/:id/members/:memberId | Owner/Admin | Remove |

### Feedback (X-API-Key auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | /feedbacks | List (?status=, ?category=) |
| POST | /feedbacks | Submit (auto-votes for creator) |
| GET | /feedbacks/:id | Details |
| PATCH | /feedbacks/:id | Update (Bearer + access) |
| DELETE | /feedbacks/:id | Delete (Bearer + Owner/Admin) |
| POST | /feedbacks/merge | Merge items (Bearer + Owner/Admin) |

### Votes (X-API-Key auth)

| Method | Path | Description |
|--------|------|-------------|
| POST | /feedbacks/:id/votes | Vote (blocked if archived/completed/rejected) |
| DELETE | /feedbacks/:id/votes | Remove vote |
| GET | /votes/unsubscribe?key=UUID | One-click unsubscribe (no auth, returns HTML) |

**Vote Request Body:**
```json
{
  "userId": "string",
  "email": "string (optional)",
  "notifyStatusChange": "bool (optional, default false)"
}
```

### Comments (X-API-Key auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | /feedbacks/:id/comments | List |
| POST | /feedbacks/:id/comments | Add (blocked if archived) |
| DELETE | /feedbacks/:id/comments/:commentId | Delete |

### SDK Users & Events (Bearer auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | /users/project/:projectId | List users for project |
| GET | /users/project/:projectId/stats | Stats (total, MRR) |
| POST | /events/track | Track event (X-API-Key) |
| GET | /events/project/:projectId/stats | Stats (?days=N) |
| GET | /dashboard/home | KPIs across all projects |

## Integrations

All integrations follow the same pattern:

- **Settings:** `PATCH /projects/:id/{integration}`
- **Single create:** `POST /projects/:id/{integration}/{item}`
- **Bulk create:** `POST /projects/:id/{integration}/{items}`
- **Discovery:** Various endpoints for pickers (teams, boards, databases)

### Integration Endpoints

| Integration | Settings Path | Create Path | Discovery |
|-------------|---------------|-------------|-----------|
| Slack | /slack | - | - |
| GitHub | /github | /github/issue(s) | - |
| ClickUp | /clickup | /clickup/task(s) | /workspaces, /spaces, /folders, /lists |
| Notion | /notion | /notion/page(s) | /databases, /database/:id/properties |
| Monday | /monday | /monday/item(s) | /boards, /boards/:id/groups, /columns |
| Linear | /linear | /linear/issue(s) | /teams, /projects, /states, /labels |
| Trello | /trello | /trello/card(s) | /boards, /boards/:id/lists |
| Airtable | /airtable | /airtable/record(s) | /bases, /bases/:id/tables, /fields |
| Asana | /asana | /asana/task(s) | /workspaces, /projects, /sections |
| Basecamp | /basecamp | /basecamp/todo(s) | /accounts, /projects, /todolists |

### Status Mapping

All integrations map feedback status similarly:
- `pending` → backlog/to do
- `approved` → approved/unstarted
- `in_progress` → in progress/started
- `testflight` → in review/started
- `completed` → complete/done
- `rejected` → closed/canceled

## Email Service

`Services/EmailService.swift` handles notifications via Resend API.

**Brand Colors:**
- Primary: `#F7A50D` (FeedbackKit orange)
- Gradient: `#FFB830` → `#F7A50D` → `#E85D04`

**Email Types:**
- Email verification, password reset
- Project invites, ownership transfer
- New feedback, new comments, status changes
- Voter status notifications (with unsubscribe link)

**Helpers:**
- `emailHeader(title:)` - Gradient header with logo
- `emailFooter(message:)` - "Powered by Feedback Kit" footer

## Vote Email Notifications

Voters can opt-in to receive status change notifications.

**Database Fields (votes table):**
- `email` (VARCHAR, nullable)
- `notify_status_change` (BOOLEAN, default false)
- `permission_key` (UUID, nullable) - For one-click unsubscribe

**Flow:**
1. Vote with `email` + `notifyStatusChange: true`
2. Server generates `permissionKey` UUID
3. On status change, voters with opt-in receive emails
4. Unsubscribe: `GET /votes/unsubscribe?key=UUID` (no auth)
5. Clicking clears the opt-in and permission key

## Rejection Reasons

When setting status to `rejected`, include optional `rejectionReason` (max 500 chars):
- Stored in `rejection_reason` field
- Included in status change notification emails
- Cleared when status changes to non-rejected

## Feedback Merging

`POST /feedbacks/merge` with `primary_feedback_id` and `secondary_feedback_ids[]`:
- Moves votes (de-duplicated by user)
- Migrates comments with origin prefix
- Recalculates MRR
- Soft-deletes secondary items (`merged_into_id`, `merged_at`)

## Automatic Cleanup (Non-Production)

Non-production environments auto-delete feedback older than 7 days:

| Environment | Cleanup |
|-------------|---------|
| Localhost | Every 24h |
| Development | Every 24h |
| TestFlight | Every 24h |
| Production | **Disabled** |

Implementation: `Jobs/FeedbackCleanupJob.swift`

## Server-Side Tier Enforcement

Returns 402 Payment Required for tier violations:

| Feature | Tier | Limit |
|---------|------|-------|
| Projects | Pro/Team | 1 (Free), 2 (Pro), ∞ (Team) |
| Feedback | Pro | 10/project (Free) |
| Team members | Team | Owner + invitee need Team |
| Integrations | Pro | All integration endpoints |
| Configurable statuses | Pro | PATCH /statuses |

## Code Patterns

**New Model:**
1. Create in `Models/`
2. Add migration in `Migrations/`
3. Register migration in `configure.swift`
4. Add DTO if needed

**New Controller:**
1. Create in `Controllers/`
2. Implement `RouteCollection`
3. Register in `routes.swift`

**Auth Patterns:**
```swift
// Bearer token
let user = try req.auth.require(User.self)

// API key (middleware)
// X-API-Key header validated by APIKeyMiddleware
```
