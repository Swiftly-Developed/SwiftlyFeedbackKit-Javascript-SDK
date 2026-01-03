# CLAUDE.md - SwiftlyFeedbackAdmin

Admin application for managing feedback projects, members, and viewing feedback.

## Build & Test

```bash
# Build via workspace
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackAdmin -sdk iphonesimulator -configuration Debug

# Test
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackAdmin test -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Directory Structure

```
SwiftlyFeedbackAdmin/
├── SwiftlyFeedbackAdminApp.swift   # App entry point
├── Models/
│   ├── AuthModels.swift            # User, token models
│   └── ProjectModels.swift         # Project, member models
├── ViewModels/
│   ├── AuthViewModel.swift         # Authentication state
│   └── ProjectViewModel.swift      # Project management state
├── Views/
│   ├── RootView.swift              # Root navigation
│   ├── MainTabView.swift           # Tab bar navigation
│   ├── Auth/
│   │   ├── AuthContainerView.swift    # Auth flow container
│   │   ├── LoginView.swift            # Login form
│   │   ├── SignupView.swift           # Signup form
│   │   └── EmailVerificationView.swift # Email verification screen
│   ├── Projects/
│   │   ├── ProjectListView.swift      # Project list with 3 view modes (list/table/grid)
│   │   ├── ProjectDetailView.swift    # Project details & feedback
│   │   ├── CreateProjectView.swift    # Create new project sheet
│   │   ├── ProjectMembersView.swift   # Manage members
│   │   └── AcceptInviteView.swift     # Accept project invite
│   └── Settings/
│       └── SettingsView.swift      # App settings
└── Services/
    ├── AdminAPIClient.swift        # API client for admin endpoints
    ├── AuthService.swift           # Authentication logic
    └── KeychainService.swift       # Secure token storage
```

## Authentication Flow

1. User logs in via `LoginView` or signs up via `SignupView`
2. New users must verify email via `EmailVerificationView` (8-character code)
3. Token stored securely in Keychain via `KeychainService`
4. `AuthViewModel` manages authentication state including `needsEmailVerification`
5. `AdminAPIClient` includes Bearer token in requests

## Code Patterns

### ViewModels
- Use `@Observable` classes marked with `@MainActor`
- Follow AGENTS.md guidelines

### Services
- `AdminAPIClient` handles all HTTP requests
- Uses async/await for networking
- Bearer token authentication

### Views
- Follow AGENTS.md SwiftUI guidelines
- Use `NavigationStack` for navigation
- Extract subviews into separate `View` structs
- Use `#if os(iOS)` / `#if os(macOS)` for platform-specific code

## Project List View Modes

The `ProjectListView` supports three view modes (persisted via `@AppStorage`):

| Mode | Icon | Description |
|------|------|-------------|
| List | `list.bullet` | Compact rows with project icon, name, description |
| Table | `tablecells` | Detailed rows with columns (name, feedback count, role, date) |
| Grid | `square.grid.2x2` | Card-based layout with full project info |

## Cross-Platform Considerations

- Use `Color(.systemBackground)` on iOS, `Color(nsColor: .textBackgroundColor)` on macOS
- Use `#if os(iOS)` for iOS-only modifiers like `.textInputAutocapitalization`
- Use `.presentationDetents` on iOS for sheet sizing
- Use `.frame(minWidth:minHeight:)` on macOS for window sizing
