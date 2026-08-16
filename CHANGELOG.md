# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `feedback.list({ includeMerged: true })` was silently ignored. Query parameter
  keys were converted to snake_case before being appended to the URL, so the SDK
  sent `include_merged`, which the API does not read — every call behaved as
  `includeMerged: false`. Query keys are now sent verbatim; JSON request bodies
  are still snake_cased, which is unchanged and correct.

## [1.1.1] - 2026-04-24

### Changed

- Version alignment with Swift SDK 1.1.1 hotfix (Xcode 26 / Swift 6.2 compatibility). No functional changes to this SDK.

## [1.1.0] - 2026-04-15

### Added

- CHANGELOG.md following Keep a Changelog format
- CONTRIBUTING.md with contribution guidelines
- SECURITY.md with vulnerability reporting policy
- CODE_OF_CONDUCT.md (Contributor Covenant v2.1)
- SUPPORT.md with support channels

### Changed

- Migrated API URLs to getfeedbackkit.com
- Updated SDK availability section in README (Flutter and Kotlin now available)
- Standardized LICENSE copyright year to 2025
- Standardized documentation across all FeedbackKit SDKs

## [1.0.1] - 2026-02-09

### Changed

- Renamed scoped package to unscoped `feedbackkit-js` for npm publishing
- Updated production URLs

## [1.0.0] - 2026-02-08

### Added

- Initial release of FeedbackKit JavaScript SDK
- TypeScript-first with full type definitions
- Zero runtime dependencies
- Tree-shakeable ESM and CJS builds
- **Core Features**
  - Feedback: list, get, submit with sorting and filtering
  - Voting: vote and unvote
  - Comments: list and create
  - User management with persistent anonymous IDs
  - Event tracking
- Typed error handling with FeedbackKitError
- Node.js 18+ and modern browser support

[1.1.1]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.1.1
[1.1.0]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.1.0
[1.0.1]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.0.1
[1.0.0]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.0.0
