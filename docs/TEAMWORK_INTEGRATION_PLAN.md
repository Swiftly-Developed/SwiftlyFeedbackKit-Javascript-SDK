# Teamwork Integration Technical Plan

> **Reference**: This integration follows the same patterns established by Monday.com, ClickUp, Linear, and GitHub integrations.

## Overview

This document outlines the technical implementation plan for integrating FeedbackKit with [Teamwork.com](https://teamwork.com), a project management platform. The integration will allow users to:

1. Push feedback items to Teamwork as tasks
2. Sync feedback status changes to Teamwork task status
3. Sync comments between FeedbackKit and Teamwork
4. Track vote counts in a custom field

---

## Table of Contents

1. [Teamwork API Overview](#1-teamwork-api-overview)
2. [Database Changes](#2-database-changes)
3. [Server Implementation](#3-server-implementation)
4. [Admin App Implementation](#4-admin-app-implementation)
5. [Status Mapping](#5-status-mapping)
6. [File Changes Summary](#6-file-changes-summary)
7. [Testing Checklist](#7-testing-checklist)

---

## 1. Teamwork API Overview

### Authentication

Teamwork supports two authentication methods:

1. **Basic Authentication** (simpler, recommended for this integration)
   - Header: `Authorization: Basic {base64(apiKey:password)}`
   - API keys can be generated in Teamwork: Settings > API & Webhooks

2. **OAuth 2.0** (for more complex integrations)
   - Header: `Authorization: Bearer {token}`

**For this integration**: Use Basic Authentication with API key (password can be any string, often "X" or left empty).

### Base URL Structure

```
https://{siteName}.teamwork.com/projects/api/v3/
```

The `siteName` is the customer's Teamwork subdomain (e.g., `mycompany.teamwork.com`).

### Key Endpoints

| Operation | Method | Endpoint |
|-----------|--------|----------|
| List Projects | GET | `/projects/api/v3/projects.json` |
| List Task Lists | GET | `/projects/api/v3/projects/{projectId}/tasklists.json` |
| Create Task | POST | `/projects/api/v3/tasklists/{tasklistId}/tasks.json` |
| Update Task | PATCH | `/projects/api/v3/tasks/{taskId}.json` |
| Complete Task | PUT | `/tasks/{id}/complete.json` (V1) |
| Uncomplete Task | PUT | `/tasks/{id}/uncomplete.json` (V1) |
| Create Comment | POST | `/tasks/{taskId}/comments.json` (V1) |
| Get Custom Fields | GET | `/projects/api/v3/projects/{projectId}/customfields.json` |

### Request/Response Format

**Create Task Request:**
```json
{
  "task": {
    "name": "Feedback Title",
    "description": "Feedback description with metadata",
    "tasklistId": 12345,
    "priority": "medium",
    "tags": [{"name": "feedback"}]
  }
}
```

**Create Task Response:**
```json
{
  "task": {
    "id": 67890,
    "name": "Feedback Title",
    ...
  }
}
```

### Rate Limits

Teamwork implements rate limiting but specific limits are not publicly documented. Implement exponential backoff for 429 responses.

---

## 2. Database Changes

### 2.1 Project Model Changes

Add these fields to the `Project` model in `SwiftlyFeedbackServer/Sources/App/Models/Project.swift`:

```swift
// MARK: - Teamwork Integration
@OptionalField(key: "teamwork_site_name")
var teamworkSiteName: String?

@OptionalField(key: "teamwork_api_key")
var teamworkApiKey: String?

@OptionalField(key: "teamwork_project_id")
var teamworkProjectId: String?

@OptionalField(key: "teamwork_project_name")
var teamworkProjectName: String?

@OptionalField(key: "teamwork_tasklist_id")
var teamworkTasklistId: String?

@OptionalField(key: "teamwork_tasklist_name")
var teamworkTasklistName: String?

@OptionalField(key: "teamwork_sync_status")
var teamworkSyncStatus: Bool

@OptionalField(key: "teamwork_sync_comments")
var teamworkSyncComments: Bool

@OptionalField(key: "teamwork_votes_field_id")
var teamworkVotesFieldId: String?

@OptionalField(key: "teamwork_is_active")
var teamworkIsActive: Bool
```

**Default values in initializer:**
```swift
self.teamworkSyncStatus = false
self.teamworkSyncComments = false
self.teamworkIsActive = true
```

### 2.2 Feedback Model Changes

Add these fields to the `Feedback` model in `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`:

```swift
// MARK: - Teamwork Integration
@OptionalField(key: "teamwork_task_url")
var teamworkTaskURL: String?

@OptionalField(key: "teamwork_task_id")
var teamworkTaskId: String?
```

### 2.3 Database Migration

Create a new migration file: `SwiftlyFeedbackServer/Sources/App/Migrations/AddTeamworkIntegration.swift`

```swift
import Fluent

struct AddTeamworkIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Project fields
        try await database.schema("projects")
            .field("teamwork_site_name", .string)
            .field("teamwork_api_key", .string)
            .field("teamwork_project_id", .string)
            .field("teamwork_project_name", .string)
            .field("teamwork_tasklist_id", .string)
            .field("teamwork_tasklist_name", .string)
            .field("teamwork_sync_status", .bool, .required, .sql(.default(false)))
            .field("teamwork_sync_comments", .bool, .required, .sql(.default(false)))
            .field("teamwork_votes_field_id", .string)
            .field("teamwork_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Feedback fields
        try await database.schema("feedbacks")
            .field("teamwork_task_url", .string)
            .field("teamwork_task_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("teamwork_site_name")
            .deleteField("teamwork_api_key")
            .deleteField("teamwork_project_id")
            .deleteField("teamwork_project_name")
            .deleteField("teamwork_tasklist_id")
            .deleteField("teamwork_tasklist_name")
            .deleteField("teamwork_sync_status")
            .deleteField("teamwork_sync_comments")
            .deleteField("teamwork_votes_field_id")
            .deleteField("teamwork_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("teamwork_task_url")
            .deleteField("teamwork_task_id")
            .update()
    }
}
```

---

## 3. Server Implementation

### 3.1 TeamworkService

Create `SwiftlyFeedbackServer/Sources/App/Services/TeamworkService.swift`:

```swift
import Vapor

struct TeamworkService {
    private let client: Client

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct TeamworkProject: Codable {
        let id: Int
        let name: String
    }

    struct TeamworkTasklist: Codable {
        let id: Int
        let name: String
        let projectId: Int
    }

    struct TeamworkTask: Codable {
        let id: Int
        let name: String
    }

    struct TeamworkCustomField: Codable {
        let id: Int
        let name: String
        let type: String
    }

    // MARK: - Base URL Helper

    private func baseURL(siteName: String) -> String {
        "https://\(siteName).teamwork.com"
    }

    // MARK: - Auth Header

    private func authHeader(apiKey: String) -> String {
        let credentials = "\(apiKey):X"
        let base64 = Data(credentials.utf8).base64EncodedString()
        return "Basic \(base64)"
    }

    // MARK: - Get Projects

    func getProjects(siteName: String, apiKey: String) async throws -> [TeamworkProject] {
        let url = "\(baseURL(siteName: siteName))/projects/api/v3/projects.json"

        let response = try await client.get(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Teamwork API error: \(response.status)")
        }

        struct ProjectsResponse: Codable {
            let projects: [TeamworkProject]
        }

        let data = try response.content.decode(ProjectsResponse.self)
        return data.projects
    }

    // MARK: - Get Task Lists

    func getTasklists(
        siteName: String,
        apiKey: String,
        projectId: String
    ) async throws -> [TeamworkTasklist] {
        let url = "\(baseURL(siteName: siteName))/projects/api/v3/projects/\(projectId)/tasklists.json"

        let response = try await client.get(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Teamwork API error: \(response.status)")
        }

        struct TasklistsResponse: Codable {
            let tasklists: [TeamworkTasklist]
        }

        let data = try response.content.decode(TasklistsResponse.self)
        return data.tasklists
    }

    // MARK: - Create Task

    func createTask(
        siteName: String,
        apiKey: String,
        tasklistId: String,
        name: String,
        description: String,
        tags: [String]? = nil
    ) async throws -> TeamworkTask {
        let url = "\(baseURL(siteName: siteName))/projects/api/v3/tasklists/\(tasklistId)/tasks.json"

        var taskBody: [String: Any] = [
            "name": name,
            "description": description
        ]

        if let tags = tags, !tags.isEmpty {
            taskBody["tagNames"] = tags.joined(separator: ",")
        }

        let body: [String: Any] = ["task": taskBody]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.post(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard response.status == .ok || response.status == .created else {
            let responseBody = response.body.map { String(buffer: $0) } ?? "no body"
            throw Abort(.badGateway, reason: "Teamwork API error: \(responseBody)")
        }

        struct CreateTaskResponse: Codable {
            let task: TeamworkTask
        }

        return try response.content.decode(CreateTaskResponse.self).task
    }

    // MARK: - Complete Task

    func completeTask(
        siteName: String,
        apiKey: String,
        taskId: String
    ) async throws {
        let url = "\(baseURL(siteName: siteName))/tasks/\(taskId)/complete.json"

        let response = try await client.put(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to complete Teamwork task")
        }
    }

    // MARK: - Uncomplete Task

    func uncompleteTask(
        siteName: String,
        apiKey: String,
        taskId: String
    ) async throws {
        let url = "\(baseURL(siteName: siteName))/tasks/\(taskId)/uncomplete.json"

        let response = try await client.put(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to uncomplete Teamwork task")
        }
    }

    // MARK: - Create Comment

    func createComment(
        siteName: String,
        apiKey: String,
        taskId: String,
        body: String
    ) async throws {
        let url = "\(baseURL(siteName: siteName))/tasks/\(taskId)/comments.json"

        let commentBody: [String: Any] = [
            "comment": [
                "body": body,
                "notify": false
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: commentBody)

        let response = try await client.post(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard response.status == .ok || response.status == .created else {
            throw Abort(.badGateway, reason: "Failed to create Teamwork comment")
        }
    }

    // MARK: - Update Custom Field (Vote Count)

    func updateCustomField(
        siteName: String,
        apiKey: String,
        taskId: String,
        customFieldId: String,
        value: Int
    ) async throws {
        let url = "\(baseURL(siteName: siteName))/projects/api/v3/tasks/\(taskId).json"

        let body: [String: Any] = [
            "task": [
                "customFields": [
                    [
                        "customFieldId": Int(customFieldId) ?? 0,
                        "value": String(value)
                    ]
                ]
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.patch(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to update Teamwork custom field")
        }
    }

    // MARK: - Get Custom Fields

    func getCustomFields(
        siteName: String,
        apiKey: String,
        projectId: String
    ) async throws -> [TeamworkCustomField] {
        let url = "\(baseURL(siteName: siteName))/projects/api/v3/projects/\(projectId)/customfields.json"

        let response = try await client.get(URI(string: url)) { req in
            req.headers.add(name: .authorization, value: authHeader(apiKey: apiKey))
            req.headers.add(name: .contentType, value: "application/json")
        }

        guard response.status == .ok else {
            return [] // Custom fields may not be available
        }

        struct CustomFieldsResponse: Codable {
            let customfields: [TeamworkCustomField]?
        }

        let data = try? response.content.decode(CustomFieldsResponse.self)
        return data?.customfields ?? []
    }

    // MARK: - Build Task Description

    func buildTaskDescription(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var description = """
        **\(feedback.category.displayName)**

        \(feedback.description)

        ---

        **Source:** SwiftlyFeedback
        **Project:** \(projectName)
        **Votes:** \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            description += "\n**MRR:** $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            description += "\n**Submitted by:** \(userEmail)"
        }

        return description
    }

    // MARK: - Build Task URL

    func buildTaskURL(siteName: String, taskId: String) -> String {
        "https://\(siteName).teamwork.com/app/tasks/\(taskId)"
    }
}

// MARK: - Request Extension

extension Request {
    var teamworkService: TeamworkService {
        TeamworkService(client: self.client)
    }
}
```

### 3.2 DTOs

Add to `SwiftlyFeedbackServer/Sources/App/DTOs/ProjectDTO.swift`:

```swift
// MARK: - Teamwork Integration DTOs

struct UpdateProjectTeamworkDTO: Content {
    var teamworkSiteName: String?
    var teamworkApiKey: String?
    var teamworkProjectId: String?
    var teamworkProjectName: String?
    var teamworkTasklistId: String?
    var teamworkTasklistName: String?
    var teamworkSyncStatus: Bool?
    var teamworkSyncComments: Bool?
    var teamworkVotesFieldId: String?
    var teamworkIsActive: Bool?
}

struct TeamworkProjectDTO: Content {
    let id: Int
    let name: String
}

struct TeamworkTasklistDTO: Content {
    let id: Int
    let name: String
    let projectId: Int
}

struct TeamworkCustomFieldDTO: Content {
    let id: Int
    let name: String
    let type: String
}

struct CreateTeamworkTaskDTO: Content {
    let feedbackId: UUID
}

struct CreateTeamworkTaskResponseDTO: Content {
    let taskURL: String
    let taskId: String
}

struct BulkCreateTeamworkTasksDTO: Content {
    let feedbackIds: [UUID]
}

struct BulkCreateTeamworkTasksResponseDTO: Content {
    let created: [CreatedTeamworkTask]
    let failed: [FailedTeamworkTask]

    struct CreatedTeamworkTask: Content {
        let feedbackId: UUID
        let taskURL: String
        let taskId: String
    }

    struct FailedTeamworkTask: Content {
        let feedbackId: UUID
        let error: String
    }
}
```

Update `ProjectDTO` to include Teamwork fields in the response:

```swift
// Add to ProjectDTO struct
let teamworkSiteName: String?
let teamworkApiKey: String?
let teamworkProjectId: String?
let teamworkProjectName: String?
let teamworkTasklistId: String?
let teamworkTasklistName: String?
let teamworkSyncStatus: Bool
let teamworkSyncComments: Bool
let teamworkVotesFieldId: String?
let teamworkIsActive: Bool

// Add to ProjectDTO initializer
self.teamworkSiteName = project.teamworkSiteName
self.teamworkApiKey = project.teamworkApiKey
self.teamworkProjectId = project.teamworkProjectId
self.teamworkProjectName = project.teamworkProjectName
self.teamworkTasklistId = project.teamworkTasklistId
self.teamworkTasklistName = project.teamworkTasklistName
self.teamworkSyncStatus = project.teamworkSyncStatus
self.teamworkSyncComments = project.teamworkSyncComments
self.teamworkVotesFieldId = project.teamworkVotesFieldId
self.teamworkIsActive = project.teamworkIsActive
```

Update `FeedbackDTO` to include Teamwork fields:

```swift
// Add to FeedbackDTO struct
let teamworkTaskURL: String?
let teamworkTaskId: String?

// Add to FeedbackDTO initializer
self.teamworkTaskURL = feedback.teamworkTaskURL
self.teamworkTaskId = feedback.teamworkTaskId
```

### 3.3 Controller Routes

Add to `SwiftlyFeedbackServer/Sources/App/Controllers/ProjectController.swift`:

**Route registration (in `boot` method):**
```swift
// Teamwork
protected.patch(":projectId", "teamwork", use: updateTeamworkSettings)
protected.post(":projectId", "teamwork", "task", use: createTeamworkTask)
protected.post(":projectId", "teamwork", "tasks", use: bulkCreateTeamworkTasks)
protected.get(":projectId", "teamwork", "projects", use: getTeamworkProjects)
protected.get(":projectId", "teamwork", "projects", ":twProjectId", "tasklists", use: getTeamworkTasklists)
protected.get(":projectId", "teamwork", "projects", ":twProjectId", "customfields", use: getTeamworkCustomFields)
```

**Controller methods:**

```swift
// MARK: - Teamwork Integration

@Sendable
func updateTeamworkSettings(req: Request) async throws -> ProjectDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Teamwork integration requires Pro subscription")
    }

    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    let project = try await getProjectWithRole(req: req, projectId: projectId, minimumRole: .admin)
    let dto = try req.content.decode(UpdateProjectTeamworkDTO.self)

    if let siteName = dto.teamworkSiteName {
        project.teamworkSiteName = siteName.isEmpty ? nil : siteName
    }
    if let apiKey = dto.teamworkApiKey {
        project.teamworkApiKey = apiKey.isEmpty ? nil : apiKey
    }
    if let projectId = dto.teamworkProjectId {
        project.teamworkProjectId = projectId.isEmpty ? nil : projectId
    }
    if let projectName = dto.teamworkProjectName {
        project.teamworkProjectName = projectName.isEmpty ? nil : projectName
    }
    if let tasklistId = dto.teamworkTasklistId {
        project.teamworkTasklistId = tasklistId.isEmpty ? nil : tasklistId
    }
    if let tasklistName = dto.teamworkTasklistName {
        project.teamworkTasklistName = tasklistName.isEmpty ? nil : tasklistName
    }
    if let syncStatus = dto.teamworkSyncStatus {
        project.teamworkSyncStatus = syncStatus
    }
    if let syncComments = dto.teamworkSyncComments {
        project.teamworkSyncComments = syncComments
    }
    if let votesFieldId = dto.teamworkVotesFieldId {
        project.teamworkVotesFieldId = votesFieldId.isEmpty ? nil : votesFieldId
    }
    if let isActive = dto.teamworkIsActive {
        project.teamworkIsActive = isActive
    }

    try await project.save(on: req.db)
    return ProjectDTO(project: project)
}

@Sendable
func createTeamworkTask(req: Request) async throws -> CreateTeamworkTaskResponseDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Teamwork integration requires Pro subscription")
    }

    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    let project = try await getProjectWithRole(req: req, projectId: projectId, minimumRole: .member)

    guard let siteName = project.teamworkSiteName,
          let apiKey = project.teamworkApiKey,
          let tasklistId = project.teamworkTasklistId else {
        throw Abort(.badRequest, reason: "Teamwork integration not configured")
    }

    let dto = try req.content.decode(CreateTeamworkTaskDTO.self)

    guard let feedback = try await Feedback.query(on: req.db)
        .filter(\.$id == dto.feedbackId)
        .filter(\.$project.$id == projectId)
        .first() else {
        throw Abort(.notFound, reason: "Feedback not found")
    }

    if feedback.teamworkTaskURL != nil {
        throw Abort(.conflict, reason: "Feedback already has a Teamwork task")
    }

    let voteCount = try await Vote.query(on: req.db)
        .filter(\.$feedback.$id == feedback.id!)
        .count()

    let mrr = try await calculateMRR(for: feedback, on: req.db)

    let description = req.teamworkService.buildTaskDescription(
        feedback: feedback,
        projectName: project.name,
        voteCount: voteCount,
        mrr: mrr
    )

    let task = try await req.teamworkService.createTask(
        siteName: siteName,
        apiKey: apiKey,
        tasklistId: tasklistId,
        name: feedback.title,
        description: description,
        tags: ["feedback", feedback.category.rawValue]
    )

    let taskId = String(task.id)
    let taskUrl = req.teamworkService.buildTaskURL(siteName: siteName, taskId: taskId)

    feedback.teamworkTaskURL = taskUrl
    feedback.teamworkTaskId = taskId
    try await feedback.save(on: req.db)

    // Update vote count custom field if configured
    if let votesFieldId = project.teamworkVotesFieldId {
        try? await req.teamworkService.updateCustomField(
            siteName: siteName,
            apiKey: apiKey,
            taskId: taskId,
            customFieldId: votesFieldId,
            value: voteCount
        )
    }

    // Sync initial status if completed/rejected
    if project.teamworkSyncStatus {
        if feedback.status == .completed {
            try? await req.teamworkService.completeTask(
                siteName: siteName,
                apiKey: apiKey,
                taskId: taskId
            )
        }
    }

    return CreateTeamworkTaskResponseDTO(taskURL: taskUrl, taskId: taskId)
}

@Sendable
func bulkCreateTeamworkTasks(req: Request) async throws -> BulkCreateTeamworkTasksResponseDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Teamwork integration requires Pro subscription")
    }

    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    let project = try await getProjectWithRole(req: req, projectId: projectId, minimumRole: .member)

    guard let siteName = project.teamworkSiteName,
          let apiKey = project.teamworkApiKey,
          let tasklistId = project.teamworkTasklistId else {
        throw Abort(.badRequest, reason: "Teamwork integration not configured")
    }

    let dto = try req.content.decode(BulkCreateTeamworkTasksDTO.self)

    var created: [BulkCreateTeamworkTasksResponseDTO.CreatedTeamworkTask] = []
    var failed: [BulkCreateTeamworkTasksResponseDTO.FailedTeamworkTask] = []

    for feedbackId in dto.feedbackIds {
        do {
            guard let feedback = try await Feedback.query(on: req.db)
                .filter(\.$id == feedbackId)
                .filter(\.$project.$id == projectId)
                .first() else {
                failed.append(.init(feedbackId: feedbackId, error: "Feedback not found"))
                continue
            }

            if feedback.teamworkTaskURL != nil {
                failed.append(.init(feedbackId: feedbackId, error: "Already has Teamwork task"))
                continue
            }

            let voteCount = try await Vote.query(on: req.db)
                .filter(\.$feedback.$id == feedback.id!)
                .count()

            let mrr = try await calculateMRR(for: feedback, on: req.db)

            let description = req.teamworkService.buildTaskDescription(
                feedback: feedback,
                projectName: project.name,
                voteCount: voteCount,
                mrr: mrr
            )

            let task = try await req.teamworkService.createTask(
                siteName: siteName,
                apiKey: apiKey,
                tasklistId: tasklistId,
                name: feedback.title,
                description: description,
                tags: ["feedback", feedback.category.rawValue]
            )

            let taskId = String(task.id)
            let taskUrl = req.teamworkService.buildTaskURL(siteName: siteName, taskId: taskId)

            feedback.teamworkTaskURL = taskUrl
            feedback.teamworkTaskId = taskId
            try await feedback.save(on: req.db)

            created.append(.init(feedbackId: feedbackId, taskURL: taskUrl, taskId: taskId))

        } catch {
            failed.append(.init(feedbackId: feedbackId, error: error.localizedDescription))
        }
    }

    return BulkCreateTeamworkTasksResponseDTO(created: created, failed: failed)
}

@Sendable
func getTeamworkProjects(req: Request) async throws -> [TeamworkProjectDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Teamwork integration requires Pro subscription")
    }

    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    let project = try await getProjectWithRole(req: req, projectId: projectId, minimumRole: .admin)

    guard let siteName = project.teamworkSiteName,
          let apiKey = project.teamworkApiKey else {
        throw Abort(.badRequest, reason: "Teamwork credentials not configured")
    }

    let projects = try await req.teamworkService.getProjects(siteName: siteName, apiKey: apiKey)
    return projects.map { TeamworkProjectDTO(id: $0.id, name: $0.name) }
}

@Sendable
func getTeamworkTasklists(req: Request) async throws -> [TeamworkTasklistDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Teamwork integration requires Pro subscription")
    }

    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    guard let twProjectId = req.parameters.get("twProjectId") else {
        throw Abort(.badRequest, reason: "Invalid Teamwork project ID")
    }

    let project = try await getProjectWithRole(req: req, projectId: projectId, minimumRole: .admin)

    guard let siteName = project.teamworkSiteName,
          let apiKey = project.teamworkApiKey else {
        throw Abort(.badRequest, reason: "Teamwork credentials not configured")
    }

    let tasklists = try await req.teamworkService.getTasklists(
        siteName: siteName,
        apiKey: apiKey,
        projectId: twProjectId
    )
    return tasklists.map { TeamworkTasklistDTO(id: $0.id, name: $0.name, projectId: $0.projectId) }
}

@Sendable
func getTeamworkCustomFields(req: Request) async throws -> [TeamworkCustomFieldDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Teamwork integration requires Pro subscription")
    }

    guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
        throw Abort(.badRequest, reason: "Invalid project ID")
    }

    guard let twProjectId = req.parameters.get("twProjectId") else {
        throw Abort(.badRequest, reason: "Invalid Teamwork project ID")
    }

    let project = try await getProjectWithRole(req: req, projectId: projectId, minimumRole: .admin)

    guard let siteName = project.teamworkSiteName,
          let apiKey = project.teamworkApiKey else {
        throw Abort(.badRequest, reason: "Teamwork credentials not configured")
    }

    let fields = try await req.teamworkService.getCustomFields(
        siteName: siteName,
        apiKey: apiKey,
        projectId: twProjectId
    )
    return fields.map { TeamworkCustomFieldDTO(id: $0.id, name: $0.name, type: $0.type) }
}
```

### 3.4 Status Sync on Feedback Update

Add Teamwork sync logic to the feedback status update handler (in `FeedbackController` or wherever status changes are handled):

```swift
// After feedback status is updated, sync to Teamwork if configured
if let taskId = feedback.teamworkTaskId,
   let siteName = project.teamworkSiteName,
   let apiKey = project.teamworkApiKey,
   project.teamworkSyncStatus,
   project.teamworkIsActive {

    switch feedback.status {
    case .completed, .rejected:
        try? await req.teamworkService.completeTask(
            siteName: siteName,
            apiKey: apiKey,
            taskId: taskId
        )
    case .pending, .approved, .inProgress, .testflight:
        try? await req.teamworkService.uncompleteTask(
            siteName: siteName,
            apiKey: apiKey,
            taskId: taskId
        )
    }
}
```

### 3.5 Comment Sync on New Comment

Add Teamwork comment sync to the comment creation handler:

```swift
// After comment is created, sync to Teamwork if configured
if let taskId = feedback.teamworkTaskId,
   let siteName = project.teamworkSiteName,
   let apiKey = project.teamworkApiKey,
   project.teamworkSyncComments,
   project.teamworkIsActive {

    let commentBody = "**\(user.name)** commented:\n\n\(comment.content)"
    try? await req.teamworkService.createComment(
        siteName: siteName,
        apiKey: apiKey,
        taskId: taskId,
        body: commentBody
    )
}
```

### 3.6 Vote Count Sync

Add vote count sync when votes change:

```swift
// After vote is added/removed, sync to Teamwork if configured
if let taskId = feedback.teamworkTaskId,
   let siteName = project.teamworkSiteName,
   let apiKey = project.teamworkApiKey,
   let votesFieldId = project.teamworkVotesFieldId,
   project.teamworkIsActive {

    let voteCount = try await Vote.query(on: req.db)
        .filter(\.$feedback.$id == feedback.id!)
        .count()

    try? await req.teamworkService.updateCustomField(
        siteName: siteName,
        apiKey: apiKey,
        taskId: taskId,
        customFieldId: votesFieldId,
        value: voteCount
    )
}
```

---

## 4. Admin App Implementation

### 4.1 Models

Add to `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/Project.swift`:

```swift
// MARK: - Teamwork Integration
var teamworkSiteName: String?
var teamworkApiKey: String?
var teamworkProjectId: String?
var teamworkProjectName: String?
var teamworkTasklistId: String?
var teamworkTasklistName: String?
var teamworkSyncStatus: Bool
var teamworkSyncComments: Bool
var teamworkVotesFieldId: String?
var teamworkIsActive: Bool
```

Add new model files for Teamwork types:

**`SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/TeamworkModels.swift`:**

```swift
import Foundation

struct TeamworkProject: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TeamworkTasklist: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let projectId: Int
}

struct TeamworkCustomField: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
}
```

### 4.2 API Client Methods

Add to `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/AdminAPIClient.swift`:

```swift
// MARK: - Teamwork Integration

func updateProjectTeamworkSettings(
    projectId: UUID,
    teamworkSiteName: String?,
    teamworkApiKey: String?,
    teamworkProjectId: String?,
    teamworkProjectName: String?,
    teamworkTasklistId: String?,
    teamworkTasklistName: String?,
    teamworkSyncStatus: Bool?,
    teamworkSyncComments: Bool?,
    teamworkVotesFieldId: String?,
    teamworkIsActive: Bool?
) async throws -> Project {
    let body: [String: Any?] = [
        "teamworkSiteName": teamworkSiteName,
        "teamworkApiKey": teamworkApiKey,
        "teamworkProjectId": teamworkProjectId,
        "teamworkProjectName": teamworkProjectName,
        "teamworkTasklistId": teamworkTasklistId,
        "teamworkTasklistName": teamworkTasklistName,
        "teamworkSyncStatus": teamworkSyncStatus,
        "teamworkSyncComments": teamworkSyncComments,
        "teamworkVotesFieldId": teamworkVotesFieldId,
        "teamworkIsActive": teamworkIsActive
    ]

    return try await patch(
        endpoint: "projects/\(projectId.uuidString)/teamwork",
        body: body.compactMapValues { $0 }
    )
}

func getTeamworkProjects(projectId: UUID) async throws -> [TeamworkProject] {
    try await get(endpoint: "projects/\(projectId.uuidString)/teamwork/projects")
}

func getTeamworkTasklists(projectId: UUID, twProjectId: Int) async throws -> [TeamworkTasklist] {
    try await get(endpoint: "projects/\(projectId.uuidString)/teamwork/projects/\(twProjectId)/tasklists")
}

func getTeamworkCustomFields(projectId: UUID, twProjectId: Int) async throws -> [TeamworkCustomField] {
    try await get(endpoint: "projects/\(projectId.uuidString)/teamwork/projects/\(twProjectId)/customfields")
}

func createTeamworkTask(projectId: UUID, feedbackId: UUID) async throws -> CreateTeamworkTaskResponse {
    try await post(
        endpoint: "projects/\(projectId.uuidString)/teamwork/task",
        body: ["feedbackId": feedbackId.uuidString]
    )
}

func bulkCreateTeamworkTasks(projectId: UUID, feedbackIds: [UUID]) async throws -> BulkCreateTeamworkTasksResponse {
    try await post(
        endpoint: "projects/\(projectId.uuidString)/teamwork/tasks",
        body: ["feedbackIds": feedbackIds.map { $0.uuidString }]
    )
}

struct CreateTeamworkTaskResponse: Codable {
    let taskURL: String
    let taskId: String
}

struct BulkCreateTeamworkTasksResponse: Codable {
    let created: [CreatedTask]
    let failed: [FailedTask]

    struct CreatedTask: Codable {
        let feedbackId: UUID
        let taskURL: String
        let taskId: String
    }

    struct FailedTask: Codable {
        let feedbackId: UUID
        let error: String
    }
}
```

### 4.3 ViewModel Methods

Add to `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/ProjectViewModel.swift`:

```swift
// MARK: - Teamwork Integration

func updateTeamworkSettings(
    projectId: UUID,
    teamworkSiteName: String?,
    teamworkApiKey: String?,
    teamworkProjectId: String?,
    teamworkProjectName: String?,
    teamworkTasklistId: String?,
    teamworkTasklistName: String?,
    teamworkSyncStatus: Bool?,
    teamworkSyncComments: Bool?,
    teamworkVotesFieldId: String?,
    teamworkIsActive: Bool?
) async -> IntegrationUpdateResult {
    isLoading = true
    defer { isLoading = false }

    do {
        let updatedProject = try await apiClient.updateProjectTeamworkSettings(
            projectId: projectId,
            teamworkSiteName: teamworkSiteName,
            teamworkApiKey: teamworkApiKey,
            teamworkProjectId: teamworkProjectId,
            teamworkProjectName: teamworkProjectName,
            teamworkTasklistId: teamworkTasklistId,
            teamworkTasklistName: teamworkTasklistName,
            teamworkSyncStatus: teamworkSyncStatus,
            teamworkSyncComments: teamworkSyncComments,
            teamworkVotesFieldId: teamworkVotesFieldId,
            teamworkIsActive: teamworkIsActive
        )

        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index] = updatedProject
        }
        selectedProject = updatedProject

        return .success
    } catch let error as APIError {
        if case .httpError(let statusCode, _) = error, statusCode == 402 {
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

func loadTeamworkProjects(projectId: UUID) async -> [TeamworkProject] {
    do {
        return try await apiClient.getTeamworkProjects(projectId: projectId)
    } catch {
        return []
    }
}

func loadTeamworkTasklists(projectId: UUID, twProjectId: Int) async -> [TeamworkTasklist] {
    do {
        return try await apiClient.getTeamworkTasklists(projectId: projectId, twProjectId: twProjectId)
    } catch {
        return []
    }
}

func loadTeamworkCustomFields(projectId: UUID, twProjectId: Int) async -> [TeamworkCustomField] {
    do {
        return try await apiClient.getTeamworkCustomFields(projectId: projectId, twProjectId: twProjectId)
    } catch {
        return []
    }
}
```

### 4.4 Settings View

Create `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/TeamworkSettingsView.swift`:

```swift
import SwiftUI

struct TeamworkSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var siteName: String
    @State private var apiKey: String
    @State private var projectId: String
    @State private var projectName: String
    @State private var tasklistId: String
    @State private var tasklistName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var votesFieldId: String
    @State private var isActive: Bool
    @State private var showingApiKeyInfo = false

    // Picker state
    @State private var twProjects: [TeamworkProject] = []
    @State private var tasklists: [TeamworkTasklist] = []
    @State private var customFields: [TeamworkCustomField] = []
    @State private var selectedTwProject: TeamworkProject?
    @State private var selectedTasklist: TeamworkTasklist?
    @State private var selectedVotesField: TeamworkCustomField?

    @State private var isLoadingProjects = false
    @State private var isLoadingTasklists = false
    @State private var isLoadingCustomFields = false
    @State private var projectsError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _siteName = State(initialValue: project.teamworkSiteName ?? "")
        _apiKey = State(initialValue: project.teamworkApiKey ?? "")
        _projectId = State(initialValue: project.teamworkProjectId ?? "")
        _projectName = State(initialValue: project.teamworkProjectName ?? "")
        _tasklistId = State(initialValue: project.teamworkTasklistId ?? "")
        _tasklistName = State(initialValue: project.teamworkTasklistName ?? "")
        _syncStatus = State(initialValue: project.teamworkSyncStatus)
        _syncComments = State(initialValue: project.teamworkSyncComments)
        _votesFieldId = State(initialValue: project.teamworkVotesFieldId ?? "")
        _isActive = State(initialValue: project.teamworkIsActive)
    }

    private var hasChanges: Bool {
        siteName != (project.teamworkSiteName ?? "") ||
        apiKey != (project.teamworkApiKey ?? "") ||
        projectId != (project.teamworkProjectId ?? "") ||
        projectName != (project.teamworkProjectName ?? "") ||
        tasklistId != (project.teamworkTasklistId ?? "") ||
        tasklistName != (project.teamworkTasklistName ?? "") ||
        syncStatus != project.teamworkSyncStatus ||
        syncComments != project.teamworkSyncComments ||
        votesFieldId != (project.teamworkVotesFieldId ?? "") ||
        isActive != project.teamworkIsActive
    }

    private var isConfigured: Bool {
        !siteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tasklistId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasCredentials: Bool {
        !siteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isConfigured {
                    Section {
                        Toggle("Integration Active", isOn: $isActive)
                    } footer: {
                        Text("When disabled, Teamwork sync will be paused.")
                    }
                }

                Section {
                    TextField("Site Name", text: $siteName)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    SecureField("API Key", text: $apiKey)
                        .onChange(of: apiKey) { _, newValue in
                            if !newValue.isEmpty && !siteName.isEmpty && twProjects.isEmpty {
                                loadProjects()
                            }
                        }

                    Button {
                        showingApiKeyInfo = true
                    } label: {
                        Label("How to get your API key", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Enter your Teamwork site name (e.g., 'mycompany' from mycompany.teamwork.com) and API key.")
                }

                if hasCredentials {
                    Section {
                        if isLoadingProjects {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading projects...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = projectsError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                loadProjects()
                            }
                        } else {
                            Picker("Project", selection: $selectedTwProject) {
                                Text("Select Project").tag(nil as TeamworkProject?)
                                ForEach(twProjects) { proj in
                                    Text(proj.name).tag(proj as TeamworkProject?)
                                }
                            }
                            .onChange(of: selectedTwProject) { _, newValue in
                                if let proj = newValue {
                                    projectId = String(proj.id)
                                    projectName = proj.name
                                    loadTasklists(twProjectId: proj.id)
                                    loadCustomFields(twProjectId: proj.id)
                                } else {
                                    projectId = ""
                                    projectName = ""
                                    tasklists = []
                                    customFields = []
                                    selectedTasklist = nil
                                    selectedVotesField = nil
                                }
                            }
                        }
                    } header: {
                        Text("Target Project")
                    } footer: {
                        if !projectName.isEmpty {
                            Text("Selected: \(projectName)")
                        } else {
                            Text("Select the Teamwork project where tasks will be created.")
                        }
                    }
                }

                if !projectId.isEmpty {
                    Section {
                        if isLoadingTasklists {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading task lists...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Task List", selection: $selectedTasklist) {
                                Text("Select Task List").tag(nil as TeamworkTasklist?)
                                ForEach(tasklists) { list in
                                    Text(list.name).tag(list as TeamworkTasklist?)
                                }
                            }
                            .onChange(of: selectedTasklist) { _, newValue in
                                if let list = newValue {
                                    tasklistId = String(list.id)
                                    tasklistName = list.name
                                } else {
                                    tasklistId = ""
                                    tasklistName = ""
                                }
                            }
                        }
                    } header: {
                        Text("Target Task List")
                    } footer: {
                        if !tasklistName.isEmpty {
                            Text("Selected: \(tasklistName)")
                        } else {
                            Text("Select the task list where feedback items will be created as tasks.")
                        }
                    }
                }

                if isConfigured {
                    Section {
                        Toggle("Sync status changes", isOn: $syncStatus)
                        Toggle("Sync comments", isOn: $syncComments)
                    } header: {
                        Text("Sync Options")
                    } footer: {
                        Text("Automatically mark Teamwork tasks as complete when feedback is completed/rejected, and add comments to tasks when new comments are added to feedback.")
                    }

                    if !customFields.isEmpty {
                        let numberFields = customFields.filter { $0.type == "number" || $0.type == "numerical" }

                        if !numberFields.isEmpty {
                            Section {
                                Picker("Votes Field", selection: $selectedVotesField) {
                                    Text("None").tag(nil as TeamworkCustomField?)
                                    ForEach(numberFields) { field in
                                        Text(field.name).tag(field as TeamworkCustomField?)
                                    }
                                }
                                .onChange(of: selectedVotesField) { _, newValue in
                                    votesFieldId = newValue.map { String($0.id) } ?? ""
                                }
                            } header: {
                                Text("Vote Count Sync")
                            } footer: {
                                Text("Select a number-type custom field to sync vote counts.")
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            clearIntegration()
                        } label: {
                            Label("Remove Teamwork Integration", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Teamwork Integration")
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
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || viewModel.isLoading)
                }
            }
            .interactiveDismissDisabled(viewModel.isLoading)
            .overlay {
                if viewModel.isLoading {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .alert("Get Your Teamwork API Key", isPresented: $showingApiKeyInfo) {
                Button("Open Teamwork") {
                    let urlString = siteName.isEmpty
                        ? "https://www.teamwork.com"
                        : "https://\(siteName).teamwork.com"
                    if let url = URL(string: urlString) {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Log in to Teamwork\n2. Click your avatar > Settings\n3. Go to 'API & Webhooks'\n4. Create a new API key or copy an existing one")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasCredentials {
                    loadProjects()
                }
            }
        }
    }

    private func loadProjects() {
        guard hasCredentials else { return }

        isLoadingProjects = true
        projectsError = nil

        Task {
            // First save credentials so the API can use them
            let result = await viewModel.updateTeamworkSettings(
                projectId: project.id,
                teamworkSiteName: siteName.trimmingCharacters(in: .whitespacesAndNewlines),
                teamworkApiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                teamworkProjectId: nil,
                teamworkProjectName: nil,
                teamworkTasklistId: nil,
                teamworkTasklistName: nil,
                teamworkSyncStatus: nil,
                teamworkSyncComments: nil,
                teamworkVotesFieldId: nil,
                teamworkIsActive: nil
            )

            if result == .success {
                twProjects = await viewModel.loadTeamworkProjects(projectId: project.id)
                if twProjects.isEmpty {
                    projectsError = "No projects found. Check your site name and API key."
                } else {
                    // Pre-select if projectId is already set
                    if !projectId.isEmpty, let id = Int(projectId) {
                        selectedTwProject = twProjects.first { $0.id == id }
                        if selectedTwProject != nil {
                            loadTasklists(twProjectId: id)
                            loadCustomFields(twProjectId: id)
                        }
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                projectsError = viewModel.errorMessage ?? "Failed to verify credentials"
            }

            isLoadingProjects = false
        }
    }

    private func loadTasklists(twProjectId: Int) {
        isLoadingTasklists = true
        Task {
            tasklists = await viewModel.loadTeamworkTasklists(projectId: project.id, twProjectId: twProjectId)

            // Pre-select if tasklistId is already set
            if !tasklistId.isEmpty, let id = Int(tasklistId) {
                selectedTasklist = tasklists.first { $0.id == id }
            }

            isLoadingTasklists = false
        }
    }

    private func loadCustomFields(twProjectId: Int) {
        isLoadingCustomFields = true
        Task {
            customFields = await viewModel.loadTeamworkCustomFields(projectId: project.id, twProjectId: twProjectId)

            // Pre-select if votesFieldId is already set
            if !votesFieldId.isEmpty, let id = Int(votesFieldId) {
                selectedVotesField = customFields.first { $0.id == id }
            }

            isLoadingCustomFields = false
        }
    }

    private func clearIntegration() {
        siteName = ""
        apiKey = ""
        projectId = ""
        projectName = ""
        tasklistId = ""
        tasklistName = ""
        syncStatus = false
        syncComments = false
        votesFieldId = ""
        selectedTwProject = nil
        selectedTasklist = nil
        selectedVotesField = nil
        twProjects = []
        tasklists = []
        customFields = []
    }

    private func saveSettings() {
        Task {
            let trimmedSiteName = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateTeamworkSettings(
                projectId: project.id,
                teamworkSiteName: trimmedSiteName.isEmpty ? "" : trimmedSiteName,
                teamworkApiKey: trimmedApiKey.isEmpty ? "" : trimmedApiKey,
                teamworkProjectId: projectId.isEmpty ? "" : projectId,
                teamworkProjectName: projectName.isEmpty ? "" : projectName,
                teamworkTasklistId: tasklistId.isEmpty ? "" : tasklistId,
                teamworkTasklistName: tasklistName.isEmpty ? "" : tasklistName,
                teamworkSyncStatus: syncStatus,
                teamworkSyncComments: syncComments,
                teamworkVotesFieldId: votesFieldId.isEmpty ? "" : votesFieldId,
                teamworkIsActive: isActive
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

#Preview {
    TeamworkSettingsView(
        project: Project(
            id: UUID(),
            name: "Test Project",
            apiKey: "test-api-key",
            description: "A test description",
            ownerId: UUID(),
            ownerEmail: "test@example.com",
            isArchived: false,
            archivedAt: nil,
            colorIndex: 0,
            feedbackCount: 42,
            memberCount: 5,
            createdAt: Date(),
            updatedAt: Date(),
            slackWebhookUrl: nil,
            slackNotifyNewFeedback: true,
            slackNotifyNewComments: true,
            slackNotifyStatusChanges: true,
            allowedStatuses: ["pending", "approved", "in_progress", "completed", "rejected"]
        ),
        viewModel: ProjectViewModel()
    )
}
```

### 4.5 Add Menu Item

Update the project detail menu to include Teamwork integration option (in `ProjectDetailView.swift` or similar):

```swift
// Add to the integrations menu section
Button {
    showingTeamworkSettings = true
} label: {
    Label("Teamwork Integration", systemImage: "checklist")
}
.tierBadge(.pro)
```

Add state variable:
```swift
@State private var showingTeamworkSettings = false
```

Add sheet:
```swift
.sheet(isPresented: $showingTeamworkSettings) {
    TeamworkSettingsView(project: project, viewModel: viewModel)
}
```

---

## 5. Status Mapping

| FeedbackKit Status | Teamwork Status | Notes |
|-------------------|-----------------|-------|
| `pending` | Open (uncomplete) | Default state |
| `approved` | Open (uncomplete) | Task is active |
| `in_progress` | Open (uncomplete) | Task is being worked on |
| `testflight` | Open (uncomplete) | Task in review |
| `completed` | Complete | Task marked complete |
| `rejected` | Complete | Task marked complete (closed) |

**Note**: Teamwork uses a simpler complete/incomplete model rather than custom statuses. Tasks are either open or complete. For more granular status tracking, users should use Teamwork's board/column view or custom fields.

---

## 6. File Changes Summary

### Server Files

| File | Action | Description |
|------|--------|-------------|
| `Models/Project.swift` | Modify | Add Teamwork integration fields |
| `Models/Feedback.swift` | Modify | Add `teamworkTaskURL`, `teamworkTaskId` |
| `Services/TeamworkService.swift` | Create | New service for Teamwork API |
| `DTOs/ProjectDTO.swift` | Modify | Add Teamwork DTOs |
| `Controllers/ProjectController.swift` | Modify | Add Teamwork routes and handlers |
| `Controllers/FeedbackController.swift` | Modify | Add status sync logic |
| `Controllers/CommentController.swift` | Modify | Add comment sync logic |
| `Migrations/AddTeamworkIntegration.swift` | Create | Database migration |
| `configure.swift` | Modify | Register migration |

### Admin App Files

| File | Action | Description |
|------|--------|-------------|
| `Models/Project.swift` | Modify | Add Teamwork fields |
| `Models/TeamworkModels.swift` | Create | Teamwork response types |
| `Services/AdminAPIClient.swift` | Modify | Add Teamwork API methods |
| `ViewModels/ProjectViewModel.swift` | Modify | Add Teamwork methods |
| `Views/Projects/TeamworkSettingsView.swift` | Create | Settings UI |
| `Views/Projects/ProjectDetailView.swift` | Modify | Add menu item |

---

## 7. Testing Checklist

### Server Tests

- [ ] `TeamworkService.getProjects()` returns projects
- [ ] `TeamworkService.getTasklists()` returns task lists
- [ ] `TeamworkService.createTask()` creates task successfully
- [ ] `TeamworkService.completeTask()` marks task complete
- [ ] `TeamworkService.uncompleteTask()` marks task incomplete
- [ ] `TeamworkService.createComment()` adds comment
- [ ] `TeamworkService.updateCustomField()` updates vote count
- [ ] Settings update saves all fields correctly
- [ ] Settings update clears fields when empty strings passed
- [ ] Create task returns correct URL format
- [ ] Bulk create handles partial failures correctly
- [ ] Status sync triggers on feedback status change
- [ ] Comment sync triggers on new comment
- [ ] Vote count syncs on vote change
- [ ] 402 returned when user lacks Pro subscription
- [ ] Integration respects `isActive` flag

### Admin App Tests (iOS + macOS)

- [ ] Settings view loads correctly
- [ ] Site name and API key validation works
- [ ] Project picker loads and populates
- [ ] Task list picker loads after project selection
- [ ] Custom fields picker shows number fields only
- [ ] Sync toggles save correctly
- [ ] Remove integration clears all fields
- [ ] Paywall shows for non-Pro users
- [ ] Error states display correctly
- [ ] Loading states display correctly
- [ ] Changes detection works correctly
- [ ] Save button disabled when no changes
- [ ] Menu item shows tier badge

### Integration Tests

- [ ] End-to-end: Configure integration → Create task → Verify in Teamwork
- [ ] End-to-end: Change status → Verify task completion in Teamwork
- [ ] End-to-end: Add comment → Verify comment in Teamwork
- [ ] End-to-end: Add vote → Verify custom field update in Teamwork

---

## API Reference

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| PATCH | `/projects/:id/teamwork` | Update Teamwork settings |
| POST | `/projects/:id/teamwork/task` | Create single task |
| POST | `/projects/:id/teamwork/tasks` | Bulk create tasks |
| GET | `/projects/:id/teamwork/projects` | List Teamwork projects |
| GET | `/projects/:id/teamwork/projects/:twId/tasklists` | List task lists |
| GET | `/projects/:id/teamwork/projects/:twId/customfields` | List custom fields |

### Request/Response Examples

**Update Settings:**
```http
PATCH /projects/:id/teamwork
Authorization: Bearer <token>
Content-Type: application/json

{
  "teamworkSiteName": "mycompany",
  "teamworkApiKey": "tw_abc123...",
  "teamworkProjectId": "12345",
  "teamworkProjectName": "Product Feedback",
  "teamworkTasklistId": "67890",
  "teamworkTasklistName": "Backlog",
  "teamworkSyncStatus": true,
  "teamworkSyncComments": true,
  "teamworkVotesFieldId": "111",
  "teamworkIsActive": true
}
```

**Create Task:**
```http
POST /projects/:id/teamwork/task
Authorization: Bearer <token>
Content-Type: application/json

{
  "feedbackId": "uuid-here"
}
```

**Response:**
```json
{
  "taskURL": "https://mycompany.teamwork.com/app/tasks/12345",
  "taskId": "12345"
}
```

---

## Notes

1. **Teamwork API Version**: This implementation uses V3 endpoints where available, falling back to V1 for operations not yet available in V3 (complete/uncomplete, comments).

2. **Site Name**: Unlike other integrations that use a single API endpoint, Teamwork requires the customer's site name to construct the base URL.

3. **Status Sync Limitations**: Teamwork uses a binary complete/incomplete model. More granular status tracking requires board views or custom fields in Teamwork.

4. **Rate Limiting**: Implement exponential backoff for 429 responses. Consider adding request queuing for bulk operations.

5. **Custom Fields**: Vote count sync requires the user to create a number-type custom field in Teamwork first.
