# Basecamp Integration Technical Plan

This document outlines the complete technical implementation plan for integrating Basecamp with FeedbackKit, following the established patterns from existing integrations (Monday.com, ClickUp, Linear, GitHub, Notion).

## Table of Contents

1. [Overview](#overview)
2. [Basecamp API Analysis](#basecamp-api-analysis)
3. [Integration Features](#integration-features)
4. [Database Schema](#database-schema)
5. [Server Implementation](#server-implementation)
6. [Admin App Implementation](#admin-app-implementation)
7. [SDK Changes (if any)](#sdk-changes)
8. [Status Mapping](#status-mapping)
9. [Testing Strategy](#testing-strategy)
10. [Implementation Checklist](#implementation-checklist)

---

## Overview

### Integration Summary

| Feature | Support | Notes |
|---------|---------|-------|
| Push feedback to Basecamp | Yes | Creates To-dos in selected Todolist |
| Bulk create | Yes | Multiple feedbacks at once |
| Status sync | Yes | Complete/uncomplete to-dos |
| Comment sync | Yes | Add comments to to-dos |
| Vote count sync | No | Basecamp to-dos don't have custom number fields |
| Active toggle | Yes | Pause integration without removing config |

### Basecamp Concepts Mapping

| FeedbackKit Concept | Basecamp Concept |
|---------------------|------------------|
| Feedback | To-do |
| Project (in Basecamp context) | Basecamp Project (bucket) |
| List (destination) | Todolist |
| Comment | Comment on To-do |
| Status (completed/rejected) | To-do completion state |

---

## Basecamp API Analysis

### Authentication

Basecamp uses **OAuth 2.0** for authentication:

- **Authorization URL**: `https://launchpad.37signals.com/authorization/new`
- **Token URL**: `https://launchpad.37signals.com/authorization/token`
- **Token Lifetime**: 2 weeks (refresh tokens available)

**Required OAuth Parameters:**
```
Authorization Request:
- type=web_server
- client_id
- redirect_uri
- response_type=code

Token Exchange:
- type=web_server
- client_id
- client_secret
- redirect_uri
- code
```

**Note**: Unlike other integrations that use simple API tokens, Basecamp requires full OAuth flow. This adds complexity but provides better security.

**Alternative: Personal Access Tokens**
For simpler implementation, users can generate personal access tokens at `https://launchpad.37signals.com/personal_access_tokens`. This approach is recommended for v1 of this integration to maintain consistency with other integrations.

### Base URL Structure

```
https://3.basecampapi.com/{ACCOUNT_ID}/
```

The account ID is obtained from the authorization response after OAuth.

### Required Headers

```http
Authorization: Bearer {ACCESS_TOKEN}
User-Agent: FeedbackKit (support@feedbackkit.app)
Content-Type: application/json; charset=utf-8
```

**Important**: The `User-Agent` header is **mandatory** - omitting it results in 400 Bad Request.

### Rate Limiting

- **Limit**: 50 requests per 10 seconds per IP
- **Response**: 429 Too Many Requests with `Retry-After` header
- **Strategy**: Implement exponential backoff

### Key API Endpoints

#### Projects (Buckets)

```http
GET /projects.json
```

Returns list of projects with their `dock` containing tool URLs including todosets.

**Response Structure:**
```json
{
  "id": 12345,
  "name": "Project Name",
  "dock": [
    {
      "name": "todoset",
      "url": "https://3.basecampapi.com/{account}/buckets/{bucket}/todosets/{todoset_id}.json"
    }
  ]
}
```

#### Todosets

```http
GET /buckets/{bucket_id}/todosets/{todoset_id}.json
```

Returns todoset with `todolists_url` for accessing lists.

#### Todolists

```http
GET /buckets/{bucket_id}/todosets/{todoset_id}/todolists.json
POST /buckets/{bucket_id}/todosets/{todoset_id}/todolists.json
```

**Create Todolist:**
```json
{
  "name": "List Name",
  "description": "<div>Optional HTML description</div>"
}
```

#### Todos

```http
GET /buckets/{bucket_id}/todolists/{todolist_id}/todos.json
GET /buckets/{bucket_id}/todos/{todo_id}.json
POST /buckets/{bucket_id}/todolists/{todolist_id}/todos.json
PUT /buckets/{bucket_id}/todos/{todo_id}.json
```

**Create To-do Request:**
```json
{
  "content": "To-do title",
  "description": "<div>HTML description</div>",
  "assignee_ids": [123, 456],
  "due_on": "2025-12-31",
  "notify": true
}
```

**Response includes:**
- `id`, `content`, `description`
- `completed` (boolean)
- `completion_url` - endpoint for marking complete/incomplete
- `comments_url` - endpoint for adding comments
- `app_url` - web URL for the to-do

#### Completing/Uncompleting Todos

```http
POST /buckets/{bucket_id}/todos/{todo_id}/completion.json  # Complete
DELETE /buckets/{bucket_id}/todos/{todo_id}/completion.json  # Uncomplete
```

#### Comments

```http
GET /buckets/{bucket_id}/recordings/{recording_id}/comments.json
POST /buckets/{bucket_id}/recordings/{recording_id}/comments.json
```

**Create Comment:**
```json
{
  "content": "<div>HTML comment content</div>"
}
```

The `recording_id` for a to-do is the to-do's `id`.

---

## Integration Features

### Feature Matrix Comparison

| Feature | GitHub | ClickUp | Notion | Monday | Linear | Basecamp |
|---------|--------|---------|--------|--------|--------|----------|
| Create items | Issue | Task | Page | Item | Issue | To-do |
| Bulk create | Yes | Yes | Yes | Yes | Yes | Yes |
| Status sync | Close/Reopen | Status field | Status property | Status column | Workflow state | Complete/Uncomplete |
| Comment sync | No | Yes | Yes | Yes | Yes | Yes |
| Vote count sync | No | Custom field | Number property | Number column | No | No |
| Labels/Tags | Yes | Yes | No | No | Yes | No |
| Custom fields | No | Yes | Yes | Yes | No | No |

### Supported Operations

1. **Create To-do**: Transform feedback into Basecamp to-do
2. **Bulk Create**: Create multiple to-dos at once
3. **Complete To-do**: When feedback status → `completed`
4. **Uncomplete To-do**: When feedback status → anything except `completed`/`rejected`
5. **Add Comment**: Sync FeedbackKit comments to Basecamp

### Status Sync Behavior

Since Basecamp only has complete/incomplete states (no custom statuses):

| FeedbackKit Status | Basecamp State | Action |
|-------------------|----------------|--------|
| pending | Incomplete | Uncomplete to-do |
| approved | Incomplete | Uncomplete to-do |
| in_progress | Incomplete | Uncomplete to-do |
| testflight | Incomplete | Uncomplete to-do |
| completed | Complete | Complete to-do |
| rejected | Complete | Complete to-do (with note) |

---

## Database Schema

### Migration: `AddProjectBasecampIntegration.swift`

```swift
import Fluent

struct AddProjectBasecampIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Basecamp fields to projects table
        try await database.schema("projects")
            .field("basecamp_access_token", .string)
            .field("basecamp_refresh_token", .string)
            .field("basecamp_token_expires_at", .datetime)
            .field("basecamp_account_id", .string)
            .field("basecamp_account_name", .string)
            .field("basecamp_project_id", .string)
            .field("basecamp_project_name", .string)
            .field("basecamp_todoset_id", .string)
            .field("basecamp_todolist_id", .string)
            .field("basecamp_todolist_name", .string)
            .field("basecamp_sync_status", .bool, .required, .sql(.default(false)))
            .field("basecamp_sync_comments", .bool, .required, .sql(.default(false)))
            .field("basecamp_is_active", .bool, .required, .sql(.default(false)))
            .update()

        // Add Basecamp fields to feedbacks table
        try await database.schema("feedbacks")
            .field("basecamp_todo_url", .string)
            .field("basecamp_todo_id", .string)
            .field("basecamp_bucket_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("basecamp_access_token")
            .deleteField("basecamp_refresh_token")
            .deleteField("basecamp_token_expires_at")
            .deleteField("basecamp_account_id")
            .deleteField("basecamp_account_name")
            .deleteField("basecamp_project_id")
            .deleteField("basecamp_project_name")
            .deleteField("basecamp_todoset_id")
            .deleteField("basecamp_todolist_id")
            .deleteField("basecamp_todolist_name")
            .deleteField("basecamp_sync_status")
            .deleteField("basecamp_sync_comments")
            .deleteField("basecamp_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("basecamp_todo_url")
            .deleteField("basecamp_todo_id")
            .deleteField("basecamp_bucket_id")
            .update()
    }
}
```

### Project Model Additions

```swift
// Basecamp integration fields
@OptionalField(key: "basecamp_access_token")
var basecampAccessToken: String?

@OptionalField(key: "basecamp_refresh_token")
var basecampRefreshToken: String?

@OptionalField(key: "basecamp_token_expires_at")
var basecampTokenExpiresAt: Date?

@OptionalField(key: "basecamp_account_id")
var basecampAccountId: String?

@OptionalField(key: "basecamp_account_name")
var basecampAccountName: String?

@OptionalField(key: "basecamp_project_id")
var basecampProjectId: String?

@OptionalField(key: "basecamp_project_name")
var basecampProjectName: String?

@OptionalField(key: "basecamp_todoset_id")
var basecampTodosetId: String?

@OptionalField(key: "basecamp_todolist_id")
var basecampTodolistId: String?

@OptionalField(key: "basecamp_todolist_name")
var basecampTodolistName: String?

@Field(key: "basecamp_sync_status")
var basecampSyncStatus: Bool

@Field(key: "basecamp_sync_comments")
var basecampSyncComments: Bool

@Field(key: "basecamp_is_active")
var basecampIsActive: Bool
```

### Feedback Model Additions

```swift
// Basecamp integration fields
@OptionalField(key: "basecamp_todo_url")
var basecampTodoURL: String?

@OptionalField(key: "basecamp_todo_id")
var basecampTodoId: String?

@OptionalField(key: "basecamp_bucket_id")
var basecampBucketId: String?

/// Whether this feedback has a linked Basecamp to-do
var hasBasecampTodo: Bool {
    basecampTodoURL != nil
}
```

---

## Server Implementation

### 1. BasecampService (`Services/BasecampService.swift`)

```swift
import Vapor

struct BasecampService {
    private let client: Client
    private let launchpadURL = "https://launchpad.37signals.com"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct BasecampAccount: Codable {
        let id: Int
        let name: String
        let href: String
        let product: String
    }

    struct BasecampProject: Codable {
        let id: Int
        let name: String
        let description: String?
        let dock: [DockItem]
        let appUrl: String

        enum CodingKeys: String, CodingKey {
            case id, name, description, dock
            case appUrl = "app_url"
        }

        struct DockItem: Codable {
            let name: String
            let url: String
            let enabled: Bool
        }

        var todosetURL: String? {
            dock.first { $0.name == "todoset" && $0.enabled }?.url
        }
    }

    struct BasecampTodoset: Codable {
        let id: Int
        let todolistsUrl: String
        let todolistsCount: Int

        enum CodingKeys: String, CodingKey {
            case id
            case todolistsUrl = "todolists_url"
            case todolistsCount = "todolists_count"
        }
    }

    struct BasecampTodolist: Codable {
        let id: Int
        let name: String
        let description: String?
        let todosUrl: String
        let appUrl: String

        enum CodingKeys: String, CodingKey {
            case id, name, description
            case todosUrl = "todos_url"
            case appUrl = "app_url"
        }
    }

    struct BasecampTodo: Codable {
        let id: Int
        let content: String
        let description: String?
        let completed: Bool
        let completionUrl: String
        let commentsUrl: String
        let commentsCount: Int
        let appUrl: String

        enum CodingKeys: String, CodingKey {
            case id, content, description, completed
            case completionUrl = "completion_url"
            case commentsUrl = "comments_url"
            case commentsCount = "comments_count"
            case appUrl = "app_url"
        }
    }

    struct BasecampComment: Codable {
        let id: Int
        let content: String
    }

    struct AuthorizationResponse: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    struct AuthorizationInfo: Codable {
        let identity: Identity
        let accounts: [BasecampAccount]

        struct Identity: Codable {
            let id: Int
            let firstName: String
            let lastName: String
            let emailAddress: String

            enum CodingKeys: String, CodingKey {
                case id
                case firstName = "first_name"
                case lastName = "last_name"
                case emailAddress = "email_address"
            }
        }
    }

    // MARK: - OAuth Methods

    func exchangeCodeForToken(
        code: String,
        clientId: String,
        clientSecret: String,
        redirectUri: String
    ) async throws -> AuthorizationResponse {
        let response = try await client.post(URI(string: "\(launchpadURL)/authorization/token")) { req in
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
            req.body = ByteBuffer(string: "type=web_server&client_id=\(clientId)&client_secret=\(clientSecret)&redirect_uri=\(redirectUri)&code=\(code)")
        }

        guard response.status == .ok, let body = response.body else {
            throw Abort(.badGateway, reason: "Failed to exchange Basecamp authorization code")
        }

        return try JSONDecoder().decode(AuthorizationResponse.self, from: Data(buffer: body))
    }

    func refreshAccessToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String
    ) async throws -> AuthorizationResponse {
        let response = try await client.post(URI(string: "\(launchpadURL)/authorization/token")) { req in
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
            req.body = ByteBuffer(string: "type=refresh&refresh_token=\(refreshToken)&client_id=\(clientId)&client_secret=\(clientSecret)")
        }

        guard response.status == .ok, let body = response.body else {
            throw Abort(.badGateway, reason: "Failed to refresh Basecamp token")
        }

        return try JSONDecoder().decode(AuthorizationResponse.self, from: Data(buffer: body))
    }

    func getAuthorizationInfo(accessToken: String) async throws -> AuthorizationInfo {
        let response = try await client.get(URI(string: "\(launchpadURL)/authorization.json")) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            req.headers.add(name: "User-Agent", value: "FeedbackKit (support@feedbackkit.app)")
        }

        guard response.status == .ok, let body = response.body else {
            throw Abort(.badGateway, reason: "Failed to get Basecamp authorization info")
        }

        return try JSONDecoder().decode(AuthorizationInfo.self, from: Data(buffer: body))
    }

    // MARK: - API Methods

    private func makeRequest<T: Decodable>(
        method: HTTPMethod = .GET,
        url: String,
        accessToken: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        let uri = URI(string: url)

        let response: ClientResponse
        switch method {
        case .GET:
            response = try await client.get(uri) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                req.headers.add(name: "User-Agent", value: "FeedbackKit (support@feedbackkit.app)")
            }
        case .POST:
            response = try await client.post(uri) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                req.headers.add(name: "User-Agent", value: "FeedbackKit (support@feedbackkit.app)")
                req.headers.add(name: .contentType, value: "application/json; charset=utf-8")
                if let body = body {
                    req.body = ByteBuffer(data: try JSONSerialization.data(withJSONObject: body))
                }
            }
        case .DELETE:
            response = try await client.delete(uri) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
                req.headers.add(name: "User-Agent", value: "FeedbackKit (support@feedbackkit.app)")
            }
        default:
            throw Abort(.internalServerError, reason: "Unsupported HTTP method")
        }

        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Basecamp API returned empty response")
        }

        let data = Data(buffer: bodyData)

        guard response.status.code >= 200 && response.status.code < 300 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Basecamp API error (\(response.status)): \(responseBody)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Projects

    func getProjects(accountId: String, accessToken: String) async throws -> [BasecampProject] {
        let url = "https://3.basecampapi.com/\(accountId)/projects.json"
        return try await makeRequest(url: url, accessToken: accessToken)
    }

    func getProject(accountId: String, projectId: String, accessToken: String) async throws -> BasecampProject {
        let url = "https://3.basecampapi.com/\(accountId)/projects/\(projectId).json"
        return try await makeRequest(url: url, accessToken: accessToken)
    }

    // MARK: - Todosets & Todolists

    func getTodoset(url: String, accessToken: String) async throws -> BasecampTodoset {
        return try await makeRequest(url: url, accessToken: accessToken)
    }

    func getTodolists(url: String, accessToken: String) async throws -> [BasecampTodolist] {
        return try await makeRequest(url: url, accessToken: accessToken)
    }

    func getTodolists(
        accountId: String,
        bucketId: String,
        todosetId: String,
        accessToken: String
    ) async throws -> [BasecampTodolist] {
        let url = "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/todosets/\(todosetId)/todolists.json"
        return try await makeRequest(url: url, accessToken: accessToken)
    }

    // MARK: - Todos

    func createTodo(
        accountId: String,
        bucketId: String,
        todolistId: String,
        accessToken: String,
        content: String,
        description: String?
    ) async throws -> BasecampTodo {
        let url = "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/todolists/\(todolistId)/todos.json"

        var body: [String: Any] = ["content": content]
        if let description = description {
            body["description"] = description
        }

        return try await makeRequest(method: .POST, url: url, accessToken: accessToken, body: body)
    }

    func completeTodo(
        accountId: String,
        bucketId: String,
        todoId: String,
        accessToken: String
    ) async throws {
        let url = "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/todos/\(todoId)/completion.json"

        let response = try await client.post(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            req.headers.add(name: "User-Agent", value: "FeedbackKit (support@feedbackkit.app)")
        }

        guard response.status.code >= 200 && response.status.code < 300 else {
            throw Abort(.badGateway, reason: "Failed to complete Basecamp to-do")
        }
    }

    func uncompleteTodo(
        accountId: String,
        bucketId: String,
        todoId: String,
        accessToken: String
    ) async throws {
        let url = "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/todos/\(todoId)/completion.json"

        let response = try await client.delete(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            req.headers.add(name: "User-Agent", value: "FeedbackKit (support@feedbackkit.app)")
        }

        guard response.status.code >= 200 && response.status.code < 300 else {
            throw Abort(.badGateway, reason: "Failed to uncomplete Basecamp to-do")
        }
    }

    // MARK: - Comments

    func createComment(
        accountId: String,
        bucketId: String,
        todoId: String,
        accessToken: String,
        content: String
    ) async throws -> BasecampComment {
        let url = "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/recordings/\(todoId)/comments.json"
        let body: [String: Any] = ["content": content]
        return try await makeRequest(method: .POST, url: url, accessToken: accessToken, body: body)
    }

    // MARK: - Content Builders

    func buildTodoDescription(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var html = """
        <div>
            <strong>\(escapeHtml(feedback.category.displayName))</strong>
            <br><br>
            \(escapeHtml(feedback.description))
            <br><br>
            <hr>
            <p>
                <strong>Source:</strong> FeedbackKit<br>
                <strong>Project:</strong> \(escapeHtml(projectName))<br>
                <strong>Votes:</strong> \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            html += "<br><strong>MRR:</strong> $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            html += "<br><strong>Submitted by:</strong> \(escapeHtml(userEmail))"
        }

        html += """
            </p>
        </div>
        """

        return html
    }

    func buildCommentContent(authorName: String?, content: String) -> String {
        var html = "<div>"
        if let name = authorName {
            html += "<strong>\(escapeHtml(name))</strong> commented via FeedbackKit:<br><br>"
        }
        html += "\(escapeHtml(content))</div>"
        return html
    }

    private func escapeHtml(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Request Extension

extension Request {
    var basecampService: BasecampService {
        BasecampService(client: self.client)
    }
}
```

### 2. DTOs (`DTOs/BasecampDTOs.swift`)

```swift
import Vapor

// MARK: - Request DTOs

struct UpdateProjectBasecampDTO: Content {
    var basecampAccessToken: String?
    var basecampRefreshToken: String?
    var basecampTokenExpiresAt: Date?
    var basecampAccountId: String?
    var basecampAccountName: String?
    var basecampProjectId: String?
    var basecampProjectName: String?
    var basecampTodosetId: String?
    var basecampTodolistId: String?
    var basecampTodolistName: String?
    var basecampSyncStatus: Bool?
    var basecampSyncComments: Bool?
    var basecampIsActive: Bool?
}

struct CreateBasecampTodoDTO: Content {
    let feedbackId: UUID
}

struct BulkCreateBasecampTodosDTO: Content {
    let feedbackIds: [UUID]
}

// MARK: - Response DTOs

struct BasecampAccountDTO: Content {
    let id: Int
    let name: String
}

struct BasecampProjectDTO: Content {
    let id: Int
    let name: String
    let todosetId: String?
}

struct BasecampTodolistDTO: Content {
    let id: Int
    let name: String
}

struct CreateBasecampTodoResponseDTO: Content {
    let todoId: String
    let todoUrl: String
}

struct BulkCreateBasecampTodosResponseDTO: Content {
    let created: [UUID]
    let failed: [UUID]
    let alreadyLinked: [UUID]
}
```

### 3. ProjectController Routes

Add to `ProjectController.swift`:

```swift
// In boot(routes:) method:

// Basecamp integration
protected.patch(":projectId", "basecamp", use: updateBasecampSettings)
protected.post(":projectId", "basecamp", "todo", use: createBasecampTodo)
protected.post(":projectId", "basecamp", "todos", use: bulkCreateBasecampTodos)
protected.get(":projectId", "basecamp", "accounts", use: getBasecampAccounts)
protected.get(":projectId", "basecamp", "projects", use: getBasecampProjects)
protected.get(":projectId", "basecamp", "todolists", use: getBasecampTodolists)
```

### 4. ProjectController Methods

```swift
// MARK: - Basecamp Integration

@Sendable
func updateBasecampSettings(req: Request) async throws -> ProjectResponseDTO {
    let user = try req.auth.require(User.self)

    // Check Pro tier requirement for integrations
    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Basecamp integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)
    let dto = try req.content.decode(UpdateProjectBasecampDTO.self)

    if let accessToken = dto.basecampAccessToken {
        project.basecampAccessToken = accessToken.isEmpty ? nil : accessToken
    }
    if let refreshToken = dto.basecampRefreshToken {
        project.basecampRefreshToken = refreshToken.isEmpty ? nil : refreshToken
    }
    if let expiresAt = dto.basecampTokenExpiresAt {
        project.basecampTokenExpiresAt = expiresAt
    }
    if let accountId = dto.basecampAccountId {
        project.basecampAccountId = accountId.isEmpty ? nil : accountId
    }
    if let accountName = dto.basecampAccountName {
        project.basecampAccountName = accountName.isEmpty ? nil : accountName
    }
    if let projectId = dto.basecampProjectId {
        project.basecampProjectId = projectId.isEmpty ? nil : projectId
    }
    if let projectName = dto.basecampProjectName {
        project.basecampProjectName = projectName.isEmpty ? nil : projectName
    }
    if let todosetId = dto.basecampTodosetId {
        project.basecampTodosetId = todosetId.isEmpty ? nil : todosetId
    }
    if let todolistId = dto.basecampTodolistId {
        project.basecampTodolistId = todolistId.isEmpty ? nil : todolistId
    }
    if let todolistName = dto.basecampTodolistName {
        project.basecampTodolistName = todolistName.isEmpty ? nil : todolistName
    }
    if let syncStatus = dto.basecampSyncStatus {
        project.basecampSyncStatus = syncStatus
    }
    if let syncComments = dto.basecampSyncComments {
        project.basecampSyncComments = syncComments
    }
    if let isActive = dto.basecampIsActive {
        project.basecampIsActive = isActive
    }

    try await project.save(on: req.db)

    try await project.$feedbacks.load(on: req.db)
    try await project.$members.load(on: req.db)
    try await project.$owner.load(on: req.db)

    return ProjectResponseDTO(
        project: project,
        feedbackCount: project.feedbacks.count,
        memberCount: project.members.count + 1,
        ownerEmail: project.owner.email
    )
}

@Sendable
func createBasecampTodo(req: Request) async throws -> CreateBasecampTodoResponseDTO {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let accessToken = project.basecampAccessToken,
          let accountId = project.basecampAccountId,
          let projectId = project.basecampProjectId,
          let todolistId = project.basecampTodolistId else {
        throw Abort(.badRequest, reason: "Basecamp integration not configured")
    }

    let dto = try req.content.decode(CreateBasecampTodoDTO.self)

    guard let feedback = try await Feedback.query(on: req.db)
        .filter(\.$id == dto.feedbackId)
        .filter(\.$project.$id == project.id!)
        .with(\.$votes)
        .first() else {
        throw Abort(.notFound, reason: "Feedback not found")
    }

    if feedback.basecampTodoURL != nil {
        throw Abort(.conflict, reason: "Feedback already has a Basecamp to-do")
    }

    // Calculate MRR
    let voterIds = feedback.votes.compactMap { $0.sdkUserId }
    let sdkUsers = try await SDKUser.query(on: req.db)
        .filter(\.$id ~~ voterIds)
        .all()
    let totalMRR = sdkUsers.reduce(0.0) { $0 + ($1.mrr ?? 0) }

    // Create the to-do
    let todo = try await req.basecampService.createTodo(
        accountId: accountId,
        bucketId: projectId,
        todolistId: todolistId,
        accessToken: accessToken,
        content: feedback.title,
        description: req.basecampService.buildTodoDescription(
            feedback: feedback,
            projectName: project.name,
            voteCount: feedback.voteCount,
            mrr: totalMRR > 0 ? totalMRR : nil
        )
    )

    // Save link to feedback
    feedback.basecampTodoURL = todo.appUrl
    feedback.basecampTodoId = String(todo.id)
    feedback.basecampBucketId = projectId
    try await feedback.save(on: req.db)

    // Set initial completion status if needed (fire and forget)
    if feedback.status == .completed || feedback.status == .rejected {
        Task {
            try? await req.basecampService.completeTodo(
                accountId: accountId,
                bucketId: projectId,
                todoId: String(todo.id),
                accessToken: accessToken
            )
        }
    }

    return CreateBasecampTodoResponseDTO(
        todoId: String(todo.id),
        todoUrl: todo.appUrl
    )
}

@Sendable
func bulkCreateBasecampTodos(req: Request) async throws -> BulkCreateBasecampTodosResponseDTO {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let accessToken = project.basecampAccessToken,
          let accountId = project.basecampAccountId,
          let projectId = project.basecampProjectId,
          let todolistId = project.basecampTodolistId else {
        throw Abort(.badRequest, reason: "Basecamp integration not configured")
    }

    let dto = try req.content.decode(BulkCreateBasecampTodosDTO.self)

    var created: [UUID] = []
    var failed: [UUID] = []
    var alreadyLinked: [UUID] = []

    for feedbackId in dto.feedbackIds {
        do {
            guard let feedback = try await Feedback.query(on: req.db)
                .filter(\.$id == feedbackId)
                .filter(\.$project.$id == project.id!)
                .with(\.$votes)
                .first() else {
                failed.append(feedbackId)
                continue
            }

            if feedback.basecampTodoURL != nil {
                alreadyLinked.append(feedbackId)
                continue
            }

            // Calculate MRR
            let voterIds = feedback.votes.compactMap { $0.sdkUserId }
            let sdkUsers = try await SDKUser.query(on: req.db)
                .filter(\.$id ~~ voterIds)
                .all()
            let totalMRR = sdkUsers.reduce(0.0) { $0 + ($1.mrr ?? 0) }

            let todo = try await req.basecampService.createTodo(
                accountId: accountId,
                bucketId: projectId,
                todolistId: todolistId,
                accessToken: accessToken,
                content: feedback.title,
                description: req.basecampService.buildTodoDescription(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: totalMRR > 0 ? totalMRR : nil
                )
            )

            feedback.basecampTodoURL = todo.appUrl
            feedback.basecampTodoId = String(todo.id)
            feedback.basecampBucketId = projectId
            try await feedback.save(on: req.db)

            created.append(feedbackId)
        } catch {
            failed.append(feedbackId)
        }
    }

    return BulkCreateBasecampTodosResponseDTO(
        created: created,
        failed: failed,
        alreadyLinked: alreadyLinked
    )
}

@Sendable
func getBasecampAccounts(req: Request) async throws -> [BasecampAccountDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let accessToken = project.basecampAccessToken else {
        throw Abort(.badRequest, reason: "Basecamp token not configured")
    }

    let authInfo = try await req.basecampService.getAuthorizationInfo(accessToken: accessToken)

    // Filter to only Basecamp 4 accounts
    return authInfo.accounts
        .filter { $0.product == "bc3" }
        .map { BasecampAccountDTO(id: $0.id, name: $0.name) }
}

@Sendable
func getBasecampProjects(req: Request) async throws -> [BasecampProjectDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let accessToken = project.basecampAccessToken,
          let accountId = project.basecampAccountId else {
        throw Abort(.badRequest, reason: "Basecamp account not configured")
    }

    let projects = try await req.basecampService.getProjects(
        accountId: accountId,
        accessToken: accessToken
    )

    return projects.map { bcProject in
        // Extract todoset ID from dock URL
        var todosetId: String?
        if let todosetURL = bcProject.todosetURL,
           let range = todosetURL.range(of: "/todosets/"),
           let endRange = todosetURL.range(of: ".json", range: range.upperBound..<todosetURL.endIndex) {
            todosetId = String(todosetURL[range.upperBound..<endRange.lowerBound])
        }

        return BasecampProjectDTO(
            id: bcProject.id,
            name: bcProject.name,
            todosetId: todosetId
        )
    }
}

@Sendable
func getBasecampTodolists(req: Request) async throws -> [BasecampTodolistDTO] {
    let user = try req.auth.require(User.self)
    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let accessToken = project.basecampAccessToken,
          let accountId = project.basecampAccountId,
          let bucketId = project.basecampProjectId,
          let todosetId = project.basecampTodosetId else {
        throw Abort(.badRequest, reason: "Basecamp project not configured")
    }

    let todolists = try await req.basecampService.getTodolists(
        accountId: accountId,
        bucketId: bucketId,
        todosetId: todosetId,
        accessToken: accessToken
    )

    return todolists.map { BasecampTodolistDTO(id: $0.id, name: $0.name) }
}
```

### 5. FeedbackController Status Sync

Add to `updateFeedback` in `FeedbackController.swift`:

```swift
// After status update, sync to Basecamp
if project.basecampIsActive && project.basecampSyncStatus,
   let accessToken = project.basecampAccessToken,
   let accountId = project.basecampAccountId,
   let todoId = feedback.basecampTodoId,
   let bucketId = feedback.basecampBucketId {

    Task {
        do {
            if newStatus == .completed || newStatus == .rejected {
                try await req.basecampService.completeTodo(
                    accountId: accountId,
                    bucketId: bucketId,
                    todoId: todoId,
                    accessToken: accessToken
                )
            } else {
                try await req.basecampService.uncompleteTodo(
                    accountId: accountId,
                    bucketId: bucketId,
                    todoId: todoId,
                    accessToken: accessToken
                )
            }
        } catch {
            req.logger.error("Failed to sync Basecamp status: \(error)")
        }
    }
}
```

### 6. CommentController Sync

Add to `createComment` in `CommentController.swift`:

```swift
// Sync to Basecamp
if project.basecampIsActive && project.basecampSyncComments,
   let accessToken = project.basecampAccessToken,
   let accountId = project.basecampAccountId,
   let todoId = feedback.basecampTodoId,
   let bucketId = feedback.basecampBucketId {

    Task {
        do {
            let content = req.basecampService.buildCommentContent(
                authorName: user.name,
                content: comment.content
            )
            _ = try await req.basecampService.createComment(
                accountId: accountId,
                bucketId: bucketId,
                todoId: todoId,
                accessToken: accessToken,
                content: content
            )
        } catch {
            req.logger.error("Failed to sync comment to Basecamp: \(error)")
        }
    }
}
```

---

## Admin App Implementation

### 1. Models (`Models/Basecamp.swift`)

```swift
import Foundation

struct BasecampAccount: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct BasecampProject: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let todosetId: String?
}

struct BasecampTodolist: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}
```

### 2. Update Project Model

Add to `Project.swift`:

```swift
// Basecamp integration
var basecampAccessToken: String?
var basecampAccountId: String?
var basecampAccountName: String?
var basecampProjectId: String?
var basecampProjectName: String?
var basecampTodosetId: String?
var basecampTodolistId: String?
var basecampTodolistName: String?
var basecampSyncStatus: Bool
var basecampSyncComments: Bool
var basecampIsActive: Bool

var hasBasecampIntegration: Bool {
    basecampAccessToken != nil && basecampTodolistId != nil
}

enum CodingKeys: String, CodingKey {
    // ... existing keys ...
    case basecampAccessToken = "basecamp_access_token"
    case basecampAccountId = "basecamp_account_id"
    case basecampAccountName = "basecamp_account_name"
    case basecampProjectId = "basecamp_project_id"
    case basecampProjectName = "basecamp_project_name"
    case basecampTodosetId = "basecamp_todoset_id"
    case basecampTodolistId = "basecamp_todolist_id"
    case basecampTodolistName = "basecamp_todolist_name"
    case basecampSyncStatus = "basecamp_sync_status"
    case basecampSyncComments = "basecamp_sync_comments"
    case basecampIsActive = "basecamp_is_active"
}
```

### 3. Update Feedback Model

Add to `Feedback.swift`:

```swift
var basecampTodoUrl: String?
var basecampTodoId: String?

var hasBasecampTodo: Bool {
    basecampTodoUrl != nil
}

enum CodingKeys: String, CodingKey {
    // ... existing keys ...
    case basecampTodoUrl = "basecamp_todo_url"
    case basecampTodoId = "basecamp_todo_id"
}
```

### 4. ProjectViewModel Methods

Add to `ProjectViewModel.swift`:

```swift
// MARK: - Basecamp Integration

func updateBasecampSettings(
    projectId: UUID,
    basecampAccessToken: String?,
    basecampAccountId: String?,
    basecampAccountName: String?,
    basecampProjectId: String?,
    basecampProjectName: String?,
    basecampTodosetId: String?,
    basecampTodolistId: String?,
    basecampTodolistName: String?,
    basecampSyncStatus: Bool?,
    basecampSyncComments: Bool?,
    basecampIsActive: Bool?
) async -> UpdateResult {
    isLoading = true
    defer { isLoading = false }

    do {
        var body: [String: Any] = [:]
        if let token = basecampAccessToken { body["basecampAccessToken"] = token }
        if let accountId = basecampAccountId { body["basecampAccountId"] = accountId }
        if let accountName = basecampAccountName { body["basecampAccountName"] = accountName }
        if let projectId = basecampProjectId { body["basecampProjectId"] = projectId }
        if let projectName = basecampProjectName { body["basecampProjectName"] = projectName }
        if let todosetId = basecampTodosetId { body["basecampTodosetId"] = todosetId }
        if let todolistId = basecampTodolistId { body["basecampTodolistId"] = todolistId }
        if let todolistName = basecampTodolistName { body["basecampTodolistName"] = todolistName }
        if let syncStatus = basecampSyncStatus { body["basecampSyncStatus"] = syncStatus }
        if let syncComments = basecampSyncComments { body["basecampSyncComments"] = syncComments }
        if let isActive = basecampIsActive { body["basecampIsActive"] = isActive }

        let project: Project = try await apiClient.patch(
            "projects/\(projectId)/basecamp",
            body: body
        )

        await MainActor.run {
            if let index = projects.firstIndex(where: { $0.id == projectId }) {
                projects[index] = project
            }
            selectedProject = project
        }

        return .success
    } catch let error as APIError {
        return handleAPIError(error)
    } catch {
        errorMessage = error.localizedDescription
        showError = true
        return .otherError
    }
}

func loadBasecampAccounts(projectId: UUID) async -> [BasecampAccount] {
    do {
        return try await apiClient.get("projects/\(projectId)/basecamp/accounts")
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadBasecampProjects(projectId: UUID) async -> [BasecampProject] {
    do {
        return try await apiClient.get("projects/\(projectId)/basecamp/projects")
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadBasecampTodolists(projectId: UUID) async -> [BasecampTodolist] {
    do {
        return try await apiClient.get("projects/\(projectId)/basecamp/todolists")
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func createBasecampTodo(projectId: UUID, feedbackId: UUID) async -> Bool {
    isLoading = true
    defer { isLoading = false }

    do {
        let _: CreateBasecampTodoResponse = try await apiClient.post(
            "projects/\(projectId)/basecamp/todo",
            body: ["feedbackId": feedbackId.uuidString]
        )
        return true
    } catch {
        errorMessage = error.localizedDescription
        showError = true
        return false
    }
}

func bulkCreateBasecampTodos(projectId: UUID, feedbackIds: [UUID]) async -> BulkCreateResult? {
    isLoading = true
    defer { isLoading = false }

    do {
        return try await apiClient.post(
            "projects/\(projectId)/basecamp/todos",
            body: ["feedbackIds": feedbackIds.map { $0.uuidString }]
        )
    } catch {
        errorMessage = error.localizedDescription
        showError = true
        return nil
    }
}
```

### 5. BasecampSettingsView (`Views/Projects/BasecampSettingsView.swift`)

```swift
import SwiftUI

struct BasecampSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var accessToken: String
    @State private var accountId: String
    @State private var accountName: String
    @State private var basecampProjectId: String
    @State private var basecampProjectName: String
    @State private var todosetId: String
    @State private var todolistId: String
    @State private var todolistName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var isActive: Bool
    @State private var showingTokenInfo = false

    // Selection state
    @State private var accounts: [BasecampAccount] = []
    @State private var basecampProjects: [BasecampProject] = []
    @State private var todolists: [BasecampTodolist] = []
    @State private var selectedAccount: BasecampAccount?
    @State private var selectedProject: BasecampProject?
    @State private var selectedTodolist: BasecampTodolist?

    @State private var isLoadingAccounts = false
    @State private var isLoadingProjects = false
    @State private var isLoadingTodolists = false
    @State private var accountsError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _accessToken = State(initialValue: project.basecampAccessToken ?? "")
        _accountId = State(initialValue: project.basecampAccountId ?? "")
        _accountName = State(initialValue: project.basecampAccountName ?? "")
        _basecampProjectId = State(initialValue: project.basecampProjectId ?? "")
        _basecampProjectName = State(initialValue: project.basecampProjectName ?? "")
        _todosetId = State(initialValue: project.basecampTodosetId ?? "")
        _todolistId = State(initialValue: project.basecampTodolistId ?? "")
        _todolistName = State(initialValue: project.basecampTodolistName ?? "")
        _syncStatus = State(initialValue: project.basecampSyncStatus)
        _syncComments = State(initialValue: project.basecampSyncComments)
        _isActive = State(initialValue: project.basecampIsActive)
    }

    private var hasChanges: Bool {
        accessToken != (project.basecampAccessToken ?? "") ||
        accountId != (project.basecampAccountId ?? "") ||
        accountName != (project.basecampAccountName ?? "") ||
        basecampProjectId != (project.basecampProjectId ?? "") ||
        basecampProjectName != (project.basecampProjectName ?? "") ||
        todosetId != (project.basecampTodosetId ?? "") ||
        todolistId != (project.basecampTodolistId ?? "") ||
        todolistName != (project.basecampTodolistName ?? "") ||
        syncStatus != project.basecampSyncStatus ||
        syncComments != project.basecampSyncComments ||
        isActive != project.basecampIsActive
    }

    private var isConfigured: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !todolistId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasToken: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isConfigured {
                    Section {
                        Toggle("Integration Active", isOn: $isActive)
                    } footer: {
                        Text("When disabled, Basecamp sync will be paused.")
                    }
                }

                Section {
                    SecureField("Access Token", text: $accessToken)
                        .onChange(of: accessToken) { _, newValue in
                            if !newValue.isEmpty && accounts.isEmpty {
                                loadAccounts()
                            }
                        }

                    Button {
                        showingTokenInfo = true
                    } label: {
                        Label("How to get your access token", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Generate a personal access token at launchpad.37signals.com")
                }

                if hasToken {
                    Section {
                        if isLoadingAccounts {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading accounts...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = accountsError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                loadAccounts()
                            }
                        } else {
                            Picker("Account", selection: $selectedAccount) {
                                Text("Select Account").tag(nil as BasecampAccount?)
                                ForEach(accounts) { account in
                                    Text(account.name).tag(account as BasecampAccount?)
                                }
                            }
                            .onChange(of: selectedAccount) { _, newValue in
                                if let account = newValue {
                                    accountId = String(account.id)
                                    accountName = account.name
                                    loadProjects()
                                } else {
                                    accountId = ""
                                    accountName = ""
                                    basecampProjects = []
                                    todolists = []
                                    selectedProject = nil
                                    selectedTodolist = nil
                                }
                            }
                        }
                    } header: {
                        Text("Basecamp Account")
                    }
                }

                if !accountId.isEmpty {
                    Section {
                        if isLoadingProjects {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading projects...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Project", selection: $selectedProject) {
                                Text("Select Project").tag(nil as BasecampProject?)
                                ForEach(basecampProjects) { bcProject in
                                    Text(bcProject.name).tag(bcProject as BasecampProject?)
                                }
                            }
                            .onChange(of: selectedProject) { _, newValue in
                                if let bcProject = newValue {
                                    basecampProjectId = String(bcProject.id)
                                    basecampProjectName = bcProject.name
                                    todosetId = bcProject.todosetId ?? ""
                                    if !todosetId.isEmpty {
                                        loadTodolists()
                                    }
                                } else {
                                    basecampProjectId = ""
                                    basecampProjectName = ""
                                    todosetId = ""
                                    todolists = []
                                    selectedTodolist = nil
                                }
                            }
                        }
                    } header: {
                        Text("Basecamp Project")
                    }
                }

                if !todosetId.isEmpty {
                    Section {
                        if isLoadingTodolists {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading to-do lists...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("To-do List", selection: $selectedTodolist) {
                                Text("Select To-do List").tag(nil as BasecampTodolist?)
                                ForEach(todolists) { todolist in
                                    Text(todolist.name).tag(todolist as BasecampTodolist?)
                                }
                            }
                            .onChange(of: selectedTodolist) { _, newValue in
                                if let todolist = newValue {
                                    todolistId = String(todolist.id)
                                    todolistName = todolist.name
                                } else {
                                    todolistId = ""
                                    todolistName = ""
                                }
                            }
                        }
                    } header: {
                        Text("Target To-do List")
                    } footer: {
                        Text("Feedback items will be created as to-dos in this list.")
                    }
                }

                if isConfigured {
                    Section {
                        Toggle("Sync status changes", isOn: $syncStatus)
                        Toggle("Sync comments", isOn: $syncComments)
                    } header: {
                        Text("Sync Options")
                    } footer: {
                        Text("Automatically mark to-dos complete when feedback is completed/rejected, and sync comments to Basecamp.")
                    }

                    Section {
                        Button(role: .destructive) {
                            clearIntegration()
                        } label: {
                            Label("Remove Basecamp Integration", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Basecamp Integration")
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
            .alert("Get Your Basecamp Access Token", isPresented: $showingTokenInfo) {
                Button("Open Basecamp") {
                    if let url = URL(string: "https://launchpad.37signals.com/personal_access_tokens") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to launchpad.37signals.com\n2. Navigate to Personal Access Tokens\n3. Create a new token\n4. Copy the token and paste it here")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasToken {
                    loadAccounts()
                }
            }
        }
    }

    private func loadAccounts() {
        guard hasToken else { return }

        isLoadingAccounts = true
        accountsError = nil

        Task {
            // First save the token
            let result = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                basecampAccountId: nil,
                basecampAccountName: nil,
                basecampProjectId: nil,
                basecampProjectName: nil,
                basecampTodosetId: nil,
                basecampTodolistId: nil,
                basecampTodolistName: nil,
                basecampSyncStatus: nil,
                basecampSyncComments: nil,
                basecampIsActive: nil
            )

            if result == .success {
                accounts = await viewModel.loadBasecampAccounts(projectId: project.id)
                if accounts.isEmpty {
                    accountsError = "No Basecamp accounts found. Make sure your token is valid."
                } else if !accountId.isEmpty {
                    selectedAccount = accounts.first { String($0.id) == accountId }
                    if selectedAccount != nil {
                        loadProjects()
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                accountsError = viewModel.errorMessage ?? "Failed to verify token"
            }

            isLoadingAccounts = false
        }
    }

    private func loadProjects() {
        isLoadingProjects = true
        Task {
            // Save account selection first
            _ = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: nil,
                basecampAccountId: accountId,
                basecampAccountName: accountName,
                basecampProjectId: nil,
                basecampProjectName: nil,
                basecampTodosetId: nil,
                basecampTodolistId: nil,
                basecampTodolistName: nil,
                basecampSyncStatus: nil,
                basecampSyncComments: nil,
                basecampIsActive: nil
            )

            basecampProjects = await viewModel.loadBasecampProjects(projectId: project.id)

            if !basecampProjectId.isEmpty {
                selectedProject = basecampProjects.first { String($0.id) == basecampProjectId }
                if selectedProject != nil && !todosetId.isEmpty {
                    loadTodolists()
                }
            }

            isLoadingProjects = false
        }
    }

    private func loadTodolists() {
        isLoadingTodolists = true
        Task {
            // Save project selection first
            _ = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: nil,
                basecampAccountId: nil,
                basecampAccountName: nil,
                basecampProjectId: basecampProjectId,
                basecampProjectName: basecampProjectName,
                basecampTodosetId: todosetId,
                basecampTodolistId: nil,
                basecampTodolistName: nil,
                basecampSyncStatus: nil,
                basecampSyncComments: nil,
                basecampIsActive: nil
            )

            todolists = await viewModel.loadBasecampTodolists(projectId: project.id)

            if !todolistId.isEmpty {
                selectedTodolist = todolists.first { String($0.id) == todolistId }
            }

            isLoadingTodolists = false
        }
    }

    private func clearIntegration() {
        accessToken = ""
        accountId = ""
        accountName = ""
        basecampProjectId = ""
        basecampProjectName = ""
        todosetId = ""
        todolistId = ""
        todolistName = ""
        syncStatus = false
        syncComments = false
        isActive = false
        selectedAccount = nil
        selectedProject = nil
        selectedTodolist = nil
        accounts = []
        basecampProjects = []
        todolists = []
    }

    private func saveSettings() {
        Task {
            let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: trimmedToken.isEmpty ? "" : trimmedToken,
                basecampAccountId: accountId.isEmpty ? "" : accountId,
                basecampAccountName: accountName.isEmpty ? "" : accountName,
                basecampProjectId: basecampProjectId.isEmpty ? "" : basecampProjectId,
                basecampProjectName: basecampProjectName.isEmpty ? "" : basecampProjectName,
                basecampTodosetId: todosetId.isEmpty ? "" : todosetId,
                basecampTodolistId: todolistId.isEmpty ? "" : todolistId,
                basecampTodolistName: todolistName.isEmpty ? "" : todolistName,
                basecampSyncStatus: syncStatus,
                basecampSyncComments: syncComments,
                basecampIsActive: isActive
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
```

### 6. Update Integration Menu

Add Basecamp option to the project detail menu alongside other integrations:

```swift
Button {
    showingBasecampSettings = true
} label: {
    Label("Basecamp Integration", systemImage: "checkmark.circle")
}
.sheet(isPresented: $showingBasecampSettings) {
    BasecampSettingsView(project: project, viewModel: viewModel)
}
```

---

## SDK Changes

No SDK changes required. The SDK does not interact with external integrations directly - all integration logic is server-side, triggered by Admin app actions.

---

## Status Mapping

### FeedbackStatus Extension

Add to `Feedback.swift` in the server:

```swift
/// Whether this status should mark a Basecamp to-do as complete
var basecampIsCompleted: Bool {
    switch self {
    case .completed, .rejected:
        return true
    case .pending, .approved, .inProgress, .testflight:
        return false
    }
}
```

---

## Testing Strategy

### Unit Tests

1. **BasecampService Tests**
   - Token validation
   - API response parsing
   - Error handling
   - HTML content building

2. **Controller Tests**
   - Settings update validation
   - To-do creation flow
   - Bulk creation handling
   - Authorization checks

### Integration Tests

1. **End-to-End Flow**
   - Configure integration
   - Create to-do from feedback
   - Verify to-do appears in Basecamp
   - Update feedback status → verify completion state
   - Add comment → verify Basecamp comment

2. **Error Scenarios**
   - Invalid token handling
   - Rate limit handling
   - Network failure recovery

### Manual Testing Checklist

- [ ] Configure Basecamp integration with valid token
- [ ] Select account, project, and to-do list
- [ ] Create single to-do from feedback
- [ ] Verify to-do content in Basecamp
- [ ] Create bulk to-dos
- [ ] Change feedback status to completed
- [ ] Verify to-do marked complete in Basecamp
- [ ] Change feedback status to in_progress
- [ ] Verify to-do marked incomplete
- [ ] Add comment in FeedbackKit
- [ ] Verify comment appears in Basecamp
- [ ] Disable integration
- [ ] Verify sync stops
- [ ] Remove integration
- [ ] Verify credentials cleared

---

## Implementation Checklist

### Phase 1: Server Foundation

- [ ] Create migration `AddProjectBasecampIntegration.swift`
- [ ] Add Basecamp fields to `Project.swift` model
- [ ] Add Basecamp fields to `Feedback.swift` model
- [ ] Update `ProjectResponseDTO` to include Basecamp fields
- [ ] Create `BasecampDTOs.swift`
- [ ] Create `BasecampService.swift`
- [ ] Add Request extension for basecampService
- [ ] Register migration in `configure.swift`

### Phase 2: Server Routes & Controllers

- [ ] Add Basecamp routes to `ProjectController.boot()`
- [ ] Implement `updateBasecampSettings()`
- [ ] Implement `createBasecampTodo()`
- [ ] Implement `bulkCreateBasecampTodos()`
- [ ] Implement `getBasecampAccounts()`
- [ ] Implement `getBasecampProjects()`
- [ ] Implement `getBasecampTodolists()`
- [ ] Add status sync to `FeedbackController.updateFeedback()`
- [ ] Add comment sync to `CommentController.createComment()`

### Phase 3: Admin App Models

- [ ] Create `BasecampAccount.swift`, `BasecampProject.swift`, `BasecampTodolist.swift`
- [ ] Update `Project.swift` with Basecamp fields
- [ ] Update `Feedback.swift` with Basecamp fields

### Phase 4: Admin App ViewModel

- [ ] Add `updateBasecampSettings()` to `ProjectViewModel`
- [ ] Add `loadBasecampAccounts()` to `ProjectViewModel`
- [ ] Add `loadBasecampProjects()` to `ProjectViewModel`
- [ ] Add `loadBasecampTodolists()` to `ProjectViewModel`
- [ ] Add `createBasecampTodo()` to `ProjectViewModel`
- [ ] Add `bulkCreateBasecampTodos()` to `ProjectViewModel`

### Phase 5: Admin App UI

- [ ] Create `BasecampSettingsView.swift`
- [ ] Add Basecamp menu item to project detail view
- [ ] Add Basecamp indicator to feedback list items
- [ ] Add "Push to Basecamp" action in feedback detail
- [ ] Add bulk "Push to Basecamp" action in feedback list
- [ ] Test on iOS
- [ ] Test on macOS

### Phase 6: Documentation

- [ ] Update root `CLAUDE.md` with Basecamp integration docs
- [ ] Update `SwiftlyFeedbackServer/CLAUDE.md` with API endpoints
- [ ] Update `SwiftlyFeedbackAdmin/CLAUDE.md` with UI docs

### Phase 7: Testing

- [ ] Write unit tests for BasecampService
- [ ] Write integration tests for controllers
- [ ] Manual end-to-end testing
- [ ] Test error scenarios

---

## API Reference Summary

### Server Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| PATCH | `/projects/:id/basecamp` | Update Basecamp settings |
| POST | `/projects/:id/basecamp/todo` | Create single to-do |
| POST | `/projects/:id/basecamp/todos` | Bulk create to-dos |
| GET | `/projects/:id/basecamp/accounts` | List available accounts |
| GET | `/projects/:id/basecamp/projects` | List projects in account |
| GET | `/projects/:id/basecamp/todolists` | List to-do lists in project |

### Basecamp API Endpoints Used

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/authorization.json` | Get user accounts |
| GET | `/projects.json` | List projects |
| GET | `/buckets/:id/todosets/:id.json` | Get todoset |
| GET | `/buckets/:id/todosets/:id/todolists.json` | List todolists |
| POST | `/buckets/:id/todolists/:id/todos.json` | Create to-do |
| POST | `/buckets/:id/todos/:id/completion.json` | Complete to-do |
| DELETE | `/buckets/:id/todos/:id/completion.json` | Uncomplete to-do |
| POST | `/buckets/:id/recordings/:id/comments.json` | Add comment |

---

## Notes & Considerations

### OAuth vs Personal Access Tokens

This plan uses Personal Access Tokens for simplicity, matching the pattern of other integrations. For a future enhancement, full OAuth 2.0 flow could be implemented with:
- Redirect URI handling
- Token refresh automation
- Better security for shared/team use

### Rate Limiting

Basecamp's rate limit (50 requests/10 seconds) is more restrictive than some other APIs. For bulk operations, implement:
- Request queuing
- Exponential backoff on 429 responses
- Progress indication for large batches

### No Vote Count Sync

Unlike ClickUp, Notion, and Monday.com, Basecamp to-dos don't support custom number fields. Vote counts are included in the to-do description but cannot be updated separately.

### Token Expiration

Personal access tokens don't expire, but OAuth tokens do (2 weeks). If switching to OAuth in the future, implement automatic token refresh.
