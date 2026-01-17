# CLAUDE.md - Feedback Kit Admin

Admin application for managing feedback projects and members. Runs on iOS, iPadOS, and macOS.

## Build & Test

**Always test on both iOS and macOS to catch platform-specific issues.**

```bash
# iOS build
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackAdmin -sdk iphonesimulator -configuration Debug

# macOS build
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackAdmin -destination 'platform=macOS' -configuration Debug

# iOS tests
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackAdmin test -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'

# Single test
xcodebuild test -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackAdmin -only-testing:SwiftlyFeedbackAdminTests/TestClassName/testMethodName -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Directory Structure

```
SwiftlyFeedbackAdmin/
├── SwiftlyFeedbackAdminApp.swift
├── Configuration/
│   └── AppConfiguration.swift    # Server environments
├── Models/
├── ViewModels/
├── Views/
│   ├── RootView.swift, MainTabView.swift
│   ├── Home/, Auth/, Onboarding/
│   ├── Projects/, Feedback/, Users/, Events/
│   ├── Settings/, Components/
├── Services/
│   ├── AdminAPIClient.swift
│   ├── AuthService.swift
│   ├── SubscriptionService.swift
│   └── Storage/                  # Secure storage layer
└── Utilities/
    └── BuildEnvironment.swift
```

## Storage Architecture

**Only use Keychain storage. Never use UserDefaults or @AppStorage.**

All persistent data uses Keychain via the `Storage/` module:

```
Storage/
├── SecureStorageManager.swift  # Unified interface
├── KeychainManager.swift       # Low-level operations
├── StorageKey.swift            # Type-safe keys
└── SecureAppStorage.swift      # SwiftUI property wrapper
```

### SecureStorageManager

Environment-aware storage with automatic key scoping:

```swift
// Get/set values (scoped to current environment)
let token: String? = SecureStorageManager.shared.get(.authToken)
SecureStorageManager.shared.set("token", for: .authToken)

// Convenience properties
SecureStorageManager.shared.authToken = "..."
SecureStorageManager.shared.hasCompletedOnboarding = true

// Bulk operations
SecureStorageManager.shared.clearEnvironment(.development)
```

### StorageKey Scopes

| Key | Scope | Description |
|-----|-------|-------------|
| `.authToken` | Environment | Bearer token |
| `.keepMeSignedIn` | Environment | Auto re-login toggle |
| `.savedEmail`, `.savedPassword` | Environment | Credentials for auto re-login |
| `.hasCompletedOnboarding` | Environment | Onboarding completion |
| `.feedbackViewMode` | Environment | List/Kanban preference |
| `.selectedEnvironment` | Global | Current server |
| `.simulatedSubscriptionTier` | Debug | Tier simulation |

### SecureAppStorage

SwiftUI property wrapper for Keychain-backed storage:

```swift
@SecureAppStorage(.feedbackViewMode) private var viewMode: String = "list"
```

## Server Environments

Configured via `AppEnvironment` enum in `Configuration/AppConfiguration.swift`:

| Environment | URL | Color | Available In |
|-------------|-----|-------|--------------|
| Localhost | `http://localhost:8080` | Purple | DEBUG only |
| Development | `api.feedbackkit.dev...` | Blue | DEBUG only |
| TestFlight | `api.feedbackkit.testflight...` | Orange | DEBUG, TestFlight |
| Production | `api.feedbackkit.prod...` | Red | All builds |

```swift
AppConfiguration.shared.environment      // Current
AppConfiguration.shared.baseURL          // Server URL
AppConfiguration.shared.switchTo(.development)  // Switch (logs out user)
```

**Command line args (DEBUG):** `--localhost`, `--dev-mode`, `--testflight-mode`, `--prod-mode`

## Build Environment Detection

`BuildEnvironment` in `Utilities/BuildEnvironment.swift`:

```swift
BuildEnvironment.isDebug              // Xcode DEBUG
BuildEnvironment.isTestFlight         // TestFlight
BuildEnvironment.isAppStore           // App Store
BuildEnvironment.canShowTestingFeatures  // DEBUG || TestFlight
```

Add `TESTFLIGHT` to Active Compilation Conditions for reliable TestFlight detection.

## Authentication Flow

1. Login/Signup → Email verification (8-char code) → Token stored in Keychain

**Keep Me Signed In:**
- Toggle saves credentials to Keychain
- Auto re-login on app restart or token expiry
- Credentials cleared on explicit logout

**Password Reset:** Forgot Password → Code + new password → All sessions invalidated

## Onboarding Flow

1. Welcome screens (3)
2. Create Account
3. Verify Email
4. Paywall (subscription options)
5. Project Choice (Create/Join/Skip)
6. Create or Join Project
7. Completion

`OnboardingManager` singleton tracks state in Keychain. Reset via Developer Center.

## RootView Navigation

- Not authenticated + not onboarded → `OnboardingContainerView`
- Not authenticated + onboarded → `AuthContainerView`
- Authenticated + needs verification → `EmailVerificationView`
- Authenticated + onboarded → `MainTabView`

## View Modes

| View | Options | Storage |
|------|---------|---------|
| Project List | List, Table, Grid | `@SecureAppStorage` |
| Feedback Dashboard | List, Kanban | `@SecureAppStorage` |

Preferences are environment-scoped.

## Subscription System (RevenueCat)

`SubscriptionService.shared` manages subscriptions:

```swift
subscriptionService.currentTier        // Actual from RevenueCat
subscriptionService.effectiveTier      // Considers simulation
subscriptionService.meetsRequirement(.pro)  // Check access
```

**Tier Simulation (DEBUG only):**
```swift
subscriptionService.simulatedTier = .pro
subscriptionService.clearSimulatedTier()
```

Available in Developer Center → Subscription Simulation.

**402 Handling Pattern:**
1. API returns 402 → Dismiss current sheet with flag
2. On dismiss, show PaywallView
3. After paywall, optionally re-open original sheet

## Developer Center

Available in DEBUG and TestFlight builds:
- **macOS**: Menu bar → Feedback Kit → Developer Center (⌘⇧D)
- **iOS**: Settings → Developer section

**Features:**
- Server environment switching
- Reset onboarding, auth, storage
- Clear feedback, delete projects
- Storage key viewer

**DEBUG-only:**
- Generate dummy data
- Subscription simulation
- Full database reset

## Deep Linking

URL scheme: `feedbackkit://`

| URL | Action |
|-----|--------|
| `feedbackkit://settings` | Open Settings tab |
| `feedbackkit://settings/notifications` | Open Settings (email prefs) |
| `feedbackkit://feedback/{id}` | Open feedback detail (planned) |
| `feedbackkit://project/{id}` | Open project (planned) |

`DeepLinkManager` handles URL parsing. Views respond to `pendingDestination` changes.

## Cross-Platform UI Guidelines

All views must work on iOS, iPadOS, and macOS.

### Sheet View Pattern

```swift
NavigationStack {
    Form {
        // Content sections
    }
    .formStyle(.grouped)  // REQUIRED for macOS
    .navigationTitle("Title")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { /* action */ }
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }
    .interactiveDismissDisabled(isLoading)
    .overlay {
        if isLoading {
            Color.black.opacity(0.1).ignoresSafeArea()
            ProgressView().controlSize(.large)
        }
    }
}
// NO frame modifiers - let sheet size naturally
```

### Key Rules

1. **Always use `.formStyle(.grouped)`** for proper macOS insets
2. **Never set explicit frame sizes on sheets**
3. **Platform-specific modifiers only when necessary:**
   - `.navigationBarTitleDisplayMode(.inline)` - iOS only
   - `.keyboardType()` / `.textInputAutocapitalization()` - iOS only
4. **Extract complex rows into private structs**
5. **Use Section headers and footers** for context
6. **Add loading overlay** during async operations
7. **Standard toolbar placements:** `.cancellationAction`, `.confirmationAction`, `.primaryAction`

### Empty State Pattern

```swift
VStack(spacing: 12) {
    Image(systemName: "icon.name")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
    Text("Title")
        .font(.headline)
    Text("Description")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 20)
```

### Testing Checklist

- [ ] iPhone (compact width)
- [ ] iPad (regular width, split view)
- [ ] macOS (window resizing)
- [ ] Form sections have proper insets
- [ ] Buttons are tappable/clickable
- [ ] Text is readable, not truncated

## Swift 6 Concurrency

Admin app uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

```swift
// DTOs must be nonisolated for Codable
nonisolated struct Feedback: Codable, Sendable { ... }

// Thread-safe services opt out
nonisolated enum KeychainService { ... }

// Global state flags
nonisolated(unsafe) private var _loggingEnabled = true
```

**Common fixes:**
- "Codable cannot be used in actor-isolated context" → Add `nonisolated`
- "Static method cannot be called from outside actor" → Mark type as `nonisolated`

## Platform Navigation

**macOS:** `NavigationSplitView` with sidebar sections (Home, Projects, Feedback, Users, Events, Feature Requests, Settings)

**iOS:** `TabView` with `.tabViewStyle(.sidebarAdaptable)` for iPad

## Feature Requests Tab

Dog-fooding: Uses SwiftlyFeedbackKit for the Admin app's own feature requests.

SDK configured at launch via `AppConfiguration.shared.configureSDK()` with environment-specific API key.

## Logging

```swift
AppLogger.isEnabled = false  // Disable all

// Categories: api, auth, viewModel, view, data, keychain, subscription
AppLogger.api.info("Loading...")
```

Uses `nonisolated` + `@unchecked Sendable` for Swift 6 compatibility.
