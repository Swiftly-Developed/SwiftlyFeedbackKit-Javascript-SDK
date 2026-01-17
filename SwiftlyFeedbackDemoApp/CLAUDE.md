# CLAUDE.md - Feedback Kit Demo App

Demo application showcasing SDK integration patterns for iOS and macOS.

## Build & Test

```bash
# Build
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackDemoApp -sdk iphonesimulator -configuration Debug

# Test
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace -scheme SwiftlyFeedbackDemoApp test -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Directory Structure

```
SwiftlyFeedbackDemoApp/
├── SwiftlyFeedbackDemoAppApp.swift   # Entry point with SDK config
├── ContentView.swift                  # Platform-adaptive navigation
├── Models/
│   └── AppSettings.swift             # @Observable settings with persistence
└── Views/
    ├── HomeView.swift                # Welcome screen
    └── ConfigurationView.swift       # SDK configuration form
```

## App Structure

### iOS
`TabView` with three tabs: Home, Feedback, Settings

### macOS
`NavigationSplitView` with sidebar: Home, Feedback, Settings
- Minimum window: 800x500
- Default window: 1000x700

## Screens

1. **Home** - Welcome screen with feature highlights and getting started guide
2. **Feedback** - SDK's `FeedbackListView` for browsing and submitting feedback
3. **Settings** - Configuration form demonstrating SDK options:
   - User profile (email, name, custom ID)
   - Subscription settings (amount, billing cycle for MRR)
   - Permissions (allow/disallow submission with custom message)
   - SDK behavior (vote undo, comments, email field)
   - Display options (badges, vote count, description expansion)

## SDK Integration Examples

### Configuration at Launch

```swift
SwiftlyFeedback.configure(with: "your_api_key")
SwiftlyFeedback.theme.primaryColor = .color(.blue)
SwiftlyFeedback.theme.statusColors.completed = .green
```

### User Identification

```swift
SwiftlyFeedback.updateUser(customID: "user123")
```

### Payment/Subscription Tracking

```swift
SwiftlyFeedback.updateUser(payment: .monthly(9.99))
SwiftlyFeedback.clearUserPayment()
```

### SDK Options

```swift
SwiftlyFeedback.config.allowUndoVote = true
SwiftlyFeedback.config.showCommentSection = true
SwiftlyFeedback.config.showEmailField = true
SwiftlyFeedback.config.showStatusBadge = true
SwiftlyFeedback.config.showCategoryBadge = true
SwiftlyFeedback.config.showVoteCount = true
SwiftlyFeedback.config.expandDescriptionInList = false

// Permission controls
SwiftlyFeedback.config.allowFeedbackSubmission = true
SwiftlyFeedback.config.feedbackSubmissionDisabledMessage = "Upgrade to Pro!"

// Logging
SwiftlyFeedback.config.loggingEnabled = false
```

## Settings Persistence

`AppSettings` class uses `@Observable` with `UserDefaults` persistence:
- Settings loaded on app launch
- Changes saved immediately via `didSet`
- SDK configuration applied on init and when settings change
- Use `Bindable(settings).propertyName` for view bindings

## Platform Notes

### macOS
- `NavigationSplitView` with sidebar `List`
- Window constraints via `.frame(minWidth:minHeight:)` and `.defaultSize()`

### iOS
- `TabView` with modern `Tab` API
- Each tab wraps content in `NavigationStack` where needed

## Development Notes

- Depends on SwiftlyFeedbackKit package
- Server must be running for full functionality
- Update API key for your environment
- Uses modern SwiftUI: `@Observable`, `Bindable()`, `#Preview`
- Platform conditionals: `#if os(macOS)` / `#if os(iOS)`
