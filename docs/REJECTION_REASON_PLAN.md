# Rejection Reason Feature - Technical Implementation Plan

This document outlines the technical implementation plan for adding optional rejection reasons when feedback status is changed to "rejected", with conditional display in status update emails.

## Overview

When an admin changes feedback status to "rejected", a sheet will prompt for an optional rejection reason. This reason is stored with the feedback and conditionally displayed in the status change notification email sent to the feedback submitter and opted-in voters.

## User Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Admin selects "Rejected" from status menu                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Sheet appears: "Provide a reason for rejection (optional)"      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ TextEditor for rejection reason                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│  [ Cancel ]                              [ Reject Without Reason ]│
│                                          [ Reject with Reason ]  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  API: PATCH /feedbacks/:id with status + rejectionReason         │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Email sent with conditional rejection reason section            │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Tasks

### 1. Database Migration (Server)

**File:** `SwiftlyFeedbackServer/Sources/App/Migrations/AddFeedbackRejectionReason.swift`

Create a new migration to add the `rejection_reason` column to the `feedbacks` table.

```swift
import Fluent

struct AddFeedbackRejectionReason: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("feedbacks")
            .field("rejection_reason", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("feedbacks")
            .deleteField("rejection_reason")
            .update()
    }
}
```

**Register in `configure.swift`:**
```swift
app.migrations.add(AddFeedbackRejectionReason())
```

---

### 2. Update Feedback Model (Server)

**File:** `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`

Add the optional rejection reason field to the Feedback model.

```swift
// Add after existing fields (around line 40)
@OptionalField(key: "rejection_reason")
var rejectionReason: String?
```

**Update the initializer** to include the new field (with default `nil`).

---

### 3. Update DTOs (Server)

**File:** `SwiftlyFeedbackServer/Sources/App/DTOs/FeedbackDTO.swift`

**UpdateFeedbackDTO** - Add rejection reason field:
```swift
struct UpdateFeedbackDTO: Content {
    let title: String?
    let description: String?
    let status: FeedbackStatus?
    let category: FeedbackCategory?
    let rejectionReason: String?  // NEW
}
```

**FeedbackResponse** - Include rejection reason in response:
```swift
// Add to FeedbackResponse struct
let rejectionReason: String?

// Update init to map from Feedback model
self.rejectionReason = feedback.rejectionReason
```

---

### 4. Update FeedbackController (Server)

**File:** `SwiftlyFeedbackServer/Sources/App/Controllers/FeedbackController.swift`

**In the `update` function (PATCH /feedbacks/:id):**

1. **Handle rejection reason update (around line 275):**
```swift
// Update rejection reason
// Only store if status is being set to rejected, otherwise clear it
if let newStatus = updateData.status {
    if newStatus == .rejected {
        feedback.rejectionReason = updateData.rejectionReason
    } else {
        // Clear rejection reason when moving away from rejected status
        feedback.rejectionReason = nil
    }
}
```

2. **Pass rejection reason to email service (around line 320):**
```swift
try await emailService.sendFeedbackStatusChangeNotification(
    to: [email],
    projectName: project.name,
    feedbackTitle: feedback.title,
    oldStatus: oldStatus.rawValue,
    newStatus: feedback.status.rawValue,
    rejectionReason: feedback.rejectionReason,  // NEW parameter
    unsubscribeKey: unsubscribeKeys[email]
)
```

---

### 5. Update EmailService (Server)

**File:** `SwiftlyFeedbackServer/Sources/App/Services/EmailService.swift`

**Update function signature:**
```swift
func sendFeedbackStatusChangeNotification(
    to emails: [String],
    projectName: String,
    feedbackTitle: String,
    oldStatus: String,
    newStatus: String,
    rejectionReason: String? = nil,  // NEW parameter
    unsubscribeKeys: [String: UUID] = [:]
) async throws
```

**Add conditional rejection reason section in HTML template (after the status message, around line 325):**

```swift
// Conditional rejection reason section
let rejectionReasonSection: String
if newStatus == "rejected", let reason = rejectionReason, !reason.isEmpty {
    rejectionReasonSection = """
    <tr>
        <td style="padding: 20px 30px;">
            <div style="background-color: #FEF2F2; border-left: 4px solid #EF4444; padding: 16px 20px; border-radius: 0 8px 8px 0;">
                <p style="margin: 0 0 8px 0; font-weight: 600; color: #991B1B; font-size: 14px;">
                    Reason for rejection:
                </p>
                <p style="margin: 0; color: #7F1D1D; font-size: 14px; line-height: 1.5;">
                    \(reason.htmlEscaped)
                </p>
            </div>
        </td>
    </tr>
    """
} else {
    rejectionReasonSection = ""
}
```

**Insert `\(rejectionReasonSection)` in the HTML template** after the status change display and before the footer.

**Add HTML escaping helper** (if not already present):
```swift
extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
```

---

### 6. Update Admin App Models

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/Feedback.swift`

Add the rejection reason field to the client-side Feedback model:

```swift
let rejectionReason: String?
```

Update the `CodingKeys` enum if using custom keys.

---

### 7. Update Admin App DTOs

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/DTOs/FeedbackDTOs.swift`

**UpdateFeedbackRequest:**
```swift
struct UpdateFeedbackRequest: Codable {
    let title: String?
    let description: String?
    let status: FeedbackStatus?
    let category: FeedbackCategory?
    let rejectionReason: String?  // NEW

    init(
        title: String? = nil,
        description: String? = nil,
        status: FeedbackStatus? = nil,
        category: FeedbackCategory? = nil,
        rejectionReason: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.category = category
        self.rejectionReason = rejectionReason
    }
}
```

---

### 8. Create Rejection Reason Sheet (Admin App)

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Feedback/RejectionReasonSheet.swift` (NEW)

```swift
import SwiftUI

struct RejectionReasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var rejectionReason: String
    let onReject: (String?) -> Void

    @FocusState private var isTextEditorFocused: Bool

    private let maxCharacterCount = 500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $rejectionReason)
                        .frame(minHeight: 120)
                        .focused($isTextEditorFocused)
                        .onChange(of: rejectionReason) { _, newValue in
                            if newValue.count > maxCharacterCount {
                                rejectionReason = String(newValue.prefix(maxCharacterCount))
                            }
                        }
                } header: {
                    Text("Rejection Reason")
                } footer: {
                    HStack {
                        Text("This will be included in the notification email sent to the user.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(rejectionReason.count)/\(maxCharacterCount)")
                            .foregroundStyle(rejectionReason.count >= maxCharacterCount ? .red : .secondary)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Reject Feedback")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("Reject with Reason") {
                            onReject(rejectionReason.isEmpty ? nil : rejectionReason)
                            dismiss()
                        }
                        .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Reject Without Reason") {
                            onReject(nil)
                            dismiss()
                        }
                    } label: {
                        Text("Reject")
                    }
                }
            }
            .onAppear {
                isTextEditorFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
}

#Preview {
    RejectionReasonSheet(
        rejectionReason: .constant(""),
        onReject: { _ in }
    )
}
```

---

### 9. Update FeedbackDetailView (Admin App)

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Feedback/FeedbackDetailView.swift`

**Add state for rejection sheet:**
```swift
@State private var showRejectionReasonSheet = false
@State private var rejectionReason = ""
@State private var pendingRejectionFeedbackId: UUID?
```

**Modify status menu to intercept "rejected" selection (around line 328-348):**

```swift
Menu {
    ForEach(allowedStatuses, id: \.self) { status in
        Button {
            if status == .rejected {
                // Show rejection reason sheet instead of immediate update
                pendingRejectionFeedbackId = feedback.id
                rejectionReason = ""
                showRejectionReasonSheet = true
            } else {
                Task {
                    await viewModel.updateFeedbackStatus(id: feedback.id, status: status)
                }
            }
        } label: {
            HStack {
                Text(status.displayName)
                if feedback.status == status {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
} label: {
    Label("Status", systemImage: "arrow.triangle.2.circlepath")
}
```

**Add sheet modifier:**
```swift
.sheet(isPresented: $showRejectionReasonSheet) {
    RejectionReasonSheet(rejectionReason: $rejectionReason) { reason in
        if let feedbackId = pendingRejectionFeedbackId {
            Task {
                await viewModel.updateFeedbackStatus(
                    id: feedbackId,
                    status: .rejected,
                    rejectionReason: reason
                )
            }
        }
    }
}
```

---

### 10. Update FeedbackViewModel (Admin App)

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/FeedbackViewModel.swift`

**Update the `updateFeedbackStatus` function to accept optional rejection reason:**

```swift
@discardableResult
func updateFeedbackStatus(
    id: UUID,
    status: FeedbackStatus,
    rejectionReason: String? = nil
) async -> Bool {
    do {
        let request = UpdateFeedbackRequest(
            status: status,
            rejectionReason: rejectionReason
        )
        let updatedFeedback: Feedback = try await apiClient.patch(
            "feedbacks/\(id)",
            body: request
        )

        // Update local state
        if let index = feedbacks.firstIndex(where: { $0.id == id }) {
            feedbacks[index] = updatedFeedback
        }
        if selectedFeedback?.id == id {
            selectedFeedback = updatedFeedback
        }

        Logger.info("Updated feedback \(id) to status: \(status.rawValue)")
        return true
    } catch {
        Logger.error("Failed to update feedback status: \(error)")
        self.error = error
        return false
    }
}
```

---

### 11. Display Rejection Reason in Admin App (Optional Enhancement)

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Feedback/FeedbackDetailView.swift`

Optionally display the rejection reason in the feedback detail view when status is rejected:

```swift
// Add after status display section
if feedback.status == .rejected,
   let reason = feedback.rejectionReason,
   !reason.isEmpty {
    Section("Rejection Reason") {
        Text(reason)
            .foregroundStyle(.secondary)
    }
}
```

---

## Email Template Design

### Without Rejection Reason (Current)

```
┌─────────────────────────────────────────────┐
│  ❌ Status Update                            │
│                                             │
│  Your feedback "Feature X" has been updated │
│                                             │
│  ~~pending~~ → **rejected**                 │
│                                             │
│  After review, this feedback will not be    │
│  implemented at this time.                  │
│                                             │
│  [Manage email preferences]                 │
│                                             │
│  Powered by Feedback Kit                    │
└─────────────────────────────────────────────┘
```

### With Rejection Reason (New)

```
┌─────────────────────────────────────────────┐
│  ❌ Status Update                            │
│                                             │
│  Your feedback "Feature X" has been updated │
│                                             │
│  ~~pending~~ → **rejected**                 │
│                                             │
│  After review, this feedback will not be    │
│  implemented at this time.                  │
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │ Reason for rejection:                   ││
│  │                                         ││
│  │ This feature conflicts with our current ││
│  │ roadmap priorities. We may revisit this ││
│  │ in a future release.                    ││
│  └─────────────────────────────────────────┘│
│                                             │
│  [Manage email preferences]                 │
│                                             │
│  Powered by Feedback Kit                    │
└─────────────────────────────────────────────┘
```

**Design Notes:**
- Red-tinted background (`#FEF2F2`) with red left border (`#EF4444`)
- Clear "Reason for rejection:" label in bold
- Reason text in darker red (`#7F1D1D`) for readability
- Only shown when `status == rejected` AND `rejectionReason` is non-empty

---

## Files to Create/Modify Summary

### New Files

| File | Description |
|------|-------------|
| `SwiftlyFeedbackServer/Sources/App/Migrations/AddFeedbackRejectionReason.swift` | Database migration |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Feedback/RejectionReasonSheet.swift` | Rejection reason input sheet |

### Modified Files

| File | Changes |
|------|---------|
| `SwiftlyFeedbackServer/Sources/App/configure.swift` | Register new migration |
| `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift` | Add `rejectionReason` field |
| `SwiftlyFeedbackServer/Sources/App/DTOs/FeedbackDTO.swift` | Add field to DTOs |
| `SwiftlyFeedbackServer/Sources/App/Controllers/FeedbackController.swift` | Handle rejection reason in update |
| `SwiftlyFeedbackServer/Sources/App/Services/EmailService.swift` | Add conditional reason section to email |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/Feedback.swift` | Add `rejectionReason` field |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/DTOs/FeedbackDTOs.swift` | Add field to request DTO |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Feedback/FeedbackDetailView.swift` | Add rejection sheet trigger |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/FeedbackViewModel.swift` | Update function signature |

---

## Testing Plan

### Unit Tests (Server)

1. **Migration Test:** Verify column added/removed correctly
2. **DTO Encoding:** Verify `rejectionReason` serializes correctly
3. **Controller Test:**
   - Status change to rejected with reason stores reason
   - Status change away from rejected clears reason
   - Status change to rejected without reason works

### Integration Tests

1. **API Test:** PATCH feedback with rejection reason returns updated model
2. **Email Test:** Verify email includes/excludes reason section appropriately

### UI Tests (Admin App)

1. **Sheet Display:** Selecting "rejected" shows sheet
2. **Cancel:** Cancel dismisses sheet without status change
3. **Reject Without Reason:** Updates status, no reason stored
4. **Reject With Reason:** Updates status with reason

### Manual Testing Checklist

- [ ] Select "rejected" status → sheet appears
- [ ] Cancel sheet → no status change
- [ ] Submit with reason → status changes, reason saved
- [ ] Submit without reason → status changes, no reason
- [ ] View feedback detail → rejection reason displayed (if present)
- [ ] Receive email → rejection reason section shown (if reason provided)
- [ ] Receive email → no rejection section (if no reason)
- [ ] Change status away from rejected → reason cleared
- [ ] Re-reject same feedback → can provide new reason

---

## Security Considerations

1. **HTML Escaping:** Rejection reason must be HTML-escaped in email to prevent XSS
2. **Length Limit:** 500 character limit prevents database bloat and email formatting issues
3. **Authorization:** Only users with appropriate project access can set rejection reasons (existing auth checks apply)

---

## Future Enhancements

1. **Rejection Reason Templates:** Pre-defined common rejection reasons for quick selection
2. **Rejection History:** Track multiple rejection reasons if feedback is rejected/reopened multiple times
3. **SDK Display:** Show rejection reason in the SDK's feedback detail view for end users
4. **Localization:** Support translated rejection reason labels in emails

---

## Implementation Order

1. **Server Migration** - Add database column
2. **Server Model** - Update Feedback model
3. **Server DTOs** - Update request/response DTOs
4. **Server Controller** - Handle rejection reason logic
5. **Server Email** - Add conditional email section
6. **Admin Models** - Update client-side Feedback model
7. **Admin DTOs** - Update request DTO
8. **Admin ViewModel** - Update function signature
9. **Admin Sheet** - Create RejectionReasonSheet view
10. **Admin DetailView** - Integrate sheet and display reason
11. **Testing** - Run through test plan
