# Email Notification Status Configuration - Technical Plan

This document outlines the technical implementation plan for configuring which feedback statuses trigger email notifications to voters and feedback submitters.

## Executive Summary

Currently, FeedbackKit sends email notifications to users (voters and feedback submitters) whenever a feedback status changes to **any** status. This plan introduces a project-level configuration that allows project owners to specify exactly which status transitions should trigger email notifications.

**Use Cases:**
- A project owner may want to notify users only when feedback is `completed` or `rejected` (final states)
- Another owner may prefer to keep users informed at every step (`approved`, `in_progress`, `testflight`, `completed`)
- Some projects may want to suppress emails for intermediate states like `testflight` (internal testing phase)

---

## Current System Analysis

### Available Feedback Statuses

| Status | Raw Value | Color | Description | Default Allowed |
|--------|-----------|-------|-------------|-----------------|
| Pending | `pending` | Gray | Initial state for new feedback | Yes (required) |
| Approved | `approved` | Blue | Feedback has been reviewed and accepted | Yes |
| In Progress | `in_progress` | Orange | Work has started | Yes |
| TestFlight | `testflight` | Cyan | Feature is in beta/testing | No |
| Completed | `completed` | Green | Feature shipped or bug fixed | Yes |
| Rejected | `rejected` | Red | Feedback was declined | Yes |

**File Reference:** `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift:163-170`

### Current Email Notification Flow

**File Reference:** `SwiftlyFeedbackServer/Sources/App/Controllers/FeedbackController.swift:282-329`

```swift
// Current implementation sends emails for ANY status change
if let newStatus = dto.status, newStatus != oldStatus {
    // ... collect emails ...
    try await req.emailService.sendFeedbackStatusChangeNotification(...)
}
```

**Recipients:**
1. **Feedback Submitter** - If `userEmail` was provided when submitting feedback
2. **Voters** - If they provided an email and opted into notifications (`notifyStatusChange = true`)

**Tier Requirements:**
- Feedback submitter notifications: No tier requirement
- Voter notifications: Requires project owner to have **Team** tier

### Existing Configuration Patterns

The project already has two relevant configuration fields:

1. **`allowedStatuses`** - Controls which statuses are available for feedback in a project
   - File: `SwiftlyFeedbackServer/Sources/App/Models/Project.swift:46-47`
   - Admin UI: `SwiftlyFeedbackAdmin/.../Views/Projects/StatusSettingsView.swift`

2. **Slack `notifyStatusChanges`** - Boolean to enable/disable Slack notifications for status changes
   - File: `SwiftlyFeedbackServer/Sources/App/Models/Project.swift:40-41`
   - Admin UI: `SwiftlyFeedbackAdmin/.../Views/Projects/SlackSettingsView.swift`

---

## Proposed Solution

### Design Approach: Notification-Triggering Statuses Array

Add a new project-level field `emailNotifyStatuses` that stores an array of status strings. Email notifications are sent **only when the new status is in this array**.

**Rationale for this approach:**
- Matches the existing `allowedStatuses` pattern
- Flexible: can include any combination of statuses
- Simple to understand: "Send email when status changes TO one of these"
- Future-proof: works with custom statuses if ever implemented

### Alternative Approaches Considered

| Approach | Pros | Cons |
|----------|------|------|
| Boolean per status | Explicit, matches Slack pattern | 6 fields, harder to extend |
| Single "notify on final only" toggle | Simple | Not flexible enough |
| Status transition matrix | Most flexible | Overcomplicated for the use case |
| **Array of statuses** (chosen) | Flexible, simple, matches existing patterns | None significant |

---

## Implementation Plan

### Phase 1: Server-Side Changes

#### 1.1 Database Migration

**File:** `SwiftlyFeedbackServer/Sources/App/Migrations/AddEmailNotifyStatuses.swift` (new)

```swift
import Fluent

struct AddEmailNotifyStatuses: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("projects")
            .field("email_notify_statuses", .array(of: .string), .required,
                   .sql(.default("'{\"approved\",\"in_progress\",\"completed\",\"rejected\"}'")))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("email_notify_statuses")
            .update()
    }
}
```

**Default value:** `["approved", "in_progress", "completed", "rejected"]` - All status changes except `pending` (which is typically the initial state) and `testflight` (internal testing).

#### 1.2 Project Model Update

**File:** `SwiftlyFeedbackServer/Sources/App/Models/Project.swift`

Add new field after `allowedStatuses`:

```swift
@Field(key: "email_notify_statuses")
var emailNotifyStatuses: [String]
```

Update initializer to include the new field with default value.

#### 1.3 DTO Updates

**File:** `SwiftlyFeedbackServer/Sources/App/DTOs/ProjectDTO.swift`

Add new DTO for updating email notification settings:

```swift
struct UpdateProjectEmailNotifyStatusesDTO: Content {
    var emailNotifyStatuses: [String]
}
```

Add field to `ProjectResponseDTO`:

```swift
let emailNotifyStatuses: [String]
```

Update `ProjectResponseDTO.init()` to map the new field.

#### 1.4 Controller Update - Settings Endpoint

**File:** `SwiftlyFeedbackServer/Sources/App/Controllers/ProjectController.swift`

Add new route in `boot()`:

```swift
protected.patch(":projectId", "email-notify-statuses", use: updateEmailNotifyStatuses)
```

Add handler method:

```swift
@Sendable
func updateEmailNotifyStatuses(req: Request) async throws -> ProjectResponseDTO {
    // 1. Authenticate user
    let user = try req.auth.require(User.self)

    // 2. Get project and verify ownership/admin role
    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    guard let project = try await Project.find(projectId, on: req.db) else {
        throw Abort(.notFound)
    }

    // 3. Authorization check (owner or admin)
    let isOwner = project.$owner.id == user.id
    let membership = try await ProjectMember.query(on: req.db)
        .filter(\.$project.$id == projectId)
        .filter(\.$user.$id == user.id!)
        .first()
    let isAdmin = membership?.role == .admin

    guard isOwner || isAdmin else {
        throw Abort(.forbidden)
    }

    // 4. Check subscription tier (Pro required, like other project settings)
    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Pro subscription required to configure email notifications")
    }

    // 5. Validate and update
    let dto = try req.content.decode(UpdateProjectEmailNotifyStatusesDTO.self)

    // Validate that all provided statuses are valid FeedbackStatus values
    let validStatuses = Set(FeedbackStatus.allCases.map { $0.rawValue })
    for status in dto.emailNotifyStatuses {
        guard validStatuses.contains(status) else {
            throw Abort(.badRequest, reason: "Invalid status: \(status)")
        }
    }

    project.emailNotifyStatuses = dto.emailNotifyStatuses
    try await project.save(on: req.db)

    // 6. Return response
    return try await buildProjectResponse(project: project, on: req.db)
}
```

#### 1.5 Controller Update - Status Change Notification Logic

**File:** `SwiftlyFeedbackServer/Sources/App/Controllers/FeedbackController.swift`

Modify the status change notification block (around line 283):

```swift
// Send status change notification if status changed AND new status is in notification list
if let newStatus = dto.status, newStatus != oldStatus {
    let project = feedback.project

    // Check if the new status should trigger email notifications
    let shouldNotifyByEmail = project.emailNotifyStatuses.contains(newStatus.rawValue)

    // Send email notification only if configured
    if shouldNotifyByEmail {
        Task {
            do {
                // ... existing email collection and sending logic ...
            } catch {
                req.logger.error("Failed to send status change notification: \(error)")
            }
        }
    }

    // Slack notification remains separate (unchanged)
    if let webhookURL = project.slackWebhookURL, project.slackIsActive, project.slackNotifyStatusChanges {
        // ... existing Slack logic ...
    }
}
```

### Phase 2: Admin App Changes

#### 2.1 Model Update

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/ProjectModels.swift`

Add field to `Project` struct:

```swift
let emailNotifyStatuses: [String]
```

Update `init(from decoder:)` with backwards compatibility:

```swift
emailNotifyStatuses = try container.decodeIfPresent([String].self, forKey: .emailNotifyStatuses)
    ?? ["approved", "in_progress", "completed", "rejected"]
```

Update memberwise initializer.

Add request struct:

```swift
nonisolated
struct UpdateProjectEmailNotifyStatusesRequest: Encodable, Sendable {
    let emailNotifyStatuses: [String]
}
```

#### 2.2 API Client Update

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/AdminAPIClient.swift`

Add method:

```swift
func updateEmailNotifyStatuses(projectId: UUID, statuses: [String]) async throws -> Project {
    let request = UpdateProjectEmailNotifyStatusesRequest(emailNotifyStatuses: statuses)
    return try await patch("projects/\(projectId)/email-notify-statuses", body: request)
}
```

#### 2.3 ViewModel Update

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/ProjectViewModel.swift`

Add method:

```swift
func updateEmailNotifyStatuses(projectId: UUID, statuses: [String]) async -> UpdateResult {
    isLoading = true
    defer { isLoading = false }

    do {
        let updatedProject = try await apiClient.updateEmailNotifyStatuses(projectId: projectId, statuses: statuses)
        // Update local cache if needed
        return .success
    } catch let error as APIError {
        if case .httpError(let code, _) = error, code == 402 {
            return .paymentRequired
        }
        errorMessage = error.localizedDescription
        showError = true
        return .otherError
    } catch {
        errorMessage = error.localizedDescription
        showError = true
        return .otherError
    }
}
```

#### 2.4 New Settings View

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/EmailNotifyStatusesView.swift` (new)

```swift
import SwiftUI

struct EmailNotifyStatusesView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var enabledStatuses: Set<FeedbackStatus>
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        let statusSet = Set(project.emailNotifyStatuses.compactMap { FeedbackStatus(rawValue: $0) })
        _enabledStatuses = State(initialValue: statusSet)
    }

    private var hasChanges: Bool {
        let currentStatuses = Set(project.emailNotifyStatuses.compactMap { FeedbackStatus(rawValue: $0) })
        return enabledStatuses != currentStatuses
    }

    /// Only show statuses that are allowed in this project
    private var availableStatuses: [FeedbackStatus] {
        project.allowedStatuses
            .compactMap { FeedbackStatus(rawValue: $0) }
            .filter { $0 != .pending }  // Pending is initial state, rarely needs notification
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose which status changes trigger email notifications to feedback submitters and voters who opted in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Notify when status changes to") {
                    ForEach(availableStatuses, id: \.self) { status in
                        Toggle(isOn: binding(for: status)) {
                            StatusRow(status: status)
                        }
                        .tint(statusColor(for: status))
                    }
                }

                Section {
                    Button("Enable All") {
                        enabledStatuses = Set(availableStatuses)
                    }
                    .disabled(enabledStatuses == Set(availableStatuses))

                    Button("Disable All") {
                        enabledStatuses = []
                    }
                    .disabled(enabledStatuses.isEmpty)

                    Button("Final States Only") {
                        enabledStatuses = Set([.completed, .rejected].filter { availableStatuses.contains($0) })
                    }
                } footer: {
                    Text("Final states: Completed and Rejected")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Email Notifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSettings() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges || viewModel.isLoading)
                }
            }
            .interactiveDismissDisabled(viewModel.isLoading)
            .overlay {
                if viewModel.isLoading {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
        }
    }

    private func binding(for status: FeedbackStatus) -> Binding<Bool> {
        Binding(
            get: { enabledStatuses.contains(status) },
            set: { isEnabled in
                if isEnabled {
                    enabledStatuses.insert(status)
                } else {
                    enabledStatuses.remove(status)
                }
            }
        )
    }

    private func statusColor(for status: FeedbackStatus) -> Color {
        switch status.color {
        case "gray": return .gray
        case "blue": return .blue
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "red": return .red
        default: return .primary
        }
    }

    private func saveSettings() {
        Task {
            let statusStrings = enabledStatuses.map { $0.rawValue }
            let result = await viewModel.updateEmailNotifyStatuses(
                projectId: project.id,
                statuses: statusStrings
            )
            switch result {
            case .success:
                dismiss()
            case .paymentRequired:
                showPaywall = true
            case .otherError:
                break
            }
        }
    }
}

// Reuse StatusRow from StatusSettingsView or extract to shared component
```

#### 2.5 Integration into Project Detail View

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/ProjectDetailView.swift`

Add menu item in the project settings section (near other settings like Slack, Statuses):

```swift
// In the Menu or settings section
Button {
    showEmailNotifyStatusesSheet = true
} label: {
    Label("Email Notifications", systemImage: "bell.badge")
}
.tierBadge(.pro)

// Add state
@State private var showEmailNotifyStatusesSheet = false

// Add sheet
.sheet(isPresented: $showEmailNotifyStatusesSheet) {
    EmailNotifyStatusesView(project: project, viewModel: viewModel)
}
```

### Phase 3: SDK Considerations

The SDK does not need changes for this feature since:
1. Email notifications are server-side only
2. The SDK already supports voter email opt-in via `showVoteEmailField` and `userEmail` config
3. Project owners configure which statuses trigger notifications via the Admin app

However, consider adding documentation to explain to SDK consumers that:
- Voters who opt-in will receive emails based on project configuration
- Not all status changes may trigger emails (project owner configures this)

---

## API Reference

### Update Email Notify Statuses

```
PATCH /api/v1/projects/:projectId/email-notify-statuses
```

**Headers:**
```
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body:**
```json
{
    "emailNotifyStatuses": ["approved", "in_progress", "completed", "rejected"]
}
```

**Response:** `200 OK` - Full `ProjectResponseDTO`

**Errors:**
- `400 Bad Request` - Invalid status value in array
- `401 Unauthorized` - Not authenticated
- `402 Payment Required` - Pro subscription required
- `403 Forbidden` - Not owner or admin of project
- `404 Not Found` - Project not found

---

## Data Model Changes Summary

### Projects Table

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `email_notify_statuses` | `TEXT[]` | `["approved", "in_progress", "completed", "rejected"]` | Statuses that trigger email notifications |

---

## Migration Path

### Existing Projects

The migration sets a sensible default (`["approved", "in_progress", "completed", "rejected"]`) that matches current behavior (all status changes except initial `pending` and `testflight`).

### Backwards Compatibility

- Admin apps without the new field will decode with the default array
- Older server versions will continue to send notifications for all status changes
- The new field is additive and non-breaking

---

## Testing Plan

### Unit Tests

1. **Migration Test** - Verify field is added with correct default
2. **Validation Test** - Verify invalid statuses are rejected
3. **Authorization Test** - Verify tier and role requirements
4. **Notification Logic Test** - Verify emails are sent only for configured statuses

### Integration Tests

1. **End-to-End Flow:**
   - Configure `emailNotifyStatuses` to only include `completed`
   - Change feedback status to `approved` → No email sent
   - Change feedback status to `completed` → Email sent

2. **Admin App:**
   - Verify UI shows correct current configuration
   - Verify changes persist after save
   - Verify paywall shows for Free users

### Test Cases

| Scenario | emailNotifyStatuses | Status Change | Email Sent? |
|----------|---------------------|---------------|-------------|
| Default config | `["approved", "in_progress", "completed", "rejected"]` | pending → approved | Yes |
| Default config | `["approved", "in_progress", "completed", "rejected"]` | pending → pending | No (no change) |
| Final only | `["completed", "rejected"]` | pending → approved | No |
| Final only | `["completed", "rejected"]` | in_progress → completed | Yes |
| Empty | `[]` | any → any | No |
| All statuses | `["pending", "approved", "in_progress", "testflight", "completed", "rejected"]` | any → any | Yes |

---

## Subscription Tier Enforcement

| Feature | Required Tier | Enforcement |
|---------|---------------|-------------|
| Configure emailNotifyStatuses | Pro | Server returns 402 |
| Receive email as feedback submitter | Free | Always allowed |
| Receive email as voter | Team (owner) | Server silently checks |

---

## UI/UX Recommendations

### Admin App Settings Screen

The Email Notifications settings should be accessible from:
1. **Project Detail View** → Menu (⋯) → Email Notifications
2. Optionally in a dedicated "Notifications" section alongside Slack

### Visual Design

- Use the same toggle pattern as `StatusSettingsView`
- Show status icons and colors for visual clarity
- Include quick actions: "Enable All", "Disable All", "Final States Only"
- Show tier badge (Pro) on the menu item

### Help Text

Include explanatory text:
> "Choose which status changes trigger email notifications to feedback submitters and voters who opted in. This does not affect Slack notifications."

---

## Future Considerations

### Potential Enhancements

1. **Transition-Based Rules** - "Notify when changing FROM status X TO status Y"
2. **Recipient Filtering** - Different configurations for submitters vs. voters
3. **Email Templates per Status** - Custom email content based on status
4. **Notification Scheduling** - Batch notifications or delay options

### Integration with Other Notifications

This feature is independent of:
- **Slack notifications** - Has its own `slackNotifyStatusChanges` boolean
- **Comment notifications** - Separate user preference (`notifyNewComments`)
- **New feedback notifications** - Separate user preference (`notifyNewFeedback`)

---

## Files to Modify/Create

### Server (SwiftlyFeedbackServer)

| File | Action | Description |
|------|--------|-------------|
| `Sources/App/Migrations/AddEmailNotifyStatuses.swift` | Create | Database migration |
| `Sources/App/Models/Project.swift` | Modify | Add `emailNotifyStatuses` field |
| `Sources/App/DTOs/ProjectDTO.swift` | Modify | Add DTO and response field |
| `Sources/App/Controllers/ProjectController.swift` | Modify | Add endpoint and route |
| `Sources/App/Controllers/FeedbackController.swift` | Modify | Check config before sending email |
| `Sources/App/configure.swift` | Modify | Register migration |

### Admin App (SwiftlyFeedbackAdmin)

| File | Action | Description |
|------|--------|-------------|
| `Models/ProjectModels.swift` | Modify | Add field and request struct |
| `Services/AdminAPIClient.swift` | Modify | Add API method |
| `ViewModels/ProjectViewModel.swift` | Modify | Add update method |
| `Views/Projects/EmailNotifyStatusesView.swift` | Create | New settings view |
| `Views/Projects/ProjectDetailView.swift` | Modify | Add menu item and sheet |

---

## Estimated Scope

| Component | Estimated Changes |
|-----------|-------------------|
| Server Migration | ~20 lines |
| Server Model | ~5 lines |
| Server DTOs | ~15 lines |
| Server Controller (endpoint) | ~50 lines |
| Server Controller (notification logic) | ~5 lines |
| Admin Model | ~15 lines |
| Admin API Client | ~5 lines |
| Admin ViewModel | ~20 lines |
| Admin Settings View | ~150 lines |
| Admin Integration | ~10 lines |
| Tests | ~100 lines |
| **Total** | **~400 lines** |

---

## Checklist

- [ ] Create database migration
- [ ] Update Project model (server)
- [ ] Update ProjectDTO and ProjectResponseDTO (server)
- [ ] Add PATCH endpoint for emailNotifyStatuses (server)
- [ ] Modify FeedbackController notification logic (server)
- [ ] Register migration in configure.swift
- [ ] Update Project model (Admin app)
- [ ] Add API client method (Admin app)
- [ ] Add ViewModel method (Admin app)
- [ ] Create EmailNotifyStatusesView (Admin app)
- [ ] Integrate into ProjectDetailView (Admin app)
- [ ] Write server tests
- [ ] Write Admin app tests
- [ ] Test on iOS and macOS
- [ ] Update CLAUDE.md documentation
