# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

> **Note**: See [AGENTS.md](./AGENTS.md) for Swift and SwiftUI coding guidelines.

## Project Overview

Feedback Kit is a feedback collection platform with four subprojects:

| Subproject | Description | Documentation |
|------------|-------------|---------------|
| **SwiftlyFeedbackServer** | Vapor 4 backend with PostgreSQL | [Server CLAUDE.md](./SwiftlyFeedbackServer/CLAUDE.md) |
| **SwiftlyFeedbackKit** | Swift SDK with SwiftUI views (iOS/macOS/visionOS) | [SDK CLAUDE.md](./SwiftlyFeedbackKit/CLAUDE.md) |
| **SwiftlyFeedbackAdmin** | Admin app for managing feedback | [Admin CLAUDE.md](./SwiftlyFeedbackAdmin/CLAUDE.md) |
| **SwiftlyFeedbackDemoApp** | Demo app showcasing the SDK | [Demo CLAUDE.md](./SwiftlyFeedbackDemoApp/CLAUDE.md) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     SwiftlyFeedbackAdmin                         │
│                    (Admin app - iOS/macOS)                       │
│         Manages projects, members, feedback, analytics           │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Bearer Token Auth
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SwiftlyFeedbackServer                         │
│                      (Vapor 4 Backend)                           │
│  /api/v1 - Auth, Projects, Feedback, Votes, Comments, Events     │
└───────────────────────────┬─────────────────────────────────────┘
                            │ X-API-Key Auth
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SwiftlyFeedbackKit                            │
│                     (Swift SDK Package)                          │
│    FeedbackListView, SubmitFeedbackView, FeedbackDetailView      │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Embedded in
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                   SwiftlyFeedbackDemoApp                         │
│                  (Demo integration example)                      │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

- **Language**: Swift 6.2
- **Backend**: Vapor 4, Fluent ORM, PostgreSQL
- **Auth**: Token-based (Bearer for Admin, X-API-Key for SDK)
- **Platforms**: iOS 26+, macOS 12+, visionOS 1+
- **Testing**: Swift Testing (`@Test`) + XCTest

## Quick Start

```bash
# Open workspace
open Swiftlyfeedback.xcworkspace

# Database (Docker)
docker run --name swiftly-postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=swiftly_feedback -p 5432:5432 -d postgres

# Server
cd SwiftlyFeedbackServer && swift run

# See each subproject's CLAUDE.md for specific build/test commands
```

## Git Remotes & Branching

This workspace pushes to multiple GitHub repositories using **git subtree**:

| Remote | Repository | Push Command |
|--------|------------|--------------|
| `origin` | FeedbackKit-Workspace | `git push origin dev` |
| `feedbackkit-sdk` | SwiftlyFeedbackKit | `git subtree push --prefix=SwiftlyFeedbackKit feedbackkit-sdk dev` |
| `feedbackkit-server` | SwiftlyFeedbackServer | `git subtree push --prefix=SwiftlyFeedbackServer feedbackkit-server dev` |
| `feedbackkit-admin` | SwiftlyFeedbackAdmin | `git subtree push --prefix=SwiftlyFeedbackAdmin feedbackkit-admin dev` |
| `feedbackkit-demo` | SwiftlyFeedbackDemoApp | `git subtree push --prefix=SwiftlyFeedbackDemoApp feedbackkit-demo dev` |

**Branches:** `dev` (development), `testflight` (staging), `main` (production)

**Push all remotes:**
```bash
git push origin dev && \
git subtree push --prefix=SwiftlyFeedbackKit feedbackkit-sdk dev && \
git subtree push --prefix=SwiftlyFeedbackServer feedbackkit-server dev && \
git subtree push --prefix=SwiftlyFeedbackAdmin feedbackkit-admin dev && \
git subtree push --prefix=SwiftlyFeedbackDemoApp feedbackkit-demo dev
```

> **Important:** Never use `git push feedbackkit-server dev` directly - always use `git subtree push`.

## Authorization Model

**Project Roles:**
- **Owner**: Full access (delete, archive, manage members, regenerate API key, transfer ownership)
- **Admin**: Manage settings/members, update/delete feedback
- **Member**: View and respond to feedback
- **Viewer**: Read-only

**Key Rules:**
- Archived projects: reads allowed, writes blocked
- Voting blocked on `completed`/`rejected` status feedback
- Feedback creators automatically get a vote (voteCount starts at 1)
- Voters can opt-in to status change email notifications (Team tier)
- One-click unsubscribe via permission key UUID

**Feedback Merging:**
- `POST /feedbacks/merge` combines duplicate items
- Migrates votes (de-duplicated by user) and comments
- Comments prefixed with `[Originally on: <title>]`
- Recalculates vote count and MRR

## Subscription Tiers

| Tier | Projects | Feedback | Members | Integrations |
|------|----------|----------|---------|--------------|
| Free | 1 | 10/project | No | No |
| Pro | 2 | Unlimited | No | Yes |
| Team | Unlimited | Unlimited | Yes | Yes |

Server enforces limits via 402 Payment Required responses. See [Admin CLAUDE.md](./SwiftlyFeedbackAdmin/CLAUDE.md) for client-side subscription handling.

## Feedback Statuses

| Status | Color | Can Vote |
|--------|-------|----------|
| pending | Gray | Yes |
| approved | Blue | Yes |
| in_progress | Orange | Yes |
| testflight | Cyan | Yes |
| completed | Green | No |
| rejected | Red | No |

## Integrations

Supported: Slack, GitHub, Notion, ClickUp, Linear, Monday.com, Trello, Airtable, Asana, Basecamp

All support: create/bulk create, status sync, comment sync, link tracking, active toggles.

See [Server CLAUDE.md](./SwiftlyFeedbackServer/CLAUDE.md) for API endpoints and configuration.

## Web Admin Interface

The server includes a full web admin interface built with Leaf templates:
- Dashboard with analytics and KPIs
- Feedback management with AJAX voting
- Project settings and member management
- Integration configuration UI
- Ownership transfer functionality

Access via browser at the server URL (requires authentication).

## Payment Processing

**App Store (iOS/macOS):**
- Server Notifications v2 (JWS format)
- Handles: SUBSCRIBED, DID_RENEW, EXPIRED, GRACE_PERIOD, REFUND
- Automatic tier mapping from product IDs

**Stripe (Web):**
- Checkout sessions with promotion codes
- Billing portal for subscription management
- Webhook signature verification (HMAC-SHA256)

## Push Notifications

APNs integration for real-time notifications:
- New feedback, comments, votes, status changes
- Per-user and per-project notification preferences
- Deep linking with `feedbackkit://` URL scheme
- Automatic device token lifecycle management

## Code Conventions

- `@main` for entry points
- `@Observable` + `Bindable()` for state management
- `#Preview` macro for previews
- `@Test` macro for tests
- Models: `Codable`, `Sendable`, `Equatable`
- Platform conditionals: `#if os(macOS)` / `#if os(iOS)`

## Roadmap

**Multi-Platform SDKs (Planned):**
- JavaScript SDK (npm)
- React Native SDK (npm)
- Flutter SDK (pub.dev)
- Kotlin SDK (Maven)

See [Multi-Platform SDK Plan](./SwiftlyFeedbackKit/docs/Plans/Multi-Platform-SDK-Plan.md) for details.
