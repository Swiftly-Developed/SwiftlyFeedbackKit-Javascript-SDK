# Login Screen Environment Picker Technical Plan

> **Status:** Draft
> **Created:** 2026-01-17
> **Scope:** SwiftlyFeedbackAdmin App - Login Screen Environment Switching

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Current Implementation Analysis](#2-current-implementation-analysis)
3. [Requirements](#3-requirements)
4. [Proposed Solution](#4-proposed-solution)
5. [Implementation Details](#5-implementation-details)
6. [File Changes Summary](#6-file-changes-summary)
7. [Testing Plan](#7-testing-plan)
8. [Security Considerations](#8-security-considerations)

---

## 1. Problem Statement

### 1.1 The Issue

The environment picker on the login screen does not follow the same restrictions as the Developer Center. The current behavior and desired behavior differ significantly based on build type.

### 1.2 Current vs. Desired Behavior

| Build Type | Current Login Screen | Desired Login Screen | Developer Center (Reference) |
|------------|---------------------|---------------------|------------------------------|
| **App Store (Production)** | Hidden (only 1 env) | DEV, TestFlight, Production | N/A (not available) |
| **TestFlight** | TestFlight, Production | DEV, TestFlight only | TestFlight, Production |
| **DEBUG** | All 4 environments | DEV, TestFlight, Production | All 4 environments |

### 1.3 Why This Matters

**TestFlight Security Concern:**
TestFlight builds are public and users could potentially bypass the paywall by connecting to the Production server where their paid subscription exists, while using a free TestFlight app. By restricting TestFlight builds to only DEV and TestFlight servers, we ensure:
- TestFlight testers can only test against staging environments
- Production subscriptions cannot be exploited through TestFlight builds

**Production User Experience:**
Production (App Store) users should be able to connect to any of the three remote environments (DEV, TestFlight, Production) but NOT localhost. This enables:
- Beta testers with the production app to test staging features
- Developers to debug production builds against development servers
- Support scenarios where users need to connect to different environments

---

## 2. Current Implementation Analysis

### 2.1 AppEnvironment.isAvailable (AppConfiguration.swift:46-55)

```swift
var isAvailable: Bool {
    switch self {
    case .localhost, .development:
        return BuildEnvironment.isDebug
    case .testflight:
        return BuildEnvironment.isDebug || BuildEnvironment.isTestFlight
    case .production:
        return true
    }
}
```

**Problem:** This logic is used by both the login screen picker and Developer Center. The current logic:
- Makes localhost/development available **only** in DEBUG
- Makes testflight available in DEBUG and TestFlight builds
- Makes production always available

### 2.2 Login Screen Environment Picker (LoginView.swift:31-34, 114-144)

```swift
// Visibility check (line 31)
if AppEnvironment.availableEnvironments.count > 1 {
    environmentPicker
}

// Picker implementation (lines 114-144)
private var environmentPicker: some View {
    Menu {
        ForEach(appConfiguration.availableEnvironments, id: \.self) { env in
            Button { appConfiguration.switchTo(env) } label: { ... }
        }
    } label: { ... }
}
```

**Issues:**
1. Uses `AppEnvironment.availableEnvironments` which follows the restrictive `isAvailable` logic
2. No confirmation before switching (unlike Developer Center)
3. Visibility tied to `count > 1` which hides it entirely for App Store builds

### 2.3 Developer Center Environment Section (DeveloperCenterView.swift:180-271)

The Developer Center uses:
- `appConfiguration.canSwitchEnvironment` to show/hide the picker
- `appConfiguration.availableEnvironments` for the list
- Confirmation dialog before switching
- Falls back to read-only display when switching is not allowed

### 2.4 Key Difference

The login screen directly uses `AppEnvironment.availableEnvironments` (static computed property) while the Developer Center uses `appConfiguration.availableEnvironments` (instance computed property). Both ultimately call the same logic, but the distinction suggests the architecture anticipated different contexts.

---

## 3. Requirements

### 3.1 Environment Availability by Build Type

| Build Type | Login Screen Environments | Rationale |
|------------|--------------------------|-----------|
| **App Store (Production)** | Development, TestFlight, Production | Allow production users to connect to any remote server for testing/support |
| **TestFlight** | Development, TestFlight | Prevent paywall bypass via production server |
| **DEBUG** | Development, TestFlight, Production | Match login screen (no localhost needed for login) |

**Note:** Localhost is excluded from login screen in all cases because:
- Users can't create accounts on localhost anyway
- Localhost is a developer-only feature
- It's only needed after initial authentication for debugging

### 3.2 Developer Center Availability (Unchanged)

| Build Type | Developer Center Environments |
|------------|------------------------------|
| **App Store (Production)** | (Developer Center not available) |
| **TestFlight** | TestFlight, Production |
| **DEBUG** | All 4 (localhost, development, testflight, production) |

### 3.3 UI Behavior

**Option A: Keep Picker (Recommended)**
- Show picker on login screen with the correct environment list
- Add confirmation dialog before switching (match Developer Center UX)
- Clear any existing auth tokens when switching

**Option B: Read-Only Label**
- Replace picker with a read-only text label showing current environment
- Environment switching only available in Developer Center
- Simpler implementation but less user-friendly for production users

### 3.4 Decision Criteria for Options

**Choose Option A if:**
- Production users frequently need to switch environments
- Support team uses environment switching for troubleshooting
- The additional code complexity is acceptable

**Choose Option B if:**
- Environment switching is a rare developer-only operation
- Simplicity and reduced maintenance are priorities
- The Developer Center access is sufficient for all use cases

---

## 4. Proposed Solution

### 4.1 Recommended Approach: Separate Login Environment Logic

Create a new computed property specifically for login screen environments that differs from the Developer Center logic.

### 4.2 New Environment Logic

Add to `AppEnvironment` enum in `AppConfiguration.swift`:

```swift
/// Environments available for the login screen
/// Different from isAvailable which is for Developer Center
var isAvailableForLogin: Bool {
    switch self {
    case .localhost:
        // Never show localhost on login - it's a post-auth developer feature
        return false
    case .development:
        // Always available for login (all build types)
        return true
    case .testflight:
        // Available for login in DEBUG and TestFlight, but NOT in App Store
        // This prevents App Store users from accessing staging
        // Wait - requirement says App Store should have DEV, TestFlight, Production
        // So testflight IS available for App Store builds on login
        return true
    case .production:
        // Available in DEBUG and App Store, but NOT in TestFlight
        // This prevents TestFlight users from bypassing paywall
        return !BuildEnvironment.isTestFlight
    }
}

/// Environments available on the login screen
static var loginEnvironments: [AppEnvironment] {
    allCases.filter { $0.isAvailableForLogin }
}
```

### 4.3 Summary Table

| Environment | DEBUG Login | TestFlight Login | App Store Login |
|-------------|-------------|------------------|-----------------|
| localhost | No | No | No |
| development | Yes | Yes | Yes |
| testflight | Yes | Yes | Yes |
| production | Yes | No | Yes |

---

## 5. Implementation Details

### 5.1 Phase 1: Add Login-Specific Environment Logic

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Configuration/AppConfiguration.swift`

**Changes:**

1. Add new computed property to `AppEnvironment` enum (after `isAvailable`):

```swift
/// Whether this environment is available for selection on the login screen.
/// This differs from `isAvailable` (used in Developer Center) because:
/// - Localhost is never shown (it's a post-auth developer feature)
/// - TestFlight builds cannot access production (prevents paywall bypass)
/// - App Store builds can access all remote environments
var isAvailableForLogin: Bool {
    switch self {
    case .localhost:
        // Localhost is developer-only, never shown on login screen
        return false
    case .development, .testflight:
        // Always available on login screen
        return true
    case .production:
        // Available everywhere EXCEPT TestFlight builds
        // This prevents TestFlight users from bypassing the paywall
        return !BuildEnvironment.isTestFlight
    }
}

/// Environments available for selection on the login screen
static var loginEnvironments: [AppEnvironment] {
    allCases.filter { $0.isAvailableForLogin }
}
```

2. Add corresponding instance property to `AppConfiguration` class:

```swift
/// Environments available for the login screen
/// Excludes localhost and restricts based on build type
var loginEnvironments: [AppEnvironment] {
    AppEnvironment.loginEnvironments
}

/// Whether environment switching is allowed on the login screen
var canSwitchEnvironmentOnLogin: Bool {
    loginEnvironments.count > 1
}
```

### 5.2 Phase 2: Update Login View

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Auth/LoginView.swift`

**Option A: Enhanced Picker with Confirmation**

Replace the environment picker section (lines 30-34 and 114-144):

```swift
// In body (replace lines 30-34)
// Environment picker (only shown when multiple login environments available)
if appConfiguration.canSwitchEnvironmentOnLogin {
    environmentPicker
        .padding(.top, 4)
}

// Add new state variables (after line 13)
@State private var pendingEnvironment: AppEnvironment?
@State private var showingEnvironmentConfirmation = false

// Replace environmentPicker computed property (lines 114-144)
@ViewBuilder
private var environmentPicker: some View {
    Menu {
        ForEach(appConfiguration.loginEnvironments, id: \.self) { env in
            Button {
                if env != appConfiguration.environment {
                    pendingEnvironment = env
                    showingEnvironmentConfirmation = true
                }
            } label: {
                HStack {
                    Text(env.displayName)
                    if env == appConfiguration.environment {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    } label: {
        HStack(spacing: 6) {
            Circle()
                .fill(appConfiguration.environment.color)
                .frame(width: 8, height: 8)
            Text(appConfiguration.environment.displayName)
                .font(.caption)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    .alert(
        "Switch to \(pendingEnvironment?.displayName ?? "")?",
        isPresented: $showingEnvironmentConfirmation
    ) {
        Button("Switch", role: .destructive) {
            if let env = pendingEnvironment {
                appConfiguration.switchTo(env)
            }
            pendingEnvironment = nil
        }
        Button("Cancel", role: .cancel) {
            pendingEnvironment = nil
        }
    } message: {
        Text("You will connect to the \(pendingEnvironment?.displayName ?? "") server.")
    }
}
```

**Option B: Read-Only Label (Simpler Alternative)**

If a simpler solution is preferred, replace the picker with a non-interactive label:

```swift
// In body (replace lines 30-34)
// Environment indicator (read-only)
environmentLabel
    .padding(.top, 4)

// Replace environmentPicker with environmentLabel
@ViewBuilder
private var environmentLabel: some View {
    HStack(spacing: 6) {
        Circle()
            .fill(appConfiguration.environment.color)
            .frame(width: 8, height: 8)
        Text(appConfiguration.environment.displayName)
            .font(.caption)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
    .clipShape(Capsule())
}
```

### 5.3 Phase 3: Update switchTo Method (Optional Enhancement)

**File:** `AppConfiguration.swift`

Consider adding a parameter to `switchTo` to handle login-specific validation:

```swift
/// Switch to a different environment.
/// - Parameters:
///   - environment: The target environment
///   - context: Where the switch is initiated from (.login or .developerCenter)
///   - reconfigureSDK: Whether to reconfigure the SwiftlyFeedbackKit SDK
func switchTo(_ environment: AppEnvironment, context: SwitchContext = .developerCenter, reconfigureSDK: Bool = true) {
    // Validate based on context
    let isAllowed = context == .login ? environment.isAvailableForLogin : environment.isAvailable

    guard isAllowed else {
        AppLogger.storage.warning("Environment \(environment.rawValue) not available in this context")
        return
    }

    // ... rest of existing implementation
}

enum SwitchContext {
    case login
    case developerCenter
}
```

---

## 6. File Changes Summary

### 6.1 Files to Modify

| File | Changes |
|------|---------|
| `Configuration/AppConfiguration.swift` | Add `isAvailableForLogin`, `loginEnvironments`, `canSwitchEnvironmentOnLogin` |
| `Views/Auth/LoginView.swift` | Update picker to use `loginEnvironments`, add confirmation dialog (Option A) or replace with label (Option B) |

### 6.2 No Changes Required

| File | Reason |
|------|--------|
| `DeveloperCenterView.swift` | Already uses correct logic for its context |
| `BuildEnvironment.swift` | Existing detection logic is correct |
| `SecureStorageManager.swift` | No changes needed |

---

## 7. Testing Plan

### 7.1 Unit Tests

**File:** `SwiftlyFeedbackAdminTests/AppConfigurationTests.swift` (new or existing)

```swift
@Suite("Login Environment Availability")
struct LoginEnvironmentTests {

    @Test("Localhost never available for login")
    func testLocalhostNotAvailableForLogin() {
        #expect(AppEnvironment.localhost.isAvailableForLogin == false)
    }

    @Test("Development always available for login")
    func testDevelopmentAvailableForLogin() {
        #expect(AppEnvironment.development.isAvailableForLogin == true)
    }

    @Test("TestFlight always available for login")
    func testTestFlightAvailableForLogin() {
        #expect(AppEnvironment.testflight.isAvailableForLogin == true)
    }

    @Test("Production available based on build type")
    func testProductionAvailabilityForLogin() {
        // In DEBUG builds, production should be available
        #if DEBUG
        #expect(AppEnvironment.production.isAvailableForLogin == true)
        #endif

        // Note: TestFlight behavior can only be tested in actual TestFlight builds
    }

    @Test("Login environments exclude localhost")
    func testLoginEnvironmentsExcludeLocalhost() {
        let environments = AppEnvironment.loginEnvironments
        #expect(!environments.contains(.localhost))
    }
}
```

### 7.2 Manual Testing Checklist

#### DEBUG Build
- [ ] Login screen shows picker with: Development, TestFlight, Production
- [ ] Localhost is NOT shown
- [ ] Switching environments shows confirmation dialog
- [ ] After confirming switch, app connects to new environment
- [ ] Developer Center shows all 4 environments (including localhost)

#### TestFlight Build
- [ ] Login screen shows picker with: Development, TestFlight only
- [ ] Production is NOT shown (paywall bypass prevention)
- [ ] Switching works correctly between DEV and TestFlight
- [ ] Developer Center shows: TestFlight, Production

#### App Store Build
- [ ] Login screen shows picker with: Development, TestFlight, Production
- [ ] Localhost is NOT shown
- [ ] All three environments are switchable
- [ ] Developer Center is not accessible

### 7.3 Edge Cases

- [ ] App with stored Production environment, upgraded to TestFlight build → Should default to TestFlight
- [ ] User switches environment mid-login → Auth fields are preserved
- [ ] Network failure during environment switch → Appropriate error handling

---

## 8. Security Considerations

### 8.1 Paywall Bypass Prevention

The core security concern addressed by this plan is preventing TestFlight users from bypassing the paywall:

**Attack Vector:**
1. User subscribes to Pro/Team on Production
2. User downloads TestFlight build (free, all features unlocked)
3. User connects TestFlight app to Production server
4. User gets paid features without paying (subscription valid on Production)

**Mitigation:**
- TestFlight builds cannot connect to Production server
- `isAvailableForLogin` returns `false` for `.production` when `BuildEnvironment.isTestFlight`

### 8.2 Token Security

Environment-specific tokens are already handled correctly:
- Tokens are scoped by environment in `SecureStorageManager`
- Switching environments doesn't transfer tokens
- Users must re-authenticate when changing environments

### 8.3 Server-Side Validation

The server should also validate the build type header (if implemented) to double-check that requests from TestFlight builds don't reach Production endpoints. This is a defense-in-depth measure.

---

## Appendix A: Decision Summary

| Aspect | Recommendation |
|--------|---------------|
| **Primary Solution** | Option A - Enhanced picker with confirmation |
| **Fallback Solution** | Option B - Read-only label if complexity is a concern |
| **Localhost Access** | Excluded from login screen entirely |
| **TestFlight → Production** | Blocked to prevent paywall bypass |
| **App Store → All Remotes** | Allowed for flexibility |

---

## Appendix B: Quick Reference

### Environment Matrix

| Environment | DEBUG Login | TF Login | AppStore Login | DEBUG DevCenter | TF DevCenter |
|-------------|-------------|----------|----------------|-----------------|--------------|
| localhost | No | No | No | Yes | No |
| development | Yes | Yes | Yes | Yes | No |
| testflight | Yes | Yes | Yes | Yes | Yes |
| production | Yes | **No** | Yes | Yes | Yes |

### Key Files

- `AppConfiguration.swift:46-60` - Environment availability logic
- `LoginView.swift:30-34, 114-144` - Login picker implementation
- `DeveloperCenterView.swift:180-271` - Developer Center implementation
- `BuildEnvironment.swift` - Build type detection

---

*Document Version: 1.0*
*Last Updated: 2026-01-17*
