# Trello Integration Technical Plan

**Version:** 1.1.0
**Author:** Claude Code
**Date:** 2026-01-13
**Status:** Draft

---

## Table of Contents

1. [Overview](#overview)
2. [Trello API Reference](#trello-api-reference)
3. [Architecture](#architecture)
4. [Database Schema](#database-schema)
5. [Server Implementation](#server-implementation)
6. [Admin App Implementation](#admin-app-implementation)
7. [Feature Mapping](#feature-mapping)
8. [Implementation Checklist](#implementation-checklist)
9. [Testing Plan](#testing-plan)

---

## Overview

### Goal

Add Trello integration to FeedbackKit, allowing users to automatically sync feedback items to Trello boards as cards. This follows the established integration patterns used for GitHub, ClickUp, Linear, Monday.com, and Notion.

### Features

| Feature | Description |
|---------|-------------|
| **Push to Trello** | Create Trello cards from feedback items |
| **Bulk Push** | Create multiple cards at once |
| **Status Sync** | Move cards between lists when feedback status changes |
| **Comment Sync** | Add comments to cards when feedback receives comments |
| **Active Toggle** | Enable/disable sync without losing configuration |

### Subscription Tier

**Pro tier required** (consistent with other integrations)

---

## Trello API Reference

### Base URL

```
https://api.trello.com/1
```

### Authentication

Trello uses API Key + Token authentication passed as query parameters:

```
?key={apiKey}&token={userToken}
```

| Credential | Description | Storage |
|------------|-------------|---------|
| **API Key** | FeedbackKit's application key (public) | Environment variable |
| **User Token** | User-specific access token | Project.trelloToken (encrypted) |

### Token Generation

Users generate tokens via the authorization URL:

```
https://trello.com/1/authorize?expiration=never&scope=read,write&response_type=token&key={apiKey}&name=FeedbackKit
```

| Parameter | Value | Description |
|-----------|-------|-------------|
| `expiration` | `never` | Token never expires |
| `scope` | `read,write` | Read boards/lists, create/update cards |
| `response_type` | `token` | Return token directly |
| `key` | `{apiKey}` | FeedbackKit's API key |
| `name` | `FeedbackKit` | Shown in authorization prompt |

### Rate Limits

- **Limit:** 300 requests per 10 seconds per token
- **429 Response:** Returned when limit exceeded
- **Recommendation:** Use webhooks for real-time updates (future enhancement)

### Key Endpoints

#### Boards

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Get user's boards | GET | `/members/me/boards` |
| Get board | GET | `/boards/{id}` |
| Get lists on board | GET | `/boards/{id}/lists` |
| Get labels on board | GET | `/boards/{id}/labels` |

#### Lists

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Get list | GET | `/lists/{id}` |
| Get cards in list | GET | `/lists/{id}/cards` |

#### Cards

| Operation | Method | Endpoint | Required Params |
|-----------|--------|----------|-----------------|
| Create card | POST | `/cards` | `idList`, `name` |
| Get card | GET | `/cards/{id}` | - |
| Update card | PUT | `/cards/{id}` | - |
| Delete card | DELETE | `/cards/{id}` | - |
| Move to list | PUT | `/cards/{id}` | `idList` |
| Add comment | POST | `/cards/{id}/actions/comments` | `text` |

### Card Creation Request

```http
POST https://api.trello.com/1/cards?key={key}&token={token}
Content-Type: application/json

{
  "idList": "list-id",
  "name": "Card Title",
  "desc": "Card description with markdown",
  "pos": "bottom"
}
```

### Card Creation Response

```json
{
  "id": "card-id",
  "name": "Card Title",
  "desc": "Card description",
  "url": "https://trello.com/c/shortLink/card-name",
  "shortUrl": "https://trello.com/c/shortLink",
  "idList": "list-id",
  "idBoard": "board-id"
}
```

---

## Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     SwiftlyFeedbackAdmin                         │
│                                                                  │
│  TrelloSettingsView                                              │
│  ├── Token input (manual paste)                                  │
│  ├── Board picker (cascade from token)                           │
│  ├── List picker (cascade from board)                            │
│  ├── Status sync toggle                                          │
│  ├── Comment sync toggle                                         │
│  └── Active toggle                                               │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SwiftlyFeedbackServer                         │
│                                                                  │
│  ProjectController                                               │
│  ├── PATCH /projects/:id/trello (update settings)               │
│  ├── GET /projects/:id/trello/boards (discovery)                │
│  ├── GET /projects/:id/trello/boards/:boardId/lists (discovery) │
│  ├── POST /projects/:id/trello/card (create single)             │
│  └── POST /projects/:id/trello/cards (bulk create)              │
│                                                                  │
│  TrelloService                                                   │
│  ├── getBoards(token:)                                          │
│  ├── getLists(token:boardId:)                                   │
│  ├── createCard(token:listId:name:desc:)                        │
│  ├── updateCard(token:cardId:listId:)                           │
│  └── addComment(token:cardId:text:)                             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Trello API                                │
│                  https://api.trello.com/1                        │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Hierarchy

Unlike ClickUp (Workspace → Space → Folder → List), Trello has a simple hierarchy:

```
Board → List → Card
```

User selects:
1. **Board** - Where cards will be organized
2. **List** - Default list for new cards (typically "To Do" or "Backlog")

---

## Database Schema

### Migration: `AddProjectTrelloIntegration`

**File:** `SwiftlyFeedbackServer/Sources/App/Migrations/AddProjectTrelloIntegration.swift`

#### Project Table Additions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `trello_token` | String? | nil | User's Trello API token |
| `trello_board_id` | String? | nil | Selected board ID |
| `trello_board_name` | String? | nil | Selected board name (display) |
| `trello_list_id` | String? | nil | Default list for new cards |
| `trello_list_name` | String? | nil | Default list name (display) |
| `trello_sync_status` | Bool | false | Sync status changes to Trello |
| `trello_sync_comments` | Bool | false | Sync comments to Trello |
| `trello_is_active` | Bool | true | Master toggle |

#### Feedback Table Additions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `trello_card_url` | String? | nil | URL to the Trello card |
| `trello_card_id` | String? | nil | Trello card ID |

### Migration Code

```swift
import Fluent

struct AddProjectTrelloIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Project fields
        try await database.schema("projects")
            .field("trello_token", .string)
            .field("trello_board_id", .string)
            .field("trello_board_name", .string)
            .field("trello_list_id", .string)
            .field("trello_list_name", .string)
            .field("trello_sync_status", .bool, .required, .sql(.default(false)))
            .field("trello_sync_comments", .bool, .required, .sql(.default(false)))
            .field("trello_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Feedback fields
        try await database.schema("feedbacks")
            .field("trello_card_url", .string)
            .field("trello_card_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("trello_token")
            .deleteField("trello_board_id")
            .deleteField("trello_board_name")
            .deleteField("trello_list_id")
            .deleteField("trello_list_name")
            .deleteField("trello_sync_status")
            .deleteField("trello_sync_comments")
            .deleteField("trello_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("trello_card_url")
            .deleteField("trello_card_id")
            .update()
    }
}
```

---

## Server Implementation

### 1. Environment Variable

**File:** `.env` / Environment configuration

```
TRELLO_API_KEY=your_feedbackkit_api_key
```

### 2. Model Updates

#### Project.swift

```swift
// MARK: - Trello Integration
@OptionalField(key: "trello_token") var trelloToken: String?
@OptionalField(key: "trello_board_id") var trelloBoardId: String?
@OptionalField(key: "trello_board_name") var trelloBoardName: String?
@OptionalField(key: "trello_list_id") var trelloListId: String?
@OptionalField(key: "trello_list_name") var trelloListName: String?
@Field(key: "trello_sync_status") var trelloSyncStatus: Bool
@Field(key: "trello_sync_comments") var trelloSyncComments: Bool
@Field(key: "trello_is_active") var trelloIsActive: Bool

var isTrelloConfigured: Bool {
    trelloToken != nil && trelloBoardId != nil && trelloListId != nil
}

var isTrelloActive: Bool {
    isTrelloConfigured && trelloIsActive
}
```

#### Feedback.swift

```swift
// MARK: - Trello Integration
@OptionalField(key: "trello_card_url") var trelloCardURL: String?
@OptionalField(key: "trello_card_id") var trelloCardId: String?

var hasTrelloCard: Bool {
    trelloCardURL != nil
}
```

### 3. DTOs

**File:** `SwiftlyFeedbackServer/Sources/App/DTOs/ProjectDTO.swift`

```swift
// MARK: - Trello DTOs

struct UpdateProjectTrelloDTO: Content {
    var trelloToken: String?
    var trelloBoardId: String?
    var trelloBoardName: String?
    var trelloListId: String?
    var trelloListName: String?
    var trelloSyncStatus: Bool?
    var trelloSyncComments: Bool?
    var trelloIsActive: Bool?
}

struct TrelloBoardDTO: Content {
    var id: String
    var name: String
}

struct TrelloListDTO: Content {
    var id: String
    var name: String
}

struct CreateTrelloCardDTO: Content {
    var feedbackId: UUID
}

struct CreateTrelloCardResponseDTO: Content {
    var feedbackId: UUID
    var cardUrl: String
    var cardId: String
}

struct BulkCreateTrelloCardsDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateTrelloCardsResponseDTO: Content {
    var created: [CreateTrelloCardResponseDTO]
    var failed: [UUID]
}
```

**Update ProjectResponseDTO** to include all Trello fields.

### 4. TrelloService

**File:** `SwiftlyFeedbackServer/Sources/App/Services/TrelloService.swift`

```swift
import Vapor

struct TrelloService {
    private let client: Client
    private let baseURL = "https://api.trello.com/1"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct TrelloBoard: Codable {
        let id: String
        let name: String
        let closed: Bool
        let url: String
    }

    struct TrelloList: Codable {
        let id: String
        let name: String
        let closed: Bool
        let idBoard: String
    }

    struct TrelloCard: Codable {
        let id: String
        let name: String
        let desc: String
        let url: String
        let shortUrl: String
        let idList: String
        let idBoard: String
    }

    struct TrelloComment: Codable {
        let id: String
        let data: CommentData

        struct CommentData: Codable {
            let text: String
        }
    }

    // MARK: - API Key

    private var apiKey: String {
        Environment.get("TRELLO_API_KEY") ?? ""
    }

    private func authParams(token: String) -> String {
        "key=\(apiKey)&token=\(token)"
    }

    // MARK: - Discovery

    func getBoards(token: String) async throws -> [TrelloBoard] {
        let url = URI(string: "\(baseURL)/members/me/boards?\(authParams(token: token))&filter=open")

        let response = try await client.get(url)

        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Failed to fetch Trello boards: \(response.status)")
        }

        return try response.content.decode([TrelloBoard].self)
    }

    func getLists(token: String, boardId: String) async throws -> [TrelloList] {
        let url = URI(string: "\(baseURL)/boards/\(boardId)/lists?\(authParams(token: token))&filter=open")

        let response = try await client.get(url)

        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Failed to fetch Trello lists: \(response.status)")
        }

        return try response.content.decode([TrelloList].self)
    }

    // MARK: - Card Operations

    func createCard(
        token: String,
        listId: String,
        name: String,
        description: String
    ) async throws -> TrelloCard {
        let url = URI(string: "\(baseURL)/cards?\(authParams(token: token))")

        struct CreateCardRequest: Content {
            let idList: String
            let name: String
            let desc: String
            let pos: String
        }

        let body = CreateCardRequest(
            idList: listId,
            name: name,
            desc: description,
            pos: "bottom"
        )

        let response = try await client.post(url) { req in
            try req.content.encode(body)
        }

        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Failed to create Trello card: \(response.status)")
        }

        return try response.content.decode(TrelloCard.self)
    }

    func moveCard(token: String, cardId: String, toListId: String) async throws {
        let url = URI(string: "\(baseURL)/cards/\(cardId)?\(authParams(token: token))")

        struct MoveCardRequest: Content {
            let idList: String
        }

        let response = try await client.put(url) { req in
            try req.content.encode(MoveCardRequest(idList: toListId))
        }

        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Failed to move Trello card: \(response.status)")
        }
    }

    func addComment(token: String, cardId: String, text: String) async throws {
        let url = URI(string: "\(baseURL)/cards/\(cardId)/actions/comments?\(authParams(token: token))")

        struct AddCommentRequest: Content {
            let text: String
        }

        let response = try await client.post(url) { req in
            try req.content.encode(AddCommentRequest(text: text))
        }

        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Failed to add comment to Trello card: \(response.status)")
        }
    }

    // MARK: - Content Building

    func buildCardDescription(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var description = """
        ## \(feedback.title)

        \(feedback.feedbackDescription)

        ---

        **Project:** \(projectName)
        **Category:** \(feedback.category.rawValue.capitalized)
        **Status:** \(feedback.status.rawValue.capitalized)
        **Votes:** \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            description += "\n**MRR:** $\(String(format: "%.2f", mrr))"
        }

        description += "\n\n---\n*Synced from FeedbackKit*"

        return description
    }
}

// MARK: - Request Extension

extension Request {
    var trelloService: TrelloService {
        TrelloService(client: self.client)
    }
}
```

### 5. Controller Endpoints

**File:** `SwiftlyFeedbackServer/Sources/App/Controllers/ProjectController.swift`

Add routes in `boot(routes:)`:

```swift
// Trello Integration
protected.patch(":projectId", "trello", use: updateTrelloSettings)
protected.get(":projectId", "trello", "boards", use: getTrelloBoards)
protected.get(":projectId", "trello", "boards", ":boardId", "lists", use: getTrelloLists)
protected.post(":projectId", "trello", "card", use: createTrelloCard)
protected.post(":projectId", "trello", "cards", use: bulkCreateTrelloCards)
```

Add handler functions:

```swift
// MARK: - Trello Integration

@Sendable func updateTrelloSettings(req: Request) async throws -> ProjectResponseDTO {
    let user = try req.auth.require(User.self)

    // Check Pro tier
    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Trello integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)
    let dto = try req.content.decode(UpdateProjectTrelloDTO.self)

    // Update fields
    if let token = dto.trelloToken {
        project.trelloToken = token.isEmpty ? nil : token
    }
    if let boardId = dto.trelloBoardId {
        project.trelloBoardId = boardId.isEmpty ? nil : boardId
    }
    if let boardName = dto.trelloBoardName {
        project.trelloBoardName = boardName.isEmpty ? nil : boardName
    }
    if let listId = dto.trelloListId {
        project.trelloListId = listId.isEmpty ? nil : listId
    }
    if let listName = dto.trelloListName {
        project.trelloListName = listName.isEmpty ? nil : listName
    }
    if let syncStatus = dto.trelloSyncStatus {
        project.trelloSyncStatus = syncStatus
    }
    if let syncComments = dto.trelloSyncComments {
        project.trelloSyncComments = syncComments
    }
    if let isActive = dto.trelloIsActive {
        project.trelloIsActive = isActive
    }

    try await project.save(on: req.db)
    return try await projectResponseDTO(project: project, on: req.db)
}

@Sendable func getTrelloBoards(req: Request) async throws -> [TrelloBoardDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Trello integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.trelloToken else {
        throw Abort(.badRequest, reason: "Trello token not configured")
    }

    let boards = try await req.trelloService.getBoards(token: token)

    return boards.map { TrelloBoardDTO(id: $0.id, name: $0.name) }
}

@Sendable func getTrelloLists(req: Request) async throws -> [TrelloListDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Trello integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.trelloToken else {
        throw Abort(.badRequest, reason: "Trello token not configured")
    }

    guard let boardId = req.parameters.get("boardId") else {
        throw Abort(.badRequest, reason: "Board ID required")
    }

    let lists = try await req.trelloService.getLists(token: token, boardId: boardId)

    return lists.map { TrelloListDTO(id: $0.id, name: $0.name) }
}

@Sendable func createTrelloCard(req: Request) async throws -> CreateTrelloCardResponseDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Trello integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)
    let dto = try req.content.decode(CreateTrelloCardDTO.self)

    guard project.isTrelloActive else {
        throw Abort(.badRequest, reason: "Trello integration is not active")
    }

    guard let token = project.trelloToken,
          let listId = project.trelloListId else {
        throw Abort(.badRequest, reason: "Trello integration not configured")
    }

    // Get feedback with votes
    guard let feedback = try await Feedback.query(on: req.db)
        .filter(\.$id == dto.feedbackId)
        .filter(\.$project.$id == project.id!)
        .with(\.$votes)
        .first() else {
        throw Abort(.notFound, reason: "Feedback not found")
    }

    // Check if already has card
    if feedback.hasTrelloCard {
        throw Abort(.conflict, reason: "Feedback already has a Trello card")
    }

    // Calculate MRR
    let mrr = try await calculateMRR(for: feedback, on: req.db)

    // Build description
    let description = req.trelloService.buildCardDescription(
        feedback: feedback,
        projectName: project.name,
        voteCount: feedback.votes.count,
        mrr: mrr
    )

    // Create card
    let card = try await req.trelloService.createCard(
        token: token,
        listId: listId,
        name: feedback.title,
        description: description
    )

    // Update feedback
    feedback.trelloCardURL = card.url
    feedback.trelloCardId = card.id
    try await feedback.save(on: req.db)

    return CreateTrelloCardResponseDTO(
        feedbackId: feedback.id!,
        cardUrl: card.url,
        cardId: card.id
    )
}

@Sendable func bulkCreateTrelloCards(req: Request) async throws -> BulkCreateTrelloCardsResponseDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Trello integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)
    let dto = try req.content.decode(BulkCreateTrelloCardsDTO.self)

    guard project.isTrelloActive else {
        throw Abort(.badRequest, reason: "Trello integration is not active")
    }

    var created: [CreateTrelloCardResponseDTO] = []
    var failed: [UUID] = []

    for feedbackId in dto.feedbackIds {
        do {
            let singleDTO = CreateTrelloCardDTO(feedbackId: feedbackId)
            // Encode into request content for reuse
            try req.content.encode(singleDTO)
            let result = try await createTrelloCard(req: req)
            created.append(result)
        } catch {
            failed.append(feedbackId)
        }
    }

    return BulkCreateTrelloCardsResponseDTO(created: created, failed: failed)
}
```

### 6. Status Sync Implementation

Add to `FeedbackController` when status changes:

```swift
// In updateFeedback() after saving:
if project.isTrelloActive && project.trelloSyncStatus,
   let cardId = feedback.trelloCardId,
   let token = project.trelloToken,
   oldStatus != feedback.status {

    // Map status to list (requires status-to-list mapping on project)
    // For MVP: Skip automatic list movement, require manual setup
    // Future: Add trelloStatusMapping field to Project
}
```

### 7. Comment Sync Implementation

Add to `CommentController` after creating comment:

```swift
// In createComment() after saving:
if project.isTrelloActive && project.trelloSyncComments,
   let cardId = feedback.trelloCardId,
   let token = project.trelloToken {

    let commentText = """
    **\(user.name)** commented:

    \(comment.content)

    ---
    *From FeedbackKit*
    """

    try? await req.trelloService.addComment(
        token: token,
        cardId: cardId,
        text: commentText
    )
}
```

---

## Admin App Implementation

### 1. Model Updates

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/ProjectModels.swift`

```swift
// Add to Project struct
let trelloToken: String?
let trelloBoardId: String?
let trelloBoardName: String?
let trelloListId: String?
let trelloListName: String?
let trelloSyncStatus: Bool
let trelloSyncComments: Bool
let trelloIsActive: Bool

var isTrelloConfigured: Bool {
    trelloToken != nil && trelloBoardId != nil && trelloListId != nil
}

var isTrelloActive: Bool {
    isTrelloConfigured && trelloIsActive
}
```

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/FeedbackModels.swift`

```swift
// Add to Feedback struct
let trelloCardUrl: String?
let trelloCardId: String?

var hasTrelloCard: Bool {
    trelloCardUrl != nil
}
```

### 2. API Client Methods

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/AdminAPIClient.swift`

```swift
// MARK: - Trello Integration

struct TrelloBoardDTO: Codable {
    let id: String
    let name: String
}

struct TrelloListDTO: Codable {
    let id: String
    let name: String
}

func updateTrelloSettings(
    projectId: UUID,
    token: String?,
    boardId: String?,
    boardName: String?,
    listId: String?,
    listName: String?,
    syncStatus: Bool?,
    syncComments: Bool?,
    isActive: Bool?
) async throws -> Project {
    struct UpdateTrelloDTO: Encodable {
        var trelloToken: String?
        var trelloBoardId: String?
        var trelloBoardName: String?
        var trelloListId: String?
        var trelloListName: String?
        var trelloSyncStatus: Bool?
        var trelloSyncComments: Bool?
        var trelloIsActive: Bool?
    }

    let dto = UpdateTrelloDTO(
        trelloToken: token,
        trelloBoardId: boardId,
        trelloBoardName: boardName,
        trelloListId: listId,
        trelloListName: listName,
        trelloSyncStatus: syncStatus,
        trelloSyncComments: syncComments,
        trelloIsActive: isActive
    )

    return try await request(
        method: .patch,
        path: "/projects/\(projectId)/trello",
        body: dto
    )
}

func getTrelloBoards(projectId: UUID) async throws -> [TrelloBoardDTO] {
    try await request(
        method: .get,
        path: "/projects/\(projectId)/trello/boards"
    )
}

func getTrelloLists(projectId: UUID, boardId: String) async throws -> [TrelloListDTO] {
    try await request(
        method: .get,
        path: "/projects/\(projectId)/trello/boards/\(boardId)/lists"
    )
}

func createTrelloCard(projectId: UUID, feedbackId: UUID) async throws -> CreateCardResponseDTO {
    struct CreateCardDTO: Encodable {
        let feedbackId: UUID
    }

    return try await request(
        method: .post,
        path: "/projects/\(projectId)/trello/card",
        body: CreateCardDTO(feedbackId: feedbackId)
    )
}

func bulkCreateTrelloCards(projectId: UUID, feedbackIds: [UUID]) async throws -> BulkCreateCardsResponseDTO {
    struct BulkCreateDTO: Encodable {
        let feedbackIds: [UUID]
    }

    return try await request(
        method: .post,
        path: "/projects/\(projectId)/trello/cards",
        body: BulkCreateDTO(feedbackIds: feedbackIds)
    )
}
```

### 3. TrelloSettingsView

**File:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/TrelloSettingsView.swift`

```swift
import SwiftUI

struct TrelloSettingsView: View {
    let project: Project
    let onSave: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AdminAPIClient.self) private var apiClient
    @Environment(SubscriptionService.self) private var subscriptionService

    // State
    @State private var token: String = ""
    @State private var selectedBoardId: String?
    @State private var selectedBoardName: String?
    @State private var selectedListId: String?
    @State private var selectedListName: String?
    @State private var syncStatus: Bool = false
    @State private var syncComments: Bool = false
    @State private var isActive: Bool = true

    // Discovery
    @State private var boards: [TrelloBoardDTO] = []
    @State private var lists: [TrelloListDTO] = []

    // Loading states
    @State private var isLoadingBoards = false
    @State private var isLoadingLists = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Paywall
    @State private var showPaywall = false

    private var isConfigured: Bool {
        !token.isEmpty && selectedBoardId != nil && selectedListId != nil
    }

    var body: some View {
        Form {
            if project.isTrelloConfigured {
                activeToggleSection
            }

            tokenSection

            if !token.isEmpty {
                boardSection
            }

            if selectedBoardId != nil {
                listSection
            }

            if isConfigured {
                syncOptionsSection
            }

            if project.isTrelloConfigured {
                removeSection
            }
        }
        .navigationTitle("Trello Integration")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { loadExisting() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(requiredTier: .pro)
        }
    }

    // MARK: - Sections

    private var activeToggleSection: some View {
        Section {
            Toggle("Integration Active", isOn: $isActive)
        } footer: {
            Text("Disable to pause syncing without removing configuration.")
        }
    }

    private var tokenSection: some View {
        Section {
            SecureField("API Token", text: $token)
                .textContentType(.password)
                .onChange(of: token) { _, newValue in
                    if !newValue.isEmpty {
                        Task { await loadBoards() }
                    } else {
                        boards = []
                        selectedBoardId = nil
                        selectedBoardName = nil
                    }
                }

            Link("Get your Trello token", destination: tokenURL)
                .font(.footnote)
        } header: {
            Text("Authentication")
        } footer: {
            Text("Generate a token from Trello to connect your account.")
        }
    }

    private var boardSection: some View {
        Section {
            if isLoadingBoards {
                ProgressView()
            } else {
                Picker("Board", selection: $selectedBoardId) {
                    Text("Select a board").tag(nil as String?)
                    ForEach(boards, id: \.id) { board in
                        Text(board.name).tag(board.id as String?)
                    }
                }
                .onChange(of: selectedBoardId) { _, newValue in
                    if let id = newValue {
                        selectedBoardName = boards.first { $0.id == id }?.name
                        Task { await loadLists(boardId: id) }
                    } else {
                        selectedBoardName = nil
                        lists = []
                        selectedListId = nil
                        selectedListName = nil
                    }
                }
            }
        } header: {
            Text("Board")
        }
    }

    private var listSection: some View {
        Section {
            if isLoadingLists {
                ProgressView()
            } else {
                Picker("Default List", selection: $selectedListId) {
                    Text("Select a list").tag(nil as String?)
                    ForEach(lists, id: \.id) { list in
                        Text(list.name).tag(list.id as String?)
                    }
                }
                .onChange(of: selectedListId) { _, newValue in
                    selectedListName = lists.first { $0.id == newValue }?.name
                }
            }
        } header: {
            Text("List")
        } footer: {
            Text("New cards will be created in this list.")
        }
    }

    private var syncOptionsSection: some View {
        Section {
            Toggle("Sync Status Changes", isOn: $syncStatus)
            Toggle("Sync Comments", isOn: $syncComments)
        } header: {
            Text("Sync Options")
        } footer: {
            Text("Automatically sync feedback updates to Trello.")
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove Integration", role: .destructive) {
                Task { await removeIntegration() }
            }
        }
    }

    // MARK: - Token URL

    private var tokenURL: URL {
        // Replace YOUR_API_KEY with actual key from environment or config
        let apiKey = "YOUR_FEEDBACKKIT_API_KEY"
        return URL(string: "https://trello.com/1/authorize?expiration=never&scope=read,write&response_type=token&key=\(apiKey)&name=FeedbackKit")!
    }

    // MARK: - Actions

    private func loadExisting() {
        token = project.trelloToken ?? ""
        selectedBoardId = project.trelloBoardId
        selectedBoardName = project.trelloBoardName
        selectedListId = project.trelloListId
        selectedListName = project.trelloListName
        syncStatus = project.trelloSyncStatus
        syncComments = project.trelloSyncComments
        isActive = project.trelloIsActive

        if !token.isEmpty {
            Task {
                await loadBoards()
                if let boardId = selectedBoardId {
                    await loadLists(boardId: boardId)
                }
            }
        }
    }

    private func loadBoards() async {
        isLoadingBoards = true
        defer { isLoadingBoards = false }

        do {
            // Temporarily save token to fetch boards
            _ = try await apiClient.updateTrelloSettings(
                projectId: project.id,
                token: token,
                boardId: nil,
                boardName: nil,
                listId: nil,
                listName: nil,
                syncStatus: nil,
                syncComments: nil,
                isActive: nil
            )
            boards = try await apiClient.getTrelloBoards(projectId: project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLists(boardId: String) async {
        isLoadingLists = true
        defer { isLoadingLists = false }

        do {
            lists = try await apiClient.getTrelloLists(projectId: project.id, boardId: boardId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard subscriptionService.meetsRequirement(.pro) else {
            showPaywall = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await apiClient.updateTrelloSettings(
                projectId: project.id,
                token: token.isEmpty ? "" : token,
                boardId: selectedBoardId ?? "",
                boardName: selectedBoardName ?? "",
                listId: selectedListId ?? "",
                listName: selectedListName ?? "",
                syncStatus: syncStatus,
                syncComments: syncComments,
                isActive: isActive
            )
            onSave(updated)
            dismiss()
        } catch let error as APIError where error.statusCode == 402 {
            showPaywall = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeIntegration() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try await apiClient.updateTrelloSettings(
                projectId: project.id,
                token: "",
                boardId: "",
                boardName: "",
                listId: "",
                listName: "",
                syncStatus: false,
                syncComments: false,
                isActive: false
            )
            onSave(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### 4. Add to Integration Menu

Update `ProjectDetailView` or wherever integrations are listed to include Trello:

```swift
NavigationLink {
    TrelloSettingsView(project: project) { updated in
        // Handle update
    }
} label: {
    IntegrationRow(
        name: "Trello",
        icon: "square.stack.3d.up",
        isConfigured: project.isTrelloConfigured,
        isActive: project.isTrelloActive
    )
}
.tierBadge(.pro)
```

---

## Feature Mapping

### Status to List Mapping

For MVP, cards are created in the configured default list. Future enhancement: configurable status-to-list mapping.

| FeedbackKit Status | Suggested Trello List |
|--------------------|----------------------|
| pending | Backlog / To Do |
| approved | Approved / Ready |
| in_progress | In Progress / Doing |
| testflight | In Review / Testing |
| completed | Done / Complete |
| rejected | Closed / Won't Do |

### Card Description Template

```markdown
## {feedback.title}

{feedback.description}

---

**Project:** {project.name}
**Category:** {category}
**Status:** {status}
**Votes:** {voteCount}
**MRR:** ${mrr}

---
*Synced from FeedbackKit*
```

---

## Implementation Checklist

### Server

- [ ] Add `TRELLO_API_KEY` environment variable
- [ ] Create migration `AddProjectTrelloIntegration.swift`
- [ ] Register migration in `configure.swift`
- [ ] Update `Project.swift` model with Trello fields
- [ ] Update `Feedback.swift` model with Trello fields
- [ ] Add Trello DTOs to `ProjectDTO.swift`
- [ ] Update `ProjectResponseDTO` with Trello fields
- [ ] Create `TrelloService.swift`
- [ ] Add Trello routes to `ProjectController.swift`
- [ ] Implement `updateTrelloSettings` handler
- [ ] Implement `getTrelloBoards` handler
- [ ] Implement `getTrelloLists` handler
- [ ] Implement `createTrelloCard` handler
- [ ] Implement `bulkCreateTrelloCards` handler
- [ ] Add comment sync to `CommentController`
- [ ] Add status sync to `FeedbackController` (optional for MVP)
- [ ] Write tests for TrelloService
- [ ] Write tests for Trello endpoints

### Admin App

- [ ] Update `Project` model in `ProjectModels.swift`
- [ ] Update `Feedback` model in `FeedbackModels.swift`
- [ ] Add Trello methods to `AdminAPIClient.swift`
- [ ] Create `TrelloSettingsView.swift`
- [ ] Add Trello to integration menu in project details
- [ ] Add "Push to Trello" action in feedback list/detail
- [ ] Add Trello card link display in feedback detail
- [ ] Test on iOS
- [ ] Test on macOS

### Documentation

- [ ] Update root `CLAUDE.md` with Trello integration
- [ ] Update `SwiftlyFeedbackServer/CLAUDE.md` with API endpoints
- [ ] Update `SwiftlyFeedbackAdmin/CLAUDE.md` with UI details
- [ ] Add to SDK CHANGELOG.md (if SDK-related)

---

## Testing Plan

### Unit Tests

1. **TrelloService**
   - `testGetBoards` - Mock API response, verify parsing
   - `testGetLists` - Mock API response, verify parsing
   - `testCreateCard` - Mock API response, verify request format
   - `testAddComment` - Mock API response, verify request format
   - `testBuildCardDescription` - Verify markdown output

2. **ProjectController Trello Endpoints**
   - `testUpdateTrelloSettings` - Verify field updates
   - `testUpdateTrelloSettingsRequiresPro` - Verify 402 for non-Pro
   - `testGetTrelloBoards` - Verify discovery endpoint
   - `testCreateTrelloCard` - Verify card creation and feedback update
   - `testCreateTrelloCardAlreadyExists` - Verify 409 conflict

### Integration Tests

1. **End-to-end flow**
   - Configure Trello integration
   - Create feedback
   - Push to Trello
   - Verify card exists in Trello
   - Add comment, verify sync
   - Update status, verify sync (if implemented)

### Manual Testing

1. **Admin App (iOS)**
   - Navigate to project settings
   - Open Trello integration
   - Enter token, verify boards load
   - Select board, verify lists load
   - Save configuration
   - Create card from feedback
   - Verify card appears in Trello

2. **Admin App (macOS)**
   - Same flow as iOS
   - Verify keyboard navigation works

---

## References

### Trello API Documentation

- [API Introduction](https://developer.atlassian.com/cloud/trello/guides/rest-api/api-introduction/)
- [Authorization](https://developer.atlassian.com/cloud/trello/guides/rest-api/authorization/)
- [Cards API](https://developer.atlassian.com/cloud/trello/rest/api-group-cards/)
- [Boards API](https://developer.atlassian.com/cloud/trello/rest/api-group-boards/)

### Existing Integration References

- `SwiftlyFeedbackServer/Sources/App/Services/GitHubService.swift` - Simple REST integration
- `SwiftlyFeedbackServer/Sources/App/Services/ClickUpService.swift` - Complex hierarchy
- `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/ClickUpSettingsView.swift` - Settings UI pattern

---

## Future Enhancements

1. **Status-to-List Mapping** - Allow users to configure which Trello list corresponds to each FeedbackKit status
2. **Labels Support** - Map FeedbackKit categories to Trello labels
3. **Webhooks** - Receive updates from Trello to sync back to FeedbackKit
4. **Due Dates** - Sync estimated completion dates
5. **Attachments** - Sync screenshots or files attached to feedback
