# CLAUDE.md - SwiftlyFeedback

> **Note**: Also see [AGENTS.md](./AGENTS.md) for Swift and SwiftUI coding guidelines.

## Project Overview

SwiftlyFeedback is a feedback collection and management platform consisting of:

- **SwiftlyFeedbackServer** - Vapor backend API server with PostgreSQL database
- **SwiftlyFeedbackKit** - Swift client SDK with SwiftUI views for iOS/macOS/visionOS
- **SwiftlyFeedbackAdmin** - Admin application for managing feedback
- **SwiftlyFeedbackDemoApp** - Demo application showcasing the SDK

Each project has its own `CLAUDE.md` with project-specific details.

## Tech Stack

- **Language**: Swift 6.0
- **Backend**: Vapor 4 with Fluent ORM and PostgreSQL
- **Authentication**: Token-based authentication with bcrypt password hashing
- **Client SDK**: Swift Package with SwiftUI views
- **Platforms**: iOS 15+, macOS 12+, visionOS 1+
- **Testing**: Swift Testing (`@Test` macro) + XCTest

## Directory Structure

```
SwiftlyFeedback/
├── Swiftlyfeedback.xcworkspace/      # Shared workspace (open this)
├── SwiftlyFeedbackServer/            # Vapor backend (see its CLAUDE.md)
├── SwiftlyFeedbackKit/               # Client SDK (see its CLAUDE.md)
├── SwiftlyFeedbackAdmin/             # Admin app (see its CLAUDE.md)
└── SwiftlyFeedbackDemoApp/           # Demo app (see its CLAUDE.md)
```

## Quick Start

```bash
# Open workspace
open Swiftlyfeedback.xcworkspace

# Start database (Docker)
docker run --name swiftly-postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=swiftly_feedback -p 5432:5432 -d postgres

# Run server
cd SwiftlyFeedbackServer && swift run
```

## Authorization Model

### Project Roles
- **Owner**: Full access - delete project, archive/unarchive, manage members, regenerate API key
- **Admin**: Manage project settings and members, update/delete feedback
- **Member**: View feedback and respond
- **Viewer**: Read-only access

### Archive Behavior
- Archived projects allow reads but block new feedback, votes, and comments
- Only owner can archive/unarchive

## Code Conventions

- Use `@main` attribute for app entry points
- Use SwiftUI declarative syntax with modifier chaining
- Use `#Preview` macro for SwiftUI previews
- Use Swift Testing (`@Test` macro) for unit tests
- Models are `Codable`, `Sendable`, and `Equatable`
- API client uses Swift concurrency (async/await)
- All user input is validated and trimmed
- Email validation uses regex pattern matching
- Passwords are hashed with bcrypt
