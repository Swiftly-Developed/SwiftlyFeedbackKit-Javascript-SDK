# Asana Integration - Technical Implementation Plan

This document provides a detailed technical plan for implementing Asana integration in FeedbackKit, following the established patterns used for Monday.com, ClickUp, Linear, and GitHub integrations.

## Table of Contents

1. [Overview](#overview)
2. [Asana API Reference](#asana-api-reference)
3. [Data Model Changes](#data-model-changes)
4. [Server Implementation](#server-implementation)
5. [Admin App Implementation](#admin-app-implementation)
6. [Status Mapping](#status-mapping)
7. [Implementation Checklist](#implementation-checklist)

---

## Overview

### Integration Features

| Feature | Support |
|---------|---------|
| Create Task | Yes |
| Bulk Create Tasks | Yes |
| Status Sync | Yes (via custom field enum) |
| Comment Sync | Yes (via Stories API) |
| Link Tracking | Yes |
| Active Toggle | Yes |
| Votes Sync | Yes (via custom field) |

### Asana Hierarchy

```
Workspace
  └── Project
        └── Section (optional)
              └── Task
```

Users will select:
1. **Workspace** - Organization or personal workspace
2. **Project** - Target project for tasks
3. **Section** (optional) - Specific section within the project
4. **Status Custom Field** (optional) - For status sync
5. **Votes Custom Field** (optional) - For vote count sync

---

## Asana API Reference

### Base URL
```
https://app.asana.com/api/1.0
```

### Authentication

**Personal Access Token (PAT)**
- Generated in [Asana Developer Console](https://app.asana.com/0/my-apps)
- Header format: `Authorization: Bearer ACCESS_TOKEN`
- Treat as opaque string (format may change)

### Rate Limits

| Domain Type | Requests/Minute |
|-------------|-----------------|
| Free | 150 |
| Paid | 1,500 |

**Concurrent Limits:**
- GET: 50 concurrent
- POST/PUT/PATCH/DELETE: 15 concurrent

**Rate Limit Response:**
- Status: `429 Too Many Requests`
- Header: `Retry-After` (seconds to wait)

### Key Endpoints

#### Get Workspaces
```http
GET /workspaces
Authorization: Bearer {token}

Response:
{
  "data": [
    {
      "gid": "12345",
      "name": "My Workspace",
      "resource_type": "workspace"
    }
  ]
}
```

#### Get Projects for Workspace
```http
GET /workspaces/{workspace_gid}/projects
Authorization: Bearer {token}

Response:
{
  "data": [
    {
      "gid": "67890",
      "name": "Product Feedback",
      "resource_type": "project"
    }
  ]
}
```

#### Get Sections for Project
```http
GET /projects/{project_gid}/sections
Authorization: Bearer {token}

Response:
{
  "data": [
    {
      "gid": "11111",
      "name": "Backlog",
      "resource_type": "section"
    }
  ]
}
```

#### Get Custom Field Settings for Project
```http
GET /projects/{project_gid}/custom_field_settings
Authorization: Bearer {token}

Response:
{
  "data": [
    {
      "gid": "22222",
      "custom_field": {
        "gid": "33333",
        "name": "Status",
        "resource_type": "custom_field",
        "type": "enum",
        "enum_options": [
          {
            "gid": "44444",
            "name": "To Do",
            "enabled": true,
            "color": "blue"
          },
          {
            "gid": "44445",
            "name": "In Progress",
            "enabled": true,
            "color": "yellow"
          }
        ]
      }
    }
  ]
}
```

#### Create Task
```http
POST /tasks
Authorization: Bearer {token}
Content-Type: application/json

{
  "data": {
    "name": "Task Title",
    "notes": "Task description with markdown support",
    "projects": ["67890"],
    "memberships": [
      {
        "project": "67890",
        "section": "11111"
      }
    ],
    "custom_fields": {
      "33333": "44444"  // enum custom field: option gid
    }
  }
}

Response:
{
  "data": {
    "gid": "99999",
    "name": "Task Title",
    "permalink_url": "https://app.asana.com/0/67890/99999",
    "resource_type": "task"
  }
}
```

#### Update Task
```http
PUT /tasks/{task_gid}
Authorization: Bearer {token}
Content-Type: application/json

{
  "data": {
    "custom_fields": {
      "33333": "44445"  // Update enum to different option
    }
  }
}
```

#### Create Story (Comment)
```http
POST /tasks/{task_gid}/stories
Authorization: Bearer {token}
Content-Type: application/json

{
  "data": {
    "text": "Comment text here"
  }
}

Response:
{
  "data": {
    "gid": "88888",
    "resource_type": "story",
    "type": "comment"
  }
}
```

### Custom Fields

Custom fields are a **premium feature** in Asana. The integration should handle cases where:
- Workspace doesn't have custom fields enabled
- Project doesn't have status/votes custom fields configured

**Custom Field Types:**
| Type | Value Format |
|------|--------------|
| text | `"text_value": "string"` |
| number | `"number_value": 123` |
| enum | `"enum_value": {"gid": "option_gid"}` or just `"field_gid": "option_gid"` |
| multi_enum | `"multi_enum_values": [{"gid": "..."}]` |
| date | `"date_value": {"date": "2025-01-15"}` |
| people | `"people_value": [{"gid": "user_gid"}]` |

---

## Data Model Changes

### Project Model Fields

Add to `SwiftlyFeedbackServer/Sources/App/Models/Project.swift`:

```swift
// Asana integration fields
@OptionalField(key: "asana_token")
var asanaToken: String?

@OptionalField(key: "asana_workspace_id")
var asanaWorkspaceId: String?

@OptionalField(key: "asana_workspace_name")
var asanaWorkspaceName: String?

@OptionalField(key: "asana_project_id")
var asanaProjectId: String?

@OptionalField(key: "asana_project_name")
var asanaProjectName: String?

@OptionalField(key: "asana_section_id")
var asanaSectionId: String?

@OptionalField(key: "asana_section_name")
var asanaSectionName: String?

@Field(key: "asana_sync_status")
var asanaSyncStatus: Bool

@Field(key: "asana_sync_comments")
var asanaSyncComments: Bool

@OptionalField(key: "asana_status_field_id")
var asanaStatusFieldId: String?

@OptionalField(key: "asana_votes_field_id")
var asanaVotesFieldId: String?

@Field(key: "asana_is_active")
var asanaIsActive: Bool
```

**Field Purposes:**
| Field | Purpose |
|-------|---------|
| `asanaToken` | Personal Access Token for API auth |
| `asanaWorkspaceId` | Selected workspace GID |
| `asanaWorkspaceName` | Display name for UI |
| `asanaProjectId` | Target project GID |
| `asanaProjectName` | Display name for UI |
| `asanaSectionId` | Optional section GID |
| `asanaSectionName` | Display name for UI |
| `asanaSyncStatus` | Enable status synchronization |
| `asanaSyncComments` | Enable comment synchronization |
| `asanaStatusFieldId` | Enum custom field GID for status |
| `asanaVotesFieldId` | Number custom field GID for votes |
| `asanaIsActive` | Pause/resume integration |

### Feedback Model Fields

Add to `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`:

```swift
// Asana integration fields
@OptionalField(key: "asana_task_url")
var asanaTaskURL: String?

@OptionalField(key: "asana_task_id")
var asanaTaskId: String?
```

Add helper property:

```swift
/// Whether this feedback has a linked Asana task
var hasAsanaTask: Bool {
    asanaTaskURL != nil
}
```

### Database Migration

Create `SwiftlyFeedbackServer/Sources/App/Migrations/AddProjectAsanaIntegration.swift`:

```swift
import Fluent

struct AddProjectAsanaIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Asana fields to projects table
        try await database.schema("projects")
            .field("asana_token", .string)
            .field("asana_workspace_id", .string)
            .field("asana_workspace_name", .string)
            .field("asana_project_id", .string)
            .field("asana_project_name", .string)
            .field("asana_section_id", .string)
            .field("asana_section_name", .string)
            .field("asana_sync_status", .bool, .required, .sql(.default(false)))
            .field("asana_sync_comments", .bool, .required, .sql(.default(false)))
            .field("asana_status_field_id", .string)
            .field("asana_votes_field_id", .string)
            .field("asana_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Add Asana fields to feedbacks table
        try await database.schema("feedbacks")
            .field("asana_task_url", .string)
            .field("asana_task_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("asana_token")
            .deleteField("asana_workspace_id")
            .deleteField("asana_workspace_name")
            .deleteField("asana_project_id")
            .deleteField("asana_project_name")
            .deleteField("asana_section_id")
            .deleteField("asana_section_name")
            .deleteField("asana_sync_status")
            .deleteField("asana_sync_comments")
            .deleteField("asana_status_field_id")
            .deleteField("asana_votes_field_id")
            .deleteField("asana_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("asana_task_url")
            .deleteField("asana_task_id")
            .update()
    }
}
```

Register in `configure.swift`:
```swift
app.migrations.add(AddProjectAsanaIntegration())
```

---

## Server Implementation

### DTOs

Add to `SwiftlyFeedbackServer/Sources/App/DTOs/ProjectDTO.swift`:

```swift
// MARK: - Asana DTOs

struct UpdateProjectAsanaDTO: Content {
    var asanaToken: String?
    var asanaWorkspaceId: String?
    var asanaWorkspaceName: String?
    var asanaProjectId: String?
    var asanaProjectName: String?
    var asanaSectionId: String?
    var asanaSectionName: String?
    var asanaSyncStatus: Bool?
    var asanaSyncComments: Bool?
    var asanaStatusFieldId: String?
    var asanaVotesFieldId: String?
    var asanaIsActive: Bool?
}

struct CreateAsanaTaskDTO: Content {
    var feedbackId: UUID
}

struct CreateAsanaTaskResponseDTO: Content {
    var feedbackId: UUID
    var taskUrl: String
    var taskId: String
}

struct BulkCreateAsanaTasksDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateAsanaTasksResponseDTO: Content {
    var created: [CreateAsanaTaskResponseDTO]
    var failed: [UUID]
}

// Discovery DTOs
struct AsanaWorkspaceDTO: Content, Identifiable {
    var id: String { gid }
    var gid: String
    var name: String
}

struct AsanaProjectDTO: Content, Identifiable {
    var id: String { gid }
    var gid: String
    var name: String
}

struct AsanaSectionDTO: Content, Identifiable {
    var id: String { gid }
    var gid: String
    var name: String
}

struct AsanaCustomFieldDTO: Content, Identifiable {
    var id: String { gid }
    var gid: String
    var name: String
    var type: String
    var enumOptions: [AsanaEnumOptionDTO]?
}

struct AsanaEnumOptionDTO: Content, Identifiable {
    var id: String { gid }
    var gid: String
    var name: String
    var enabled: Bool
    var color: String?
}
```

### Service Implementation

Create `SwiftlyFeedbackServer/Sources/App/Services/AsanaService.swift`:

```swift
import Vapor

struct AsanaService {
    private let client: Client
    private let baseURL = "https://app.asana.com/api/1.0"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct AsanaWorkspace: Codable {
        let gid: String
        let name: String
    }

    struct AsanaProject: Codable {
        let gid: String
        let name: String
    }

    struct AsanaSection: Codable {
        let gid: String
        let name: String
    }

    struct AsanaCustomField: Codable {
        let gid: String
        let name: String
        let type: String
        let enumOptions: [AsanaEnumOption]?

        enum CodingKeys: String, CodingKey {
            case gid, name, type
            case enumOptions = "enum_options"
        }
    }

    struct AsanaEnumOption: Codable {
        let gid: String
        let name: String
        let enabled: Bool
        let color: String?
    }

    struct AsanaCustomFieldSetting: Codable {
        let gid: String
        let customField: AsanaCustomField

        enum CodingKeys: String, CodingKey {
            case gid
            case customField = "custom_field"
        }
    }

    struct AsanaTask: Codable {
        let gid: String
        let name: String
        let permalinkUrl: String?

        enum CodingKeys: String, CodingKey {
            case gid, name
            case permalinkUrl = "permalink_url"
        }
    }

    struct AsanaStory: Codable {
        let gid: String
        let type: String?
    }

    private struct AsanaResponse<T: Codable>: Codable {
        let data: T
    }

    private struct AsanaListResponse<T: Codable>: Codable {
        let data: [T]
    }

    private struct AsanaErrorResponse: Codable {
        let errors: [AsanaError]?

        struct AsanaError: Codable {
            let message: String
            let help: String?
        }
    }

    // MARK: - HTTP Helper

    private func request<T: Codable>(
        method: HTTPMethod,
        path: String,
        token: String,
        body: [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        let uri = URI(string: "\(baseURL)\(path)")

        let response: ClientResponse
        switch method {
        case .GET:
            response = try await client.get(uri) { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
                req.headers.add(name: .accept, value: "application/json")
            }
        case .POST:
            response = try await client.post(uri) { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
                req.headers.add(name: .contentType, value: "application/json")
                req.headers.add(name: .accept, value: "application/json")
                if let body = body {
                    let jsonData = try JSONSerialization.data(withJSONObject: ["data": body])
                    req.body = ByteBuffer(data: jsonData)
                }
            }
        case .PUT:
            response = try await client.put(uri) { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
                req.headers.add(name: .contentType, value: "application/json")
                req.headers.add(name: .accept, value: "application/json")
                if let body = body {
                    let jsonData = try JSONSerialization.data(withJSONObject: ["data": body])
                    req.body = ByteBuffer(data: jsonData)
                }
            }
        default:
            throw Abort(.badRequest, reason: "Unsupported HTTP method")
        }

        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Asana API returned empty response")
        }
        let data = Data(buffer: bodyData)

        // Check for errors
        if response.status != .ok && response.status != .created {
            if let errorResponse = try? JSONDecoder().decode(AsanaErrorResponse.self, from: data),
               let error = errorResponse.errors?.first {
                throw Abort(.badGateway, reason: "Asana API error: \(error.message)")
            }
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Asana API error (\(response.status)): \(responseBody)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "decode failed"
            throw Abort(.badGateway, reason: "Failed to decode Asana response: \(error.localizedDescription). Body: \(responseBody)")
        }
    }

    // MARK: - Workspaces

    func getWorkspaces(token: String) async throws -> [AsanaWorkspace] {
        let response: AsanaListResponse<AsanaWorkspace> = try await request(
            method: .GET,
            path: "/workspaces",
            token: token,
            responseType: AsanaListResponse<AsanaWorkspace>.self
        )
        return response.data
    }

    // MARK: - Projects

    func getProjects(workspaceId: String, token: String) async throws -> [AsanaProject] {
        let response: AsanaListResponse<AsanaProject> = try await request(
            method: .GET,
            path: "/workspaces/\(workspaceId)/projects",
            token: token,
            responseType: AsanaListResponse<AsanaProject>.self
        )
        return response.data
    }

    // MARK: - Sections

    func getSections(projectId: String, token: String) async throws -> [AsanaSection] {
        let response: AsanaListResponse<AsanaSection> = try await request(
            method: .GET,
            path: "/projects/\(projectId)/sections",
            token: token,
            responseType: AsanaListResponse<AsanaSection>.self
        )
        return response.data
    }

    // MARK: - Custom Fields

    func getCustomFields(projectId: String, token: String) async throws -> [AsanaCustomField] {
        let response: AsanaListResponse<AsanaCustomFieldSetting> = try await request(
            method: .GET,
            path: "/projects/\(projectId)/custom_field_settings",
            token: token,
            responseType: AsanaListResponse<AsanaCustomFieldSetting>.self
        )
        return response.data.map { $0.customField }
    }

    // MARK: - Task Creation

    func createTask(
        projectId: String,
        sectionId: String?,
        token: String,
        name: String,
        notes: String,
        customFields: [String: Any]? = nil
    ) async throws -> AsanaTask {
        var body: [String: Any] = [
            "name": name,
            "notes": notes,
            "projects": [projectId]
        ]

        // Add section membership if specified
        if let sectionId = sectionId, !sectionId.isEmpty {
            body["memberships"] = [
                [
                    "project": projectId,
                    "section": sectionId
                ]
            ]
        }

        // Add custom fields if provided
        if let customFields = customFields, !customFields.isEmpty {
            body["custom_fields"] = customFields
        }

        let response: AsanaResponse<AsanaTask> = try await request(
            method: .POST,
            path: "/tasks",
            token: token,
            body: body,
            responseType: AsanaResponse<AsanaTask>.self
        )

        return response.data
    }

    // MARK: - Task Update

    func updateTask(
        taskId: String,
        token: String,
        customFields: [String: Any]
    ) async throws {
        let _: AsanaResponse<AsanaTask> = try await request(
            method: .PUT,
            path: "/tasks/\(taskId)",
            token: token,
            body: ["custom_fields": customFields],
            responseType: AsanaResponse<AsanaTask>.self
        )
    }

    func updateTaskStatus(
        taskId: String,
        statusFieldId: String,
        statusOptionId: String,
        token: String
    ) async throws {
        try await updateTask(
            taskId: taskId,
            token: token,
            customFields: [statusFieldId: statusOptionId]
        )
    }

    func updateTaskVotes(
        taskId: String,
        votesFieldId: String,
        voteCount: Int,
        token: String
    ) async throws {
        try await updateTask(
            taskId: taskId,
            token: token,
            customFields: [votesFieldId: voteCount]
        )
    }

    // MARK: - Stories (Comments)

    func createStory(
        taskId: String,
        token: String,
        text: String
    ) async throws -> AsanaStory {
        let response: AsanaResponse<AsanaStory> = try await request(
            method: .POST,
            path: "/tasks/\(taskId)/stories",
            token: token,
            body: ["text": text],
            responseType: AsanaResponse<AsanaStory>.self
        )
        return response.data
    }

    // MARK: - Content Building

    func buildTaskNotes(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var notes = """
        \(feedback.category.displayName)

        \(feedback.description)

        ---

        Source: FeedbackKit
        Project: \(projectName)
        Votes: \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            notes += "\nMRR: $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            notes += "\nSubmitted by: \(userEmail)"
        }

        return notes
    }
}

// MARK: - Request Extension

extension Request {
    var asanaService: AsanaService {
        AsanaService(client: self.client)
    }
}
```

### Controller Routes

Add to `SwiftlyFeedbackServer/Sources/App/Controllers/ProjectController.swift`:

**Route Registration:**
```swift
// Asana integration
protected.patch(":projectId", "asana", use: updateAsanaSettings)
protected.post(":projectId", "asana", "task", use: createAsanaTask)
protected.post(":projectId", "asana", "tasks", use: bulkCreateAsanaTasks)
protected.get(":projectId", "asana", "workspaces", use: getAsanaWorkspaces)
protected.get(":projectId", "asana", "workspaces", ":workspaceId", "projects", use: getAsanaProjects)
protected.get(":projectId", "asana", "projects", ":asanaProjectId", "sections", use: getAsanaSections)
protected.get(":projectId", "asana", "projects", ":asanaProjectId", "custom-fields", use: getAsanaCustomFields)
```

**Controller Methods:**

```swift
// MARK: - Asana Integration

func updateAsanaSettings(req: Request) async throws -> ProjectDTO {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    let dto = try req.content.decode(UpdateProjectAsanaDTO.self)

    if let token = dto.asanaToken {
        project.asanaToken = token.isEmpty ? nil : token
    }
    if let workspaceId = dto.asanaWorkspaceId {
        project.asanaWorkspaceId = workspaceId.isEmpty ? nil : workspaceId
    }
    if let workspaceName = dto.asanaWorkspaceName {
        project.asanaWorkspaceName = workspaceName.isEmpty ? nil : workspaceName
    }
    if let projectId = dto.asanaProjectId {
        project.asanaProjectId = projectId.isEmpty ? nil : projectId
    }
    if let projectName = dto.asanaProjectName {
        project.asanaProjectName = projectName.isEmpty ? nil : projectName
    }
    if let sectionId = dto.asanaSectionId {
        project.asanaSectionId = sectionId.isEmpty ? nil : sectionId
    }
    if let sectionName = dto.asanaSectionName {
        project.asanaSectionName = sectionName.isEmpty ? nil : sectionName
    }
    if let syncStatus = dto.asanaSyncStatus {
        project.asanaSyncStatus = syncStatus
    }
    if let syncComments = dto.asanaSyncComments {
        project.asanaSyncComments = syncComments
    }
    if let statusFieldId = dto.asanaStatusFieldId {
        project.asanaStatusFieldId = statusFieldId.isEmpty ? nil : statusFieldId
    }
    if let votesFieldId = dto.asanaVotesFieldId {
        project.asanaVotesFieldId = votesFieldId.isEmpty ? nil : votesFieldId
    }
    if let isActive = dto.asanaIsActive {
        project.asanaIsActive = isActive
    }

    try await project.save(on: req.db)
    return try await project.toDTO(on: req.db)
}

func createAsanaTask(req: Request) async throws -> CreateAsanaTaskResponseDTO {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    guard let token = project.asanaToken,
          let asanaProjectId = project.asanaProjectId else {
        throw Abort(.badRequest, reason: "Asana integration not configured")
    }

    let dto = try req.content.decode(CreateAsanaTaskDTO.self)

    guard let feedback = try await Feedback.find(dto.feedbackId, on: req.db),
          feedback.$project.id == project.id else {
        throw Abort(.notFound, reason: "Feedback not found")
    }

    if feedback.asanaTaskURL != nil {
        throw Abort(.conflict, reason: "Feedback already has an Asana task")
    }

    // Calculate MRR if available
    var mrr: Double?
    if let sdkUser = try? await SDKUser.query(on: req.db)
        .filter(\.$sdkUserId == feedback.userId)
        .first() {
        mrr = sdkUser.mrr
    }

    // Build task notes
    let notes = req.asanaService.buildTaskNotes(
        feedback: feedback,
        projectName: project.name,
        voteCount: feedback.voteCount,
        mrr: mrr
    )

    // Build custom fields
    var customFields: [String: Any] = [:]
    if let statusFieldId = project.asanaStatusFieldId {
        // Get the status field options and find matching one
        let fields = try await req.asanaService.getCustomFields(projectId: asanaProjectId, token: token)
        if let statusField = fields.first(where: { $0.gid == statusFieldId }),
           let options = statusField.enumOptions {
            let targetStatus = feedback.status.asanaStatusName
            if let option = options.first(where: { $0.name.lowercased() == targetStatus.lowercased() && $0.enabled }) {
                customFields[statusFieldId] = option.gid
            }
        }
    }
    if let votesFieldId = project.asanaVotesFieldId {
        customFields[votesFieldId] = feedback.voteCount
    }

    // Create task
    let task = try await req.asanaService.createTask(
        projectId: asanaProjectId,
        sectionId: project.asanaSectionId,
        token: token,
        name: feedback.title,
        notes: notes,
        customFields: customFields.isEmpty ? nil : customFields
    )

    // Build URL (use permalink_url from response, or construct manually)
    let taskUrl = task.permalinkUrl ?? "https://app.asana.com/0/\(asanaProjectId)/\(task.gid)"

    // Save link to feedback
    feedback.asanaTaskURL = taskUrl
    feedback.asanaTaskId = task.gid
    try await feedback.save(on: req.db)

    return CreateAsanaTaskResponseDTO(
        feedbackId: feedback.id!,
        taskUrl: taskUrl,
        taskId: task.gid
    )
}

func bulkCreateAsanaTasks(req: Request) async throws -> BulkCreateAsanaTasksResponseDTO {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    guard let token = project.asanaToken,
          let asanaProjectId = project.asanaProjectId else {
        throw Abort(.badRequest, reason: "Asana integration not configured")
    }

    let dto = try req.content.decode(BulkCreateAsanaTasksDTO.self)

    var created: [CreateAsanaTaskResponseDTO] = []
    var failed: [UUID] = []

    // Pre-fetch custom field options if status sync is enabled
    var statusOptions: [String: String] = [:]  // status name -> option gid
    if let statusFieldId = project.asanaStatusFieldId {
        let fields = try await req.asanaService.getCustomFields(projectId: asanaProjectId, token: token)
        if let statusField = fields.first(where: { $0.gid == statusFieldId }),
           let options = statusField.enumOptions {
            for option in options where option.enabled {
                statusOptions[option.name.lowercased()] = option.gid
            }
        }
    }

    for feedbackId in dto.feedbackIds {
        do {
            guard let feedback = try await Feedback.find(feedbackId, on: req.db),
                  feedback.$project.id == project.id else {
                failed.append(feedbackId)
                continue
            }

            if feedback.asanaTaskURL != nil {
                failed.append(feedbackId)
                continue
            }

            var mrr: Double?
            if let sdkUser = try? await SDKUser.query(on: req.db)
                .filter(\.$sdkUserId == feedback.userId)
                .first() {
                mrr = sdkUser.mrr
            }

            let notes = req.asanaService.buildTaskNotes(
                feedback: feedback,
                projectName: project.name,
                voteCount: feedback.voteCount,
                mrr: mrr
            )

            var customFields: [String: Any] = [:]
            if let statusFieldId = project.asanaStatusFieldId {
                let targetStatus = feedback.status.asanaStatusName.lowercased()
                if let optionGid = statusOptions[targetStatus] {
                    customFields[statusFieldId] = optionGid
                }
            }
            if let votesFieldId = project.asanaVotesFieldId {
                customFields[votesFieldId] = feedback.voteCount
            }

            let task = try await req.asanaService.createTask(
                projectId: asanaProjectId,
                sectionId: project.asanaSectionId,
                token: token,
                name: feedback.title,
                notes: notes,
                customFields: customFields.isEmpty ? nil : customFields
            )

            let taskUrl = task.permalinkUrl ?? "https://app.asana.com/0/\(asanaProjectId)/\(task.gid)"

            feedback.asanaTaskURL = taskUrl
            feedback.asanaTaskId = task.gid
            try await feedback.save(on: req.db)

            created.append(CreateAsanaTaskResponseDTO(
                feedbackId: feedback.id!,
                taskUrl: taskUrl,
                taskId: task.gid
            ))
        } catch {
            failed.append(feedbackId)
        }
    }

    return BulkCreateAsanaTasksResponseDTO(created: created, failed: failed)
}

func getAsanaWorkspaces(req: Request) async throws -> [AsanaWorkspaceDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    guard let token = project.asanaToken else {
        throw Abort(.badRequest, reason: "Asana token not configured")
    }

    let workspaces = try await req.asanaService.getWorkspaces(token: token)
    return workspaces.map { AsanaWorkspaceDTO(gid: $0.gid, name: $0.name) }
}

func getAsanaProjects(req: Request) async throws -> [AsanaProjectDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    guard let token = project.asanaToken else {
        throw Abort(.badRequest, reason: "Asana token not configured")
    }

    guard let workspaceId = req.parameters.get("workspaceId") else {
        throw Abort(.badRequest, reason: "Workspace ID required")
    }

    let projects = try await req.asanaService.getProjects(workspaceId: workspaceId, token: token)
    return projects.map { AsanaProjectDTO(gid: $0.gid, name: $0.name) }
}

func getAsanaSections(req: Request) async throws -> [AsanaSectionDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    guard let token = project.asanaToken else {
        throw Abort(.badRequest, reason: "Asana token not configured")
    }

    guard let asanaProjectId = req.parameters.get("asanaProjectId") else {
        throw Abort(.badRequest, reason: "Asana Project ID required")
    }

    let sections = try await req.asanaService.getSections(projectId: asanaProjectId, token: token)
    return sections.map { AsanaSectionDTO(gid: $0.gid, name: $0.name) }
}

func getAsanaCustomFields(req: Request) async throws -> [AsanaCustomFieldDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired)
    }

    guard let token = project.asanaToken else {
        throw Abort(.badRequest, reason: "Asana token not configured")
    }

    guard let asanaProjectId = req.parameters.get("asanaProjectId") else {
        throw Abort(.badRequest, reason: "Asana Project ID required")
    }

    let fields = try await req.asanaService.getCustomFields(projectId: asanaProjectId, token: token)
    return fields.map { field in
        AsanaCustomFieldDTO(
            gid: field.gid,
            name: field.name,
            type: field.type,
            enumOptions: field.enumOptions?.map { option in
                AsanaEnumOptionDTO(
                    gid: option.gid,
                    name: option.name,
                    enabled: option.enabled,
                    color: option.color
                )
            }
        )
    }
}
```

### Status Sync in FeedbackController

Add Asana status sync to `FeedbackController.swift` in the `updateFeedback` method (alongside existing integrations):

```swift
// Asana status sync
if project.asanaIsActive,
   project.asanaSyncStatus,
   let asanaTaskId = feedback.asanaTaskId,
   let asanaToken = project.asanaToken,
   let asanaProjectId = project.asanaProjectId,
   let asanaStatusFieldId = project.asanaStatusFieldId {

    Task {
        do {
            // Get status field options
            let fields = try await req.asanaService.getCustomFields(projectId: asanaProjectId, token: asanaToken)
            if let statusField = fields.first(where: { $0.gid == asanaStatusFieldId }),
               let options = statusField.enumOptions {
                let targetStatus = newStatus.asanaStatusName.lowercased()
                if let option = options.first(where: { $0.name.lowercased() == targetStatus && $0.enabled }) {
                    try await req.asanaService.updateTaskStatus(
                        taskId: asanaTaskId,
                        statusFieldId: asanaStatusFieldId,
                        statusOptionId: option.gid,
                        token: asanaToken
                    )
                }
            }
        } catch {
            req.logger.error("Failed to sync Asana status: \(error)")
        }
    }
}
```

### Comment Sync in CommentController

Add Asana comment sync to `CommentController.swift` in the `createComment` method:

```swift
// Asana comment sync
if project.asanaIsActive,
   project.asanaSyncComments,
   let asanaTaskId = feedback.asanaTaskId,
   let asanaToken = project.asanaToken {

    Task {
        let commentText = "Comment from \(user.name ?? user.email):\n\n\(dto.content)"
        _ = try? await req.asanaService.createStory(
            taskId: asanaTaskId,
            token: asanaToken,
            text: commentText
        )
    }
}
```

### Vote Count Sync

Add to `VoteController.swift` when votes are added/removed:

```swift
// Asana votes sync
if project.asanaIsActive,
   let asanaTaskId = feedback.asanaTaskId,
   let asanaToken = project.asanaToken,
   let asanaVotesFieldId = project.asanaVotesFieldId {

    Task {
        try? await req.asanaService.updateTaskVotes(
            taskId: asanaTaskId,
            votesFieldId: asanaVotesFieldId,
            voteCount: feedback.voteCount,
            token: asanaToken
        )
    }
}
```

---

## Admin App Implementation

### Project Model Extension

Add to `SwiftlyFeedbackAdmin/Models/Project.swift`:

```swift
// Asana integration
var asanaToken: String?
var asanaWorkspaceId: String?
var asanaWorkspaceName: String?
var asanaProjectId: String?
var asanaProjectName: String?
var asanaSectionId: String?
var asanaSectionName: String?
var asanaSyncStatus: Bool
var asanaSyncComments: Bool
var asanaStatusFieldId: String?
var asanaVotesFieldId: String?
var asanaIsActive: Bool
```

Update `CodingKeys` enum accordingly.

### Feedback Model Extension

Add to `SwiftlyFeedbackAdmin/Models/Feedback.swift`:

```swift
var asanaTaskURL: String?
var asanaTaskId: String?

var hasAsanaTask: Bool {
    asanaTaskURL != nil
}
```

### API Client Methods

Add to `SwiftlyFeedbackAdmin/Services/APIClient.swift`:

```swift
// MARK: - Asana Integration

func updateAsanaSettings(
    projectId: UUID,
    asanaToken: String?,
    asanaWorkspaceId: String?,
    asanaWorkspaceName: String?,
    asanaProjectId: String?,
    asanaProjectName: String?,
    asanaSectionId: String?,
    asanaSectionName: String?,
    asanaSyncStatus: Bool?,
    asanaSyncComments: Bool?,
    asanaStatusFieldId: String?,
    asanaVotesFieldId: String?,
    asanaIsActive: Bool?
) async throws -> Project {
    var body: [String: Any] = [:]
    if let v = asanaToken { body["asanaToken"] = v }
    if let v = asanaWorkspaceId { body["asanaWorkspaceId"] = v }
    if let v = asanaWorkspaceName { body["asanaWorkspaceName"] = v }
    if let v = asanaProjectId { body["asanaProjectId"] = v }
    if let v = asanaProjectName { body["asanaProjectName"] = v }
    if let v = asanaSectionId { body["asanaSectionId"] = v }
    if let v = asanaSectionName { body["asanaSectionName"] = v }
    if let v = asanaSyncStatus { body["asanaSyncStatus"] = v }
    if let v = asanaSyncComments { body["asanaSyncComments"] = v }
    if let v = asanaStatusFieldId { body["asanaStatusFieldId"] = v }
    if let v = asanaVotesFieldId { body["asanaVotesFieldId"] = v }
    if let v = asanaIsActive { body["asanaIsActive"] = v }

    return try await request(
        method: .patch,
        path: "/projects/\(projectId)/asana",
        body: body
    )
}

func loadAsanaWorkspaces(projectId: UUID) async throws -> [AsanaWorkspace] {
    try await request(method: .get, path: "/projects/\(projectId)/asana/workspaces")
}

func loadAsanaProjects(projectId: UUID, workspaceId: String) async throws -> [AsanaProject] {
    try await request(method: .get, path: "/projects/\(projectId)/asana/workspaces/\(workspaceId)/projects")
}

func loadAsanaSections(projectId: UUID, asanaProjectId: String) async throws -> [AsanaSection] {
    try await request(method: .get, path: "/projects/\(projectId)/asana/projects/\(asanaProjectId)/sections")
}

func loadAsanaCustomFields(projectId: UUID, asanaProjectId: String) async throws -> [AsanaCustomField] {
    try await request(method: .get, path: "/projects/\(projectId)/asana/projects/\(asanaProjectId)/custom-fields")
}

func createAsanaTask(projectId: UUID, feedbackId: UUID) async throws -> CreateAsanaTaskResponse {
    try await request(
        method: .post,
        path: "/projects/\(projectId)/asana/task",
        body: ["feedbackId": feedbackId.uuidString]
    )
}

func bulkCreateAsanaTasks(projectId: UUID, feedbackIds: [UUID]) async throws -> BulkCreateAsanaTasksResponse {
    try await request(
        method: .post,
        path: "/projects/\(projectId)/asana/tasks",
        body: ["feedbackIds": feedbackIds.map { $0.uuidString }]
    )
}
```

### DTOs for Admin App

Add to `SwiftlyFeedbackAdmin/Models/IntegrationDTOs.swift` (or create new file):

```swift
// MARK: - Asana DTOs

struct AsanaWorkspace: Codable, Identifiable, Hashable {
    var id: String { gid }
    let gid: String
    let name: String
}

struct AsanaProject: Codable, Identifiable, Hashable {
    var id: String { gid }
    let gid: String
    let name: String
}

struct AsanaSection: Codable, Identifiable, Hashable {
    var id: String { gid }
    let gid: String
    let name: String
}

struct AsanaCustomField: Codable, Identifiable {
    var id: String { gid }
    let gid: String
    let name: String
    let type: String
    let enumOptions: [AsanaEnumOption]?
}

struct AsanaEnumOption: Codable, Identifiable, Hashable {
    var id: String { gid }
    let gid: String
    let name: String
    let enabled: Bool
    let color: String?
}

struct CreateAsanaTaskResponse: Codable {
    let feedbackId: UUID
    let taskUrl: String
    let taskId: String
}

struct BulkCreateAsanaTasksResponse: Codable {
    let created: [CreateAsanaTaskResponse]
    let failed: [UUID]
}
```

### ProjectViewModel Methods

Add to `SwiftlyFeedbackAdmin/ViewModels/ProjectViewModel.swift`:

```swift
// MARK: - Asana Integration

func updateAsanaSettings(
    projectId: UUID,
    asanaToken: String?,
    asanaWorkspaceId: String?,
    asanaWorkspaceName: String?,
    asanaProjectId: String?,
    asanaProjectName: String?,
    asanaSectionId: String?,
    asanaSectionName: String?,
    asanaSyncStatus: Bool?,
    asanaSyncComments: Bool?,
    asanaStatusFieldId: String?,
    asanaVotesFieldId: String?,
    asanaIsActive: Bool?
) async -> UpdateResult {
    isLoading = true
    defer { isLoading = false }

    do {
        let updated = try await apiClient.updateAsanaSettings(
            projectId: projectId,
            asanaToken: asanaToken,
            asanaWorkspaceId: asanaWorkspaceId,
            asanaWorkspaceName: asanaWorkspaceName,
            asanaProjectId: asanaProjectId,
            asanaProjectName: asanaProjectName,
            asanaSectionId: asanaSectionId,
            asanaSectionName: asanaSectionName,
            asanaSyncStatus: asanaSyncStatus,
            asanaSyncComments: asanaSyncComments,
            asanaStatusFieldId: asanaStatusFieldId,
            asanaVotesFieldId: asanaVotesFieldId,
            asanaIsActive: asanaIsActive
        )
        updateProject(updated)
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

func loadAsanaWorkspaces(projectId: UUID) async -> [AsanaWorkspace] {
    do {
        return try await apiClient.loadAsanaWorkspaces(projectId: projectId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadAsanaProjects(projectId: UUID, workspaceId: String) async -> [AsanaProject] {
    do {
        return try await apiClient.loadAsanaProjects(projectId: projectId, workspaceId: workspaceId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadAsanaSections(projectId: UUID, asanaProjectId: String) async -> [AsanaSection] {
    do {
        return try await apiClient.loadAsanaSections(projectId: projectId, asanaProjectId: asanaProjectId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadAsanaCustomFields(projectId: UUID, asanaProjectId: String) async -> [AsanaCustomField] {
    do {
        return try await apiClient.loadAsanaCustomFields(projectId: projectId, asanaProjectId: asanaProjectId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}
```

### Settings View

Create `SwiftlyFeedbackAdmin/Views/Projects/AsanaSettingsView.swift`:

```swift
import SwiftUI

struct AsanaSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var token: String
    @State private var workspaceId: String
    @State private var workspaceName: String
    @State private var asanaProjectId: String
    @State private var asanaProjectName: String
    @State private var sectionId: String
    @State private var sectionName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var statusFieldId: String
    @State private var votesFieldId: String
    @State private var isActive: Bool
    @State private var showingTokenInfo = false

    // Selection state
    @State private var workspaces: [AsanaWorkspace] = []
    @State private var projects: [AsanaProject] = []
    @State private var sections: [AsanaSection] = []
    @State private var customFields: [AsanaCustomField] = []
    @State private var selectedWorkspace: AsanaWorkspace?
    @State private var selectedProject: AsanaProject?
    @State private var selectedSection: AsanaSection?
    @State private var selectedStatusField: AsanaCustomField?
    @State private var selectedVotesField: AsanaCustomField?

    @State private var isLoadingWorkspaces = false
    @State private var isLoadingProjects = false
    @State private var isLoadingSections = false
    @State private var isLoadingFields = false
    @State private var workspacesError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _token = State(initialValue: project.asanaToken ?? "")
        _workspaceId = State(initialValue: project.asanaWorkspaceId ?? "")
        _workspaceName = State(initialValue: project.asanaWorkspaceName ?? "")
        _asanaProjectId = State(initialValue: project.asanaProjectId ?? "")
        _asanaProjectName = State(initialValue: project.asanaProjectName ?? "")
        _sectionId = State(initialValue: project.asanaSectionId ?? "")
        _sectionName = State(initialValue: project.asanaSectionName ?? "")
        _syncStatus = State(initialValue: project.asanaSyncStatus)
        _syncComments = State(initialValue: project.asanaSyncComments)
        _statusFieldId = State(initialValue: project.asanaStatusFieldId ?? "")
        _votesFieldId = State(initialValue: project.asanaVotesFieldId ?? "")
        _isActive = State(initialValue: project.asanaIsActive)
    }

    private var hasChanges: Bool {
        token != (project.asanaToken ?? "") ||
        workspaceId != (project.asanaWorkspaceId ?? "") ||
        workspaceName != (project.asanaWorkspaceName ?? "") ||
        asanaProjectId != (project.asanaProjectId ?? "") ||
        asanaProjectName != (project.asanaProjectName ?? "") ||
        sectionId != (project.asanaSectionId ?? "") ||
        sectionName != (project.asanaSectionName ?? "") ||
        syncStatus != project.asanaSyncStatus ||
        syncComments != project.asanaSyncComments ||
        statusFieldId != (project.asanaStatusFieldId ?? "") ||
        votesFieldId != (project.asanaVotesFieldId ?? "") ||
        isActive != project.asanaIsActive
    }

    private var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !asanaProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isConfigured {
                    Section {
                        Toggle("Integration Active", isOn: $isActive)
                    } footer: {
                        Text("When disabled, Asana sync will be paused.")
                    }
                }

                Section {
                    SecureField("Personal Access Token", text: $token)
                        .onChange(of: token) { _, newValue in
                            if !newValue.isEmpty && workspaces.isEmpty {
                                loadWorkspaces()
                            }
                        }

                    Button {
                        showingTokenInfo = true
                    } label: {
                        Label("How to get your token", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Create a Personal Access Token in the Asana Developer Console.")
                }

                if hasToken {
                    workspaceSection
                }

                if !workspaceId.isEmpty {
                    projectSection
                }

                if !asanaProjectId.isEmpty {
                    sectionSection
                }

                if isConfigured {
                    syncOptionsSection
                    customFieldsSection
                    removeIntegrationSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Asana Integration")
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
            .alert("Get Your Asana Personal Access Token", isPresented: $showingTokenInfo) {
                Button("Open Asana Developer Console") {
                    if let url = URL(string: "https://app.asana.com/0/my-apps") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to app.asana.com/0/my-apps\n2. Click 'Create new token'\n3. Give it a description\n4. Copy the generated token")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasToken { loadWorkspaces() }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var workspaceSection: some View {
        Section {
            if isLoadingWorkspaces {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading workspaces...").foregroundStyle(.secondary)
                }
            } else if let error = workspacesError {
                Text(error).foregroundStyle(.red).font(.caption)
                Button("Retry") { loadWorkspaces() }
            } else {
                Picker("Workspace", selection: $selectedWorkspace) {
                    Text("Select Workspace").tag(nil as AsanaWorkspace?)
                    ForEach(workspaces) { workspace in
                        Text(workspace.name).tag(workspace as AsanaWorkspace?)
                    }
                }
                .onChange(of: selectedWorkspace) { _, newValue in
                    if let workspace = newValue {
                        workspaceId = workspace.gid
                        workspaceName = workspace.name
                        loadProjects(workspaceId: workspace.gid)
                    } else {
                        clearFromWorkspace()
                    }
                }
            }
        } header: {
            Text("Workspace")
        } footer: {
            if !workspaceName.isEmpty {
                Text("Selected: \(workspaceName)")
            } else {
                Text("Select the Asana workspace containing your project.")
            }
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        Section {
            if isLoadingProjects {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading projects...").foregroundStyle(.secondary)
                }
            } else {
                Picker("Project", selection: $selectedProject) {
                    Text("Select Project").tag(nil as AsanaProject?)
                    ForEach(projects) { proj in
                        Text(proj.name).tag(proj as AsanaProject?)
                    }
                }
                .onChange(of: selectedProject) { _, newValue in
                    if let proj = newValue {
                        asanaProjectId = proj.gid
                        asanaProjectName = proj.name
                        loadSections(projectId: proj.gid)
                        loadCustomFields(projectId: proj.gid)
                    } else {
                        clearFromProject()
                    }
                }
            }
        } header: {
            Text("Target Project")
        } footer: {
            if !asanaProjectName.isEmpty {
                Text("Selected: \(asanaProjectName)")
            } else {
                Text("Select the project where tasks will be created.")
            }
        }
    }

    @ViewBuilder
    private var sectionSection: some View {
        Section {
            if isLoadingSections {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading sections...").foregroundStyle(.secondary)
                }
            } else {
                Picker("Section", selection: $selectedSection) {
                    Text("No specific section").tag(nil as AsanaSection?)
                    ForEach(sections) { section in
                        Text(section.name).tag(section as AsanaSection?)
                    }
                }
                .onChange(of: selectedSection) { _, newValue in
                    if let section = newValue {
                        sectionId = section.gid
                        sectionName = section.name
                    } else {
                        sectionId = ""
                        sectionName = ""
                    }
                }
            }
        } header: {
            Text("Target Section (Optional)")
        } footer: {
            Text("Optionally select a section within the project. Leave empty to add to the project without a specific section.")
        }
    }

    @ViewBuilder
    private var syncOptionsSection: some View {
        Section {
            Toggle("Sync status changes", isOn: $syncStatus)
            Toggle("Sync comments", isOn: $syncComments)
        } header: {
            Text("Sync Options")
        } footer: {
            Text("Automatically update Asana task status when feedback status changes, and add comments as task comments.")
        }
    }

    @ViewBuilder
    private var customFieldsSection: some View {
        if !customFields.isEmpty {
            let enumFields = customFields.filter { $0.type == "enum" }
            let numberFields = customFields.filter { $0.type == "number" }

            if !enumFields.isEmpty {
                Section {
                    Picker("Status Field", selection: $selectedStatusField) {
                        Text("None").tag(nil as AsanaCustomField?)
                        ForEach(enumFields) { field in
                            Text(field.name).tag(field as AsanaCustomField?)
                        }
                    }
                    .onChange(of: selectedStatusField) { _, newValue in
                        statusFieldId = newValue?.gid ?? ""
                    }
                } header: {
                    Text("Status Custom Field")
                } footer: {
                    Text("Select an Enum custom field to sync feedback status. The field should have options matching: To Do, Approved, In Progress, In Review, Complete, Closed.")
                }
            }

            if !numberFields.isEmpty {
                Section {
                    Picker("Votes Field", selection: $selectedVotesField) {
                        Text("None").tag(nil as AsanaCustomField?)
                        ForEach(numberFields) { field in
                            Text(field.name).tag(field as AsanaCustomField?)
                        }
                    }
                    .onChange(of: selectedVotesField) { _, newValue in
                        votesFieldId = newValue?.gid ?? ""
                    }
                } header: {
                    Text("Vote Count Custom Field")
                } footer: {
                    Text("Select a Number custom field to sync vote counts.")
                }
            }
        }
    }

    @ViewBuilder
    private var removeIntegrationSection: some View {
        Section {
            Button(role: .destructive) {
                clearIntegration()
            } label: {
                Label("Remove Asana Integration", systemImage: "trash")
            }
        }
    }

    // MARK: - Data Loading

    private func loadWorkspaces() {
        guard hasToken else { return }
        isLoadingWorkspaces = true
        workspacesError = nil

        Task {
            let result = await viewModel.updateAsanaSettings(
                projectId: project.id,
                asanaToken: token.trimmingCharacters(in: .whitespacesAndNewlines),
                asanaWorkspaceId: nil, asanaWorkspaceName: nil,
                asanaProjectId: nil, asanaProjectName: nil,
                asanaSectionId: nil, asanaSectionName: nil,
                asanaSyncStatus: nil, asanaSyncComments: nil,
                asanaStatusFieldId: nil, asanaVotesFieldId: nil,
                asanaIsActive: nil
            )

            if result == .success {
                workspaces = await viewModel.loadAsanaWorkspaces(projectId: project.id)
                if workspaces.isEmpty {
                    workspacesError = "No workspaces found. Make sure your token is valid."
                } else if !workspaceId.isEmpty {
                    selectedWorkspace = workspaces.first { $0.gid == workspaceId }
                    if selectedWorkspace != nil {
                        loadProjects(workspaceId: workspaceId)
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                workspacesError = viewModel.errorMessage ?? "Failed to verify token"
            }

            isLoadingWorkspaces = false
        }
    }

    private func loadProjects(workspaceId: String) {
        isLoadingProjects = true
        Task {
            projects = await viewModel.loadAsanaProjects(projectId: project.id, workspaceId: workspaceId)
            if !asanaProjectId.isEmpty {
                selectedProject = projects.first { $0.gid == asanaProjectId }
                if selectedProject != nil {
                    loadSections(projectId: asanaProjectId)
                    loadCustomFields(projectId: asanaProjectId)
                }
            }
            isLoadingProjects = false
        }
    }

    private func loadSections(projectId: String) {
        isLoadingSections = true
        Task {
            sections = await viewModel.loadAsanaSections(projectId: project.id, asanaProjectId: projectId)
            if !sectionId.isEmpty {
                selectedSection = sections.first { $0.gid == sectionId }
            }
            isLoadingSections = false
        }
    }

    private func loadCustomFields(projectId: String) {
        isLoadingFields = true
        Task {
            customFields = await viewModel.loadAsanaCustomFields(projectId: project.id, asanaProjectId: projectId)
            if !statusFieldId.isEmpty {
                selectedStatusField = customFields.first { $0.gid == statusFieldId }
            }
            if !votesFieldId.isEmpty {
                selectedVotesField = customFields.first { $0.gid == votesFieldId }
            }
            isLoadingFields = false
        }
    }

    // MARK: - Helpers

    private func clearFromWorkspace() {
        workspaceId = ""
        workspaceName = ""
        clearFromProject()
        projects = []
    }

    private func clearFromProject() {
        asanaProjectId = ""
        asanaProjectName = ""
        sectionId = ""
        sectionName = ""
        statusFieldId = ""
        votesFieldId = ""
        selectedProject = nil
        selectedSection = nil
        selectedStatusField = nil
        selectedVotesField = nil
        sections = []
        customFields = []
    }

    private func clearIntegration() {
        token = ""
        clearFromWorkspace()
        workspaces = []
        syncStatus = false
        syncComments = false
    }

    private func saveSettings() {
        Task {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateAsanaSettings(
                projectId: project.id,
                asanaToken: trimmedToken.isEmpty ? "" : trimmedToken,
                asanaWorkspaceId: workspaceId.isEmpty ? "" : workspaceId,
                asanaWorkspaceName: workspaceName.isEmpty ? "" : workspaceName,
                asanaProjectId: asanaProjectId.isEmpty ? "" : asanaProjectId,
                asanaProjectName: asanaProjectName.isEmpty ? "" : asanaProjectName,
                asanaSectionId: sectionId.isEmpty ? "" : sectionId,
                asanaSectionName: sectionName.isEmpty ? "" : sectionName,
                asanaSyncStatus: syncStatus,
                asanaSyncComments: syncComments,
                asanaStatusFieldId: statusFieldId.isEmpty ? "" : statusFieldId,
                asanaVotesFieldId: votesFieldId.isEmpty ? "" : votesFieldId,
                asanaIsActive: isActive
            )

            switch result {
            case .success: dismiss()
            case .paymentRequired: showPaywall = true
            case .otherError: break
            }
        }
    }
}
```

### Add Menu Item

Update `ProjectDetailView.swift` to add Asana to the integrations menu:

```swift
Button {
    showAsanaSettings = true
} label: {
    Label("Asana Integration", systemImage: "checkmark.circle")
}

// Add state
@State private var showAsanaSettings = false

// Add sheet
.sheet(isPresented: $showAsanaSettings) {
    AsanaSettingsView(project: project, viewModel: viewModel)
}
```

---

## Status Mapping

Add to `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`:

```swift
/// Maps SwiftlyFeedback status to Asana status names (for enum custom field)
var asanaStatusName: String {
    switch self {
    case .pending:
        return "To Do"
    case .approved:
        return "Approved"
    case .inProgress:
        return "In Progress"
    case .testflight:
        return "In Review"
    case .completed:
        return "Complete"
    case .rejected:
        return "Closed"
    }
}
```

### Status Mapping Table

| FeedbackKit Status | Asana Status Name |
|--------------------|-------------------|
| pending | To Do |
| approved | Approved |
| inProgress | In Progress |
| testflight | In Review |
| completed | Complete |
| rejected | Closed |

Users should create an Enum custom field in Asana with these option names for status sync to work properly.

---

## Implementation Checklist

### Server

- [ ] Create migration `AddProjectAsanaIntegration.swift`
- [ ] Add Asana fields to `Project` model
- [ ] Add Asana fields to `Feedback` model
- [ ] Add `hasAsanaTask` computed property to Feedback
- [ ] Create `AsanaService.swift`
- [ ] Add Asana DTOs to `ProjectDTO.swift`
- [ ] Add controller routes in `ProjectController.swift`
- [ ] Implement `updateAsanaSettings`
- [ ] Implement `createAsanaTask`
- [ ] Implement `bulkCreateAsanaTasks`
- [ ] Implement `getAsanaWorkspaces`
- [ ] Implement `getAsanaProjects`
- [ ] Implement `getAsanaSections`
- [ ] Implement `getAsanaCustomFields`
- [ ] Add status sync to `FeedbackController.updateFeedback`
- [ ] Add comment sync to `CommentController.createComment`
- [ ] Add votes sync to `VoteController`
- [ ] Add `asanaStatusName` to `FeedbackStatus` enum
- [ ] Register migration in `configure.swift`
- [ ] Update `ProjectDTO.toDTO()` to include Asana fields

### Admin App

- [ ] Add Asana fields to `Project` model
- [ ] Add Asana fields to `Feedback` model
- [ ] Add Asana DTOs
- [ ] Add API client methods for Asana
- [ ] Add ProjectViewModel methods for Asana
- [ ] Create `AsanaSettingsView.swift`
- [ ] Add Asana menu item to `ProjectDetailView`
- [ ] Add "Create Asana Task" action to feedback detail/list views
- [ ] Add Asana task link display to feedback cards

### Documentation

- [ ] Update root `CLAUDE.md` integrations table
- [ ] Update `SwiftlyFeedbackServer/CLAUDE.md` with API endpoints

### Testing

- [ ] Test token validation
- [ ] Test workspace discovery
- [ ] Test project discovery
- [ ] Test section discovery
- [ ] Test custom field discovery
- [ ] Test task creation (single)
- [ ] Test task creation (bulk)
- [ ] Test status sync
- [ ] Test comment sync
- [ ] Test votes sync
- [ ] Test with free Asana workspace (custom fields disabled)
- [ ] Test error handling (invalid token, rate limits)
- [ ] Test tier gating (Pro required)

---

## Notes

### Custom Fields Availability

Custom fields are an Asana Premium feature. The integration should gracefully handle:
- Workspaces without custom fields enabled (status/votes sync disabled)
- Projects without the expected custom fields configured

### Rate Limits

Asana has relatively low rate limits for free workspaces (150 req/min). Bulk operations should:
- Use reasonable batch sizes
- Implement exponential backoff on 429 responses
- Respect `Retry-After` header

### Task URL Construction

Asana tasks return `permalink_url` in the response. Use this when available, otherwise construct:
```
https://app.asana.com/0/{project_gid}/{task_gid}
```

### Asana vs Other Integrations

| Aspect | Monday.com | Linear | Asana |
|--------|------------|--------|-------|
| API Type | GraphQL | GraphQL | REST |
| Status | Column value | Workflow state | Custom field enum |
| Comments | Updates | Comments | Stories |
| Hierarchy | Board > Group | Team > Project | Workspace > Project > Section |
| Rate Limit | Higher | Higher | Lower (150/min free) |
