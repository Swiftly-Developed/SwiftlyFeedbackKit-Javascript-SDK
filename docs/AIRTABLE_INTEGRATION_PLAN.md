# Airtable Integration Technical Plan

This document provides a detailed technical plan for implementing Airtable integration in FeedbackKit, following the established patterns used for Monday.com, ClickUp, Linear, GitHub, and Notion integrations.

## Table of Contents

1. [Overview](#overview)
2. [Airtable API Reference](#airtable-api-reference)
3. [Database Schema Changes](#database-schema-changes)
4. [Server Implementation](#server-implementation)
5. [Admin App Implementation](#admin-app-implementation)
6. [Status Mapping](#status-mapping)
7. [Implementation Checklist](#implementation-checklist)
8. [Testing Plan](#testing-plan)

---

## Overview

### Integration Features

| Feature | Support | Notes |
|---------|---------|-------|
| Push feedback to Airtable | Yes | Create records in configured table |
| Bulk creation | Yes | Create multiple records at once |
| Status sync | Yes | Update Single Select field on status change |
| Comment sync | Yes | Add comments to record (via Long Text field or linked Comments table) |
| Vote count sync | Yes | Update Number field with vote count |
| Link tracking | Yes | Store record URL and ID on feedback |
| Active toggle | Yes | Enable/disable integration without removing config |

### Hierarchy Structure

```
Airtable Workspace
└── Base (like a database)
    └── Table (like a spreadsheet)
        └── Fields (columns)
            ├── Single Select (for status)
            ├── Number (for votes)
            └── Long Text (for description/comments)
```

---

## Airtable API Reference

### Authentication

Airtable uses **Personal Access Tokens (PAT)** for authentication. OAuth is also available but PAT is simpler for integrations.

**Header format:**
```
Authorization: Bearer pat_xxxxxxxxxxxxxxxxxxxxx
```

**Token creation:**
1. Go to https://airtable.com/create/tokens
2. Create a new token with scopes:
   - `data.records:read` - Read records
   - `data.records:write` - Create/update records
   - `schema.bases:read` - List bases and tables

### Base URL

```
https://api.airtable.com/v0
```

### Rate Limits

- **5 requests per second** per base
- Implement exponential backoff for 429 responses

### Key Endpoints

#### List Bases
```http
GET /meta/bases
Authorization: Bearer {token}

Response:
{
  "bases": [
    {
      "id": "appXXXXXXXXXXXXXX",
      "name": "My Base",
      "permissionLevel": "create"
    }
  ]
}
```

#### Get Base Schema (Tables)
```http
GET /meta/bases/{baseId}/tables
Authorization: Bearer {token}

Response:
{
  "tables": [
    {
      "id": "tblXXXXXXXXXXXXXX",
      "name": "Feedback",
      "fields": [
        {
          "id": "fldXXXXXXXXXXXXXX",
          "name": "Status",
          "type": "singleSelect",
          "options": {
            "choices": [
              { "id": "selXXX", "name": "Pending", "color": "grayLight2" },
              { "id": "selYYY", "name": "Approved", "color": "blueLight2" }
            ]
          }
        },
        {
          "id": "fldYYYYYYYYYYYYYY",
          "name": "Votes",
          "type": "number"
        }
      ]
    }
  ]
}
```

#### Create Record
```http
POST /v0/{baseId}/{tableIdOrName}
Authorization: Bearer {token}
Content-Type: application/json

{
  "fields": {
    "Title": "Feature request title",
    "Description": "Detailed description here",
    "Status": "Pending",
    "Votes": 5,
    "Category": "Feature Request"
  },
  "typecast": true
}

Response:
{
  "id": "recXXXXXXXXXXXXXX",
  "createdTime": "2024-01-15T12:00:00.000Z",
  "fields": {
    "Title": "Feature request title",
    ...
  }
}
```

**Note:** `typecast: true` allows Airtable to automatically create new select options if they don't exist.

#### Update Record
```http
PATCH /v0/{baseId}/{tableIdOrName}/{recordId}
Authorization: Bearer {token}
Content-Type: application/json

{
  "fields": {
    "Status": "In Progress",
    "Votes": 10
  },
  "typecast": true
}
```

#### Bulk Create Records
```http
POST /v0/{baseId}/{tableIdOrName}
Authorization: Bearer {token}
Content-Type: application/json

{
  "records": [
    { "fields": { "Title": "Feedback 1", ... } },
    { "fields": { "Title": "Feedback 2", ... } }
  ],
  "typecast": true
}
```

**Limit:** Maximum 10 records per request

### Record URL Format

```
https://airtable.com/{baseId}/{tableId}/{recordId}
```

---

## Database Schema Changes

### Migration: `AddProjectAirtableIntegration.swift`

**Location:** `SwiftlyFeedbackServer/Sources/App/Migrations/AddProjectAirtableIntegration.swift`

```swift
import Fluent

struct AddProjectAirtableIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Add Airtable fields to projects table
        try await database.schema("projects")
            .field("airtable_token", .string)
            .field("airtable_base_id", .string)
            .field("airtable_base_name", .string)
            .field("airtable_table_id", .string)
            .field("airtable_table_name", .string)
            .field("airtable_sync_status", .bool, .required, .sql(.default(false)))
            .field("airtable_sync_comments", .bool, .required, .sql(.default(false)))
            .field("airtable_status_field_id", .string)
            .field("airtable_votes_field_id", .string)
            .field("airtable_title_field_id", .string)
            .field("airtable_description_field_id", .string)
            .field("airtable_category_field_id", .string)
            .field("airtable_is_active", .bool, .required, .sql(.default(true)))
            .update()

        // Add Airtable fields to feedbacks table
        try await database.schema("feedbacks")
            .field("airtable_record_url", .string)
            .field("airtable_record_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("airtable_token")
            .deleteField("airtable_base_id")
            .deleteField("airtable_base_name")
            .deleteField("airtable_table_id")
            .deleteField("airtable_table_name")
            .deleteField("airtable_sync_status")
            .deleteField("airtable_sync_comments")
            .deleteField("airtable_status_field_id")
            .deleteField("airtable_votes_field_id")
            .deleteField("airtable_title_field_id")
            .deleteField("airtable_description_field_id")
            .deleteField("airtable_category_field_id")
            .deleteField("airtable_is_active")
            .update()

        try await database.schema("feedbacks")
            .deleteField("airtable_record_url")
            .deleteField("airtable_record_id")
            .update()
    }
}
```

### Project Model Updates

**Location:** `SwiftlyFeedbackServer/Sources/App/Models/Project.swift`

Add the following fields to the `Project` model:

```swift
// MARK: - Airtable Integration

@OptionalField(key: "airtable_token")
var airtableToken: String?

@OptionalField(key: "airtable_base_id")
var airtableBaseId: String?

@OptionalField(key: "airtable_base_name")
var airtableBaseName: String?

@OptionalField(key: "airtable_table_id")
var airtableTableId: String?

@OptionalField(key: "airtable_table_name")
var airtableTableName: String?

@Field(key: "airtable_sync_status")
var airtableSyncStatus: Bool

@Field(key: "airtable_sync_comments")
var airtableSyncComments: Bool

@OptionalField(key: "airtable_status_field_id")
var airtableStatusFieldId: String?

@OptionalField(key: "airtable_votes_field_id")
var airtableVotesFieldId: String?

@OptionalField(key: "airtable_title_field_id")
var airtableTitleFieldId: String?

@OptionalField(key: "airtable_description_field_id")
var airtableDescriptionFieldId: String?

@OptionalField(key: "airtable_category_field_id")
var airtableCategoryFieldId: String?

@Field(key: "airtable_is_active")
var airtableIsActive: Bool
```

### Feedback Model Updates

**Location:** `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`

Add the following fields:

```swift
// MARK: - Airtable Integration

@OptionalField(key: "airtable_record_url")
var airtableRecordURL: String?

@OptionalField(key: "airtable_record_id")
var airtableRecordId: String?
```

---

## Server Implementation

### AirtableService

**Location:** `SwiftlyFeedbackServer/Sources/App/Services/AirtableService.swift`

```swift
import Vapor

struct AirtableService {
    private let client: Client
    private let baseURL = "https://api.airtable.com/v0"
    private let metaURL = "https://api.airtable.com/v0/meta"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct AirtableBase: Codable {
        let id: String
        let name: String
        let permissionLevel: String
    }

    struct AirtableTable: Codable {
        let id: String
        let name: String
        let fields: [AirtableField]
    }

    struct AirtableField: Codable {
        let id: String
        let name: String
        let type: String
        let options: FieldOptions?

        struct FieldOptions: Codable {
            let choices: [SelectChoice]?

            struct SelectChoice: Codable {
                let id: String
                let name: String
                let color: String?
            }
        }
    }

    struct AirtableRecord: Codable {
        let id: String
        let createdTime: String
        let fields: [String: AnyCodable]
    }

    struct BasesResponse: Codable {
        let bases: [AirtableBase]
        let offset: String?
    }

    struct TablesResponse: Codable {
        let tables: [AirtableTable]
    }

    struct CreateRecordResponse: Codable {
        let id: String
        let createdTime: String
        let fields: [String: AnyCodable]
    }

    struct BulkCreateResponse: Codable {
        let records: [CreateRecordResponse]
    }

    // MARK: - API Helper

    private func request<T: Decodable>(
        method: HTTPMethod,
        url: String,
        token: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        let uri = URI(string: url)

        let response = try await client.send(method, to: uri) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .contentType, value: "application/json")

            if let body = body {
                let jsonData = try JSONSerialization.data(withJSONObject: body)
                req.body = ByteBuffer(data: jsonData)
            }
        }

        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Airtable API returned empty response")
        }

        let data = Data(buffer: bodyData)

        // Check for error response
        if response.status == .tooManyRequests {
            throw Abort(.tooManyRequests, reason: "Airtable rate limit exceeded. Please try again.")
        }

        guard response.status.code >= 200 && response.status.code < 300 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Airtable API error (\(response.status)): \(responseBody)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "decode failed"
            throw Abort(.badGateway, reason: "Failed to decode Airtable response: \(error.localizedDescription). Body: \(responseBody)")
        }
    }

    // MARK: - List Bases

    func getBases(token: String) async throws -> [AirtableBase] {
        let response: BasesResponse = try await request(
            method: .GET,
            url: "\(metaURL)/bases",
            token: token
        )
        return response.bases
    }

    // MARK: - Get Tables for Base

    func getTables(baseId: String, token: String) async throws -> [AirtableTable] {
        let response: TablesResponse = try await request(
            method: .GET,
            url: "\(metaURL)/bases/\(baseId)/tables",
            token: token
        )
        return response.tables
    }

    // MARK: - Get Fields for Table

    func getFields(baseId: String, tableId: String, token: String) async throws -> [AirtableField] {
        let tables = try await getTables(baseId: baseId, token: token)
        guard let table = tables.first(where: { $0.id == tableId }) else {
            throw Abort(.notFound, reason: "Table not found")
        }
        return table.fields
    }

    // MARK: - Create Record

    func createRecord(
        baseId: String,
        tableId: String,
        token: String,
        fields: [String: Any]
    ) async throws -> CreateRecordResponse {
        let body: [String: Any] = [
            "fields": fields,
            "typecast": true
        ]

        return try await request(
            method: .POST,
            url: "\(baseURL)/\(baseId)/\(tableId)",
            token: token,
            body: body
        )
    }

    // MARK: - Update Record

    func updateRecord(
        baseId: String,
        tableId: String,
        recordId: String,
        token: String,
        fields: [String: Any]
    ) async throws {
        let body: [String: Any] = [
            "fields": fields,
            "typecast": true
        ]

        struct UpdateResponse: Codable {
            let id: String
        }

        let _: UpdateResponse = try await request(
            method: .PATCH,
            url: "\(baseURL)/\(baseId)/\(tableId)/\(recordId)",
            token: token,
            body: body
        )
    }

    // MARK: - Bulk Create Records

    func bulkCreateRecords(
        baseId: String,
        tableId: String,
        token: String,
        recordFields: [[String: Any]]
    ) async throws -> [CreateRecordResponse] {
        // Airtable limits to 10 records per request
        var allRecords: [CreateRecordResponse] = []

        for chunk in recordFields.chunked(into: 10) {
            let records = chunk.map { ["fields": $0] }
            let body: [String: Any] = [
                "records": records,
                "typecast": true
            ]

            let response: BulkCreateResponse = try await request(
                method: .POST,
                url: "\(baseURL)/\(baseId)/\(tableId)",
                token: token,
                body: body
            )

            allRecords.append(contentsOf: response.records)
        }

        return allRecords
    }

    // MARK: - Build Record URL

    func buildRecordURL(baseId: String, tableId: String, recordId: String) -> String {
        "https://airtable.com/\(baseId)/\(tableId)/\(recordId)"
    }

    // MARK: - Build Record Fields

    func buildRecordFields(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?,
        titleFieldId: String?,
        descriptionFieldId: String?,
        categoryFieldId: String?,
        statusFieldId: String?,
        votesFieldId: String?
    ) -> [String: Any] {
        var fields: [String: Any] = [:]

        // Use field IDs if configured, otherwise use default field names
        let titleKey = titleFieldId ?? "Title"
        let descriptionKey = descriptionFieldId ?? "Description"
        let categoryKey = categoryFieldId ?? "Category"

        fields[titleKey] = feedback.title

        // Build rich description
        var description = feedback.description
        description += "\n\n---"
        description += "\n**Source:** FeedbackKit"
        description += "\n**Project:** \(projectName)"
        description += "\n**Votes:** \(voteCount)"

        if let mrr = mrr, mrr > 0 {
            description += "\n**MRR:** $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            description += "\n**Submitted by:** \(userEmail)"
        }

        fields[descriptionKey] = description
        fields[categoryKey] = feedback.category.displayName

        // Optional status field
        if let statusFieldId = statusFieldId {
            fields[statusFieldId] = feedback.status.airtableStatusName
        }

        // Optional votes field
        if let votesFieldId = votesFieldId {
            fields[votesFieldId] = voteCount
        }

        return fields
    }
}

// MARK: - Request Extension

extension Request {
    var airtableService: AirtableService {
        AirtableService(client: self.client)
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

### DTOs

**Location:** `SwiftlyFeedbackServer/Sources/App/DTOs/ProjectDTO.swift`

Add the following DTOs:

```swift
// MARK: - Airtable DTOs

struct UpdateProjectAirtableDTO: Content {
    var airtableToken: String?
    var airtableBaseId: String?
    var airtableBaseName: String?
    var airtableTableId: String?
    var airtableTableName: String?
    var airtableSyncStatus: Bool?
    var airtableSyncComments: Bool?
    var airtableStatusFieldId: String?
    var airtableVotesFieldId: String?
    var airtableTitleFieldId: String?
    var airtableDescriptionFieldId: String?
    var airtableCategoryFieldId: String?
    var airtableIsActive: Bool?
}

struct CreateAirtableRecordDTO: Content, Validatable {
    var feedbackId: UUID

    static func validations(_ validations: inout Validations) {
        validations.add("feedbackId", as: UUID.self, is: .valid)
    }
}

struct BulkCreateAirtableRecordsDTO: Content, Validatable {
    var feedbackIds: [UUID]

    static func validations(_ validations: inout Validations) {
        validations.add("feedbackIds", as: [UUID].self, is: !.empty)
    }
}

struct CreateAirtableRecordResponseDTO: Content {
    var feedbackId: UUID
    var recordUrl: String
    var recordId: String
}

struct BulkCreateAirtableRecordsResponseDTO: Content {
    var created: [CreateAirtableRecordResponseDTO]
    var failed: [UUID]
}

struct AirtableBaseDTO: Content {
    var id: String
    var name: String
}

struct AirtableTableDTO: Content {
    var id: String
    var name: String
}

struct AirtableFieldDTO: Content {
    var id: String
    var name: String
    var type: String
}
```

### Controller Endpoints

**Location:** `SwiftlyFeedbackServer/Sources/App/Controllers/ProjectController.swift`

Add the following routes and handlers:

```swift
// MARK: - Route Registration (in routes method)

// Airtable Integration
protected.patch(":projectId", "airtable", use: updateAirtableSettings)
protected.post(":projectId", "airtable", "record", use: createAirtableRecord)
protected.post(":projectId", "airtable", "records", use: bulkCreateAirtableRecords)
protected.get(":projectId", "airtable", "bases", use: getAirtableBases)
protected.get(":projectId", "airtable", "tables", ":baseId", use: getAirtableTables)
protected.get(":projectId", "airtable", "fields", use: getAirtableFields)

// MARK: - Airtable Handlers

@Sendable
func updateAirtableSettings(req: Request) async throws -> ProjectResponseDTO {
    let user = try req.auth.require(User.self)

    // Tier check - Pro required for integrations
    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Airtable integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)
    let dto = try req.content.decode(UpdateProjectAirtableDTO.self)

    if let token = dto.airtableToken {
        project.airtableToken = token.isEmpty ? nil : token
    }
    if let baseId = dto.airtableBaseId {
        project.airtableBaseId = baseId.isEmpty ? nil : baseId
    }
    if let baseName = dto.airtableBaseName {
        project.airtableBaseName = baseName.isEmpty ? nil : baseName
    }
    if let tableId = dto.airtableTableId {
        project.airtableTableId = tableId.isEmpty ? nil : tableId
    }
    if let tableName = dto.airtableTableName {
        project.airtableTableName = tableName.isEmpty ? nil : tableName
    }
    if let syncStatus = dto.airtableSyncStatus {
        project.airtableSyncStatus = syncStatus
    }
    if let syncComments = dto.airtableSyncComments {
        project.airtableSyncComments = syncComments
    }
    if let statusFieldId = dto.airtableStatusFieldId {
        project.airtableStatusFieldId = statusFieldId.isEmpty ? nil : statusFieldId
    }
    if let votesFieldId = dto.airtableVotesFieldId {
        project.airtableVotesFieldId = votesFieldId.isEmpty ? nil : votesFieldId
    }
    if let titleFieldId = dto.airtableTitleFieldId {
        project.airtableTitleFieldId = titleFieldId.isEmpty ? nil : titleFieldId
    }
    if let descriptionFieldId = dto.airtableDescriptionFieldId {
        project.airtableDescriptionFieldId = descriptionFieldId.isEmpty ? nil : descriptionFieldId
    }
    if let categoryFieldId = dto.airtableCategoryFieldId {
        project.airtableCategoryFieldId = categoryFieldId.isEmpty ? nil : categoryFieldId
    }
    if let isActive = dto.airtableIsActive {
        project.airtableIsActive = isActive
    }

    try await project.save(on: req.db)

    return try await buildProjectResponse(project: project, on: req.db)
}

@Sendable
func createAirtableRecord(req: Request) async throws -> CreateAirtableRecordResponseDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Airtable integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.airtableToken,
          let baseId = project.airtableBaseId,
          let tableId = project.airtableTableId else {
        throw Abort(.badRequest, reason: "Airtable integration not configured")
    }

    guard project.airtableIsActive else {
        throw Abort(.badRequest, reason: "Airtable integration is disabled")
    }

    let dto = try req.content.decode(CreateAirtableRecordDTO.self)

    guard let feedback = try await Feedback.find(dto.feedbackId, on: req.db) else {
        throw Abort(.notFound, reason: "Feedback not found")
    }

    // Prevent duplicate links
    if feedback.airtableRecordURL != nil {
        throw Abort(.conflict, reason: "Feedback already has an Airtable record")
    }

    // Calculate MRR for voters
    let totalMrr = try await calculateMrrForFeedback(feedbackId: feedback.id!, on: req.db)

    // Build record fields
    let fields = req.airtableService.buildRecordFields(
        feedback: feedback,
        projectName: project.name,
        voteCount: feedback.voteCount,
        mrr: totalMrr > 0 ? totalMrr : nil,
        titleFieldId: project.airtableTitleFieldId,
        descriptionFieldId: project.airtableDescriptionFieldId,
        categoryFieldId: project.airtableCategoryFieldId,
        statusFieldId: project.airtableStatusFieldId,
        votesFieldId: project.airtableVotesFieldId
    )

    // Create record
    let response = try await req.airtableService.createRecord(
        baseId: baseId,
        tableId: tableId,
        token: token,
        fields: fields
    )

    // Build and store URL
    let recordUrl = req.airtableService.buildRecordURL(
        baseId: baseId,
        tableId: tableId,
        recordId: response.id
    )

    feedback.airtableRecordURL = recordUrl
    feedback.airtableRecordId = response.id
    try await feedback.save(on: req.db)

    return CreateAirtableRecordResponseDTO(
        feedbackId: feedback.id!,
        recordUrl: recordUrl,
        recordId: response.id
    )
}

@Sendable
func bulkCreateAirtableRecords(req: Request) async throws -> BulkCreateAirtableRecordsResponseDTO {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Airtable integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.airtableToken,
          let baseId = project.airtableBaseId,
          let tableId = project.airtableTableId else {
        throw Abort(.badRequest, reason: "Airtable integration not configured")
    }

    guard project.airtableIsActive else {
        throw Abort(.badRequest, reason: "Airtable integration is disabled")
    }

    let dto = try req.content.decode(BulkCreateAirtableRecordsDTO.self)

    var created: [CreateAirtableRecordResponseDTO] = []
    var failed: [UUID] = []

    for feedbackId in dto.feedbackIds {
        do {
            guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
                failed.append(feedbackId)
                continue
            }

            // Skip if already linked
            if feedback.airtableRecordURL != nil {
                failed.append(feedbackId)
                continue
            }

            let totalMrr = try await calculateMrrForFeedback(feedbackId: feedbackId, on: req.db)

            let fields = req.airtableService.buildRecordFields(
                feedback: feedback,
                projectName: project.name,
                voteCount: feedback.voteCount,
                mrr: totalMrr > 0 ? totalMrr : nil,
                titleFieldId: project.airtableTitleFieldId,
                descriptionFieldId: project.airtableDescriptionFieldId,
                categoryFieldId: project.airtableCategoryFieldId,
                statusFieldId: project.airtableStatusFieldId,
                votesFieldId: project.airtableVotesFieldId
            )

            let response = try await req.airtableService.createRecord(
                baseId: baseId,
                tableId: tableId,
                token: token,
                fields: fields
            )

            let recordUrl = req.airtableService.buildRecordURL(
                baseId: baseId,
                tableId: tableId,
                recordId: response.id
            )

            feedback.airtableRecordURL = recordUrl
            feedback.airtableRecordId = response.id
            try await feedback.save(on: req.db)

            created.append(CreateAirtableRecordResponseDTO(
                feedbackId: feedbackId,
                recordUrl: recordUrl,
                recordId: response.id
            ))
        } catch {
            req.logger.error("Failed to create Airtable record for \(feedbackId): \(error)")
            failed.append(feedbackId)
        }
    }

    return BulkCreateAirtableRecordsResponseDTO(created: created, failed: failed)
}

@Sendable
func getAirtableBases(req: Request) async throws -> [AirtableBaseDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Airtable integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.airtableToken else {
        throw Abort(.badRequest, reason: "Airtable token not configured")
    }

    let bases = try await req.airtableService.getBases(token: token)

    return bases.map { AirtableBaseDTO(id: $0.id, name: $0.name) }
}

@Sendable
func getAirtableTables(req: Request) async throws -> [AirtableTableDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Airtable integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.airtableToken else {
        throw Abort(.badRequest, reason: "Airtable token not configured")
    }

    guard let baseId = req.parameters.get("baseId") else {
        throw Abort(.badRequest, reason: "Base ID required")
    }

    let tables = try await req.airtableService.getTables(baseId: baseId, token: token)

    return tables.map { AirtableTableDTO(id: $0.id, name: $0.name) }
}

@Sendable
func getAirtableFields(req: Request) async throws -> [AirtableFieldDTO] {
    let user = try req.auth.require(User.self)

    guard user.subscriptionTier.meetsRequirement(.pro) else {
        throw Abort(.paymentRequired, reason: "Airtable integration requires Pro subscription")
    }

    let project = try await getProjectAsOwnerOrAdmin(req: req, user: user)

    guard let token = project.airtableToken,
          let baseId = project.airtableBaseId,
          let tableId = project.airtableTableId else {
        throw Abort(.badRequest, reason: "Airtable base and table not configured")
    }

    let fields = try await req.airtableService.getFields(
        baseId: baseId,
        tableId: tableId,
        token: token
    )

    return fields.map { AirtableFieldDTO(id: $0.id, name: $0.name, type: $0.type) }
}
```

### Status Sync on Feedback Update

**Location:** `SwiftlyFeedbackServer/Sources/App/Controllers/FeedbackController.swift`

Add Airtable sync to the status update handler (similar to existing integrations):

```swift
// In updateFeedbackStatus or updateFeedback handler, after saving:

// Sync to Airtable if enabled
if project.airtableSyncStatus,
   project.airtableIsActive,
   let token = project.airtableToken,
   let baseId = project.airtableBaseId,
   let tableId = project.airtableTableId,
   let recordId = feedback.airtableRecordId,
   let statusFieldId = project.airtableStatusFieldId {
    Task {
        try? await req.airtableService.updateRecord(
            baseId: baseId,
            tableId: tableId,
            recordId: recordId,
            token: token,
            fields: [statusFieldId: feedback.status.airtableStatusName]
        )
    }
}
```

### Vote Count Sync

**Location:** `SwiftlyFeedbackServer/Sources/App/Controllers/VoteController.swift`

Add Airtable sync when votes change:

```swift
// After vote is added/removed:

// Sync vote count to Airtable if enabled
if let project = try? await Project.find(feedback.$project.id, on: req.db),
   project.airtableIsActive,
   let token = project.airtableToken,
   let baseId = project.airtableBaseId,
   let tableId = project.airtableTableId,
   let recordId = feedback.airtableRecordId,
   let votesFieldId = project.airtableVotesFieldId {
    Task {
        try? await req.airtableService.updateRecord(
            baseId: baseId,
            tableId: tableId,
            recordId: recordId,
            token: token,
            fields: [votesFieldId: feedback.voteCount]
        )
    }
}
```

### Comment Sync

**Location:** `SwiftlyFeedbackServer/Sources/App/Controllers/CommentController.swift`

Add Airtable sync when comments are added:

```swift
// After comment is created:

// Note: Airtable doesn't have native comments on records.
// Options:
// 1. Append to a Long Text field (not ideal for multiple comments)
// 2. Create linked records in a Comments table
// 3. Skip comment sync for Airtable

// Recommended: Skip or use linked table approach
// For simplicity, this plan omits comment sync for Airtable
```

---

## Admin App Implementation

### Models

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/Project.swift`

Add Airtable fields to the Project model:

```swift
// MARK: - Airtable Integration

var airtableToken: String?
var airtableBaseId: String?
var airtableBaseName: String?
var airtableTableId: String?
var airtableTableName: String?
var airtableSyncStatus: Bool
var airtableSyncComments: Bool
var airtableStatusFieldId: String?
var airtableVotesFieldId: String?
var airtableTitleFieldId: String?
var airtableDescriptionFieldId: String?
var airtableCategoryFieldId: String?
var airtableIsActive: Bool
```

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/Feedback.swift`

```swift
// MARK: - Airtable Integration

var airtableRecordURL: String?
var airtableRecordId: String?
```

### Airtable Models

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Models/AirtableModels.swift` (new file)

```swift
import Foundation

struct AirtableBase: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct AirtableTable: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct AirtableField: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
}

struct CreateAirtableRecordResponse: Codable {
    let feedbackId: UUID
    let recordUrl: String
    let recordId: String
}

struct BulkCreateAirtableRecordsResponse: Codable {
    let created: [CreateAirtableRecordResponse]
    let failed: [UUID]
}
```

### API Client Methods

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Services/AdminAPIClient.swift`

```swift
// MARK: - Airtable Integration

func updateProjectAirtableSettings(
    projectId: UUID,
    airtableToken: String?,
    airtableBaseId: String?,
    airtableBaseName: String?,
    airtableTableId: String?,
    airtableTableName: String?,
    airtableSyncStatus: Bool?,
    airtableSyncComments: Bool?,
    airtableStatusFieldId: String?,
    airtableVotesFieldId: String?,
    airtableTitleFieldId: String?,
    airtableDescriptionFieldId: String?,
    airtableCategoryFieldId: String?,
    airtableIsActive: Bool?
) async throws -> Project {
    let path = "projects/\(projectId)/airtable"
    let body = UpdateProjectAirtableRequest(
        airtableToken: airtableToken,
        airtableBaseId: airtableBaseId,
        airtableBaseName: airtableBaseName,
        airtableTableId: airtableTableId,
        airtableTableName: airtableTableName,
        airtableSyncStatus: airtableSyncStatus,
        airtableSyncComments: airtableSyncComments,
        airtableStatusFieldId: airtableStatusFieldId,
        airtableVotesFieldId: airtableVotesFieldId,
        airtableTitleFieldId: airtableTitleFieldId,
        airtableDescriptionFieldId: airtableDescriptionFieldId,
        airtableCategoryFieldId: airtableCategoryFieldId,
        airtableIsActive: airtableIsActive
    )
    return try await patch(path: path, body: body)
}

func createAirtableRecord(
    projectId: UUID,
    feedbackId: UUID
) async throws -> CreateAirtableRecordResponse {
    let path = "projects/\(projectId)/airtable/record"
    let body = CreateAirtableRecordRequest(feedbackId: feedbackId)
    return try await post(path: path, body: body)
}

func bulkCreateAirtableRecords(
    projectId: UUID,
    feedbackIds: [UUID]
) async throws -> BulkCreateAirtableRecordsResponse {
    let path = "projects/\(projectId)/airtable/records"
    let body = BulkCreateAirtableRecordsRequest(feedbackIds: feedbackIds)
    return try await post(path: path, body: body)
}

func getAirtableBases(projectId: UUID) async throws -> [AirtableBase] {
    let path = "projects/\(projectId)/airtable/bases"
    return try await get(path: path)
}

func getAirtableTables(projectId: UUID, baseId: String) async throws -> [AirtableTable] {
    let path = "projects/\(projectId)/airtable/tables/\(baseId)"
    return try await get(path: path)
}

func getAirtableFields(projectId: UUID) async throws -> [AirtableField] {
    let path = "projects/\(projectId)/airtable/fields"
    return try await get(path: path)
}

// Request types
private struct UpdateProjectAirtableRequest: Codable {
    let airtableToken: String?
    let airtableBaseId: String?
    let airtableBaseName: String?
    let airtableTableId: String?
    let airtableTableName: String?
    let airtableSyncStatus: Bool?
    let airtableSyncComments: Bool?
    let airtableStatusFieldId: String?
    let airtableVotesFieldId: String?
    let airtableTitleFieldId: String?
    let airtableDescriptionFieldId: String?
    let airtableCategoryFieldId: String?
    let airtableIsActive: Bool?
}

private struct CreateAirtableRecordRequest: Codable {
    let feedbackId: UUID
}

private struct BulkCreateAirtableRecordsRequest: Codable {
    let feedbackIds: [UUID]
}
```

### ProjectViewModel Methods

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/ViewModels/ProjectViewModel.swift`

```swift
// MARK: - Airtable Integration

func updateAirtableSettings(
    projectId: UUID,
    airtableToken: String?,
    airtableBaseId: String?,
    airtableBaseName: String?,
    airtableTableId: String?,
    airtableTableName: String?,
    airtableSyncStatus: Bool?,
    airtableSyncComments: Bool?,
    airtableStatusFieldId: String?,
    airtableVotesFieldId: String?,
    airtableTitleFieldId: String?,
    airtableDescriptionFieldId: String?,
    airtableCategoryFieldId: String?,
    airtableIsActive: Bool?
) async -> UpdateResult {
    isLoading = true
    defer { isLoading = false }

    do {
        let updatedProject = try await apiClient.updateProjectAirtableSettings(
            projectId: projectId,
            airtableToken: airtableToken,
            airtableBaseId: airtableBaseId,
            airtableBaseName: airtableBaseName,
            airtableTableId: airtableTableId,
            airtableTableName: airtableTableName,
            airtableSyncStatus: airtableSyncStatus,
            airtableSyncComments: airtableSyncComments,
            airtableStatusFieldId: airtableStatusFieldId,
            airtableVotesFieldId: airtableVotesFieldId,
            airtableTitleFieldId: airtableTitleFieldId,
            airtableDescriptionFieldId: airtableDescriptionFieldId,
            airtableCategoryFieldId: airtableCategoryFieldId,
            airtableIsActive: airtableIsActive
        )

        if let index = projects.firstIndex(where: { $0.id == projectId }) {
            projects[index] = updatedProject
        }

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

func loadAirtableBases(projectId: UUID) async -> [AirtableBase] {
    do {
        return try await apiClient.getAirtableBases(projectId: projectId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadAirtableTables(projectId: UUID, baseId: String) async -> [AirtableTable] {
    do {
        return try await apiClient.getAirtableTables(projectId: projectId, baseId: baseId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func loadAirtableFields(projectId: UUID) async -> [AirtableField] {
    do {
        return try await apiClient.getAirtableFields(projectId: projectId)
    } catch {
        errorMessage = error.localizedDescription
        return []
    }
}

func createAirtableRecord(projectId: UUID, feedbackId: UUID) async -> CreateAirtableRecordResponse? {
    do {
        return try await apiClient.createAirtableRecord(projectId: projectId, feedbackId: feedbackId)
    } catch {
        errorMessage = error.localizedDescription
        showError = true
        return nil
    }
}

func bulkCreateAirtableRecords(projectId: UUID, feedbackIds: [UUID]) async -> BulkCreateAirtableRecordsResponse? {
    do {
        return try await apiClient.bulkCreateAirtableRecords(projectId: projectId, feedbackIds: feedbackIds)
    } catch {
        errorMessage = error.localizedDescription
        showError = true
        return nil
    }
}
```

### Settings View

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/AirtableSettingsView.swift` (new file)

```swift
import SwiftUI

struct AirtableSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var token: String
    @State private var baseId: String
    @State private var baseName: String
    @State private var tableId: String
    @State private var tableName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var statusFieldId: String
    @State private var votesFieldId: String
    @State private var titleFieldId: String
    @State private var descriptionFieldId: String
    @State private var categoryFieldId: String
    @State private var isActive: Bool
    @State private var showingTokenInfo = false

    // Selection state
    @State private var bases: [AirtableBase] = []
    @State private var tables: [AirtableTable] = []
    @State private var fields: [AirtableField] = []
    @State private var selectedBase: AirtableBase?
    @State private var selectedTable: AirtableTable?
    @State private var selectedStatusField: AirtableField?
    @State private var selectedVotesField: AirtableField?
    @State private var selectedTitleField: AirtableField?
    @State private var selectedDescriptionField: AirtableField?
    @State private var selectedCategoryField: AirtableField?

    @State private var isLoadingBases = false
    @State private var isLoadingTables = false
    @State private var isLoadingFields = false
    @State private var basesError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _token = State(initialValue: project.airtableToken ?? "")
        _baseId = State(initialValue: project.airtableBaseId ?? "")
        _baseName = State(initialValue: project.airtableBaseName ?? "")
        _tableId = State(initialValue: project.airtableTableId ?? "")
        _tableName = State(initialValue: project.airtableTableName ?? "")
        _syncStatus = State(initialValue: project.airtableSyncStatus)
        _syncComments = State(initialValue: project.airtableSyncComments)
        _statusFieldId = State(initialValue: project.airtableStatusFieldId ?? "")
        _votesFieldId = State(initialValue: project.airtableVotesFieldId ?? "")
        _titleFieldId = State(initialValue: project.airtableTitleFieldId ?? "")
        _descriptionFieldId = State(initialValue: project.airtableDescriptionFieldId ?? "")
        _categoryFieldId = State(initialValue: project.airtableCategoryFieldId ?? "")
        _isActive = State(initialValue: project.airtableIsActive)
    }

    private var hasChanges: Bool {
        token != (project.airtableToken ?? "") ||
        baseId != (project.airtableBaseId ?? "") ||
        baseName != (project.airtableBaseName ?? "") ||
        tableId != (project.airtableTableId ?? "") ||
        tableName != (project.airtableTableName ?? "") ||
        syncStatus != project.airtableSyncStatus ||
        syncComments != project.airtableSyncComments ||
        statusFieldId != (project.airtableStatusFieldId ?? "") ||
        votesFieldId != (project.airtableVotesFieldId ?? "") ||
        titleFieldId != (project.airtableTitleFieldId ?? "") ||
        descriptionFieldId != (project.airtableDescriptionFieldId ?? "") ||
        categoryFieldId != (project.airtableCategoryFieldId ?? "") ||
        isActive != project.airtableIsActive
    }

    private var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tableId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        Text("When disabled, Airtable sync will be paused.")
                    }
                }

                Section {
                    SecureField("Personal Access Token", text: $token)
                        .onChange(of: token) { _, newValue in
                            if !newValue.isEmpty && bases.isEmpty {
                                loadBases()
                            }
                        }

                    Button {
                        showingTokenInfo = true
                    } label: {
                        Label("How to create a token", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Create a Personal Access Token at airtable.com/create/tokens with data.records:read, data.records:write, and schema.bases:read scopes.")
                }

                if hasToken {
                    Section {
                        if isLoadingBases {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading bases...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = basesError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                loadBases()
                            }
                        } else {
                            Picker("Base", selection: $selectedBase) {
                                Text("Select Base").tag(nil as AirtableBase?)
                                ForEach(bases) { base in
                                    Text(base.name).tag(base as AirtableBase?)
                                }
                            }
                            .onChange(of: selectedBase) { _, newValue in
                                if let base = newValue {
                                    baseId = base.id
                                    baseName = base.name
                                    loadTables(baseId: base.id)
                                } else {
                                    baseId = ""
                                    baseName = ""
                                    tables = []
                                    fields = []
                                    selectedTable = nil
                                    clearFieldSelections()
                                }
                            }
                        }
                    } header: {
                        Text("Target Base")
                    } footer: {
                        if isConfigured {
                            Text("Selected: \(baseName)")
                        } else {
                            Text("Select the Airtable base containing your feedback table.")
                        }
                    }
                }

                if !baseId.isEmpty {
                    Section {
                        if isLoadingTables {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading tables...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Table", selection: $selectedTable) {
                                Text("Select Table").tag(nil as AirtableTable?)
                                ForEach(tables) { table in
                                    Text(table.name).tag(table as AirtableTable?)
                                }
                            }
                            .onChange(of: selectedTable) { _, newValue in
                                if let table = newValue {
                                    tableId = table.id
                                    tableName = table.name
                                    loadFields()
                                } else {
                                    tableId = ""
                                    tableName = ""
                                    fields = []
                                    clearFieldSelections()
                                }
                            }
                        }
                    } header: {
                        Text("Target Table")
                    } footer: {
                        Text("Select the table where feedback records will be created.")
                    }
                }

                if isConfigured && !fields.isEmpty {
                    fieldMappingSection
                    syncOptionsSection
                }

                if isConfigured {
                    Section {
                        Button(role: .destructive) {
                            clearIntegration()
                        } label: {
                            Label("Remove Airtable Integration", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Airtable Integration")
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
            .alert("Create Airtable Personal Access Token", isPresented: $showingTokenInfo) {
                Button("Open Airtable") {
                    if let url = URL(string: "https://airtable.com/create/tokens") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to airtable.com/create/tokens\n2. Click 'Create new token'\n3. Add scopes: data.records:read, data.records:write, schema.bases:read\n4. Select your base(s)\n5. Copy the token")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasToken {
                    loadBases()
                }
            }
        }
    }

    @ViewBuilder
    private var fieldMappingSection: some View {
        let textFields = fields.filter { ["singleLineText", "multilineText", "richText"].contains($0.type) }
        let selectFields = fields.filter { $0.type == "singleSelect" }
        let numberFields = fields.filter { $0.type == "number" }

        Section {
            if !textFields.isEmpty {
                Picker("Title Field", selection: $selectedTitleField) {
                    Text("Auto-detect").tag(nil as AirtableField?)
                    ForEach(textFields) { field in
                        Text(field.name).tag(field as AirtableField?)
                    }
                }
                .onChange(of: selectedTitleField) { _, newValue in
                    titleFieldId = newValue?.id ?? ""
                }

                Picker("Description Field", selection: $selectedDescriptionField) {
                    Text("Auto-detect").tag(nil as AirtableField?)
                    ForEach(textFields) { field in
                        Text(field.name).tag(field as AirtableField?)
                    }
                }
                .onChange(of: selectedDescriptionField) { _, newValue in
                    descriptionFieldId = newValue?.id ?? ""
                }
            }

            if !selectFields.isEmpty {
                Picker("Category Field", selection: $selectedCategoryField) {
                    Text("None").tag(nil as AirtableField?)
                    ForEach(selectFields) { field in
                        Text(field.name).tag(field as AirtableField?)
                    }
                }
                .onChange(of: selectedCategoryField) { _, newValue in
                    categoryFieldId = newValue?.id ?? ""
                }
            }
        } header: {
            Text("Field Mapping")
        } footer: {
            Text("Map feedback properties to Airtable fields. 'Auto-detect' uses default field names (Title, Description).")
        }

        if !selectFields.isEmpty {
            Section {
                Picker("Status Field", selection: $selectedStatusField) {
                    Text("None").tag(nil as AirtableField?)
                    ForEach(selectFields) { field in
                        Text(field.name).tag(field as AirtableField?)
                    }
                }
                .onChange(of: selectedStatusField) { _, newValue in
                    statusFieldId = newValue?.id ?? ""
                }
            } header: {
                Text("Status Mapping")
            } footer: {
                Text("Select a Single Select field to sync feedback status. Options should include: Pending, Approved, In Progress, TestFlight, Completed, Rejected.")
            }
        }

        if !numberFields.isEmpty {
            Section {
                Picker("Votes Field", selection: $selectedVotesField) {
                    Text("None").tag(nil as AirtableField?)
                    ForEach(numberFields) { field in
                        Text(field.name).tag(field as AirtableField?)
                    }
                }
                .onChange(of: selectedVotesField) { _, newValue in
                    votesFieldId = newValue?.id ?? ""
                }
            } header: {
                Text("Vote Count")
            } footer: {
                Text("Select a Number field to sync vote counts.")
            }
        }
    }

    @ViewBuilder
    private var syncOptionsSection: some View {
        Section {
            Toggle("Sync status changes", isOn: $syncStatus)
            // Note: Comment sync is complex for Airtable, may be disabled
            // Toggle("Sync comments", isOn: $syncComments)
        } header: {
            Text("Sync Options")
        } footer: {
            Text("Automatically update Airtable record status when feedback status changes in FeedbackKit.")
        }
    }

    private func clearFieldSelections() {
        selectedStatusField = nil
        selectedVotesField = nil
        selectedTitleField = nil
        selectedDescriptionField = nil
        selectedCategoryField = nil
        statusFieldId = ""
        votesFieldId = ""
        titleFieldId = ""
        descriptionFieldId = ""
        categoryFieldId = ""
    }

    private func loadBases() {
        guard hasToken else { return }

        isLoadingBases = true
        basesError = nil

        Task {
            // First save the token so the API can use it
            let result = await viewModel.updateAirtableSettings(
                projectId: project.id,
                airtableToken: token.trimmingCharacters(in: .whitespacesAndNewlines),
                airtableBaseId: nil,
                airtableBaseName: nil,
                airtableTableId: nil,
                airtableTableName: nil,
                airtableSyncStatus: nil,
                airtableSyncComments: nil,
                airtableStatusFieldId: nil,
                airtableVotesFieldId: nil,
                airtableTitleFieldId: nil,
                airtableDescriptionFieldId: nil,
                airtableCategoryFieldId: nil,
                airtableIsActive: nil
            )

            if result == .success {
                bases = await viewModel.loadAirtableBases(projectId: project.id)
                if bases.isEmpty {
                    basesError = "No bases found. Make sure your token has access to at least one base."
                } else {
                    // Pre-select if baseId is already set
                    if !baseId.isEmpty {
                        selectedBase = bases.first { $0.id == baseId }
                        if selectedBase != nil {
                            loadTables(baseId: baseId)
                        }
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                basesError = viewModel.errorMessage ?? "Failed to verify token"
            }

            isLoadingBases = false
        }
    }

    private func loadTables(baseId: String) {
        isLoadingTables = true
        Task {
            tables = await viewModel.loadAirtableTables(projectId: project.id, baseId: baseId)

            // Pre-select if tableId is already set
            if !tableId.isEmpty {
                selectedTable = tables.first { $0.id == tableId }
                if selectedTable != nil {
                    loadFields()
                }
            }

            isLoadingTables = false
        }
    }

    private func loadFields() {
        isLoadingFields = true
        Task {
            fields = await viewModel.loadAirtableFields(projectId: project.id)

            // Pre-select configured fields
            if !statusFieldId.isEmpty {
                selectedStatusField = fields.first { $0.id == statusFieldId }
            }
            if !votesFieldId.isEmpty {
                selectedVotesField = fields.first { $0.id == votesFieldId }
            }
            if !titleFieldId.isEmpty {
                selectedTitleField = fields.first { $0.id == titleFieldId }
            }
            if !descriptionFieldId.isEmpty {
                selectedDescriptionField = fields.first { $0.id == descriptionFieldId }
            }
            if !categoryFieldId.isEmpty {
                selectedCategoryField = fields.first { $0.id == categoryFieldId }
            }

            isLoadingFields = false
        }
    }

    private func clearIntegration() {
        token = ""
        baseId = ""
        baseName = ""
        tableId = ""
        tableName = ""
        syncStatus = false
        syncComments = false
        clearFieldSelections()
        selectedBase = nil
        selectedTable = nil
        bases = []
        tables = []
        fields = []
    }

    private func saveSettings() {
        Task {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateAirtableSettings(
                projectId: project.id,
                airtableToken: trimmedToken.isEmpty ? "" : trimmedToken,
                airtableBaseId: baseId.isEmpty ? "" : baseId,
                airtableBaseName: baseName.isEmpty ? "" : baseName,
                airtableTableId: tableId.isEmpty ? "" : tableId,
                airtableTableName: tableName.isEmpty ? "" : tableName,
                airtableSyncStatus: syncStatus,
                airtableSyncComments: syncComments,
                airtableStatusFieldId: statusFieldId.isEmpty ? "" : statusFieldId,
                airtableVotesFieldId: votesFieldId.isEmpty ? "" : votesFieldId,
                airtableTitleFieldId: titleFieldId.isEmpty ? "" : titleFieldId,
                airtableDescriptionFieldId: descriptionFieldId.isEmpty ? "" : descriptionFieldId,
                airtableCategoryFieldId: categoryFieldId.isEmpty ? "" : categoryFieldId,
                airtableIsActive: isActive
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
    AirtableSettingsView(
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

### Menu Integration

Add Airtable to the project menu (where other integrations are listed):

**Location:** `SwiftlyFeedbackAdmin/SwiftlyFeedbackAdmin/Views/Projects/ProjectDetailView.swift`

```swift
// In the integrations menu section, add:

Button {
    showingAirtableSettings = true
} label: {
    Label("Airtable Integration", systemImage: "tablecells")
}
.tierBadge(.pro)

// Add state variable:
@State private var showingAirtableSettings = false

// Add sheet:
.sheet(isPresented: $showingAirtableSettings) {
    AirtableSettingsView(project: project, viewModel: viewModel)
}
```

---

## Status Mapping

### FeedbackStatus Extension

**Location:** `SwiftlyFeedbackServer/Sources/App/Models/Feedback.swift`

Add the Airtable status mapping to the `FeedbackStatus` enum:

```swift
// MARK: - Airtable Status Mapping

var airtableStatusName: String {
    switch self {
    case .pending:
        return "Pending"
    case .approved:
        return "Approved"
    case .inProgress:
        return "In Progress"
    case .testflight:
        return "TestFlight"
    case .completed:
        return "Completed"
    case .rejected:
        return "Rejected"
    }
}

// Initialize from Airtable status (for future bi-directional sync)
init?(airtableStatus: String) {
    switch airtableStatus.lowercased() {
    case "pending":
        self = .pending
    case "approved":
        self = .approved
    case "in progress", "in_progress":
        self = .inProgress
    case "testflight", "test flight":
        self = .testflight
    case "completed", "complete", "done":
        self = .completed
    case "rejected", "closed":
        self = .rejected
    default:
        return nil
    }
}
```

### Recommended Airtable Table Schema

Users should create an Airtable table with the following fields:

| Field Name | Field Type | Purpose |
|------------|------------|---------|
| Title | Single line text | Feedback title |
| Description | Long text | Feedback description + metadata |
| Category | Single select | Feature Request, Bug Report, etc. |
| Status | Single select | Pending, Approved, In Progress, TestFlight, Completed, Rejected |
| Votes | Number | Vote count |
| Created | Created time | Auto-generated |

---

## Implementation Checklist

### Phase 1: Server-Side Foundation

- [ ] Create migration `AddProjectAirtableIntegration.swift`
- [ ] Add Airtable fields to `Project` model
- [ ] Add Airtable fields to `Feedback` model
- [ ] Register migration in `configure.swift`
- [ ] Create `AirtableService.swift`
- [ ] Add Airtable DTOs to `ProjectDTO.swift`
- [ ] Update `ProjectResponseDTO` to include Airtable fields
- [ ] Update `FeedbackResponseDTO` to include Airtable fields

### Phase 2: Server-Side Endpoints

- [ ] Add `updateAirtableSettings` handler
- [ ] Add `createAirtableRecord` handler
- [ ] Add `bulkCreateAirtableRecords` handler
- [ ] Add `getAirtableBases` handler
- [ ] Add `getAirtableTables` handler
- [ ] Add `getAirtableFields` handler
- [ ] Register routes in `ProjectController`
- [ ] Add status sync to `FeedbackController`
- [ ] Add vote sync to `VoteController`

### Phase 3: Admin App Models

- [ ] Add Airtable fields to `Project` model
- [ ] Add Airtable fields to `Feedback` model
- [ ] Create `AirtableModels.swift`
- [ ] Add API request/response types

### Phase 4: Admin App API & ViewModel

- [ ] Add Airtable methods to `AdminAPIClient`
- [ ] Add Airtable methods to `ProjectViewModel`
- [ ] Add Airtable methods to `FeedbackViewModel` (for single/bulk creation)

### Phase 5: Admin App UI

- [ ] Create `AirtableSettingsView.swift`
- [ ] Add Airtable menu item to `ProjectDetailView`
- [ ] Add "Push to Airtable" action in feedback list
- [ ] Add Airtable link display on feedback detail
- [ ] Test on iOS and macOS

### Phase 6: Documentation & Testing

- [ ] Update `CLAUDE.md` with Airtable integration docs
- [ ] Update `SwiftlyFeedbackServer/CLAUDE.md` with endpoints
- [ ] Write server tests for Airtable endpoints
- [ ] Manual end-to-end testing
- [ ] Update Integrations table in documentation

---

## Testing Plan

### Unit Tests

1. **AirtableService Tests**
   - Test `buildRecordFields` output format
   - Test `buildRecordURL` format
   - Test field mapping with various configurations

2. **Controller Tests**
   - Test tier gating (402 for non-Pro users)
   - Test validation (missing token, base, table)
   - Test duplicate prevention (already linked)

### Integration Tests

1. **API Flow Tests**
   - Create record flow
   - Bulk create flow
   - Status sync flow
   - Vote sync flow

### Manual Testing Checklist

1. **Setup Flow**
   - [ ] Enter valid token → bases load
   - [ ] Enter invalid token → error shown
   - [ ] Select base → tables load
   - [ ] Select table → fields load
   - [ ] Save configuration → persisted

2. **Record Creation**
   - [ ] Single feedback → creates record
   - [ ] Bulk selection → creates multiple records
   - [ ] Already linked → shows error/skipped
   - [ ] Record URL → opens correct Airtable page

3. **Sync Features**
   - [ ] Status change → updates Airtable
   - [ ] Vote added → updates vote count
   - [ ] Toggle off → sync stops

4. **Error Handling**
   - [ ] Rate limit → shows retry message
   - [ ] Invalid token → shows error
   - [ ] Network error → graceful failure

---

## Future Enhancements

1. **Bi-directional Sync**: Listen for Airtable webhooks to sync status changes back to FeedbackKit
2. **Comment Sync**: Create linked Comments table in Airtable for full comment sync
3. **Custom Field Mapping**: Allow users to map additional custom fields
4. **Attachment Sync**: Sync feedback attachments to Airtable attachment fields
5. **View Links**: Generate Airtable view URLs for filtered feedback lists
