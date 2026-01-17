# Project Ownership Transfer Technical Plan

> **Status:** Draft
> **Created:** January 2026
> **Last Updated:** January 2026
> **Target:** SwiftlyFeedback Platform (Server + Admin App)

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Requirements](#3-requirements)
4. [Architecture Design](#4-architecture-design)
5. [Database Schema](#5-database-schema)
6. [API Design](#6-api-design)
7. [Server Implementation](#7-server-implementation)
8. [Admin App Implementation](#8-admin-app-implementation)
9. [Email Notifications](#9-email-notifications)
10. [Testing Strategy](#10-testing-strategy)
11. [Migration Plan](#11-migration-plan)
12. [Security Considerations](#12-security-considerations)
13. [File Reference](#13-file-reference)

---

## 1. Overview

### 1.1 Goal

Implement the ability for project owners to transfer ownership of their projects to other users. This enables:
- Business continuity when team leads change
- Handoff of projects between team members
- Account migration scenarios

### 1.2 Scope

| Component | Changes |
|-----------|---------|
| SwiftlyFeedbackServer | New endpoint, DTOs, email service method |
| SwiftlyFeedbackAdmin | Transfer UI, view model methods, confirmation flow |
| SwiftlyFeedbackKit | No changes (SDK doesn't manage ownership) |

### 1.3 Key Behaviors

| Scenario | Behavior |
|----------|----------|
| Transfer to existing member | Member removed from members list, becomes owner |
| Transfer to non-member user | User becomes owner directly |
| Previous owner after transfer | Automatically added as Admin member |
| Project with members | New owner must have Team tier |
| Project without members | New owner can have any tier |

---

## 2. Current State Analysis

### 2.1 Ownership Model

The current ownership model stores the owner directly on the Project model:

**Project.swift** (lines 19-20):
```swift
@Parent(key: "owner_id")
var user: User
```

**Key characteristics:**
- One owner per project (required field)
- Owner stored via foreign key with cascade delete
- Owner is NOT in the ProjectMember table
- Owner has implicit full access to all project operations

### 2.2 Project Roles

**ProjectMember.swift** (lines 36-40):
```swift
enum ProjectRole: String, Codable {
    case admin
    case member
    case viewer
}
```

| Role | Permissions |
|------|-------------|
| Owner | Full access: delete, archive, manage members, regenerate API key, configure integrations |
| Admin | Manage settings/members, update/delete feedback |
| Member | View and respond to feedback |
| Viewer | Read-only access |

### 2.3 Authorization Patterns

**ProjectController.swift** provides three authorization helpers:

```swift
// Any access (owner or any member role)
private func getProjectWithAccess(req: Request, user: User) -> Project

// Owner only (line 3501-3516)
private func getProjectAsOwner(req: Request, user: User) -> Project {
    // Checks: user.id == project.$owner.id
    // Throws: .forbidden if not owner
}

// Owner or Admin role (line 3518-3545)
private func getProjectAsOwnerOrAdmin(req: Request, user: User) -> Project
```

### 2.4 Subscription Tier Constraints

**Current enforcement for team features:**
- Project owner must have Team tier to invite members
- Invitee must have Team tier to accept invite
- Server returns 402 Payment Required if tier insufficient

**ProjectController.swift** (lines 361-365):
```swift
try await project.$owner.load(on: req.db)
guard project.owner.subscriptionTier.meetsRequirement(.team) else {
    throw Abort(.paymentRequired, reason: "Project owner needs Team subscription")
}
```

### 2.5 Member Management Flow

**Add member endpoint** (`POST /projects/:projectId/members`):
1. Validates owner has Team tier
2. Checks if user exists
3. If exists: creates ProjectMember directly
4. If not exists: creates ProjectInvite with 8-char code
5. Sends invitation email

---

## 3. Requirements

### 3.1 Functional Requirements

#### Transfer Initiation
- [ ] Only current owner can initiate transfer
- [ ] Owner can transfer to any registered user (member or non-member)
- [ ] Transfer requires explicit confirmation
- [ ] Owner cannot transfer to themselves

#### Tier Validation
- [ ] If project has existing members, new owner must have Team tier
- [ ] If project has no members, any tier is acceptable
- [ ] Validate tier before executing transfer

#### Post-Transfer State
- [ ] New owner has full project access immediately
- [ ] Previous owner is added as Admin member
- [ ] If new owner was a member, their membership is removed (they become owner)
- [ ] All project settings, integrations, and data remain unchanged
- [ ] API key remains the same (no regeneration)

#### Notifications
- [ ] Email notification sent to new owner
- [ ] Optional: Email confirmation to previous owner

### 3.2 Non-Functional Requirements

- **Atomicity:** Transfer must be all-or-nothing (use database transaction)
- **Audit:** Log ownership transfers for compliance
- **Security:** Validate all inputs, prevent unauthorized access
- **UX:** Clear confirmation flow, success/error feedback

### 3.3 Edge Cases

| Edge Case | Expected Behavior |
|-----------|-------------------|
| New owner doesn't exist | 404 Not Found |
| New owner is current owner | 400 Bad Request |
| New owner is existing member | Remove membership, make owner |
| Project archived | Allow transfer (archived is a state, not a blocker) |
| New owner at project limit | Allow (transfer doesn't count as "creating" a project) |
| Pending invites exist | Keep invites (they reference project, not owner) |

---

## 4. Architecture Design

### 4.1 Transfer Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Admin App                                      │
│  ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐  │
│  │ Project Details │────▶│ Transfer Sheet   │────▶│ Confirmation    │  │
│  │ Menu            │     │ (Select User)    │     │ Alert           │  │
│  └─────────────────┘     └──────────────────┘     └────────┬────────┘  │
└─────────────────────────────────────────────────────────────┼──────────┘
                                                              │
                                                              │ POST /transfer-ownership
                                                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Server                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    ProjectController                              │   │
│  │  transferOwnership(req:)                                         │   │
│  │    1. Authenticate & authorize (owner only)                      │   │
│  │    2. Validate new owner exists                                  │   │
│  │    3. Check tier requirements                                    │   │
│  │    4. Begin transaction                                          │   │
│  │       a. Update project.owner_id                                 │   │
│  │       b. Remove new owner's membership (if exists)               │   │
│  │       c. Add previous owner as Admin member                      │   │
│  │    5. Commit transaction                                         │   │
│  │    6. Send email notification                                    │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                      EmailService                                 │   │
│  │  sendOwnershipTransferNotification()                             │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 State Transitions

**Before Transfer:**
```
Project
├── owner: User A
└── members: [User B (admin), User C (member)]
```

**After Transfer to User B:**
```
Project
├── owner: User B
└── members: [User A (admin), User C (member)]
```

**After Transfer to User D (non-member):**
```
Project
├── owner: User D
└── members: [User A (admin), User B (admin), User C (member)]
```

---

## 5. Database Schema

### 5.1 Existing Schema (No Changes Required)

The ownership transfer feature can be implemented without schema changes:

```sql
-- Existing projects table
CREATE TABLE projects (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    -- ... other fields
);

-- Existing project_members table
CREATE TABLE project_members (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL,
    -- ... other fields
    UNIQUE(project_id, user_id)
);
```

### 5.2 Optional: Transfer Audit Log

If audit logging is required, add a new table:

```sql
CREATE TABLE project_ownership_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    previous_owner_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    new_owner_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    transferred_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    transferred_by_id UUID REFERENCES users(id) ON DELETE SET NULL,

    CONSTRAINT fk_project FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE INDEX idx_ownership_transfers_project ON project_ownership_transfers(project_id);
CREATE INDEX idx_ownership_transfers_date ON project_ownership_transfers(transferred_at);
```

**Migration file:** `CreateProjectOwnershipTransfers.swift`

```swift
struct CreateProjectOwnershipTransfers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("project_ownership_transfers")
            .id()
            .field("project_id", .uuid, .required, .references("projects", "id", onDelete: .cascade))
            .field("previous_owner_id", .uuid, .required, .references("users", "id", onDelete: .setNull))
            .field("new_owner_id", .uuid, .required, .references("users", "id", onDelete: .setNull))
            .field("transferred_at", .datetime, .required)
            .field("transferred_by_id", .uuid, .references("users", "id", onDelete: .setNull))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("project_ownership_transfers").delete()
    }
}
```

---

## 6. API Design

### 6.1 Endpoint

```http
POST /api/v1/projects/{projectId}/transfer-ownership
Authorization: Bearer <token>
Content-Type: application/json
```

### 6.2 Request Body

```json
{
    "newOwnerId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Alternative: Transfer by email** (more user-friendly):
```json
{
    "newOwnerEmail": "newowner@example.com"
}
```

### 6.3 Response (200 OK)

```json
{
    "projectId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "projectName": "My App Feedback",
    "newOwner": {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "email": "newowner@example.com",
        "name": "New Owner"
    },
    "previousOwner": {
        "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
        "email": "previousowner@example.com",
        "name": "Previous Owner"
    },
    "transferredAt": "2026-01-17T12:00:00Z"
}
```

### 6.4 Error Responses

| Status | Reason | Response |
|--------|--------|----------|
| 400 | Transfer to self | `{ "error": true, "reason": "Cannot transfer ownership to yourself" }` |
| 400 | Invalid UUID | `{ "error": true, "reason": "Invalid user ID format" }` |
| 401 | Not authenticated | `{ "error": true, "reason": "Unauthorized" }` |
| 402 | Tier requirement | `{ "error": true, "reason": "New owner needs Team subscription to own a project with members" }` |
| 403 | Not project owner | `{ "error": true, "reason": "Only the project owner can transfer ownership" }` |
| 404 | Project not found | `{ "error": true, "reason": "Project not found" }` |
| 404 | User not found | `{ "error": true, "reason": "User not found" }` |

### 6.5 DTOs

```swift
// MARK: - Request DTO

struct TransferOwnershipDTO: Content, Validatable {
    let newOwnerId: UUID?
    let newOwnerEmail: String?

    static func validations(_ validations: inout Validations) {
        // At least one identifier required
        validations.add("newOwnerId", as: UUID?.self, is: .nil || .valid)
        validations.add("newOwnerEmail", as: String?.self, is: .nil || .email)
    }

    func validate() throws {
        guard newOwnerId != nil || newOwnerEmail != nil else {
            throw Abort(.badRequest, reason: "Either newOwnerId or newOwnerEmail is required")
        }
    }
}

// MARK: - Response DTO

struct TransferOwnershipResponseDTO: Content {
    let projectId: UUID
    let projectName: String
    let newOwner: UserSummaryDTO
    let previousOwner: UserSummaryDTO
    let transferredAt: Date

    struct UserSummaryDTO: Content {
        let id: UUID
        let email: String
        let name: String
    }
}
```

---

## 7. Server Implementation

### 7.1 Route Registration

**routes.swift** - Add to protected project routes:

```swift
// Project ownership transfer
protected.post(":projectId", "transfer-ownership", use: projectController.transferOwnership)
```

### 7.2 Controller Implementation

**ProjectController.swift** - Add after `regenerateApiKey()`:

```swift
/// Transfer project ownership to another user
/// - Route: POST /projects/:projectId/transfer-ownership
/// - Authorization: Project owner only
@Sendable
func transferOwnership(req: Request) async throws -> TransferOwnershipResponseDTO {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwner(req: req, user: user)

    // Decode and validate request
    try TransferOwnershipDTO.validate(content: req)
    let dto = try req.content.decode(TransferOwnershipDTO.self)
    try dto.validate()

    let currentOwnerId = try user.requireID()
    let projectId = try project.requireID()

    // Resolve new owner (by ID or email)
    let newOwner: User
    if let newOwnerId = dto.newOwnerId {
        guard let foundUser = try await User.find(newOwnerId, on: req.db) else {
            throw Abort(.notFound, reason: "User not found")
        }
        newOwner = foundUser
    } else if let email = dto.newOwnerEmail {
        guard let foundUser = try await User.query(on: req.db)
            .filter(\.$email == email.lowercased())
            .first() else {
            throw Abort(.notFound, reason: "User not found")
        }
        newOwner = foundUser
    } else {
        throw Abort(.badRequest, reason: "Either newOwnerId or newOwnerEmail is required")
    }

    let newOwnerId = try newOwner.requireID()

    // Validation 1: Cannot transfer to self
    guard newOwnerId != currentOwnerId else {
        throw Abort(.badRequest, reason: "Cannot transfer ownership to yourself")
    }

    // Validation 2: Check tier requirements if project has members
    let memberCount = try await ProjectMember.query(on: req.db)
        .filter(\.$project.$id == projectId)
        .count()

    if memberCount > 0 && !newOwner.subscriptionTier.meetsRequirement(.team) {
        throw Abort(
            .paymentRequired,
            reason: "New owner needs Team subscription to own a project with members"
        )
    }

    // Execute transfer in transaction
    try await req.db.transaction { database in
        // Check if new owner is currently a member
        if let existingMembership = try await ProjectMember.query(on: database)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == newOwnerId)
            .first() {
            // Remove their membership (they're becoming owner)
            try await existingMembership.delete(on: database)
        }

        // Update project owner
        project.$owner.id = newOwnerId
        try await project.save(on: database)

        // Add previous owner as Admin member
        let adminMember = ProjectMember(
            projectId: projectId,
            userId: currentOwnerId,
            role: .admin
        )
        try await adminMember.save(on: database)

        // Optional: Log the transfer for audit
        // let transferLog = ProjectOwnershipTransfer(...)
        // try await transferLog.save(on: database)
    }

    // Send notification email (outside transaction)
    Task {
        do {
            try await req.emailService.sendOwnershipTransferNotification(
                to: newOwner.email,
                newOwnerName: newOwner.name,
                projectName: project.name,
                previousOwnerName: user.name
            )
        } catch {
            req.logger.error("Failed to send ownership transfer email: \(error)")
        }
    }

    // Build response
    return TransferOwnershipResponseDTO(
        projectId: projectId,
        projectName: project.name,
        newOwner: .init(
            id: newOwnerId,
            email: newOwner.email,
            name: newOwner.name
        ),
        previousOwner: .init(
            id: currentOwnerId,
            email: user.email,
            name: user.name
        ),
        transferredAt: Date()
    )
}
```

### 7.3 Model Extension (Optional)

**Project.swift** - Add helper method:

```swift
extension Project {
    /// Transfer ownership to a new user
    /// - Note: Call within a transaction for atomicity
    func transferOwnership(
        to newOwner: User,
        previousOwner: User,
        on database: Database
    ) async throws {
        let projectId = try requireID()
        let newOwnerId = try newOwner.requireID()
        let previousOwnerId = try previousOwner.requireID()

        // Remove new owner's membership if exists
        try await ProjectMember.query(on: database)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == newOwnerId)
            .delete()

        // Update owner
        self.$owner.id = newOwnerId
        try await self.save(on: database)

        // Add previous owner as admin
        let adminMember = ProjectMember(
            projectId: projectId,
            userId: previousOwnerId,
            role: .admin
        )
        try await adminMember.save(on: database)
    }
}
```

---

## 8. Admin App Implementation

### 8.1 API Client Methods

**AdminAPIClient.swift** - Add transfer method:

```swift
// MARK: - Ownership Transfer

struct TransferOwnershipRequest: Codable {
    let newOwnerId: UUID?
    let newOwnerEmail: String?

    init(newOwnerId: UUID) {
        self.newOwnerId = newOwnerId
        self.newOwnerEmail = nil
    }

    init(newOwnerEmail: String) {
        self.newOwnerId = nil
        self.newOwnerEmail = newOwnerEmail
    }
}

struct TransferOwnershipResponse: Codable {
    let projectId: UUID
    let projectName: String
    let newOwner: UserSummary
    let previousOwner: UserSummary
    let transferredAt: Date

    struct UserSummary: Codable {
        let id: UUID
        let email: String
        let name: String
    }
}

func transferProjectOwnership(
    projectId: UUID,
    newOwnerId: UUID
) async throws -> TransferOwnershipResponse {
    let request = TransferOwnershipRequest(newOwnerId: newOwnerId)
    return try await post(
        path: "projects/\(projectId)/transfer-ownership",
        body: request
    )
}

func transferProjectOwnership(
    projectId: UUID,
    newOwnerEmail: String
) async throws -> TransferOwnershipResponse {
    let request = TransferOwnershipRequest(newOwnerEmail: newOwnerEmail)
    return try await post(
        path: "projects/\(projectId)/transfer-ownership",
        body: request
    )
}
```

### 8.2 ViewModel Methods

**ProjectViewModel.swift** - Add transfer functionality:

```swift
// MARK: - Ownership Transfer

@Published var showingTransferSheet = false
@Published var showingTransferConfirmation = false
@Published var selectedTransferRecipient: ProjectMember?
@Published var transferEmail: String = ""

func transferOwnership(to memberId: UUID) async -> Bool {
    isLoading = true
    errorMessage = nil

    guard let projectId = selectedProject?.id else {
        showError(message: "No project selected")
        isLoading = false
        return false
    }

    do {
        let response = try await AdminAPIClient.shared.transferProjectOwnership(
            projectId: projectId,
            newOwnerId: memberId
        )

        // Reload project to get updated owner
        await loadProject(id: projectId)
        await loadMembers()

        isLoading = false
        showSuccess(message: "Ownership transferred to \(response.newOwner.name)")
        return true

    } catch let error as APIError {
        isLoading = false

        if error.isPaymentRequired {
            showError(message: "New owner needs Team subscription to own a project with members")
        } else if error.statusCode == 404 {
            showError(message: "User not found")
        } else if error.statusCode == 403 {
            showError(message: "Only the project owner can transfer ownership")
        } else {
            showError(message: error.localizedDescription)
        }
        return false

    } catch {
        isLoading = false
        showError(message: error.localizedDescription)
        return false
    }
}

func transferOwnership(toEmail email: String) async -> Bool {
    isLoading = true
    errorMessage = nil

    guard let projectId = selectedProject?.id else {
        showError(message: "No project selected")
        isLoading = false
        return false
    }

    do {
        let response = try await AdminAPIClient.shared.transferProjectOwnership(
            projectId: projectId,
            newOwnerEmail: email
        )

        await loadProject(id: projectId)
        await loadMembers()

        isLoading = false
        showSuccess(message: "Ownership transferred to \(response.newOwner.name)")
        return true

    } catch let error as APIError {
        isLoading = false

        if error.isPaymentRequired {
            showError(message: "New owner needs Team subscription to own a project with members")
        } else if error.statusCode == 404 {
            showError(message: "No user found with that email address")
        } else {
            showError(message: error.localizedDescription)
        }
        return false

    } catch {
        isLoading = false
        showError(message: error.localizedDescription)
        return false
    }
}
```

### 8.3 Transfer Sheet View

**TransferOwnershipSheet.swift** - New file:

```swift
import SwiftUI

struct TransferOwnershipSheet: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMemberId: UUID?
    @State private var showingConfirmation = false
    @State private var transferMode: TransferMode = .selectMember
    @State private var emailInput: String = ""

    enum TransferMode: String, CaseIterable {
        case selectMember = "Select Member"
        case enterEmail = "Enter Email"
    }

    var body: some View {
        NavigationStack {
            Form {
                transferModeSection

                switch transferMode {
                case .selectMember:
                    memberSelectionSection
                case .enterEmail:
                    emailInputSection
                }

                warningSection
            }
            .navigationTitle("Transfer Ownership")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") {
                        showingConfirmation = true
                    }
                    .disabled(!canTransfer)
                }
            }
            .confirmationDialog(
                "Transfer Ownership",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Transfer Ownership", role: .destructive) {
                    Task {
                        await performTransfer()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var transferModeSection: some View {
        Section {
            Picker("Transfer To", selection: $transferMode) {
                ForEach(TransferMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var memberSelectionSection: some View {
        Section {
            if viewModel.projectMembers.isEmpty {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.slash",
                    description: Text("Add team members first, or enter an email address to transfer to any user.")
                )
            } else {
                ForEach(viewModel.projectMembers) { member in
                    Button {
                        selectedMemberId = member.user.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.user.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(member.user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            RoleBadge(role: member.role)

                            if member.user.id == selectedMemberId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Select New Owner")
        } footer: {
            Text("The selected member will become the project owner. You will be demoted to Admin.")
        }
    }

    @ViewBuilder
    private var emailInputSection: some View {
        Section {
            TextField("Email address", text: $emailInput)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        } header: {
            Text("New Owner Email")
        } footer: {
            Text("Enter the email address of a registered Feedback Kit user. They will receive a notification.")
        }
    }

    @ViewBuilder
    private var warningSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This action cannot be undone")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("You will lose owner privileges and become an Admin member of this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if !viewModel.projectMembers.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Team subscription required")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("This project has team members. The new owner must have a Team subscription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var canTransfer: Bool {
        switch transferMode {
        case .selectMember:
            return selectedMemberId != nil && !viewModel.isLoading
        case .enterEmail:
            return isValidEmail(emailInput) && !viewModel.isLoading
        }
    }

    private var confirmationMessage: String {
        switch transferMode {
        case .selectMember:
            if let memberId = selectedMemberId,
               let member = viewModel.projectMembers.first(where: { $0.user.id == memberId }) {
                return "Transfer ownership of \"\(project.name)\" to \(member.user.name)? You will become an Admin member."
            }
            return "Transfer ownership?"
        case .enterEmail:
            return "Transfer ownership of \"\(project.name)\" to \(emailInput)? You will become an Admin member."
        }
    }

    // MARK: - Actions

    private func performTransfer() async {
        let success: Bool

        switch transferMode {
        case .selectMember:
            guard let memberId = selectedMemberId else { return }
            success = await viewModel.transferOwnership(to: memberId)
        case .enterEmail:
            success = await viewModel.transferOwnership(toEmail: emailInput)
        }

        if success {
            dismiss()
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
}

// MARK: - Role Badge

struct RoleBadge: View {
    let role: ProjectRole

    var body: some View {
        Text(role.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(role.color.opacity(0.15))
            .foregroundStyle(role.color)
            .clipShape(Capsule())
    }
}

extension ProjectRole {
    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .member: return "Member"
        case .viewer: return "Viewer"
        }
    }

    var color: Color {
        switch self {
        case .admin: return .orange
        case .member: return .blue
        case .viewer: return .gray
        }
    }
}
```

### 8.4 Integration with Project Menu

**ProjectDetailView.swift** or project menu - Add transfer option:

```swift
// Add state variable
@State private var showingTransferSheet = false

// In the menu
Menu {
    // ... existing menu items ...

    Divider()

    if viewModel.isOwner {
        Button(role: .destructive) {
            showingTransferSheet = true
        } label: {
            Label("Transfer Ownership", systemImage: "arrow.right.arrow.left.circle")
        }
    }
}
.sheet(isPresented: $showingTransferSheet) {
    TransferOwnershipSheet(project: project, viewModel: viewModel)
}
```

### 8.5 Project Members View Integration

**ProjectMembersView.swift** - Add transfer button for owners:

```swift
// In toolbar or as a section
if viewModel.isOwner {
    Section {
        Button {
            showingTransferSheet = true
        } label: {
            Label("Transfer Ownership", systemImage: "arrow.right.arrow.left.circle")
        }
    } header: {
        Text("Ownership")
    } footer: {
        Text("Transfer this project to another user. You will become an Admin member.")
    }
}
```

---

## 9. Email Notifications

### 9.1 New Owner Notification

**EmailService.swift** - Add method:

```swift
/// Send notification to new owner after ownership transfer
func sendOwnershipTransferNotification(
    to email: String,
    newOwnerName: String,
    projectName: String,
    previousOwnerName: String
) async throws {
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        \(emailHeader(title: "You're Now a Project Owner"))

        <div style="background: #ffffff; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
            <p style="font-size: 16px; margin-bottom: 20px;">Hi \(newOwnerName.htmlEscaped),</p>

            <p style="font-size: 16px; margin-bottom: 20px;">
                <strong>\(previousOwnerName.htmlEscaped)</strong> has transferred ownership of
                <strong>\(projectName.htmlEscaped)</strong> to you.
            </p>

            <div style="background: #FFF8E7; border-left: 4px solid \(primaryColor); border-radius: 0 8px 8px 0; padding: 20px; margin: 25px 0;">
                <p style="font-size: 14px; color: #333; margin: 0 0 10px 0; font-weight: 600;">
                    As the new owner, you can:
                </p>
                <ul style="font-size: 14px; color: #555; margin: 0; padding-left: 20px;">
                    <li>Manage team members and their roles</li>
                    <li>Configure project settings and integrations</li>
                    <li>Archive or delete the project</li>
                    <li>Regenerate the API key</li>
                    <li>Transfer ownership to another user</li>
                </ul>
            </div>

            <p style="font-size: 14px; color: #666; margin-bottom: 20px;">
                \(previousOwnerName.htmlEscaped) has been added as an Admin member and retains access to manage feedback.
            </p>

            <div style="text-align: center; margin: 30px 0;">
                <a href="feedbackkit://project/open"
                   style="display: inline-block; background: linear-gradient(135deg, \(gradientStart) 0%, \(primaryColor) 50%, \(gradientEnd) 100%); color: white; text-decoration: none; padding: 14px 32px; border-radius: 8px; font-weight: 600; font-size: 16px;">
                    Open Project
                </a>
            </div>

            \(emailFooter(message: "If you didn't expect this transfer, please contact \(previousOwnerName.htmlEscaped) directly."))
        </div>
    </body>
    </html>
    """

    let request = ResendEmailRequest(
        from: "Feedback Kit <noreply@\(emailDomain)>",
        to: [email],
        subject: "You're now the owner of \(projectName)",
        html: html
    )

    try await sendEmail(request)
}
```

### 9.2 Previous Owner Confirmation (Optional)

```swift
/// Send confirmation to previous owner after transfer
func sendOwnershipTransferConfirmation(
    to email: String,
    previousOwnerName: String,
    projectName: String,
    newOwnerName: String
) async throws {
    let html = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        \(emailHeader(title: "Ownership Transferred"))

        <div style="background: #ffffff; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 12px 12px;">
            <p style="font-size: 16px; margin-bottom: 20px;">Hi \(previousOwnerName.htmlEscaped),</p>

            <p style="font-size: 16px; margin-bottom: 20px;">
                You have successfully transferred ownership of <strong>\(projectName.htmlEscaped)</strong>
                to <strong>\(newOwnerName.htmlEscaped)</strong>.
            </p>

            <div style="background: #F0F7FF; border-left: 4px solid #3B82F6; border-radius: 0 8px 8px 0; padding: 20px; margin: 25px 0;">
                <p style="font-size: 14px; color: #333; margin: 0;">
                    <strong>Your new role:</strong> Admin<br>
                    You still have access to manage feedback, comments, and project settings.
                </p>
            </div>

            <p style="font-size: 14px; color: #666;">
                If you did not initiate this transfer, please contact support immediately.
            </p>

            \(emailFooter(message: "This is a confirmation of your ownership transfer request."))
        </div>
    </body>
    </html>
    """

    let request = ResendEmailRequest(
        from: "Feedback Kit <noreply@\(emailDomain)>",
        to: [email],
        subject: "Ownership of \(projectName) has been transferred",
        html: html
    )

    try await sendEmail(request)
}
```

---

## 10. Testing Strategy

### 10.1 Server Unit Tests

**ProjectOwnershipTransferTests.swift**:

```swift
import XCTVapor
import Testing
@testable import App

@Suite("Project Ownership Transfer Tests")
struct ProjectOwnershipTransferTests {

    @Test("Owner can transfer to team member")
    func testTransferToMember() async throws {
        // Setup: Owner with Team tier, project with member
        // Action: Transfer to member
        // Assert: Member is now owner, previous owner is Admin
    }

    @Test("Owner can transfer to non-member user")
    func testTransferToNonMember() async throws {
        // Setup: Owner, project, separate user not in project
        // Action: Transfer to non-member
        // Assert: User is now owner, previous owner is Admin
    }

    @Test("Cannot transfer to self")
    func testCannotTransferToSelf() async throws {
        // Setup: Owner and project
        // Action: Attempt transfer to self
        // Assert: 400 Bad Request
    }

    @Test("Cannot transfer to non-existent user")
    func testCannotTransferToNonExistentUser() async throws {
        // Setup: Owner and project
        // Action: Transfer to random UUID
        // Assert: 404 Not Found
    }

    @Test("Non-owner cannot transfer")
    func testNonOwnerCannotTransfer() async throws {
        // Setup: Owner, project, admin member
        // Action: Admin attempts transfer
        // Assert: 403 Forbidden
    }

    @Test("Transfer fails if new owner lacks Team tier with members")
    func testTierRequirement() async throws {
        // Setup: Project with members, new owner with Free tier
        // Action: Attempt transfer
        // Assert: 402 Payment Required
    }

    @Test("Transfer succeeds if new owner lacks Team tier without members")
    func testNoTierRequirementWithoutMembers() async throws {
        // Setup: Project without members, new owner with Free tier
        // Action: Transfer
        // Assert: Success
    }

    @Test("Previous owner becomes Admin after transfer")
    func testPreviousOwnerBecomesAdmin() async throws {
        // Setup: Owner and project
        // Action: Transfer
        // Assert: Previous owner in ProjectMember with .admin role
    }

    @Test("New owner membership removed after transfer")
    func testNewOwnerMembershipRemoved() async throws {
        // Setup: Owner, project, member
        // Action: Transfer to member
        // Assert: No ProjectMember record for new owner
    }

    @Test("Transfer by email works")
    func testTransferByEmail() async throws {
        // Setup: Owner, project, user with known email
        // Action: Transfer by email
        // Assert: Success, correct user is new owner
    }

    @Test("Email notification sent to new owner")
    func testEmailNotificationSent() async throws {
        // Setup: Owner, project, recipient
        // Action: Transfer
        // Assert: Email service called with correct parameters
    }
}
```

### 10.2 Admin App Tests

**TransferOwnershipTests.swift**:

```swift
import XCTest
import Testing
@testable import SwiftlyFeedbackAdmin

@Suite("Transfer Ownership UI Tests")
struct TransferOwnershipUITests {

    @Test("Transfer button only visible to owner")
    func testTransferButtonVisibility() {
        // Assert: Transfer option shown only when user is owner
    }

    @Test("Member selection updates correctly")
    func testMemberSelection() {
        // Action: Tap member in list
        // Assert: Selection indicator shown
    }

    @Test("Email validation works")
    func testEmailValidation() {
        // Assert: Invalid email disables transfer button
        // Assert: Valid email enables transfer button
    }

    @Test("Confirmation dialog shows correct message")
    func testConfirmationMessage() {
        // Assert: Message includes project name and recipient
    }

    @Test("Success dismisses sheet")
    func testSuccessDismissesSheet() {
        // Action: Successful transfer
        // Assert: Sheet dismissed, success message shown
    }

    @Test("Error displays alert")
    func testErrorDisplaysAlert() {
        // Action: Failed transfer
        // Assert: Error alert shown with message
    }
}
```

### 10.3 Manual Testing Checklist

#### Server
- [ ] Transfer to existing member succeeds
- [ ] Transfer to non-member user succeeds
- [ ] Transfer to self returns 400
- [ ] Transfer to non-existent user returns 404
- [ ] Non-owner transfer returns 403
- [ ] Tier requirement enforced (402 when needed)
- [ ] Previous owner added as Admin
- [ ] New owner's membership removed
- [ ] Email sent to new owner
- [ ] Transaction rollback on failure

#### Admin App (iOS)
- [ ] Transfer button visible only to owner
- [ ] Member list displays correctly
- [ ] Email input validates format
- [ ] Segmented picker switches modes
- [ ] Confirmation dialog appears
- [ ] Loading state shown during transfer
- [ ] Success message displayed
- [ ] Error alert shown on failure
- [ ] Sheet dismisses after success
- [ ] Project details update after transfer

#### Admin App (macOS)
- [ ] Same checklist as iOS
- [ ] Keyboard navigation works
- [ ] Menu item accessible

---

## 11. Migration Plan

### 11.1 Deployment Order

1. **Server deployment:**
   - Deploy new endpoint (backward compatible)
   - No database migration required for basic feature
   - Optional: Deploy audit log migration

2. **Admin app release:**
   - Include transfer UI in next app version
   - Feature available immediately after update

### 11.2 Rollback Plan

- Server endpoint can be removed without data loss
- No schema changes to rollback (unless audit log added)
- Admin app can be updated to remove UI

### 11.3 Feature Flags (Optional)

If gradual rollout desired:

```swift
// Server
let transferOwnershipEnabled = Environment.get("FEATURE_TRANSFER_OWNERSHIP") == "true"

// In controller
guard transferOwnershipEnabled else {
    throw Abort(.notFound)
}
```

---

## 12. Security Considerations

### 12.1 Authorization

- **Strict owner check:** Only project owner can initiate transfer
- **Use existing helper:** `getProjectAsOwner()` provides consistent authorization
- **No elevated privileges:** Transfer doesn't bypass tier requirements

### 12.2 Input Validation

- **UUID validation:** Validate format before database query
- **Email normalization:** Lowercase before lookup
- **Prevent self-transfer:** Explicit check against current owner

### 12.3 Transaction Safety

- **Atomic operations:** Use database transaction for all changes
- **Rollback on failure:** Any error reverts all changes
- **Consistent state:** No partial transfers possible

### 12.4 Rate Limiting

Consider adding rate limiting to prevent abuse:
- Max 5 transfer attempts per hour per user
- Implement via existing rate limiting middleware

### 12.5 Audit Trail

- Log all transfer attempts (success and failure)
- Include: timestamp, project ID, previous owner, new owner, IP address
- Retain logs for compliance period

---

## 13. File Reference

### 13.1 Server Files

#### New Files to Create

| File | Purpose |
|------|---------|
| `DTOs/TransferOwnershipDTO.swift` | Request/response models (or add to ProjectDTO.swift) |
| `Migrations/CreateProjectOwnershipTransfers.swift` | Audit log table (optional) |
| `Models/ProjectOwnershipTransfer.swift` | Audit log model (optional) |

#### Files to Modify

| File | Changes |
|------|---------|
| `Controllers/ProjectController.swift` | Add `transferOwnership()` method |
| `routes.swift` | Register new endpoint |
| `Services/EmailService.swift` | Add notification methods |

### 13.2 Admin App Files

#### New Files to Create

| File | Purpose |
|------|---------|
| `Views/Projects/TransferOwnershipSheet.swift` | Transfer UI sheet |

#### Files to Modify

| File | Changes |
|------|---------|
| `Services/AdminAPIClient.swift` | Add transfer API methods |
| `ViewModels/ProjectViewModel.swift` | Add transfer functionality |
| `Views/Projects/ProjectDetailView.swift` | Add menu option |
| `Views/Projects/ProjectMembersView.swift` | Add transfer section |

### 13.3 Test Files

| File | Purpose |
|------|---------|
| `Tests/AppTests/ProjectOwnershipTransferTests.swift` | Server unit tests |
| `SwiftlyFeedbackAdminTests/TransferOwnershipTests.swift` | Admin app tests |

---

## Appendix A: API Quick Reference

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/projects/:id/transfer-ownership` | Bearer (Owner) | Transfer project ownership |

## Appendix B: Error Code Reference

| HTTP Status | Error Code | Description |
|-------------|------------|-------------|
| 400 | `self_transfer` | Cannot transfer to yourself |
| 400 | `invalid_input` | Missing or invalid request body |
| 401 | `unauthorized` | Not authenticated |
| 402 | `tier_required` | New owner needs Team tier |
| 403 | `forbidden` | Not the project owner |
| 404 | `project_not_found` | Project doesn't exist |
| 404 | `user_not_found` | New owner doesn't exist |

---

*Document Version: 1.0*
*Last Updated: January 2026*
