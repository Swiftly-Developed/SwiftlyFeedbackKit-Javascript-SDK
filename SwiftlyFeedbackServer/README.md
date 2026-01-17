# FeedbackKit Server

Vapor 4 backend API server for FeedbackKit.

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Vapor 4](https://img.shields.io/badge/Vapor-4-blue.svg)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-336791.svg)

## Features

- **RESTful API** — Clean `/api/v1` endpoints for feedback, voting, and comments
- **Dual authentication** — Bearer tokens for admin, API keys for SDK
- **Email notifications** — Resend-powered emails for verification, invites, and status updates
- **Integrations** — Slack, GitHub, Notion, Linear, ClickUp, Monday.com, Trello
- **Analytics** — Event tracking and dashboard stats
- **MRR tracking** — Associate feedback with customer revenue

## Requirements

- Swift 6.2+
- PostgreSQL 15+
- Docker (recommended for local development)

## Quick Start

### 1. Start PostgreSQL

```bash
docker run --name swiftly-postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=swiftly_feedback \
  -p 5432:5432 \
  -d postgres
```

### 2. Build and Run

```bash
swift build
swift run
```

The server starts at `http://localhost:8080`.

### 3. Run Tests

```bash
swift test
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_HOST` | PostgreSQL host | `localhost` |
| `DATABASE_PORT` | PostgreSQL port | `5432` |
| `DATABASE_USERNAME` | Database user | `postgres` |
| `DATABASE_PASSWORD` | Database password | `postgres` |
| `DATABASE_NAME` | Database name | `swiftly_feedback` |
| `RESEND_API_KEY` | Resend API key for emails | - |
| `TRELLO_API_KEY` | Trello integration API key | - |

## API Overview

All endpoints are prefixed with `/api/v1`.

### Authentication

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/signup` | Create account |
| POST | `/auth/login` | Login (returns token) |
| GET | `/auth/me` | Get current user |
| POST | `/auth/logout` | Logout |
| POST | `/auth/verify-email` | Verify email with code |
| POST | `/auth/forgot-password` | Request password reset |
| POST | `/auth/reset-password` | Reset with code |

### Projects (Bearer auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects` | List user's projects |
| POST | `/projects` | Create project |
| GET | `/projects/:id` | Get project details |
| PATCH | `/projects/:id` | Update project |
| DELETE | `/projects/:id` | Delete project |
| POST | `/projects/:id/archive` | Archive project |
| POST | `/projects/:id/regenerate-key` | Regenerate API key |

### Feedback (X-API-Key auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/feedbacks` | List feedback |
| POST | `/feedbacks` | Submit feedback |
| GET | `/feedbacks/:id` | Get feedback details |
| PATCH | `/feedbacks/:id` | Update feedback |
| DELETE | `/feedbacks/:id` | Delete feedback |
| POST | `/feedbacks/merge` | Merge feedback items |

### Votes (X-API-Key auth)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/feedbacks/:id/votes` | Vote for feedback |
| DELETE | `/feedbacks/:id/votes` | Remove vote |

### Comments (X-API-Key auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/feedbacks/:id/comments` | List comments |
| POST | `/feedbacks/:id/comments` | Add comment |
| DELETE | `/feedbacks/:id/comments/:commentId` | Delete comment |

### Events

| Method | Path | Description |
|--------|------|-------------|
| POST | `/events/track` | Track event (X-API-Key) |
| GET | `/events/project/:id/stats` | Get event stats (Bearer) |

### Dashboard (Bearer auth)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/dashboard/home` | KPIs across all projects |

## Integrations

All integrations follow the same pattern:

- **Settings:** `PATCH /projects/:id/{integration}`
- **Create item:** `POST /projects/:id/{integration}/{item}`
- **Bulk create:** `POST /projects/:id/{integration}/{items}`

| Integration | Push To | Status Sync |
|-------------|---------|-------------|
| Slack | Webhook | Notifications |
| GitHub | Issues | Close/reopen |
| Notion | Database pages | Status property |
| Linear | Issues | Workflow states |
| ClickUp | Tasks | Status |
| Monday.com | Board items | Status column |
| Trello | Cards | List-based |

## Project Structure

```
Sources/App/
├── Controllers/     # Route handlers
├── Models/          # Fluent models
├── Migrations/      # Database migrations
├── DTOs/            # Data transfer objects
├── Services/        # Email, integrations
├── Jobs/            # Background tasks
├── configure.swift  # App configuration
└── routes.swift     # Route registration
```

## Authorization Model

**Project Roles:**
- **Owner** — Full access (delete, archive, manage members)
- **Admin** — Manage settings, update/delete feedback
- **Member** — View and respond to feedback
- **Viewer** — Read-only access

**Auth Methods:**
- `Bearer` token — Admin app (user accounts)
- `X-API-Key` header — SDK (project API keys)

## Related Projects

- [SwiftlyFeedbackKit](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit) — Swift SDK
- [SwiftlyFeedbackAdmin](https://github.com/Swiftly-Developed/SwiftlyFeedbackAdmin) — Admin app
- [SwiftlyFeedbackDemoApp](https://github.com/Swiftly-Developed/SwiftlyFeedbackDemoApp) — Demo app

## License

FeedbackKit Server is available under the MIT license.
