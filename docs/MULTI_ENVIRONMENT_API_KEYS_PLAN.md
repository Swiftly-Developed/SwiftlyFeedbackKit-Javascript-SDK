# Multi-Environment API Keys Technical Plan

> **Status:** Proposed
> **Created:** 2026-01-17
> **Scope:** SwiftlyFeedbackKit SDK

## Problem Statement

The current `configureAuto(with:)` method accepts a single API key but automatically switches between three different server environments based on build type:

| Build Type | Server Environment |
|------------|-------------------|
| DEBUG | Localhost (`http://localhost:8080`) |
| TestFlight | Staging (`api.feedbackkit.testflight.swiftly-developed.com`) |
| App Store | Production (`api.feedbackkit.prod.swiftly-developed.com`) |

**The Problem:** Each server environment has its own separate database with different projects and API keys. A production API key won't work on the staging server, and vice versa. This means developers must:

1. Create separate projects on each environment
2. Manually switch API keys when testing different builds
3. Risk shipping TestFlight builds with localhost API keys

## Proposed Solution

Introduce a new `configureAuto(keys:)` method that accepts API keys for all three environments, automatically selecting the correct one based on the detected build environment.

### New API Design

```swift
/// Configuration for environment-specific API keys
public struct EnvironmentAPIKeys: Sendable {
    public let debug: String?
    public let testflight: String
    public let production: String

    /// Initialize with keys for each environment
    /// - Parameters:
    ///   - debug: API key for DEBUG builds (localhost). If nil, uses testflight key.
    ///   - testflight: API key for TestFlight/staging builds
    ///   - production: API key for App Store/production builds
    public init(
        debug: String? = nil,
        testflight: String,
        production: String
    ) {
        self.debug = debug
        self.testflight = testflight
        self.production = production
    }
}
```

### Usage Examples

**Basic Usage (Two Keys):**
```swift
// Debug builds will use the testflight key against localhost
SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
    testflight: "sf_staging_abc123",
    production: "sf_prod_xyz789"
))
```

**Full Usage (Three Keys):**
```swift
SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
    debug: "sf_local_dev123",       // Localhost project
    testflight: "sf_staging_abc123", // Staging project
    production: "sf_prod_xyz789"     // Production project
))
```

**Recommended Pattern (Environment Variables/Secrets):**
```swift
SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
    debug: Bundle.main.infoDictionary?["FEEDBACKKIT_DEBUG_KEY"] as? String,
    testflight: Bundle.main.infoDictionary?["FEEDBACKKIT_STAGING_KEY"] as! String,
    production: Bundle.main.infoDictionary?["FEEDBACKKIT_PROD_KEY"] as! String
))
```

## Implementation Plan

### Phase 1: Core Data Structures

**File:** `SwiftlyFeedbackKit/Sources/SwiftlyFeedbackKit/Configuration/EnvironmentAPIKeys.swift` (new file)

```swift
import Foundation

/// API keys for each server environment.
///
/// Use with `SwiftlyFeedback.configureAuto(keys:)` to automatically
/// select the correct API key based on the current build environment.
///
/// ## Example
/// ```swift
/// SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
///     debug: "sf_local_...",      // Optional: localhost
///     testflight: "sf_staging_...", // Required: staging server
///     production: "sf_prod_..."     // Required: production server
/// ))
/// ```
public struct EnvironmentAPIKeys: Sendable {

    /// API key for DEBUG builds running against localhost.
    /// If nil, the testflight key will be used for DEBUG builds.
    public let debug: String?

    /// API key for TestFlight builds running against the staging server.
    public let testflight: String

    /// API key for App Store builds running against the production server.
    public let production: String

    /// Creates environment-specific API key configuration.
    ///
    /// - Parameters:
    ///   - debug: API key for localhost (DEBUG builds). Defaults to nil,
    ///     which will use the testflight key for DEBUG builds.
    ///   - testflight: API key for the staging server (TestFlight builds).
    ///   - production: API key for the production server (App Store builds).
    public init(
        debug: String? = nil,
        testflight: String,
        production: String
    ) {
        self.debug = debug
        self.testflight = testflight
        self.production = production
    }

    /// Returns the appropriate API key for the current build environment.
    internal var currentKey: String {
        #if DEBUG
        // DEBUG: Use debug key if provided, otherwise fall back to testflight
        return debug ?? testflight
        #else
        if BuildEnvironment.isTestFlight {
            return testflight
        } else {
            return production
        }
        #endif
    }

    /// Returns the server URL for the current build environment.
    internal var currentServerURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:8080/api/v1")!
        #else
        if BuildEnvironment.isTestFlight {
            return URL(string: "https://api.feedbackkit.testflight.swiftly-developed.com/api/v1")!
        } else {
            return URL(string: "https://api.feedbackkit.prod.swiftly-developed.com/api/v1")!
        }
        #endif
    }

    /// Returns a description of the current environment for logging.
    internal var currentEnvironmentName: String {
        #if DEBUG
        return "localhost (DEBUG)"
        #else
        if BuildEnvironment.isTestFlight {
            return "staging (TestFlight)"
        } else {
            return "production (App Store)"
        }
        #endif
    }
}
```

### Phase 2: Update SwiftlyFeedback Entry Point

**File:** `SwiftlyFeedbackKit/Sources/SwiftlyFeedbackKit/SwiftlyFeedback.swift`

**Add new method (after existing `configureAuto`):**

```swift
// MARK: - Multi-Environment Auto-Configuration

/// Configures the SDK with environment-specific API keys.
///
/// This method automatically detects the current build environment and
/// selects the appropriate API key and server URL:
///
/// | Build Type | Server | API Key Used |
/// |------------|--------|--------------|
/// | DEBUG | localhost:8080 | `keys.debug` (or `keys.testflight` if nil) |
/// | TestFlight | staging server | `keys.testflight` |
/// | App Store | production server | `keys.production` |
///
/// ## Usage
/// ```swift
/// // In your App's init or AppDelegate
/// SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
///     debug: "sf_local_...",        // Optional
///     testflight: "sf_staging_...",  // Required
///     production: "sf_prod_..."      // Required
/// ))
/// ```
///
/// - Parameter keys: Environment-specific API keys configuration.
///
/// - Note: For security, consider storing API keys in your app's
///   Info.plist or using a secrets management solution rather than
///   hardcoding them in source code.
public static func configureAuto(keys: EnvironmentAPIKeys) {
    let apiKey = keys.currentKey
    let baseURL = keys.currentServerURL

    configure(with: apiKey, baseURL: baseURL)

    SDKLogger.info("Auto-configured for \(keys.currentEnvironmentName)")

    #if DEBUG
    // In DEBUG, log which key type is being used
    if keys.debug != nil {
        SDKLogger.debug("Using dedicated DEBUG API key")
    } else {
        SDKLogger.debug("Using TestFlight API key (no DEBUG key provided)")
    }
    #endif
}
```

**Deprecate single-key auto-configure (optional but recommended):**

```swift
/// Configures the SDK with automatic server detection.
///
/// - Important: This method uses a single API key for all environments,
///   which may cause authentication failures when switching between
///   DEBUG, TestFlight, and App Store builds. Consider using
///   `configureAuto(keys:)` instead.
///
/// - Parameter apiKey: The API key for authentication.
@available(*, deprecated, message: "Use configureAuto(keys:) for multi-environment support")
public static func configureAuto(with apiKey: String) {
    // Existing implementation unchanged
    let baseURL = detectServerURL()
    configure(with: apiKey, baseURL: baseURL)

    #if DEBUG
    SDKLogger.info("Auto-configured with localhost (DEBUG)")
    #else
    if BuildEnvironment.isTestFlight {
        SDKLogger.info("Auto-configured with staging (TestFlight)")
    } else {
        SDKLogger.info("Auto-configured with production (App Store)")
    }
    #endif
}
```

### Phase 3: Update Public API Exports

**File:** `SwiftlyFeedbackKit/Sources/SwiftlyFeedbackKit/SwiftlyFeedbackKit.swift` (or main export file)

Ensure `EnvironmentAPIKeys` is exported:

```swift
// Public API exports
@_exported import struct SwiftlyFeedbackKit.EnvironmentAPIKeys
```

### Phase 4: Update Documentation

**File:** `SwiftlyFeedbackKit/CLAUDE.md`

Add new section under SDK Configuration:

```markdown
## Multi-Environment Configuration

For apps that need different API keys per environment:

```swift
SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
    debug: "sf_local_...",        // Optional: localhost
    testflight: "sf_staging_...",  // Required: staging
    production: "sf_prod_..."      // Required: production
))
```

| Build | Server | Key Used |
|-------|--------|----------|
| DEBUG | localhost:8080 | debug (or testflight if nil) |
| TestFlight | staging | testflight |
| App Store | production | production |
```

**File:** `SwiftlyFeedbackKit/README.md`

Update quick start section to show both options.

### Phase 5: Update Demo App

**File:** `SwiftlyFeedbackDemoApp/.../SwiftlyFeedbackDemoAppApp.swift`

Update to use new multi-key configuration:

```swift
init() {
    // Configure with environment-specific API keys
    SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
        debug: ProcessInfo.processInfo.environment["FEEDBACKKIT_DEBUG_KEY"],
        testflight: "sf_staging_demo_key",
        production: "sf_prod_demo_key"
    ))
}
```

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `Configuration/EnvironmentAPIKeys.swift` | **New** | New struct for multi-environment keys |
| `SwiftlyFeedback.swift` | **Modified** | Add `configureAuto(keys:)` method |
| `SwiftlyFeedbackKit.swift` | **Modified** | Export new type |
| `SwiftlyFeedbackKit/CLAUDE.md` | **Modified** | Document new API |
| `SwiftlyFeedbackKit/README.md` | **Modified** | Update quick start |
| `SwiftlyFeedbackDemoApp/...App.swift` | **Modified** | Use new configuration |

## Migration Guide

### For Existing Users

**Before (single key):**
```swift
SwiftlyFeedback.configureAuto(with: "sf_my_api_key")
```

**After (multi-environment):**
```swift
SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
    testflight: "sf_staging_key",
    production: "sf_prod_key"
))
```

### Backward Compatibility

The existing `configureAuto(with:)` method will continue to work but will be marked as deprecated. This gives developers time to migrate while maintaining backward compatibility.

## Security Considerations

### API Key Storage Recommendations

1. **Info.plist with xcconfig files:**
   ```swift
   // Info.plist: FEEDBACKKIT_KEY = $(FEEDBACKKIT_API_KEY)
   let key = Bundle.main.infoDictionary?["FEEDBACKKIT_KEY"] as? String
   ```

2. **Environment variables (CI/CD):**
   ```swift
   let key = ProcessInfo.processInfo.environment["FEEDBACKKIT_KEY"]
   ```

3. **Xcode Build Settings:**
   - Define keys per configuration (Debug/Release/TestFlight)
   - Reference in Info.plist

4. **Secrets Management (recommended for teams):**
   - Use tools like `cocoapods-keys` or `swift-secrets`
   - Store encrypted keys that are decrypted at build time

### What NOT to Do

```swift
// DON'T: Hardcode keys in source code
SwiftlyFeedback.configureAuto(keys: EnvironmentAPIKeys(
    testflight: "sf_staging_abc123",  // Visible in git history!
    production: "sf_prod_xyz789"
))
```

## Testing Plan

### Unit Tests

**File:** `SwiftlyFeedbackKit/Tests/EnvironmentAPIKeysTests.swift`

```swift
import Testing
@testable import SwiftlyFeedbackKit

@Suite("EnvironmentAPIKeys")
struct EnvironmentAPIKeysTests {

    @Test("Initialization with all keys")
    func initWithAllKeys() {
        let keys = EnvironmentAPIKeys(
            debug: "debug_key",
            testflight: "tf_key",
            production: "prod_key"
        )

        #expect(keys.debug == "debug_key")
        #expect(keys.testflight == "tf_key")
        #expect(keys.production == "prod_key")
    }

    @Test("Initialization without debug key")
    func initWithoutDebugKey() {
        let keys = EnvironmentAPIKeys(
            testflight: "tf_key",
            production: "prod_key"
        )

        #expect(keys.debug == nil)
        #expect(keys.testflight == "tf_key")
        #expect(keys.production == "prod_key")
    }

    @Test("Current key selection in DEBUG")
    func currentKeyInDebug() {
        // This test only makes sense in DEBUG builds
        #if DEBUG
        let keysWithDebug = EnvironmentAPIKeys(
            debug: "debug_key",
            testflight: "tf_key",
            production: "prod_key"
        )
        #expect(keysWithDebug.currentKey == "debug_key")

        let keysWithoutDebug = EnvironmentAPIKeys(
            testflight: "tf_key",
            production: "prod_key"
        )
        #expect(keysWithoutDebug.currentKey == "tf_key")
        #endif
    }

    @Test("Server URL selection")
    func serverURLSelection() {
        let keys = EnvironmentAPIKeys(
            testflight: "tf_key",
            production: "prod_key"
        )

        #if DEBUG
        #expect(keys.currentServerURL.host == "localhost")
        #endif
    }
}
```

### Integration Tests

1. **DEBUG build:** Verify localhost is used with debug key (or testflight key if nil)
2. **TestFlight build:** Verify staging server is used with testflight key
3. **Release build:** Verify production server is used with production key

### Manual Testing Checklist

- [ ] Configure with all three keys, verify correct key used in DEBUG
- [ ] Configure without debug key, verify testflight key used in DEBUG
- [ ] Create TestFlight build, verify staging server connection
- [ ] Create Release build, verify production server connection
- [ ] Verify deprecation warning appears for old `configureAuto(with:)`
- [ ] Verify documentation is accurate and complete

## Timeline Estimate

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Phase 1 | Create `EnvironmentAPIKeys` struct | Low |
| Phase 2 | Add `configureAuto(keys:)` method | Low |
| Phase 3 | Update exports | Low |
| Phase 4 | Update documentation | Low |
| Phase 5 | Update demo app | Low |
| Testing | Unit tests + manual testing | Medium |

**Total:** This is a straightforward addition with no breaking changes.

## Future Considerations

### Potential Enhancements

1. **Custom Server URLs:**
   ```swift
   public struct EnvironmentConfig: Sendable {
       public let apiKey: String
       public let serverURL: URL
   }

   public struct EnvironmentAPIKeys {
       public let debug: EnvironmentConfig?
       public let testflight: EnvironmentConfig
       public let production: EnvironmentConfig
   }
   ```

2. **Runtime Environment Override:**
   ```swift
   // For testing production keys in DEBUG
   SwiftlyFeedback.overrideEnvironment(.production)
   ```

3. **Validation:**
   ```swift
   // Validate key format (sf_prefix, length, etc.)
   public init(debug: String?, testflight: String, production: String) throws {
       guard testflight.hasPrefix("sf_") else {
           throw ConfigurationError.invalidKeyFormat
       }
       // ...
   }
   ```

4. **Async Configuration with Validation:**
   ```swift
   // Validate keys against servers before completing configuration
   try await SwiftlyFeedback.configureAutoValidated(keys: keys)
   ```

These enhancements are out of scope for the initial implementation but could be added in future versions based on user feedback.

## Conclusion

This plan introduces multi-environment API key support with:

- **Minimal API surface:** One new type, one new method
- **Full backward compatibility:** Existing code continues to work
- **Clear migration path:** Deprecation warnings guide users to new API
- **Security guidance:** Documentation on proper key storage
- **Comprehensive testing:** Unit tests and manual test checklist

The implementation is straightforward and addresses the core problem of needing different API keys for each server environment while maintaining the simplicity of auto-configuration.
