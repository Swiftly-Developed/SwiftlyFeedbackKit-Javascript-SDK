# FeedbackKit Demo App

Sample app demonstrating FeedbackKit SDK integration.

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS-blue.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-5-green.svg)

## Overview

This demo app shows how to integrate FeedbackKit into your iOS or macOS app. It demonstrates all major SDK features including configuration, theming, user identification, and MRR tracking.

## Requirements

- iOS 26.0+ / macOS 26.0+
- Xcode 26.0+
- Swift 6.2+
- Running FeedbackKit server (for full functionality)

## Build

Build via the workspace:

```bash
xcodebuild -workspace ../Swiftlyfeedback.xcworkspace \
  -scheme SwiftlyFeedbackDemoApp \
  -sdk iphonesimulator \
  -configuration Debug
```

## App Structure

### iOS
Three tabs: Home, Feedback, Settings

### macOS
Sidebar navigation with the same sections

### Screens

1. **Home** — Welcome screen with feature overview
2. **Feedback** — FeedbackKit's `FeedbackListView` for browsing and submitting feedback
3. **Settings** — Configuration options to explore SDK features

## Features Demonstrated

### Basic Setup

```swift
import SwiftlyFeedbackKit

@main
struct DemoApp: App {
    init() {
        SwiftlyFeedback.configure(with: "sf_your_api_key")
        SwiftlyFeedback.theme.primaryColor = .color(.blue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### User Identification

```swift
// Associate feedback with your user system
SwiftlyFeedback.updateUser(customID: "user_12345")
```

### MRR Tracking

```swift
// Track subscription revenue
SwiftlyFeedback.updateUser(payment: .monthly(9.99))
SwiftlyFeedback.updateUser(payment: .yearly(99.99))

// Clear on cancellation
SwiftlyFeedback.clearUserPayment()
```

### Configuration Options

The Settings screen lets you toggle SDK options in real-time:

```swift
// Voting behavior
SwiftlyFeedback.config.allowUndoVote = true

// UI elements
SwiftlyFeedback.config.showStatusBadge = true
SwiftlyFeedback.config.showCategoryBadge = true
SwiftlyFeedback.config.showVoteCount = true
SwiftlyFeedback.config.showCommentSection = true
SwiftlyFeedback.config.showEmailField = true

// Permissions
SwiftlyFeedback.config.allowFeedbackSubmission = true
SwiftlyFeedback.config.feedbackSubmissionDisabledMessage = "Upgrade to submit feedback"
```

## Settings Persistence

All settings are persisted to UserDefaults and restored on app launch. Changes are applied immediately to the SDK configuration.

## Project Structure

```
SwiftlyFeedbackDemoApp/
├── SwiftlyFeedbackDemoAppApp.swift   # App entry with SDK configuration
├── ContentView.swift                  # Platform-adaptive navigation
├── Models/
│   └── AppSettings.swift             # Settings persistence
└── Views/
    ├── HomeView.swift                # Welcome screen
    └── ConfigurationView.swift       # SDK settings form
```

## Running the Demo

1. Ensure the FeedbackKit server is running (see [SwiftlyFeedbackServer](https://github.com/Swiftly-Developed/SwiftlyFeedbackServer))
2. Update the API key in `SwiftlyFeedbackDemoAppApp.swift`
3. Build and run the app
4. Explore the Settings tab to try different SDK configurations

## Related Projects

- [SwiftlyFeedbackKit](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit) — Swift SDK
- [SwiftlyFeedbackServer](https://github.com/Swiftly-Developed/SwiftlyFeedbackServer) — Backend server
- [SwiftlyFeedbackAdmin](https://github.com/Swiftly-Developed/SwiftlyFeedbackAdmin) — Admin app

## License

FeedbackKit Demo App is available under the MIT license.
