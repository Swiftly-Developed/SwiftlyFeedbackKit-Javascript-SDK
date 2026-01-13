# FeedbackKit Admin

Native admin app for managing FeedbackKit projects and feedback.

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS-blue.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-5-green.svg)

## Features

- **Project management** — Create, configure, and archive projects
- **Feedback dashboard** — List and Kanban views with drag-and-drop status updates
- **Team collaboration** — Invite members with role-based permissions
- **Integrations** — Connect to Slack, GitHub, Notion, Linear, ClickUp, Monday.com, Trello
- **Analytics** — View events, user stats, and MRR tracking
- **Multi-platform** — Native iOS and macOS apps from a single codebase

## Requirements

- iOS 26.0+ / macOS 26.0+
- Xcode 26.0+
- Swift 6.2+

## Build

Build via the workspace for proper dependency resolution:

```bash
# iOS
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace \
  -scheme SwiftlyFeedbackAdmin \
  -sdk iphonesimulator \
  -configuration Debug

# macOS
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace \
  -scheme SwiftlyFeedbackAdmin \
  -destination 'platform=macOS' \
  -configuration Debug
```

**Important:** Always test on both iOS and macOS to catch platform-specific issues.

## Test

```bash
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace \
  -scheme SwiftlyFeedbackAdmin test \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## App Structure

### iOS
- Tab-based navigation with sidebar adaptable for iPad
- Tabs: Home, Projects, Feedback, Users, Events, Feature Requests, Settings

### macOS
- NavigationSplitView with sidebar
- Same feature set as iOS with keyboard shortcuts

## Key Features

### Authentication
- Email/password login with "Keep Me Signed In" option
- Email verification with 8-character code
- Password reset flow with session invalidation

### Onboarding
New users go through a guided setup:
1. Welcome screens
2. Account creation
3. Email verification
4. Project creation or join via invite

### Feedback Management
- **List view** — Sortable, filterable feedback list
- **Kanban view** — Drag-and-drop cards between status columns
- **Merge** — Combine duplicate feedback items
- **Bulk actions** — Multi-select for status changes and integration sync

### Integrations
Push feedback to external tools:
- **Slack** — Notifications for new feedback and status changes
- **GitHub** — Create issues with labels
- **Notion** — Sync to database pages
- **Linear** — Create issues in teams/projects
- **ClickUp** — Create tasks in lists
- **Monday.com** — Create board items
- **Trello** — Create cards in lists

### Analytics
- Event tracking with daily/weekly/monthly charts
- User stats including MRR
- Per-project breakdown

## Server Environments

The app supports multiple server environments:

| Environment | Available In |
|-------------|--------------|
| Localhost | DEBUG only |
| Development | DEBUG only |
| TestFlight | DEBUG, TestFlight builds |
| Production | All builds |

Switch environments via Settings → Developer Center (DEBUG/TestFlight builds only).

## Developer Center

Available in DEBUG and TestFlight builds:
- Switch server environments
- Reset onboarding and authentication
- Generate test data
- Clear storage
- Subscription simulation (DEBUG only)

Access via:
- **iOS:** Settings → Developer section
- **macOS:** Menu bar → Feedback Kit → Developer Center (⌘⇧D)

## Subscriptions

RevenueCat-powered subscription management:

| Tier | Projects | Feedback | Team Members |
|------|----------|----------|--------------|
| Free | 1 | 10/project | No |
| Pro | 2 | Unlimited | No |
| Team | Unlimited | Unlimited | Yes |

## Project Structure

```
SwiftlyFeedbackAdmin/
├── SwiftlyFeedbackAdminApp.swift
├── Models/           # Data models
├── ViewModels/       # View state management
├── Views/
│   ├── Auth/         # Login, signup, verification
│   ├── Onboarding/   # New user flow
│   ├── Home/         # Dashboard
│   ├── Projects/     # Project management
│   ├── Feedback/     # Feedback views (list, kanban, detail)
│   ├── Users/        # SDK user analytics
│   ├── Events/       # Event tracking
│   └── Settings/     # App settings, developer tools
├── Services/         # API client, auth, subscriptions
├── Configuration/    # Environment setup
└── Utilities/        # Helpers, extensions
```

## Related Projects

- [SwiftlyFeedbackKit](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit) — Swift SDK
- [SwiftlyFeedbackServer](https://github.com/Swiftly-Developed/SwiftlyFeedbackServer) — Backend server
- [SwiftlyFeedbackDemoApp](https://github.com/Swiftly-Developed/SwiftlyFeedbackDemoApp) — Demo app

## License

FeedbackKit Admin is available under the MIT license.
