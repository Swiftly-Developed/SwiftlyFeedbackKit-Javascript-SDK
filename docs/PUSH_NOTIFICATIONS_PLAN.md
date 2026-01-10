# Push Notifications Technical Plan

> **Status:** Draft
> **Created:** January 2026
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
9. [Deep Linking](#9-deep-linking)
10. [Testing Strategy](#10-testing-strategy)
11. [Migration Plan](#11-migration-plan)
12. [Dependencies](#12-dependencies)
13. [File Reference](#13-file-reference)

---

## 1. Overview

### 1.1 Goal

Implement push notifications for the FeedbackKit platform to notify users when:
- New feedback is submitted to their projects
- Comments are added to feedback
- Votes are cast on feedback
- Feedback status changes

Users should be able to configure notifications at two levels:
1. **Personal level** - Global preferences for all projects
2. **Project level** - Per-project overrides for granular control

### 1.2 Scope

| Component | Changes |
|-----------|---------|
| SwiftlyFeedbackServer | New models, migrations, service, controller updates |
| SwiftlyFeedbackAdmin | Settings UI, device registration, notification handling |
| SwiftlyFeedbackKit | No changes (SDK users don't receive push notifications) |

### 1.3 Notification Types

| Type | Trigger | Recipients |
|------|---------|------------|
| New Feedback | Feedback created via SDK | Project owner + members |
| New Comment | Comment added to feedback | Project owner + members + feedback submitter |
| New Vote | Vote cast on feedback | Feedback submitter (if registered user) |
| Status Change | Feedback status updated | Feedback submitter + voters (if registered) |

---

## 2. Current State Analysis

### 2.1 Existing Email Notification System

The platform already has a mature email notification system via Resend API.

**Current Implementation:**
- `EmailService.swift` handles all email dispatch
- User preferences stored in `User` model: `notifyNewFeedback`, `notifyNewComments`
- Notifications dispatched asynchronously via `Task { }` blocks in controllers
- Errors logged but don't block API responses

**Current Email Notification Types:**
```
✅ New Feedback → Project owner + members
✅ New Comments → Project owner + members
✅ Status Changes → Feedback submitter only
❌ Votes → Not implemented (no email stored for voters)
```

### 2.2 Notification Dispatch Pattern

All controllers follow this pattern:

```swift
// In FeedbackController.create()
Task {
    do {
        // 1. Load recipients
        try await project.$owner.load(on: req.db)
        let members = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == project.id!)
            .with(\.$user)
            .all()

        // 2. Filter by preferences
        var emails: [String] = []
        if project.owner.notifyNewFeedback {
            emails.append(project.owner.email)
        }
        for member in members where member.user.notifyNewFeedback {
            emails.append(member.user.email)
        }

        // 3. Send notification
        try await req.emailService.sendNewFeedbackNotification(...)
    } catch {
        req.logger.error("Failed to send notification: \(error)")
    }
}
```

### 2.3 Project-Level Settings Pattern (Slack)

The Slack integration provides a pattern for project-level notification settings:

```swift
// Project.swift
@OptionalField(key: "slack_webhook_url") var slackWebhookURL: String?
@Field(key: "slack_notify_new_feedback") var slackNotifyNewFeedback: Bool
@Field(key: "slack_notify_new_comments") var slackNotifyNewComments: Bool
@Field(key: "slack_notify_status_changes") var slackNotifyStatusChanges: Bool
@Field(key: "slack_is_active") var slackIsActive: Bool
```

### 2.4 Current Limitations

| Limitation | Impact | Solution |
|------------|--------|----------|
| Vote model has no `userEmail` field | Can't notify voters of status changes | Add optional email field to Vote |
| No per-project user preferences | Members can't opt out of specific projects | Add ProjectMemberPreference model |
| No device token storage | Can't send push notifications | Add DeviceToken model |

---

## 3. Requirements

### 3.1 Functional Requirements

#### Personal-Level Preferences
- [ ] Enable/disable push notifications globally
- [ ] Toggle for each notification type (feedback, comments, votes, status)
- [ ] Independent from email preferences
- [ ] Support multiple devices per user

#### Project-Level Preferences
- [ ] Override personal preferences per project
- [ ] Master toggle to pause all push notifications for a project
- [ ] Same granularity as personal (feedback, comments, votes, status)
- [ ] Default to personal preferences when no override set

#### Notification Delivery
- [ ] Send to all active devices for a user
- [ ] Handle device token expiry gracefully
- [ ] Include deep link URL in payload for navigation
- [ ] Show appropriate badge count
- [ ] Play default system sound

### 3.2 Non-Functional Requirements

- **Reliability:** Notifications must not block API responses
- **Scalability:** Handle multiple devices per user efficiently
- **Privacy:** Device tokens stored securely, not exposed via API
- **Monitoring:** Track delivery success/failure rates

### 3.3 Preference Resolution Logic

```
Final Decision = Project Override ?? Personal Preference ?? Default (enabled)

┌─────────────────┬──────────────────┬────────────────┬────────────┐
│ Personal Global │ Personal Type    │ Project Override│ Result     │
├─────────────────┼──────────────────┼────────────────┼────────────┤
│ Disabled        │ Any              │ Any            │ No notify  │
│ Enabled         │ Disabled         │ None           │ No notify  │
│ Enabled         │ Enabled          │ None           │ Notify     │
│ Enabled         │ Enabled          │ Disabled       │ No notify  │
│ Enabled         │ Disabled         │ Enabled        │ Notify     │
└─────────────────┴──────────────────┴────────────────┴────────────┘
```

---

## 4. Architecture Design

### 4.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Admin App (iOS/macOS)                         │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ UNNotification  │  │ Settings View    │  │ Deep Link Handler │  │
│  │ Center          │  │ (Push Prefs)     │  │                   │  │
│  └────────┬────────┘  └────────┬─────────┘  └─────────┬─────────┘  │
│           │                    │                      │             │
│           │ Device Token       │ Preferences          │ Tap Action  │
│           ▼                    ▼                      ▼             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      AuthViewModel                           │   │
│  └──────────────────────────┬──────────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────────┘
                              │ HTTPS (Bearer Token)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      SwiftlyFeedback Server                          │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                        API Routes                             │   │
│  │  POST /devices/register    PATCH /auth/notifications          │   │
│  │  DELETE /devices/:id       PATCH /projects/:id/push-settings  │   │
│  └──────────────────────────────┬───────────────────────────────┘   │
│                                 │                                    │
│  ┌──────────────────────────────▼───────────────────────────────┐   │
│  │                   PushNotificationService                     │   │
│  │  - resolveRecipients()      - sendNotification()              │   │
│  │  - checkPreferences()       - handleTokenExpiry()             │   │
│  └──────────────────────────────┬───────────────────────────────┘   │
│                                 │                                    │
│  ┌──────────────────────────────▼───────────────────────────────┐   │
│  │                      APNs Client                              │   │
│  │                (apple-pnp-kit / Swift-NIO)                    │   │
│  └──────────────────────────────┬───────────────────────────────┘   │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │ HTTP/2
                                  ▼
                      ┌───────────────────────┐
                      │  Apple Push Notification │
                      │       Service (APNs)     │
                      └───────────────────────┘
```

### 4.2 Notification Flow

```
1. Feedback Created
        │
        ▼
2. FeedbackController.create()
        │
        ├──► Email Notification (existing)
        │
        └──► Push Notification (new)
                │
                ▼
3. PushNotificationService.sendNewFeedbackNotification()
        │
        ▼
4. Resolve Recipients
        │
        ├── Load project owner
        ├── Load project members
        └── Filter by preferences
                │
                ▼
5. For each recipient:
        │
        ├── Check personal global toggle
        ├── Check personal type toggle
        ├── Check project override (if exists)
        └── If all pass → continue
                │
                ▼
6. Load active device tokens for user
        │
        ▼
7. Send to APNs for each device
        │
        ▼
8. Handle response (success/token expired/error)
```

### 4.3 Preference Model

```
┌──────────────────────────────────────────────────────────────────┐
│                              User                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Personal Preferences (applies to ALL projects by default)  │  │
│  │                                                            │  │
│  │  pushNotificationsEnabled: Bool (master toggle)            │  │
│  │  pushNotifyNewFeedback: Bool                               │  │
│  │  pushNotifyNewComments: Bool                               │  │
│  │  pushNotifyVotes: Bool                                     │  │
│  │  pushNotifyStatusChanges: Bool                             │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              │ has many
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                    ProjectMemberPreference                        │
│  (Optional per-project overrides - only created when user        │
│   explicitly customizes settings for a specific project)         │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  user_id: UUID (FK)                                        │  │
│  │  project_id: UUID (FK)                                     │  │
│  │                                                            │  │
│  │  pushNotifyNewFeedback: Bool?    (null = use personal)     │  │
│  │  pushNotifyNewComments: Bool?    (null = use personal)     │  │
│  │  pushNotifyVotes: Bool?          (null = use personal)     │  │
│  │  pushNotifyStatusChanges: Bool?  (null = use personal)     │  │
│  │  pushMuted: Bool                 (mute all for project)    │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. Database Schema

### 5.1 New Tables

#### DeviceToken Table

```sql
CREATE TABLE device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    platform VARCHAR(10) NOT NULL,  -- 'iOS', 'macOS'
    app_version VARCHAR(20),
    os_version VARCHAR(20),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_used_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT valid_platform CHECK (platform IN ('iOS', 'macOS'))
);

CREATE INDEX idx_device_tokens_user_id ON device_tokens(user_id);
CREATE INDEX idx_device_tokens_token ON device_tokens(token);
CREATE INDEX idx_device_tokens_active ON device_tokens(user_id, is_active) WHERE is_active = TRUE;
```

#### ProjectMemberPreference Table

```sql
CREATE TABLE project_member_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,

    push_notify_new_feedback BOOLEAN,  -- NULL = use personal preference
    push_notify_new_comments BOOLEAN,
    push_notify_votes BOOLEAN,
    push_notify_status_changes BOOLEAN,
    push_muted BOOLEAN NOT NULL DEFAULT FALSE,

    -- Email preferences (future expansion)
    email_notify_new_feedback BOOLEAN,
    email_notify_new_comments BOOLEAN,
    email_muted BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT unique_user_project UNIQUE (user_id, project_id)
);

CREATE INDEX idx_project_member_prefs_user ON project_member_preferences(user_id);
CREATE INDEX idx_project_member_prefs_project ON project_member_preferences(project_id);
```

#### PushNotificationLog Table (Monitoring)

```sql
CREATE TABLE push_notification_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_token_id UUID REFERENCES device_tokens(id) ON DELETE SET NULL,

    notification_type VARCHAR(50) NOT NULL,  -- 'new_feedback', 'new_comment', etc.
    status VARCHAR(20) NOT NULL,             -- 'sent', 'delivered', 'failed', 'token_expired'

    feedback_id UUID REFERENCES feedbacks(id) ON DELETE SET NULL,
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,

    payload JSONB,
    error_message TEXT,
    apns_id VARCHAR(100),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_push_logs_user ON push_notification_logs(user_id);
CREATE INDEX idx_push_logs_status ON push_notification_logs(status);
CREATE INDEX idx_push_logs_created ON push_notification_logs(created_at);
```

### 5.2 Schema Changes to Existing Tables

#### Users Table Additions

```sql
ALTER TABLE users ADD COLUMN push_notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN push_notify_new_feedback BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN push_notify_new_comments BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN push_notify_votes BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN push_notify_status_changes BOOLEAN NOT NULL DEFAULT TRUE;
```

#### Votes Table Addition (Fix Limitation)

```sql
ALTER TABLE votes ADD COLUMN user_email VARCHAR(255);
```

---

## 6. API Design

### 6.1 Device Management Endpoints

#### Register Device Token

```http
POST /api/v1/devices/register
Authorization: Bearer <token>
Content-Type: application/json

{
    "token": "abc123...xyz",
    "platform": "iOS",
    "appVersion": "1.2.0",
    "osVersion": "18.0"
}
```

**Response (201 Created):**
```json
{
    "id": "uuid",
    "platform": "iOS",
    "isActive": true,
    "createdAt": "2026-01-10T12:00:00Z"
}
```

#### Unregister Device

```http
DELETE /api/v1/devices/{deviceId}
Authorization: Bearer <token>
```

**Response:** 204 No Content

#### List User Devices

```http
GET /api/v1/devices
Authorization: Bearer <token>
```

**Response:**
```json
{
    "devices": [
        {
            "id": "uuid",
            "platform": "iOS",
            "appVersion": "1.2.0",
            "isActive": true,
            "lastUsedAt": "2026-01-10T12:00:00Z"
        }
    ]
}
```

### 6.2 Notification Preferences Endpoints

#### Update Personal Preferences

```http
PATCH /api/v1/auth/notifications
Authorization: Bearer <token>
Content-Type: application/json

{
    // Email preferences (existing)
    "notifyNewFeedback": true,
    "notifyNewComments": true,

    // Push preferences (new)
    "pushNotificationsEnabled": true,
    "pushNotifyNewFeedback": true,
    "pushNotifyNewComments": true,
    "pushNotifyVotes": false,
    "pushNotifyStatusChanges": true
}
```

**Response:** Updated `User` object

#### Get/Update Project-Specific Preferences

```http
GET /api/v1/projects/{projectId}/notification-preferences
Authorization: Bearer <token>
```

**Response:**
```json
{
    "projectId": "uuid",
    "userId": "uuid",

    "push": {
        "muted": false,
        "newFeedback": null,
        "newComments": true,
        "votes": null,
        "statusChanges": false
    },

    "email": {
        "muted": false,
        "newFeedback": null,
        "newComments": null
    },

    "effectivePreferences": {
        "push": {
            "newFeedback": true,
            "newComments": true,
            "votes": false,
            "statusChanges": false
        }
    }
}
```

```http
PATCH /api/v1/projects/{projectId}/notification-preferences
Authorization: Bearer <token>
Content-Type: application/json

{
    "push": {
        "muted": false,
        "newFeedback": null,
        "newComments": true,
        "votes": null,
        "statusChanges": false
    }
}
```

### 6.3 DTOs

```swift
// Request DTOs
struct RegisterDeviceDTO: Content {
    let token: String
    let platform: String
    let appVersion: String?
    let osVersion: String?
}

struct UpdateNotificationSettingsDTO: Content {
    // Email (existing)
    let notifyNewFeedback: Bool?
    let notifyNewComments: Bool?

    // Push (new)
    let pushNotificationsEnabled: Bool?
    let pushNotifyNewFeedback: Bool?
    let pushNotifyNewComments: Bool?
    let pushNotifyVotes: Bool?
    let pushNotifyStatusChanges: Bool?
}

struct UpdateProjectNotificationPreferencesDTO: Content {
    struct PushPreferences: Content {
        let muted: Bool?
        let newFeedback: Bool??  // nil = remove override, .some(nil) = keep, .some(value) = set
        let newComments: Bool??
        let votes: Bool??
        let statusChanges: Bool??
    }

    let push: PushPreferences?
}

// Response DTOs
struct DeviceResponseDTO: Content {
    let id: UUID
    let platform: String
    let appVersion: String?
    let isActive: Bool
    let lastUsedAt: Date?
    let createdAt: Date?
}

struct ProjectNotificationPreferencesDTO: Content {
    let projectId: UUID
    let userId: UUID

    struct PushSettings: Content {
        let muted: Bool
        let newFeedback: Bool?
        let newComments: Bool?
        let votes: Bool?
        let statusChanges: Bool?
    }

    struct EffectivePreferences: Content {
        struct PushEffective: Content {
            let newFeedback: Bool
            let newComments: Bool
            let votes: Bool
            let statusChanges: Bool
        }
        let push: PushEffective
    }

    let push: PushSettings
    let effectivePreferences: EffectivePreferences
}
```

---

## 7. Server Implementation

### 7.1 New Files to Create

```
SwiftlyFeedbackServer/Sources/App/
├── Models/
│   ├── DeviceToken.swift
│   ├── ProjectMemberPreference.swift
│   └── PushNotificationLog.swift
├── Migrations/
│   ├── CreateDeviceToken.swift
│   ├── CreateProjectMemberPreference.swift
│   ├── CreatePushNotificationLog.swift
│   ├── AddUserPushNotificationSettings.swift
│   └── AddVoteUserEmail.swift
├── Services/
│   └── PushNotificationService.swift
└── Controllers/
    └── DeviceController.swift
```

### 7.2 Model Implementations

#### DeviceToken.swift

```swift
import Fluent
import Vapor

final class DeviceToken: Model, Content, @unchecked Sendable {
    static let schema = "device_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token")
    var token: String

    @Field(key: "platform")
    var platform: String

    @OptionalField(key: "app_version")
    var appVersion: String?

    @OptionalField(key: "os_version")
    var osVersion: String?

    @Field(key: "is_active")
    var isActive: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "last_used_at", on: .none)
    var lastUsedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        token: String,
        platform: String,
        appVersion: String? = nil,
        osVersion: String? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.token = token
        self.platform = platform
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.isActive = true
    }
}
```

#### ProjectMemberPreference.swift

```swift
import Fluent
import Vapor

final class ProjectMemberPreference: Model, Content, @unchecked Sendable {
    static let schema = "project_member_preferences"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "project_id")
    var project: Project

    // Push notification overrides (nil = use personal preference)
    @OptionalField(key: "push_notify_new_feedback")
    var pushNotifyNewFeedback: Bool?

    @OptionalField(key: "push_notify_new_comments")
    var pushNotifyNewComments: Bool?

    @OptionalField(key: "push_notify_votes")
    var pushNotifyVotes: Bool?

    @OptionalField(key: "push_notify_status_changes")
    var pushNotifyStatusChanges: Bool?

    @Field(key: "push_muted")
    var pushMuted: Bool

    // Email notification overrides
    @OptionalField(key: "email_notify_new_feedback")
    var emailNotifyNewFeedback: Bool?

    @OptionalField(key: "email_notify_new_comments")
    var emailNotifyNewComments: Bool?

    @Field(key: "email_muted")
    var emailMuted: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: UUID, projectID: UUID) {
        self.$user.id = userID
        self.$project.id = projectID
        self.pushMuted = false
        self.emailMuted = false
    }
}
```

### 7.3 PushNotificationService

```swift
import Vapor
import APNS
import APNSCore

actor PushNotificationService {
    private let app: Application
    private let apnsClient: APNSClient<JSONDecoder, JSONEncoder>

    init(app: Application) throws {
        self.app = app

        // Configure APNs client
        let apnsConfig = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .loadFrom(filePath: Environment.get("APNS_KEY_PATH")!),
                keyIdentifier: Environment.get("APNS_KEY_ID")!,
                teamIdentifier: Environment.get("APNS_TEAM_ID")!
            ),
            environment: Environment.get("APNS_PRODUCTION") == "true" ? .production : .sandbox
        )

        self.apnsClient = APNSClient(
            configuration: apnsConfig,
            eventLoopGroupProvider: .shared(app.eventLoopGroup)
        )
    }

    // MARK: - Notification Types

    enum NotificationType: String {
        case newFeedback = "new_feedback"
        case newComment = "new_comment"
        case newVote = "new_vote"
        case statusChange = "status_change"
    }

    // MARK: - Public Methods

    func sendNewFeedbackNotification(
        feedback: Feedback,
        project: Project,
        on db: Database
    ) async throws {
        let recipients = try await resolveRecipients(
            for: project,
            notificationType: .newFeedback,
            excludeUserIds: [],
            on: db
        )

        for recipient in recipients {
            try await sendNotification(
                to: recipient,
                title: "New Feedback",
                body: feedback.title,
                payload: [
                    "type": NotificationType.newFeedback.rawValue,
                    "feedbackId": feedback.id?.uuidString ?? "",
                    "projectId": project.id?.uuidString ?? ""
                ],
                on: db
            )
        }
    }

    func sendNewCommentNotification(
        comment: Comment,
        feedback: Feedback,
        project: Project,
        authorId: UUID,
        on db: Database
    ) async throws {
        let recipients = try await resolveRecipients(
            for: project,
            notificationType: .newComment,
            excludeUserIds: [authorId],
            on: db
        )

        // Also notify feedback submitter if they're a registered user
        if let submitterEmail = feedback.userEmail,
           let submitter = try await User.query(on: db)
            .filter(\.$email == submitterEmail)
            .first(),
           submitter.id != authorId {

            let shouldNotify = try await shouldSendNotification(
                to: submitter,
                for: project,
                type: .newComment,
                on: db
            )

            if shouldNotify && !recipients.contains(where: { $0.id == submitter.id }) {
                try await sendNotification(
                    to: submitter,
                    title: "New Comment",
                    body: "Comment on: \(feedback.title)",
                    payload: [
                        "type": NotificationType.newComment.rawValue,
                        "feedbackId": feedback.id?.uuidString ?? "",
                        "commentId": comment.id?.uuidString ?? "",
                        "projectId": project.id?.uuidString ?? ""
                    ],
                    on: db
                )
            }
        }

        for recipient in recipients {
            try await sendNotification(
                to: recipient,
                title: "New Comment",
                body: "Comment on: \(feedback.title)",
                payload: [
                    "type": NotificationType.newComment.rawValue,
                    "feedbackId": feedback.id?.uuidString ?? "",
                    "commentId": comment.id?.uuidString ?? "",
                    "projectId": project.id?.uuidString ?? ""
                ],
                on: db
            )
        }
    }

    func sendVoteNotification(
        feedback: Feedback,
        voteCount: Int,
        on db: Database
    ) async throws {
        // Notify feedback submitter
        guard let submitterEmail = feedback.userEmail,
              let submitter = try await User.query(on: db)
                .filter(\.$email == submitterEmail)
                .first() else {
            return
        }

        let project = try await feedback.$project.get(on: db)

        let shouldNotify = try await shouldSendNotification(
            to: submitter,
            for: project,
            type: .newVote,
            on: db
        )

        guard shouldNotify else { return }

        try await sendNotification(
            to: submitter,
            title: "New Vote",
            body: "\(feedback.title) now has \(voteCount) vote\(voteCount == 1 ? "" : "s")",
            badge: voteCount,
            payload: [
                "type": NotificationType.newVote.rawValue,
                "feedbackId": feedback.id?.uuidString ?? "",
                "projectId": project.id?.uuidString ?? "",
                "voteCount": String(voteCount)
            ],
            on: db
        )
    }

    func sendStatusChangeNotification(
        feedback: Feedback,
        oldStatus: FeedbackStatus,
        newStatus: FeedbackStatus,
        project: Project,
        on db: Database
    ) async throws {
        var notifiedUserIds: Set<UUID> = []

        // Notify feedback submitter
        if let submitterEmail = feedback.userEmail,
           let submitter = try await User.query(on: db)
            .filter(\.$email == submitterEmail)
            .first() {

            let shouldNotify = try await shouldSendNotification(
                to: submitter,
                for: project,
                type: .statusChange,
                on: db
            )

            if shouldNotify {
                try await sendNotification(
                    to: submitter,
                    title: "Status Updated",
                    body: "\(feedback.title) is now \(newStatus.displayName)",
                    payload: [
                        "type": NotificationType.statusChange.rawValue,
                        "feedbackId": feedback.id?.uuidString ?? "",
                        "projectId": project.id?.uuidString ?? "",
                        "oldStatus": oldStatus.rawValue,
                        "newStatus": newStatus.rawValue
                    ],
                    on: db
                )
                notifiedUserIds.insert(submitter.id!)
            }
        }

        // Notify voters who provided emails
        let votes = try await Vote.query(on: db)
            .filter(\.$feedback.$id == feedback.id!)
            .all()

        for vote in votes {
            guard let voterEmail = vote.userEmail,
                  let voter = try await User.query(on: db)
                    .filter(\.$email == voterEmail)
                    .first(),
                  !notifiedUserIds.contains(voter.id!) else {
                continue
            }

            let shouldNotify = try await shouldSendNotification(
                to: voter,
                for: project,
                type: .statusChange,
                on: db
            )

            if shouldNotify {
                try await sendNotification(
                    to: voter,
                    title: "Status Updated",
                    body: "Feedback you voted on: \(newStatus.displayName)",
                    payload: [
                        "type": NotificationType.statusChange.rawValue,
                        "feedbackId": feedback.id?.uuidString ?? "",
                        "projectId": project.id?.uuidString ?? "",
                        "newStatus": newStatus.rawValue
                    ],
                    on: db
                )
                notifiedUserIds.insert(voter.id!)
            }
        }
    }

    // MARK: - Private Methods

    private func resolveRecipients(
        for project: Project,
        notificationType: NotificationType,
        excludeUserIds: [UUID],
        on db: Database
    ) async throws -> [User] {
        var recipients: [User] = []

        // Load project owner
        try await project.$owner.load(on: db)
        if !excludeUserIds.contains(project.owner.id!) {
            let shouldNotify = try await shouldSendNotification(
                to: project.owner,
                for: project,
                type: notificationType,
                on: db
            )
            if shouldNotify {
                recipients.append(project.owner)
            }
        }

        // Load project members
        let members = try await ProjectMember.query(on: db)
            .filter(\.$project.$id == project.id!)
            .with(\.$user)
            .all()

        for member in members {
            guard !excludeUserIds.contains(member.user.id!) else { continue }
            guard !recipients.contains(where: { $0.id == member.user.id }) else { continue }

            let shouldNotify = try await shouldSendNotification(
                to: member.user,
                for: project,
                type: notificationType,
                on: db
            )

            if shouldNotify {
                recipients.append(member.user)
            }
        }

        return recipients
    }

    private func shouldSendNotification(
        to user: User,
        for project: Project,
        type: NotificationType,
        on db: Database
    ) async throws -> Bool {
        // Check global toggle first
        guard user.pushNotificationsEnabled else { return false }

        // Check personal preference for this type
        let personalEnabled: Bool
        switch type {
        case .newFeedback: personalEnabled = user.pushNotifyNewFeedback
        case .newComment: personalEnabled = user.pushNotifyNewComments
        case .newVote: personalEnabled = user.pushNotifyVotes
        case .statusChange: personalEnabled = user.pushNotifyStatusChanges
        }

        // Check for project-specific override
        if let projectPrefs = try await ProjectMemberPreference.query(on: db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$project.$id == project.id!)
            .first() {

            // Project muted = no notifications
            if projectPrefs.pushMuted { return false }

            // Check type-specific override
            let override: Bool?
            switch type {
            case .newFeedback: override = projectPrefs.pushNotifyNewFeedback
            case .newComment: override = projectPrefs.pushNotifyNewComments
            case .newVote: override = projectPrefs.pushNotifyVotes
            case .statusChange: override = projectPrefs.pushNotifyStatusChanges
            }

            // Override takes precedence if set
            if let override = override {
                return override
            }
        }

        // Fall back to personal preference
        return personalEnabled
    }

    private func sendNotification(
        to user: User,
        title: String,
        body: String,
        badge: Int? = nil,
        payload: [String: String],
        on db: Database
    ) async throws {
        // Load active device tokens
        let devices = try await DeviceToken.query(on: db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$isActive == true)
            .all()

        guard !devices.isEmpty else { return }

        for device in devices {
            do {
                let notification = APNSAlertNotification(
                    alert: APNSAlertNotificationContent(
                        title: .raw(title),
                        body: .raw(body)
                    ),
                    expiration: .immediately,
                    priority: .immediately,
                    topic: Environment.get("APNS_BUNDLE_ID")!,
                    payload: payload
                )

                try await apnsClient.sendAlertNotification(
                    notification,
                    deviceToken: device.token
                )

                // Update last used timestamp
                device.lastUsedAt = Date()
                try await device.save(on: db)

                // Log success
                try await logNotification(
                    userId: user.id!,
                    deviceTokenId: device.id,
                    type: payload["type"] ?? "unknown",
                    status: "sent",
                    payload: payload,
                    on: db
                )

            } catch let error as APNSError {
                // Handle token expiry
                if case .badRequest(let reason) = error,
                   reason == .badDeviceToken || reason == .unregistered {
                    device.isActive = false
                    try await device.save(on: db)

                    try await logNotification(
                        userId: user.id!,
                        deviceTokenId: device.id,
                        type: payload["type"] ?? "unknown",
                        status: "token_expired",
                        payload: payload,
                        errorMessage: error.localizedDescription,
                        on: db
                    )
                } else {
                    try await logNotification(
                        userId: user.id!,
                        deviceTokenId: device.id,
                        type: payload["type"] ?? "unknown",
                        status: "failed",
                        payload: payload,
                        errorMessage: error.localizedDescription,
                        on: db
                    )
                }
            }
        }
    }

    private func logNotification(
        userId: UUID,
        deviceTokenId: UUID?,
        type: String,
        status: String,
        payload: [String: String],
        errorMessage: String? = nil,
        on db: Database
    ) async throws {
        let log = PushNotificationLog(
            userId: userId,
            deviceTokenId: deviceTokenId,
            type: type,
            status: status,
            payload: payload,
            errorMessage: errorMessage
        )
        try await log.save(on: db)
    }
}

// MARK: - Request Extension

extension Request {
    var pushNotificationService: PushNotificationService {
        get async throws {
            try await PushNotificationService(app: application)
        }
    }
}
```

### 7.4 Controller Updates

#### FeedbackController Updates

Add after existing email notification dispatch (~line 210):

```swift
// Push notification dispatch
Task {
    do {
        let pushService = try await req.pushNotificationService
        try await pushService.sendNewFeedbackNotification(
            feedback: feedback,
            project: project,
            on: req.db
        )
    } catch {
        req.logger.error("Failed to send push notification: \(error)")
    }
}
```

#### CommentController Updates

Add after existing email notification dispatch (~line 117):

```swift
// Push notification dispatch
Task {
    do {
        let pushService = try await req.pushNotificationService
        try await pushService.sendNewCommentNotification(
            comment: comment,
            feedback: feedback,
            project: project,
            authorId: req.auth.require(User.self).id!,
            on: req.db
        )
    } catch {
        req.logger.error("Failed to send push notification: \(error)")
    }
}
```

#### VoteController Updates (New)

Add after vote save (~line 53):

```swift
// Push notification dispatch
Task {
    do {
        let pushService = try await req.pushNotificationService
        try await pushService.sendVoteNotification(
            feedback: feedback,
            voteCount: feedback.voteCount,
            on: req.db
        )
    } catch {
        req.logger.error("Failed to send vote notification: \(error)")
    }
}
```

---

## 8. Admin App Implementation

### 8.1 New Files to Create

```
SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/
├── Services/
│   └── PushNotificationManager.swift
├── Views/Settings/
│   └── PushNotificationSettingsView.swift
└── Views/Projects/
    └── ProjectNotificationSettingsView.swift
```

### 8.2 PushNotificationManager

```swift
import Foundation
import UserNotifications
import UIKit

@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private(set) var isAuthorized = false
    private(set) var deviceToken: String?

    private init() {}

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            isAuthorized = granted

            if granted {
                await registerForRemoteNotifications()
            }

            return granted
        } catch {
            print("Failed to request notification authorization: \(error)")
            return false
        }
    }

    func registerForRemoteNotifications() async {
        await MainActor.run {
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token

        Task {
            await registerTokenWithServer(token)
        }
    }

    func handleRegistrationError(_ error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    private func registerTokenWithServer(_ token: String) async {
        guard AuthService.shared.isAuthenticated else { return }

        do {
            let platform: String
            #if os(iOS)
            platform = "iOS"
            #elseif os(macOS)
            platform = "macOS"
            #endif

            _ = try await AdminAPIClient.shared.registerDevice(
                token: token,
                platform: platform,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString
            )
        } catch {
            print("Failed to register device token: \(error)")
        }
    }

    func unregisterDevice() async {
        guard let token = deviceToken else { return }

        do {
            try await AdminAPIClient.shared.unregisterDevice(token: token)
            self.deviceToken = nil
        } catch {
            print("Failed to unregister device: \(error)")
        }
    }
}
```

### 8.3 App Entry Point Updates

```swift
// SwiftlyFeedbackAdminApp.swift

@main
struct SwiftlyFeedbackAdminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // ... existing code ...
}

// AppDelegate.swift (iOS)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationError(error)
        }
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String,
           let feedbackId = userInfo["feedbackId"] as? String {

            // Build deep link URL
            let url = URL(string: "feedbackkit://feedback/\(feedbackId)")!
            Task { @MainActor in
                DeepLinkManager.shared.handleURL(url)
            }
        }

        completionHandler()
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
```

### 8.4 Settings View Updates

```swift
// PushNotificationSettingsView.swift

import SwiftUI

struct PushNotificationSettingsView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var showingSystemSettings = false

    private var pushManager: PushNotificationManager { .shared }

    var body: some View {
        Form {
            Section {
                masterToggle

                if authViewModel.currentUser?.pushNotificationsEnabled == true {
                    notificationTypeToggles
                }
            } header: {
                Text("Push Notifications")
            } footer: {
                Text("Receive notifications on this device when activity occurs in your projects.")
            }

            if !pushManager.isAuthorized {
                Section {
                    systemSettingsButton
                } footer: {
                    Text("Push notifications are disabled in system settings.")
                }
            }
        }
        .navigationTitle("Push Notifications")
    }

    @ViewBuilder
    private var masterToggle: some View {
        Toggle(isOn: Binding(
            get: { authViewModel.currentUser?.pushNotificationsEnabled ?? true },
            set: { newValue in
                Task {
                    await authViewModel.updateNotificationSettings(
                        pushNotificationsEnabled: newValue
                    )
                }
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Push Notifications")
                    Text("Master toggle for all push notifications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.purple)
            }
        }
    }

    @ViewBuilder
    private var notificationTypeToggles: some View {
        Group {
            Toggle("New Feedback", isOn: Binding(
                get: { authViewModel.currentUser?.pushNotifyNewFeedback ?? true },
                set: { newValue in
                    Task {
                        await authViewModel.updateNotificationSettings(
                            pushNotifyNewFeedback: newValue
                        )
                    }
                }
            ))

            Toggle("New Comments", isOn: Binding(
                get: { authViewModel.currentUser?.pushNotifyNewComments ?? true },
                set: { newValue in
                    Task {
                        await authViewModel.updateNotificationSettings(
                            pushNotifyNewComments: newValue
                        )
                    }
                }
            ))

            Toggle("New Votes", isOn: Binding(
                get: { authViewModel.currentUser?.pushNotifyVotes ?? true },
                set: { newValue in
                    Task {
                        await authViewModel.updateNotificationSettings(
                            pushNotifyVotes: newValue
                        )
                    }
                }
            ))

            Toggle("Status Changes", isOn: Binding(
                get: { authViewModel.currentUser?.pushNotifyStatusChanges ?? true },
                set: { newValue in
                    Task {
                        await authViewModel.updateNotificationSettings(
                            pushNotifyStatusChanges: newValue
                        )
                    }
                }
            ))
        }
        .padding(.leading, 20)
    }

    @ViewBuilder
    private var systemSettingsButton: some View {
        Button {
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            Label("Open System Settings", systemImage: "gear")
        }
    }
}
```

### 8.5 Project-Specific Settings View

```swift
// ProjectNotificationSettingsView.swift

import SwiftUI

struct ProjectNotificationSettingsView: View {
    let project: Project
    @Bindable var projectViewModel: ProjectViewModel

    @State private var preferences: ProjectNotificationPreferences?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Form {
            if isLoading {
                ProgressView()
            } else if let prefs = preferences {
                pushNotificationsSection(prefs)
                emailNotificationsSection(prefs)
            }
        }
        .navigationTitle("Notifications")
        .task {
            await loadPreferences()
        }
    }

    @ViewBuilder
    private func pushNotificationsSection(_ prefs: ProjectNotificationPreferences) -> some View {
        Section {
            Toggle("Mute All Push Notifications", isOn: Binding(
                get: { prefs.push.muted },
                set: { newValue in
                    Task {
                        await updatePreferences(pushMuted: newValue)
                    }
                }
            ))

            if !prefs.push.muted {
                preferenceToggle(
                    title: "New Feedback",
                    value: prefs.push.newFeedback,
                    effectiveValue: prefs.effectivePreferences.push.newFeedback,
                    onChange: { newValue in
                        await updatePreferences(pushNewFeedback: newValue)
                    }
                )

                preferenceToggle(
                    title: "New Comments",
                    value: prefs.push.newComments,
                    effectiveValue: prefs.effectivePreferences.push.newComments,
                    onChange: { newValue in
                        await updatePreferences(pushNewComments: newValue)
                    }
                )

                preferenceToggle(
                    title: "New Votes",
                    value: prefs.push.votes,
                    effectiveValue: prefs.effectivePreferences.push.votes,
                    onChange: { newValue in
                        await updatePreferences(pushVotes: newValue)
                    }
                )

                preferenceToggle(
                    title: "Status Changes",
                    value: prefs.push.statusChanges,
                    effectiveValue: prefs.effectivePreferences.push.statusChanges,
                    onChange: { newValue in
                        await updatePreferences(pushStatusChanges: newValue)
                    }
                )
            }
        } header: {
            Text("Push Notifications")
        } footer: {
            Text("Override your personal notification preferences for this project. Switches show the effective setting.")
        }
    }

    @ViewBuilder
    private func preferenceToggle(
        title: String,
        value: Bool?,
        effectiveValue: Bool,
        onChange: @escaping (Bool?) async -> Void
    ) -> some View {
        HStack {
            Text(title)

            Spacer()

            // Show override indicator
            if value != nil {
                Text("Override")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: Capsule())
            }

            Toggle("", isOn: Binding(
                get: { effectiveValue },
                set: { newValue in
                    Task {
                        await onChange(newValue)
                    }
                }
            ))
            .labelsHidden()
        }
        .swipeActions(edge: .trailing) {
            if value != nil {
                Button("Reset") {
                    Task {
                        await onChange(nil)
                    }
                }
                .tint(.gray)
            }
        }
    }

    private func loadPreferences() async {
        isLoading = true
        do {
            preferences = try await AdminAPIClient.shared.getProjectNotificationPreferences(
                projectId: project.id
            )
        } catch {
            self.error = error
        }
        isLoading = false
    }

    private func updatePreferences(
        pushMuted: Bool? = nil,
        pushNewFeedback: Bool?? = nil,
        pushNewComments: Bool?? = nil,
        pushVotes: Bool?? = nil,
        pushStatusChanges: Bool?? = nil
    ) async {
        do {
            preferences = try await AdminAPIClient.shared.updateProjectNotificationPreferences(
                projectId: project.id,
                pushMuted: pushMuted,
                pushNewFeedback: pushNewFeedback,
                pushNewComments: pushNewComments,
                pushVotes: pushVotes,
                pushStatusChanges: pushStatusChanges
            )
        } catch {
            self.error = error
        }
    }
}
```

---

## 9. Deep Linking

### 9.1 New URL Schemes

Add to existing `feedbackkit://` scheme:

| URL | Action |
|-----|--------|
| `feedbackkit://feedback/{id}` | Open feedback detail |
| `feedbackkit://feedback/{id}/comments` | Open feedback detail, scroll to comments |
| `feedbackkit://project/{id}` | Open project feedback list |
| `feedbackkit://settings/notifications` | Open notification settings (existing) |
| `feedbackkit://settings/notifications/push` | Open push notification settings |

### 9.2 DeepLinkManager Updates

```swift
// Add to DeepLinkManager.swift

enum DeepLinkDestination: Equatable {
    case settings
    case settingsNotifications
    case settingsNotificationsPush
    case feedback(id: UUID)
    case feedbackComments(feedbackId: UUID)
    case project(id: UUID)
}

extension DeepLinkManager {
    func parseURL(_ url: URL) -> DeepLinkDestination? {
        guard url.scheme == "feedbackkit" else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch url.host {
        case "settings":
            if pathComponents.contains("notifications") {
                if pathComponents.contains("push") {
                    return .settingsNotificationsPush
                }
                return .settingsNotifications
            }
            return .settings

        case "feedback":
            guard let idString = pathComponents.first,
                  let id = UUID(uuidString: idString) else {
                return nil
            }
            if pathComponents.contains("comments") {
                return .feedbackComments(feedbackId: id)
            }
            return .feedback(id: id)

        case "project":
            guard let idString = pathComponents.first,
                  let id = UUID(uuidString: idString) else {
                return nil
            }
            return .project(id: id)

        default:
            return nil
        }
    }
}
```

### 9.3 Notification Payload Format

```json
{
    "aps": {
        "alert": {
            "title": "New Feedback",
            "body": "Feature request: Dark mode support"
        },
        "badge": 1,
        "sound": "default",
        "mutable-content": 1
    },
    "type": "new_feedback",
    "feedbackId": "550e8400-e29b-41d4-a716-446655440000",
    "projectId": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "actionUrl": "feedbackkit://feedback/550e8400-e29b-41d4-a716-446655440000"
}
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

#### Server Tests

```swift
// Tests/AppTests/PushNotificationTests.swift

@Test func testShouldSendNotification_personalEnabled() async throws {
    // Setup user with notifications enabled
    let user = User(email: "test@example.com", name: "Test")
    user.pushNotificationsEnabled = true
    user.pushNotifyNewFeedback = true

    // No project override
    let result = try await pushService.shouldSendNotification(
        to: user,
        for: project,
        type: .newFeedback,
        on: db
    )

    #expect(result == true)
}

@Test func testShouldSendNotification_projectMuted() async throws {
    // Setup user with notifications enabled
    let user = User(email: "test@example.com", name: "Test")
    user.pushNotificationsEnabled = true
    user.pushNotifyNewFeedback = true

    // Project is muted
    let prefs = ProjectMemberPreference(userID: user.id!, projectID: project.id!)
    prefs.pushMuted = true
    try await prefs.save(on: db)

    let result = try await pushService.shouldSendNotification(
        to: user,
        for: project,
        type: .newFeedback,
        on: db
    )

    #expect(result == false)
}

@Test func testShouldSendNotification_projectOverride() async throws {
    // User has notifications disabled for feedback
    let user = User(email: "test@example.com", name: "Test")
    user.pushNotificationsEnabled = true
    user.pushNotifyNewFeedback = false

    // But project override enables it
    let prefs = ProjectMemberPreference(userID: user.id!, projectID: project.id!)
    prefs.pushNotifyNewFeedback = true
    try await prefs.save(on: db)

    let result = try await pushService.shouldSendNotification(
        to: user,
        for: project,
        type: .newFeedback,
        on: db
    )

    #expect(result == true)
}
```

#### Admin App Tests

```swift
// SwiftlyFeedbackAdminTests/PushNotificationTests.swift

@Test func testDeviceTokenRegistration() async throws {
    let tokenData = Data([0x01, 0x02, 0x03, 0x04])
    let expectedToken = "01020304"

    await PushNotificationManager.shared.handleDeviceToken(tokenData)

    #expect(PushNotificationManager.shared.deviceToken == expectedToken)
}

@Test func testDeepLinkParsing_feedback() {
    let url = URL(string: "feedbackkit://feedback/550e8400-e29b-41d4-a716-446655440000")!
    let destination = DeepLinkManager.shared.parseURL(url)

    #expect(destination == .feedback(id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!))
}
```

### 10.2 Integration Tests

| Scenario | Steps | Expected Result |
|----------|-------|-----------------|
| New feedback triggers push | 1. Create feedback via SDK<br>2. Check project owner's device | Push notification received |
| Muted project no notification | 1. Mute project notifications<br>2. Create feedback | No push notification |
| Project override works | 1. Disable personal preference<br>2. Enable project override<br>3. Create feedback | Push notification received |
| Token expiry handling | 1. Register device<br>2. Invalidate token in APNs<br>3. Send notification | Token marked inactive, no crash |

### 10.3 Manual Testing Checklist

- [ ] Register device token on iOS
- [ ] Register device token on macOS
- [ ] Receive push when new feedback created
- [ ] Receive push when comment added
- [ ] Receive push when vote cast
- [ ] Receive push when status changes
- [ ] Tap notification navigates to correct feedback
- [ ] Toggle personal preferences works
- [ ] Toggle project preferences works
- [ ] Mute project stops all notifications
- [ ] Uninstall/reinstall handles token correctly
- [ ] Multiple devices receive notifications
- [ ] Badge count updates correctly

---

## 11. Migration Plan

### 11.1 Migration Order

Run migrations in this order:

1. `CreateDeviceToken` - New table
2. `CreateProjectMemberPreference` - New table
3. `CreatePushNotificationLog` - New table (monitoring)
4. `AddUserPushNotificationSettings` - Add columns to users
5. `AddVoteUserEmail` - Add column to votes

### 11.2 Migration Scripts

```swift
// 1. CreateDeviceToken.swift
struct CreateDeviceToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("device_tokens")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token", .string, .required)
            .field("platform", .string, .required)
            .field("app_version", .string)
            .field("os_version", .string)
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("created_at", .datetime)
            .field("last_used_at", .datetime)
            .unique(on: "token")
            .create()

        try await database.schema("device_tokens")
            .index(on: "user_id")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("device_tokens").delete()
    }
}

// 4. AddUserPushNotificationSettings.swift
struct AddUserPushNotificationSettings: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("push_notifications_enabled", .bool, .required, .sql(.default(true)))
            .field("push_notify_new_feedback", .bool, .required, .sql(.default(true)))
            .field("push_notify_new_comments", .bool, .required, .sql(.default(true)))
            .field("push_notify_votes", .bool, .required, .sql(.default(true)))
            .field("push_notify_status_changes", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("push_notifications_enabled")
            .deleteField("push_notify_new_feedback")
            .deleteField("push_notify_new_comments")
            .deleteField("push_notify_votes")
            .deleteField("push_notify_status_changes")
            .update()
    }
}

// 5. AddVoteUserEmail.swift
struct AddVoteUserEmail: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("votes")
            .field("user_email", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("votes")
            .deleteField("user_email")
            .update()
    }
}
```

### 11.3 Backward Compatibility

- All new user fields default to `true` (opt-out model)
- Existing users automatically have push enabled after migration
- No changes to existing email notification behavior
- Project preferences are optional (only created when user customizes)

---

## 12. Dependencies

### 12.1 Server Dependencies

Add to `Package.swift`:

```swift
dependencies: [
    // Existing dependencies...
    .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "5.0.0"),
],
targets: [
    .target(
        name: "App",
        dependencies: [
            // Existing dependencies...
            .product(name: "APNSwift", package: "APNSwift"),
        ]
    ),
]
```

### 12.2 Environment Variables

```bash
# APNs Configuration
APNS_KEY_ID=XXXXXXXXXX           # Key ID from Apple Developer Portal
APNS_TEAM_ID=XXXXXXXXXX          # Team ID from Apple Developer Portal
APNS_BUNDLE_ID=com.swiftly-developed.feedbackkit.admin
APNS_KEY_PATH=/path/to/AuthKey_XXXXXXXX.p8
APNS_PRODUCTION=false            # true for production, false for sandbox
```

### 12.3 Apple Developer Setup

1. Create APNs Key in Apple Developer Portal
2. Download `.p8` file
3. Enable Push Notifications capability in Xcode
4. Add `aps-environment` entitlement

---

## 13. File Reference

### 13.1 Server Files

| File | Purpose |
|------|---------|
| `Models/DeviceToken.swift` | Device token storage model |
| `Models/ProjectMemberPreference.swift` | Per-project notification overrides |
| `Models/PushNotificationLog.swift` | Notification delivery logging |
| `Services/PushNotificationService.swift` | Core notification dispatch logic |
| `Controllers/DeviceController.swift` | Device registration endpoints |
| `Migrations/CreateDeviceToken.swift` | Database migration |
| `Migrations/CreateProjectMemberPreference.swift` | Database migration |
| `Migrations/AddUserPushNotificationSettings.swift` | User model migration |
| `Migrations/AddVoteUserEmail.swift` | Vote model migration |

### 13.2 Admin App Files

| File | Purpose |
|------|---------|
| `Services/PushNotificationManager.swift` | Device registration, token handling |
| `Views/Settings/PushNotificationSettingsView.swift` | Personal push preferences UI |
| `Views/Projects/ProjectNotificationSettingsView.swift` | Project-specific preferences UI |
| `AppDelegate.swift` | APNs delegate methods |

### 13.3 Files to Modify

| File | Changes |
|------|---------|
| `SwiftlyFeedbackServer/Sources/App/Models/User.swift` | Add push preference fields |
| `SwiftlyFeedbackServer/Sources/App/Models/Vote.swift` | Add userEmail field |
| `SwiftlyFeedbackServer/Sources/App/Controllers/FeedbackController.swift` | Add push dispatch |
| `SwiftlyFeedbackServer/Sources/App/Controllers/CommentController.swift` | Add push dispatch |
| `SwiftlyFeedbackServer/Sources/App/Controllers/VoteController.swift` | Add push dispatch |
| `SwiftlyFeedbackServer/Sources/App/Controllers/AuthController.swift` | Add push settings endpoint |
| `SwiftlyFeedbackServer/Sources/App/routes.swift` | Register new routes |
| `SwiftlyFeedbackServer/Sources/App/configure.swift` | Register migrations, configure APNs |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Settings/SettingsView.swift` | Add push settings link |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/DeepLinkManager.swift` | Add new URL schemes |
| `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/AdminAPIClient.swift` | Add device & preference endpoints |

---

## Appendix A: Notification Message Templates

| Type | Title | Body |
|------|-------|------|
| New Feedback | "New Feedback" | `{feedback.title}` |
| New Comment | "New Comment" | "Comment on: {feedback.title}" |
| New Vote | "New Vote" | "{feedback.title} now has {count} vote(s)" |
| Status Change | "Status Updated" | "{feedback.title} is now {status}" |

## Appendix B: Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| `BadDeviceToken` | Token invalid or expired | Mark token inactive |
| `Unregistered` | App uninstalled | Mark token inactive |
| `PayloadTooLarge` | Payload > 4KB | Truncate body |
| `TooManyRequests` | Rate limited | Implement backoff |

---

*Document Version: 1.0*
*Last Updated: January 2026*
