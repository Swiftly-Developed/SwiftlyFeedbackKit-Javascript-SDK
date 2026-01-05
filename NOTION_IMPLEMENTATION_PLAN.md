# Notion Integration Implementation Plan

This document outlines the detailed technical implementation plan for adding Notion integration to SwiftlyFeedback, following the same patterns as the existing ClickUp integration.

## Overview

The Notion integration will allow users to push feedback items to a Notion database as pages, with optional status synchronization and comment syncing.

---

## Phase 1: Server-Side Implementation

### 1.1 Database Migration

**File:** `SwiftlyFeedbackServer/Sources/App/Migrations/AddProjectNotionIntegration.swift`

```swift
import Fluent

struct AddProjectNotionIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Notion fields to projects table
        try await database.schema("projects")
            .field("notion_token", .string)
            .field("notion_database_id", .string)
            .field("notion_database_name", .string)
            .field("notion_sync_status", .bool, .required, .sql(.default(false)))
            .field("notion_sync_comments", .bool, .required, .sql(.default(false)))
            .field("notion_status_property", .string)
            .field("notion_votes_property", .string)
            .update()

        // Add Notion fields to feedbacks table
        try await database.schema("feedbacks")
            .field("notion_page_url", .string)
            .field("notion_page_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("notion_token")
            .deleteField("notion_database_id")
            .deleteField("notion_database_name")
            .deleteField("notion_sync_status")
            .deleteField("notion_sync_comments")
            .deleteField("notion_status_property")
            .deleteField("notion_votes_property")
            .update()

        try await database.schema("feedbacks")
            .deleteField("notion_page_url")
            .deleteField("notion_page_id")
            .update()
    }
}
```

**Register in `configure.swift`:**
```swift
app.migrations.add(AddProjectNotionIntegration())
```

### 1.2 Update Project Model

**File:** `SwiftlyFeedbackServer/Sources/App/Models/Project.swift`

Add fields after ClickUp fields:

```swift
// Notion integration fields
@OptionalField(key: "notion_token")
var notionToken: String?

@OptionalField(key: "notion_database_id")
var notionDatabaseId: String?

@OptionalField(key: "notion_database_name")
var notionDatabaseName: String?

@Field(key: "notion_sync_status")
var notionSyncStatus: Bool

@Field(key: "notion_sync_comments")
var notionSyncComments: Bool

@OptionalField(key: "notion_status_property")
var notionStatusProperty: String?

@OptionalField(key: "notion_votes_property")
var notionVotesProperty: String?
```

Update `init()` with new parameters and defaults.

### 1.3 Update Feedback Model

**File:** `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`

Add after ClickUp fields:

```swift
// Notion integration fields
@OptionalField(key: "notion_page_url")
var notionPageURL: String?

@OptionalField(key: "notion_page_id")
var notionPageId: String?

/// Whether this feedback has a linked Notion page
var hasNotionPage: Bool {
    notionPageURL != nil
}
```

Add status mapping for Notion:

```swift
/// Maps SwiftlyFeedback status to Notion status names
var notionStatusName: String {
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

### 1.4 Create NotionService

**File:** `SwiftlyFeedbackServer/Sources/App/Services/NotionService.swift`

```swift
import Vapor

struct NotionService {
    private let client: Client
    private let baseURL = "https://api.notion.com/v1"
    private let apiVersion = "2022-06-28"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct NotionPageResponse: Codable {
        let id: String
        let url: String
        let properties: [String: PropertyValue]?

        struct PropertyValue: Codable {
            let id: String
            let type: String
        }
    }

    struct NotionDatabase: Codable {
        let id: String
        let title: [RichText]
        let properties: [String: DatabaseProperty]

        var name: String {
            title.first?.plainText ?? "Untitled"
        }
    }

    struct DatabaseProperty: Codable {
        let id: String
        let name: String
        let type: String
    }

    struct RichText: Codable {
        let plainText: String

        enum CodingKeys: String, CodingKey {
            case plainText = "plain_text"
        }
    }

    struct NotionSearchResponse: Codable {
        let results: [SearchResult]
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case results
            case hasMore = "has_more"
        }
    }

    struct SearchResult: Codable {
        let object: String
        let id: String
        let title: [RichText]?

        var name: String {
            title?.first?.plainText ?? "Untitled"
        }
    }

    struct NotionCommentResponse: Codable {
        let id: String
        let discussionId: String

        enum CodingKeys: String, CodingKey {
            case id
            case discussionId = "discussion_id"
        }
    }

    struct NotionErrorResponse: Codable {
        let code: String
        let message: String
    }

    // MARK: - Create Page

    func createPage(
        databaseId: String,
        token: String,
        title: String,
        properties: [String: Any],
        content: String
    ) async throws -> NotionPageResponse {
        let url = URI(string: "\(baseURL)/pages")

        // Build properties dictionary
        var propsDict: [String: Any] = [
            "Title": [
                "title": [
                    ["type": "text", "text": ["content": title]]
                ]
            ]
        ]

        // Merge additional properties
        for (key, value) in properties {
            propsDict[key] = value
        }

        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": propsDict,
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [
                            ["type": "text", "text": ["content": content]]
                        ]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.post(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: "Notion-Version", value: apiVersion)
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        return try await handleResponse(response)
    }

    // MARK: - Update Page Status

    func updatePageStatus(
        pageId: String,
        token: String,
        statusProperty: String,
        statusValue: String
    ) async throws {
        let url = URI(string: "\(baseURL)/pages/\(pageId)")

        let body: [String: Any] = [
            "properties": [
                statusProperty: [
                    "status": ["name": statusValue]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.patch(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: "Notion-Version", value: apiVersion)
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard response.status == .ok else {
            try await handleError(response)
        }
    }

    // MARK: - Update Page Number Property (Vote Count)

    func updatePageNumber(
        pageId: String,
        token: String,
        propertyName: String,
        value: Int
    ) async throws {
        let url = URI(string: "\(baseURL)/pages/\(pageId)")

        let body: [String: Any] = [
            "properties": [
                propertyName: [
                    "number": value
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.patch(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: "Notion-Version", value: apiVersion)
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard response.status == .ok else {
            try await handleError(response)
        }
    }

    // MARK: - Create Comment

    func createComment(
        pageId: String,
        token: String,
        text: String
    ) async throws -> NotionCommentResponse {
        let url = URI(string: "\(baseURL)/comments")

        let body: [String: Any] = [
            "parent": ["page_id": pageId],
            "rich_text": [
                ["type": "text", "text": ["content": text]]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.post(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: "Notion-Version", value: apiVersion)
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        return try await handleResponse(response)
    }

    // MARK: - Search Databases

    func searchDatabases(token: String) async throws -> [NotionDatabase] {
        let url = URI(string: "\(baseURL)/search")

        let body: [String: Any] = [
            "filter": [
                "value": "database",
                "property": "object"
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.post(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: "Notion-Version", value: apiVersion)
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard response.status == .ok, let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Failed to search Notion databases")
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(NotionSearchResponse.self, from: Data(buffer: bodyData))

        // Fetch full database details for each result
        var databases: [NotionDatabase] = []
        for result in searchResponse.results where result.object == "database" {
            if let db = try? await getDatabase(databaseId: result.id, token: token) {
                databases.append(db)
            }
        }

        return databases
    }

    // MARK: - Get Database

    func getDatabase(databaseId: String, token: String) async throws -> NotionDatabase {
        let url = URI(string: "\(baseURL)/databases/\(databaseId)")

        let response = try await client.get(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: "Notion-Version", value: apiVersion)
        }

        return try await handleResponse(response)
    }

    // MARK: - Build Page Content

    func buildPageContent(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var content = """
        \(feedback.category.displayName)

        \(feedback.description)

        ---

        Source: SwiftlyFeedback
        Project: \(projectName)
        Votes: \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            content += "\nMRR: $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            content += "\nSubmitted by: \(userEmail)"
        }

        return content
    }

    // MARK: - Build Page Properties

    func buildPageProperties(
        feedback: Feedback,
        voteCount: Int,
        mrr: Double?,
        statusProperty: String?,
        votesProperty: String?
    ) -> [String: Any] {
        var properties: [String: Any] = [:]

        // Add status if property name is configured
        if let statusProp = statusProperty, !statusProp.isEmpty {
            properties[statusProp] = [
                "status": ["name": feedback.status.notionStatusName]
            ]
        }

        // Add category as select
        properties["Category"] = [
            "select": ["name": feedback.category.displayName]
        ]

        // Add votes if property name is configured
        if let votesProp = votesProperty, !votesProp.isEmpty {
            properties[votesProp] = ["number": voteCount]
        }

        // Add MRR if available
        if let mrr = mrr, mrr > 0 {
            properties["MRR"] = ["number": mrr]
        }

        // Add submitter email if available
        if let email = feedback.userEmail {
            properties["Submitter Email"] = ["email": email]
        }

        return properties
    }

    // MARK: - Helpers

    private func handleResponse<T: Decodable>(_ response: ClientResponse) async throws -> T {
        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Notion API returned empty response")
        }
        let data = Data(buffer: bodyData)

        guard response.status == .ok || response.status == .created else {
            if let errorResponse = try? JSONDecoder().decode(NotionErrorResponse.self, from: data) {
                throw Abort(.badGateway, reason: "Notion API error: \(errorResponse.message)")
            }
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Notion API error (\(response.status)): \(responseBody)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "decode failed"
            throw Abort(.badGateway, reason: "Failed to decode Notion response: \(error.localizedDescription). Body: \(responseBody)")
        }
    }

    private func handleError(_ response: ClientResponse) async throws {
        if let bodyData = response.body {
            let data = Data(buffer: bodyData)
            if let errorResponse = try? JSONDecoder().decode(NotionErrorResponse.self, from: data) {
                throw Abort(.badGateway, reason: "Notion API error: \(errorResponse.message)")
            }
        }
        throw Abort(.badGateway, reason: "Notion API error: \(response.status)")
    }
}

// MARK: - Request Extension

extension Request {
    var notionService: NotionService {
        NotionService(client: self.client)
    }
}
```

### 1.5 Add DTOs

**File:** `SwiftlyFeedbackServer/Sources/App/DTOs/ProjectDTO.swift`

Add after ClickUp DTOs:

```swift
// MARK: - Notion Integration DTOs

struct UpdateProjectNotionDTO: Content {
    var notionToken: String?
    var notionDatabaseId: String?
    var notionDatabaseName: String?
    var notionSyncStatus: Bool?
    var notionSyncComments: Bool?
    var notionStatusProperty: String?
    var notionVotesProperty: String?
}

struct CreateNotionPageDTO: Content {
    var feedbackId: UUID
}

struct CreateNotionPageResponseDTO: Content {
    var feedbackId: UUID
    var pageUrl: String
    var pageId: String
}

struct BulkCreateNotionPagesDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateNotionPagesResponseDTO: Content {
    var created: [CreateNotionPageResponseDTO]
    var failed: [UUID]
}

struct NotionDatabaseDTO: Content {
    var id: String
    var name: String
    var properties: [NotionPropertyDTO]
}

struct NotionPropertyDTO: Content {
    var id: String
    var name: String
    var type: String
}
```

Update `ProjectResponseDTO` to include Notion fields.

### 1.6 Add Controller Routes

**File:** `SwiftlyFeedbackServer/Sources/App/Controllers/ProjectController.swift`

Add routes in `boot()` after ClickUp routes:

```swift
// Notion integration
protected.patch(":projectId", "notion", use: updateNotionSettings)
protected.post(":projectId", "notion", "page", use: createNotionPage)
protected.post(":projectId", "notion", "pages", use: bulkCreateNotionPages)
protected.get(":projectId", "notion", "databases", use: getNotionDatabases)
protected.get(":projectId", "notion", "database", ":databaseId", "properties", use: getNotionDatabaseProperties)
```

Add handler functions (following ClickUp pattern).

### 1.7 Update Status Change Handlers

**Files to update:**
- `FeedbackController.swift` - Add Notion status sync when feedback status changes
- `CommentController.swift` - Add Notion comment sync when comments are created
- `VoteController.swift` - Add Notion vote count sync when votes change

---

## Phase 2: Admin App Implementation

### 2.1 Update Project Model

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/ProjectModels.swift`

Add Notion fields to `Project` struct:

```swift
// Notion integration fields
let notionToken: String?
let notionDatabaseId: String?
let notionDatabaseName: String?
let notionSyncStatus: Bool
let notionSyncComments: Bool
let notionStatusProperty: String?
let notionVotesProperty: String?

/// Whether Notion integration is configured
var isNotionConfigured: Bool {
    notionToken != nil && notionDatabaseId != nil
}
```

Update decoder and init for backwards compatibility.

Add request/response types:

```swift
// MARK: - Notion Integration

struct UpdateProjectNotionRequest: Encodable {
    let notionToken: String?
    let notionDatabaseId: String?
    let notionDatabaseName: String?
    let notionSyncStatus: Bool?
    let notionSyncComments: Bool?
    let notionStatusProperty: String?
    let notionVotesProperty: String?
}

struct CreateNotionPageRequest: Encodable {
    let feedbackId: UUID
}

struct CreateNotionPageResponse: Decodable {
    let feedbackId: UUID
    let pageUrl: String
    let pageId: String
}

struct BulkCreateNotionPagesRequest: Encodable {
    let feedbackIds: [UUID]
}

struct BulkCreateNotionPagesResponse: Decodable {
    let created: [CreateNotionPageResponse]
    let failed: [UUID]
}

struct NotionDatabase: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let properties: [NotionProperty]
}

struct NotionProperty: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
}
```

### 2.2 Update Feedback Model

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/FeedbackModels.swift`

Add to `Feedback` struct:

```swift
let notionPageUrl: String?
let notionPageId: String?

var hasNotionPage: Bool {
    notionPageUrl != nil
}
```

### 2.3 Update APIClient

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/APIClient.swift`

Add Notion methods:

```swift
// MARK: - Notion Integration

func updateNotionSettings(projectId: UUID, request: UpdateProjectNotionRequest) async throws -> Project {
    try await patch("projects/\(projectId)/notion", body: request)
}

func createNotionPage(projectId: UUID, feedbackId: UUID) async throws -> CreateNotionPageResponse {
    let request = CreateNotionPageRequest(feedbackId: feedbackId)
    return try await post("projects/\(projectId)/notion/page", body: request)
}

func bulkCreateNotionPages(projectId: UUID, feedbackIds: [UUID]) async throws -> BulkCreateNotionPagesResponse {
    let request = BulkCreateNotionPagesRequest(feedbackIds: feedbackIds)
    return try await post("projects/\(projectId)/notion/pages", body: request)
}

func getNotionDatabases(projectId: UUID) async throws -> [NotionDatabase] {
    try await get("projects/\(projectId)/notion/databases")
}

func getNotionDatabaseProperties(projectId: UUID, databaseId: String) async throws -> NotionDatabase {
    try await get("projects/\(projectId)/notion/database/\(databaseId)/properties")
}
```

### 2.4 Update ProjectViewModel

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/ProjectViewModel.swift`

Add Notion methods:

```swift
// MARK: - Notion Integration

@MainActor
func updateNotionSettings(
    projectId: UUID?,
    notionToken: String?,
    notionDatabaseId: String?,
    notionDatabaseName: String?,
    notionSyncStatus: Bool?,
    notionSyncComments: Bool?,
    notionStatusProperty: String?,
    notionVotesProperty: String?
) async -> Bool {
    guard let projectId else { return false }

    isLoading = true
    defer { isLoading = false }

    do {
        let request = UpdateProjectNotionRequest(
            notionToken: notionToken,
            notionDatabaseId: notionDatabaseId,
            notionDatabaseName: notionDatabaseName,
            notionSyncStatus: notionSyncStatus,
            notionSyncComments: notionSyncComments,
            notionStatusProperty: notionStatusProperty,
            notionVotesProperty: notionVotesProperty
        )
        selectedProject = try await apiClient.updateNotionSettings(projectId: projectId, request: request)
        return true
    } catch {
        handleError(error)
        return false
    }
}

@MainActor
func loadNotionDatabases(projectId: UUID?) async -> [NotionDatabase] {
    guard let projectId else { return [] }

    do {
        return try await apiClient.getNotionDatabases(projectId: projectId)
    } catch {
        AppLogger.api.error("Failed to load Notion databases: \(error)")
        return []
    }
}

@MainActor
func loadNotionDatabaseProperties(projectId: UUID?, databaseId: String) async -> NotionDatabase? {
    guard let projectId else { return nil }

    do {
        return try await apiClient.getNotionDatabaseProperties(projectId: projectId, databaseId: databaseId)
    } catch {
        AppLogger.api.error("Failed to load Notion database properties: \(error)")
        return nil
    }
}
```

### 2.5 Update FeedbackViewModel

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/FeedbackViewModel.swift`

Add Notion methods:

```swift
// MARK: - Notion Integration

@MainActor
func createNotionPage(projectId: UUID, feedbackId: UUID) async -> CreateNotionPageResponse? {
    isLoading = true
    defer { isLoading = false }

    do {
        let response = try await apiClient.createNotionPage(projectId: projectId, feedbackId: feedbackId)
        // Refresh feedback to get updated notionPageUrl
        await loadFeedback()
        return response
    } catch {
        handleError(error)
        return nil
    }
}

@MainActor
func bulkCreateNotionPages(projectId: UUID, feedbackIds: [UUID]) async -> BulkCreateNotionPagesResponse? {
    isLoading = true
    defer { isLoading = false }

    do {
        let response = try await apiClient.bulkCreateNotionPages(projectId: projectId, feedbackIds: feedbackIds)
        await loadFeedback()
        return response
    } catch {
        handleError(error)
        return nil
    }
}
```

### 2.6 Create NotionSettingsView

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/NotionSettingsView.swift`

Create a new view following the `ClickUpSettingsView` pattern:
- Token input field with help button
- Database picker (loads available databases)
- Status property picker (from database schema)
- Votes property picker (number fields only)
- Sync toggles for status and comments
- Remove integration button

### 2.7 Update ProjectDetailView

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/ProjectDetailView.swift`

Add Notion menu item alongside ClickUp:

```swift
Button {
    showingNotionSettings = true
} label: {
    Label("Notion Integration", systemImage: "doc.text")
}
```

Add sheet:

```swift
.sheet(isPresented: $showingNotionSettings) {
    NotionSettingsView(project: project, viewModel: viewModel)
}
```

### 2.8 Update Feedback Context Menu

**File:** Update context menu in feedback list/detail views

Add Notion actions:

```swift
if project.isNotionConfigured {
    if feedback.hasNotionPage {
        Button {
            if let url = URL(string: feedback.notionPageUrl!) {
                openURL(url)
            }
        } label: {
            Label("View Notion Page", systemImage: "arrow.up.right.square")
        }
    } else {
        Button {
            Task {
                await viewModel.createNotionPage(projectId: project.id, feedbackId: feedback.id)
            }
        } label: {
            Label("Push to Notion", systemImage: "doc.text")
        }
    }
}
```

### 2.9 Update FeedbackCardView

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Feedback/FeedbackCardView.swift`

Add Notion badge (black icon) next to GitHub/ClickUp badges:

```swift
if feedback.hasNotionPage {
    Image(systemName: "doc.text.fill")
        .font(.caption)
        .foregroundStyle(.primary)
}
```

### 2.10 Update Selection Action Bar

**File:** Update bulk action bar for selected feedback

Add "Push to Notion" button when Notion is configured:

```swift
if project.isNotionConfigured {
    Button {
        Task {
            let feedbackIds = selectedFeedback.filter { !$0.hasNotionPage }.map { $0.id }
            await viewModel.bulkCreateNotionPages(projectId: project.id, feedbackIds: feedbackIds)
        }
    } label: {
        Label("Push to Notion", systemImage: "doc.text")
    }
    .disabled(selectedFeedback.allSatisfy { $0.hasNotionPage })
}
```

### 2.11 Update Integrations Display

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/ProjectDetailView.swift`

Add Notion to the integrations section that shows configured integrations:

```swift
if project.isNotionConfigured {
    Label("Notion: \(project.notionDatabaseName ?? "Configured")", systemImage: "doc.text")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

---

## Phase 3: Testing & Documentation

### 3.1 Test Cases

1. **Settings Flow**
   - Enter valid token → databases load
   - Enter invalid token → error displayed
   - Select database → properties load
   - Configure status/votes properties
   - Save settings → project updated

2. **Push to Notion**
   - Single feedback → page created
   - Bulk feedback → pages created
   - Already pushed → shows error/skip
   - Notion badge appears on card

3. **Status Sync**
   - Change feedback status → Notion page updated
   - Invalid status property → graceful failure

4. **Comment Sync**
   - Add comment → Notion comment created
   - Sync disabled → no comment created

5. **Vote Sync**
   - Add/remove vote → Notion votes property updated
   - Votes property not configured → no update

### 3.2 Error Handling

- 401 Unauthorized → "Invalid or expired token"
- 403 Forbidden → "Database not shared with integration"
- 404 Not Found → "Database or page not found"
- 429 Rate Limited → Retry with Retry-After header
- 500 Server Error → "Notion service unavailable"

---

## Implementation Order

1. **Server Migration** - Add database fields
2. **Server Models** - Update Project and Feedback models
3. **NotionService** - Create the API client service
4. **Server DTOs** - Add request/response types
5. **Server Routes** - Add controller handlers
6. **Server Sync** - Add status/comment/vote sync triggers
7. **Admin Models** - Update client-side models
8. **Admin APIClient** - Add API methods
9. **Admin ViewModels** - Add Notion methods
10. **NotionSettingsView** - Create settings UI
11. **Admin Integration** - Update menus, badges, actions
12. **Testing** - Verify all flows work correctly
13. **Documentation** - Update CLAUDE.md (done)

---

## File Changes Summary

### New Files
- `SwiftlyFeedbackServer/Sources/App/Migrations/AddProjectNotionIntegration.swift`
- `SwiftlyFeedbackServer/Sources/App/Services/NotionService.swift`
- `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/NotionSettingsView.swift`

### Modified Files (Server)
- `Sources/App/Models/Project.swift`
- `Sources/App/Models/Feedback.swift`
- `Sources/App/DTOs/ProjectDTO.swift`
- `Sources/App/DTOs/FeedbackDTO.swift`
- `Sources/App/Controllers/ProjectController.swift`
- `Sources/App/Controllers/FeedbackController.swift`
- `Sources/App/Controllers/CommentController.swift`
- `Sources/App/Controllers/VoteController.swift`
- `Sources/App/configure.swift`

### Modified Files (Admin App)
- `Models/ProjectModels.swift`
- `Models/FeedbackModels.swift`
- `Services/APIClient.swift`
- `ViewModels/ProjectViewModel.swift`
- `ViewModels/FeedbackViewModel.swift`
- `Views/Projects/ProjectDetailView.swift`
- `Views/Feedback/FeedbackCardView.swift`
- `Views/Feedback/FeedbackListView.swift` (context menu)
- `Views/Feedback/FeedbackDetailView.swift` (context menu)
