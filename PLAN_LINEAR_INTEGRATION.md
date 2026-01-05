# Linear Integration - Technical Implementation Plan

> **Reference**: This plan follows the patterns established by ClickUp, GitHub, and Notion integrations.

## Overview

Integrate Linear as a feedback destination, allowing admins to push feedback items as Linear issues. Linear uses a **GraphQL API** (unlike the REST APIs used by other integrations), which requires a different service implementation approach.

**Linear API Details:**
- **Endpoint**: `https://api.linear.app/graphql`
- **Auth**: Bearer token (Personal API Key or OAuth2)
- **Rate Limits**: Evolving limits for equitable access

---

## 1. Database Schema Changes

### 1.1 Project Model Fields

Add to `Project.swift`:

```swift
// Linear Integration
@OptionalField(key: "linear_token")
var linearToken: String?

@OptionalField(key: "linear_team_id")
var linearTeamId: String?

@OptionalField(key: "linear_team_name")
var linearTeamName: String?

@OptionalField(key: "linear_project_id")
var linearProjectId: String?

@OptionalField(key: "linear_project_name")
var linearProjectName: String?

@OptionalField(key: "linear_default_label_ids")
var linearDefaultLabelIds: [String]?

@Field(key: "linear_sync_status")
var linearSyncStatus: Bool

@Field(key: "linear_sync_comments")
var linearSyncComments: Bool
```

### 1.2 Feedback Model Fields

Add to `Feedback.swift`:

```swift
// Linear Integration
@OptionalField(key: "linear_issue_url")
var linearIssueURL: String?

@OptionalField(key: "linear_issue_id")
var linearIssueId: String?
```

### 1.3 Migration File

Create `Sources/App/Migrations/AddProjectLinearIntegration.swift`:

```swift
import Fluent

struct AddProjectLinearIntegration: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Project fields
        try await database.schema("projects")
            .field("linear_token", .string)
            .field("linear_team_id", .string)
            .field("linear_team_name", .string)
            .field("linear_project_id", .string)
            .field("linear_project_name", .string)
            .field("linear_default_label_ids", .array(of: .string))
            .field("linear_sync_status", .bool, .required, .sql(.default(false)))
            .field("linear_sync_comments", .bool, .required, .sql(.default(false)))
            .update()

        // Feedback fields
        try await database.schema("feedbacks")
            .field("linear_issue_url", .string)
            .field("linear_issue_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("projects")
            .deleteField("linear_token")
            .deleteField("linear_team_id")
            .deleteField("linear_team_name")
            .deleteField("linear_project_id")
            .deleteField("linear_project_name")
            .deleteField("linear_default_label_ids")
            .deleteField("linear_sync_status")
            .deleteField("linear_sync_comments")
            .update()

        try await database.schema("feedbacks")
            .deleteField("linear_issue_url")
            .deleteField("linear_issue_id")
            .update()
    }
}
```

---

## 2. Server-Side Implementation

### 2.1 LinearService

Create `Sources/App/Services/LinearService.swift`:

```swift
import Vapor

struct LinearService {
    let client: Client
    let logger: Logger

    private let apiURL = "https://api.linear.app/graphql"

    // MARK: - GraphQL Execution

    private func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil,
        token: String,
        responseType: T.Type
    ) async throws -> T {
        // Build GraphQL request body
        var body: [String: Any] = ["query": query]
        if let variables = variables {
            body["variables"] = variables
        }

        let response = try await client.post(URI(string: apiURL)) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .contentType, value: "application/json")
            try req.content.encode(body, as: .json)
        }

        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Linear API error: \(response.status)")
        }

        // Parse GraphQL response
        let graphQLResponse = try response.content.decode(GraphQLResponse<T>.self)
        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw Abort(.badRequest, reason: errors.first?.message ?? "Linear GraphQL error")
        }
        guard let data = graphQLResponse.data else {
            throw Abort(.badRequest, reason: "No data in Linear response")
        }
        return data
    }

    // MARK: - Teams

    func getTeams(token: String) async throws -> [LinearTeam] {
        let query = """
        query {
            teams {
                nodes {
                    id
                    name
                    key
                }
            }
        }
        """
        let response = try await execute(
            query: query,
            token: token,
            responseType: TeamsResponse.self
        )
        return response.teams.nodes
    }

    // MARK: - Projects

    func getProjects(teamId: String, token: String) async throws -> [LinearProject] {
        let query = """
        query($teamId: String!) {
            team(id: $teamId) {
                projects {
                    nodes {
                        id
                        name
                        state
                    }
                }
            }
        }
        """
        let response = try await execute(
            query: query,
            variables: ["teamId": teamId],
            token: token,
            responseType: TeamProjectsResponse.self
        )
        return response.team.projects.nodes
    }

    // MARK: - Workflow States (Statuses)

    func getWorkflowStates(teamId: String, token: String) async throws -> [LinearWorkflowState] {
        let query = """
        query($teamId: String!) {
            workflowStates(filter: { team: { id: { eq: $teamId } } }) {
                nodes {
                    id
                    name
                    type
                    position
                }
            }
        }
        """
        let response = try await execute(
            query: query,
            variables: ["teamId": teamId],
            token: token,
            responseType: WorkflowStatesResponse.self
        )
        return response.workflowStates.nodes
    }

    // MARK: - Labels

    func getLabels(teamId: String, token: String) async throws -> [LinearLabel] {
        let query = """
        query($teamId: String!) {
            issueLabels(filter: { team: { id: { eq: $teamId } } }) {
                nodes {
                    id
                    name
                    color
                }
            }
        }
        """
        let response = try await execute(
            query: query,
            variables: ["teamId": teamId],
            token: token,
            responseType: LabelsResponse.self
        )
        return response.issueLabels.nodes
    }

    // MARK: - Issue Creation

    func createIssue(
        teamId: String,
        projectId: String?,
        title: String,
        description: String,
        labelIds: [String]?,
        token: String
    ) async throws -> LinearIssue {
        let query = """
        mutation($input: IssueCreateInput!) {
            issueCreate(input: $input) {
                success
                issue {
                    id
                    identifier
                    title
                    url
                }
            }
        }
        """

        var input: [String: Any] = [
            "teamId": teamId,
            "title": title,
            "description": description
        ]
        if let projectId = projectId {
            input["projectId"] = projectId
        }
        if let labelIds = labelIds, !labelIds.isEmpty {
            input["labelIds"] = labelIds
        }

        let response = try await execute(
            query: query,
            variables: ["input": input],
            token: token,
            responseType: IssueCreateResponse.self
        )

        guard response.issueCreate.success else {
            throw Abort(.badRequest, reason: "Failed to create Linear issue")
        }
        return response.issueCreate.issue
    }

    // MARK: - Issue Update (Status Sync)

    func updateIssueState(
        issueId: String,
        stateId: String,
        token: String
    ) async throws {
        let query = """
        mutation($issueId: String!, $stateId: String!) {
            issueUpdate(id: $issueId, input: { stateId: $stateId }) {
                success
            }
        }
        """
        let _ = try await execute(
            query: query,
            variables: ["issueId": issueId, "stateId": stateId],
            token: token,
            responseType: IssueUpdateResponse.self
        )
    }

    // MARK: - Comments

    func createComment(
        issueId: String,
        body: String,
        token: String
    ) async throws {
        let query = """
        mutation($issueId: String!, $body: String!) {
            commentCreate(input: { issueId: $issueId, body: $body }) {
                success
            }
        }
        """
        let _ = try await execute(
            query: query,
            variables: ["issueId": issueId, "body": body],
            token: token,
            responseType: CommentCreateResponse.self
        )
    }

    // MARK: - Content Building

    func buildIssueDescription(
        feedback: Feedback,
        voteCount: Int,
        totalMrr: Double
    ) -> String {
        var description = ""

        description += "**Category:** \(feedback.category.displayName)\n\n"

        if let desc = feedback.description, !desc.isEmpty {
            description += "\(desc)\n\n"
        }

        description += "---\n\n"
        description += "**Votes:** \(voteCount)\n"

        if totalMrr > 0 {
            description += "**MRR:** $\(Int(totalMrr))\n"
        }

        if let email = feedback.userEmail {
            description += "**Submitted by:** \(email)\n"
        }

        description += "\n*Synced from SwiftlyFeedback*"

        return description
    }
}

// MARK: - Request Extension

extension Request {
    var linearService: LinearService {
        LinearService(client: self.client, logger: self.logger)
    }
}
```

### 2.2 Linear DTOs

Add to `Sources/App/DTOs/LinearDTOs.swift`:

```swift
import Vapor

// MARK: - GraphQL Response Wrapper

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}

// MARK: - Linear Models

struct LinearTeam: Content {
    let id: String
    let name: String
    let key: String
}

struct LinearProject: Content {
    let id: String
    let name: String
    let state: String
}

struct LinearWorkflowState: Content {
    let id: String
    let name: String
    let type: String  // "backlog", "unstarted", "started", "completed", "canceled"
    let position: Double
}

struct LinearLabel: Content {
    let id: String
    let name: String
    let color: String
}

struct LinearIssue: Content {
    let id: String
    let identifier: String  // e.g., "ENG-123"
    let title: String
    let url: String
}

// MARK: - GraphQL Response Types

struct TeamsResponse: Decodable {
    let teams: NodesWrapper<LinearTeam>
}

struct TeamProjectsResponse: Decodable {
    let team: TeamProjects

    struct TeamProjects: Decodable {
        let projects: NodesWrapper<LinearProject>
    }
}

struct WorkflowStatesResponse: Decodable {
    let workflowStates: NodesWrapper<LinearWorkflowState>
}

struct LabelsResponse: Decodable {
    let issueLabels: NodesWrapper<LinearLabel>
}

struct NodesWrapper<T: Decodable>: Decodable {
    let nodes: [T]
}

struct IssueCreateResponse: Decodable {
    let issueCreate: IssueCreateResult

    struct IssueCreateResult: Decodable {
        let success: Bool
        let issue: LinearIssue
    }
}

struct IssueUpdateResponse: Decodable {
    let issueUpdate: SuccessResult
}

struct CommentCreateResponse: Decodable {
    let commentCreate: SuccessResult
}

struct SuccessResult: Decodable {
    let success: Bool
}

// MARK: - API Request/Response DTOs

struct UpdateProjectLinearDTO: Content {
    var linearToken: String?
    var linearTeamId: String?
    var linearTeamName: String?
    var linearProjectId: String?
    var linearProjectName: String?
    var linearDefaultLabelIds: [String]?
    var linearSyncStatus: Bool?
    var linearSyncComments: Bool?
}

struct CreateLinearIssueDTO: Content {
    var feedbackId: UUID
    var additionalLabelIds: [String]?
}

struct BulkCreateLinearIssuesDTO: Content {
    var feedbackIds: [UUID]
    var additionalLabelIds: [String]?
}

struct CreateLinearIssueResponseDTO: Content {
    var feedbackId: UUID
    var issueUrl: String
    var issueId: String
    var identifier: String
}

struct BulkCreateLinearIssuesResponseDTO: Content {
    var created: [CreateLinearIssueResponseDTO]
    var failed: [UUID]
}
```

### 2.3 FeedbackStatus Extension

Add Linear status mapping to `FeedbackStatus`:

```swift
extension FeedbackStatus {
    /// Maps SwiftlyFeedback status to Linear workflow state type
    var linearStateType: String {
        switch self {
        case .pending: return "backlog"
        case .approved: return "unstarted"
        case .inProgress: return "started"
        case .testflight: return "started"
        case .completed: return "completed"
        case .rejected: return "canceled"
        }
    }
}
```

### 2.4 ProjectController Routes

Add to `ProjectController.swift`:

```swift
// MARK: - Linear Integration Routes

// Update Linear settings
projectRoutes.patch(":projectId", "linear", use: updateLinearSettings)

// Create Linear issue
projectRoutes.post(":projectId", "linear", "issue", use: createLinearIssue)

// Bulk create Linear issues
projectRoutes.post(":projectId", "linear", "issues", use: bulkCreateLinearIssues)

// Hierarchy picker endpoints
projectRoutes.get(":projectId", "linear", "teams", use: getLinearTeams)
projectRoutes.get(":projectId", "linear", "projects", ":teamId", use: getLinearProjects)
projectRoutes.get(":projectId", "linear", "states", ":teamId", use: getLinearWorkflowStates)
projectRoutes.get(":projectId", "linear", "labels", ":teamId", use: getLinearLabels)
```

### 2.5 ProjectController Handlers

```swift
// MARK: - Linear Handlers

func updateLinearSettings(req: Request) async throws -> Project.Public {
    let project = try await getProjectWithAdminAccess(req: req)
    let dto = try req.content.decode(UpdateProjectLinearDTO.self)

    if let token = dto.linearToken { project.linearToken = token.isEmpty ? nil : token }
    if let teamId = dto.linearTeamId { project.linearTeamId = teamId.isEmpty ? nil : teamId }
    if let teamName = dto.linearTeamName { project.linearTeamName = teamName.isEmpty ? nil : teamName }
    if let projectId = dto.linearProjectId { project.linearProjectId = projectId.isEmpty ? nil : projectId }
    if let projectName = dto.linearProjectName { project.linearProjectName = projectName.isEmpty ? nil : projectName }
    if let labelIds = dto.linearDefaultLabelIds { project.linearDefaultLabelIds = labelIds.isEmpty ? nil : labelIds }
    if let syncStatus = dto.linearSyncStatus { project.linearSyncStatus = syncStatus }
    if let syncComments = dto.linearSyncComments { project.linearSyncComments = syncComments }

    try await project.save(on: req.db)
    return project.toPublic()
}

func createLinearIssue(req: Request) async throws -> CreateLinearIssueResponseDTO {
    let project = try await getProjectWithAdminAccess(req: req)
    let dto = try req.content.decode(CreateLinearIssueDTO.self)

    guard let token = project.linearToken,
          let teamId = project.linearTeamId else {
        throw Abort(.badRequest, reason: "Linear integration not configured")
    }

    guard let feedback = try await Feedback.find(dto.feedbackId, on: req.db) else {
        throw Abort(.notFound, reason: "Feedback not found")
    }

    // Calculate vote count and MRR
    let voteCount = try await Vote.query(on: req.db)
        .filter(\.$feedback.$id == feedback.id!)
        .count()
    let totalMrr = try await calculateFeedbackMRR(feedback: feedback, on: req.db)

    // Combine default labels with additional labels
    var labelIds = project.linearDefaultLabelIds ?? []
    if let additional = dto.additionalLabelIds {
        labelIds.append(contentsOf: additional)
    }

    let description = req.linearService.buildIssueDescription(
        feedback: feedback,
        voteCount: voteCount,
        totalMrr: totalMrr
    )

    let issue = try await req.linearService.createIssue(
        teamId: teamId,
        projectId: project.linearProjectId,
        title: feedback.title,
        description: description,
        labelIds: labelIds.isEmpty ? nil : labelIds,
        token: token
    )

    // Store issue reference on feedback
    feedback.linearIssueURL = issue.url
    feedback.linearIssueId = issue.id
    try await feedback.save(on: req.db)

    return CreateLinearIssueResponseDTO(
        feedbackId: feedback.id!,
        issueUrl: issue.url,
        issueId: issue.id,
        identifier: issue.identifier
    )
}

func bulkCreateLinearIssues(req: Request) async throws -> BulkCreateLinearIssuesResponseDTO {
    let project = try await getProjectWithAdminAccess(req: req)
    let dto = try req.content.decode(BulkCreateLinearIssuesDTO.self)

    guard let token = project.linearToken,
          let teamId = project.linearTeamId else {
        throw Abort(.badRequest, reason: "Linear integration not configured")
    }

    var created: [CreateLinearIssueResponseDTO] = []
    var failed: [UUID] = []

    for feedbackId in dto.feedbackIds {
        do {
            guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
                failed.append(feedbackId)
                continue
            }

            // Skip if already linked
            if feedback.linearIssueId != nil {
                failed.append(feedbackId)
                continue
            }

            let voteCount = try await Vote.query(on: req.db)
                .filter(\.$feedback.$id == feedback.id!)
                .count()
            let totalMrr = try await calculateFeedbackMRR(feedback: feedback, on: req.db)

            var labelIds = project.linearDefaultLabelIds ?? []
            if let additional = dto.additionalLabelIds {
                labelIds.append(contentsOf: additional)
            }

            let description = req.linearService.buildIssueDescription(
                feedback: feedback,
                voteCount: voteCount,
                totalMrr: totalMrr
            )

            let issue = try await req.linearService.createIssue(
                teamId: teamId,
                projectId: project.linearProjectId,
                title: feedback.title,
                description: description,
                labelIds: labelIds.isEmpty ? nil : labelIds,
                token: token
            )

            feedback.linearIssueURL = issue.url
            feedback.linearIssueId = issue.id
            try await feedback.save(on: req.db)

            created.append(CreateLinearIssueResponseDTO(
                feedbackId: feedback.id!,
                issueUrl: issue.url,
                issueId: issue.id,
                identifier: issue.identifier
            ))
        } catch {
            req.logger.error("Failed to create Linear issue for feedback \(feedbackId): \(error)")
            failed.append(feedbackId)
        }
    }

    return BulkCreateLinearIssuesResponseDTO(created: created, failed: failed)
}

// Hierarchy picker handlers
func getLinearTeams(req: Request) async throws -> [LinearTeam] {
    let project = try await getProjectWithAdminAccess(req: req)
    guard let token = project.linearToken else {
        throw Abort(.badRequest, reason: "Linear token not configured")
    }
    return try await req.linearService.getTeams(token: token)
}

func getLinearProjects(req: Request) async throws -> [LinearProject] {
    let project = try await getProjectWithAdminAccess(req: req)
    guard let token = project.linearToken,
          let teamId = req.parameters.get("teamId") else {
        throw Abort(.badRequest, reason: "Linear token or team ID not provided")
    }
    return try await req.linearService.getProjects(teamId: teamId, token: token)
}

func getLinearWorkflowStates(req: Request) async throws -> [LinearWorkflowState] {
    let project = try await getProjectWithAdminAccess(req: req)
    guard let token = project.linearToken,
          let teamId = req.parameters.get("teamId") else {
        throw Abort(.badRequest, reason: "Linear token or team ID not provided")
    }
    return try await req.linearService.getWorkflowStates(teamId: teamId, token: token)
}

func getLinearLabels(req: Request) async throws -> [LinearLabel] {
    let project = try await getProjectWithAdminAccess(req: req)
    guard let token = project.linearToken,
          let teamId = req.parameters.get("teamId") else {
        throw Abort(.badRequest, reason: "Linear token or team ID not provided")
    }
    return try await req.linearService.getLabels(teamId: teamId, token: token)
}
```

### 2.6 Status Sync in FeedbackController

Add to `updateFeedback` handler after status change:

```swift
// Linear status sync
if let linearIssueId = feedback.linearIssueId,
   project.linearSyncStatus,
   let token = project.linearToken,
   let teamId = project.linearTeamId {
    Task {
        do {
            // Fetch workflow states for the team
            let states = try await req.linearService.getWorkflowStates(teamId: teamId, token: token)

            // Find matching state by type
            let targetType = newStatus.linearStateType
            if let targetState = states.first(where: { $0.type == targetType }) {
                try await req.linearService.updateIssueState(
                    issueId: linearIssueId,
                    stateId: targetState.id,
                    token: token
                )
            }
        } catch {
            req.logger.error("Failed to sync Linear issue status: \(error)")
        }
    }
}
```

### 2.7 Comment Sync in CommentController

Add to `createComment` handler:

```swift
// Linear comment sync
if let linearIssueId = feedback.linearIssueId,
   project.linearSyncComments,
   let token = project.linearToken {
    Task {
        do {
            let commenterType = comment.isAdmin ? "Admin" : "User"
            let body = "**[\(commenterType)] Comment:**\n\n\(comment.content)"
            try await req.linearService.createComment(
                issueId: linearIssueId,
                body: body,
                token: token
            )
        } catch {
            req.logger.error("Failed to sync comment to Linear: \(error)")
        }
    }
}
```

---

## 3. Admin App Implementation

### 3.1 ProjectModels Extension

Add to `ProjectModels.swift`:

```swift
// Linear Integration fields
var linearToken: String?
var linearTeamId: String?
var linearTeamName: String?
var linearProjectId: String?
var linearProjectName: String?
var linearDefaultLabelIds: [String]?
var linearSyncStatus: Bool
var linearSyncComments: Bool

var isLinearConfigured: Bool {
    linearToken != nil && linearTeamId != nil
}
```

Update `hasAnyIntegration`:
```swift
var hasAnyIntegration: Bool {
    isSlackConfigured || isGitHubConfigured || isClickUpConfigured ||
    isNotionConfigured || isLinearConfigured
}
```

### 3.2 FeedbackModels Extension

Add to `FeedbackModels.swift`:

```swift
var linearIssueURL: String?
var linearIssueId: String?

var hasLinearIssue: Bool {
    linearIssueURL != nil
}
```

### 3.3 Linear DTOs for Admin App

Add to `AdminModels.swift` or create `LinearModels.swift`:

```swift
struct LinearTeam: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let key: String
}

struct LinearProject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let state: String
}

struct LinearWorkflowState: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let position: Double
}

struct LinearLabel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String
}

struct UpdateProjectLinearDTO: Codable {
    var linearToken: String?
    var linearTeamId: String?
    var linearTeamName: String?
    var linearProjectId: String?
    var linearProjectName: String?
    var linearDefaultLabelIds: [String]?
    var linearSyncStatus: Bool?
    var linearSyncComments: Bool?
}

struct CreateLinearIssueDTO: Codable {
    var feedbackId: UUID
    var additionalLabelIds: [String]?
}

struct BulkCreateLinearIssuesDTO: Codable {
    var feedbackIds: [UUID]
    var additionalLabelIds: [String]?
}

struct CreateLinearIssueResponseDTO: Codable {
    var feedbackId: UUID
    var issueUrl: String
    var issueId: String
    var identifier: String
}

struct BulkCreateLinearIssuesResponseDTO: Codable {
    var created: [CreateLinearIssueResponseDTO]
    var failed: [UUID]
}
```

### 3.4 AdminAPIClient Extensions

Add to `AdminAPIClient.swift`:

```swift
// MARK: - Linear Integration

func updateLinearSettings(projectId: UUID, dto: UpdateProjectLinearDTO) async throws -> Project {
    return try await patch("projects/\(projectId)/linear", body: dto)
}

func getLinearTeams(projectId: UUID) async throws -> [LinearTeam] {
    return try await get("projects/\(projectId)/linear/teams")
}

func getLinearProjects(projectId: UUID, teamId: String) async throws -> [LinearProject] {
    return try await get("projects/\(projectId)/linear/projects/\(teamId)")
}

func getLinearWorkflowStates(projectId: UUID, teamId: String) async throws -> [LinearWorkflowState] {
    return try await get("projects/\(projectId)/linear/states/\(teamId)")
}

func getLinearLabels(projectId: UUID, teamId: String) async throws -> [LinearLabel] {
    return try await get("projects/\(projectId)/linear/labels/\(teamId)")
}

func createLinearIssue(projectId: UUID, feedbackId: UUID, additionalLabelIds: [String]? = nil) async throws -> CreateLinearIssueResponseDTO {
    let dto = CreateLinearIssueDTO(feedbackId: feedbackId, additionalLabelIds: additionalLabelIds)
    return try await post("projects/\(projectId)/linear/issue", body: dto)
}

func bulkCreateLinearIssues(projectId: UUID, feedbackIds: [UUID], additionalLabelIds: [String]? = nil) async throws -> BulkCreateLinearIssuesResponseDTO {
    let dto = BulkCreateLinearIssuesDTO(feedbackIds: feedbackIds, additionalLabelIds: additionalLabelIds)
    return try await post("projects/\(projectId)/linear/issues", body: dto)
}
```

### 3.5 LinearSettingsView

Create `SwiftlyFeedbackAdmin/Views/Projects/LinearSettingsView.swift`:

```swift
import SwiftUI

struct LinearSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: AdminAPIClient

    let project: Project
    let onSave: (Project) -> Void

    // Form state
    @State private var token: String = ""
    @State private var selectedTeam: LinearTeam?
    @State private var selectedProject: LinearProject?
    @State private var selectedLabelIds: Set<String> = []
    @State private var syncStatus: Bool = false
    @State private var syncComments: Bool = false

    // Picker data
    @State private var teams: [LinearTeam] = []
    @State private var projects: [LinearProject] = []
    @State private var labels: [LinearLabel] = []

    // Loading states
    @State private var isLoadingTeams = false
    @State private var isLoadingProjects = false
    @State private var isLoadingLabels = false
    @State private var isSaving = false
    @State private var error: String?

    private var hasChanges: Bool {
        token != (project.linearToken ?? "") ||
        selectedTeam?.id != project.linearTeamId ||
        selectedProject?.id != project.linearProjectId ||
        Array(selectedLabelIds).sorted() != (project.linearDefaultLabelIds ?? []).sorted() ||
        syncStatus != project.linearSyncStatus ||
        syncComments != project.linearSyncComments
    }

    var body: some View {
        Form {
            // Token Section
            Section {
                SecureField("API Token", text: $token)
                    .onChange(of: token) { _, newValue in
                        if !newValue.isEmpty {
                            loadTeams()
                        } else {
                            clearAll()
                        }
                    }

                Button("Get API Token") {
                    // Open Linear API settings
                    if let url = URL(string: "https://linear.app/settings/api") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                .font(.caption)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Create a Personal API Key in Linear Settings → API")
            }

            // Team Selection
            if !teams.isEmpty {
                Section("Team") {
                    Picker("Team", selection: $selectedTeam) {
                        Text("Select a team").tag(nil as LinearTeam?)
                        ForEach(teams) { team in
                            Text("\(team.name) (\(team.key))").tag(team as LinearTeam?)
                        }
                    }
                    .onChange(of: selectedTeam) { _, newValue in
                        selectedProject = nil
                        projects = []
                        selectedLabelIds = []
                        labels = []
                        if let team = newValue {
                            loadProjects(teamId: team.id)
                            loadLabels(teamId: team.id)
                        }
                    }
                }
            }

            // Project Selection (optional)
            if !projects.isEmpty {
                Section("Project (Optional)") {
                    Picker("Project", selection: $selectedProject) {
                        Text("No project").tag(nil as LinearProject?)
                        ForEach(projects.filter { $0.state != "canceled" }) { project in
                            Text(project.name).tag(project as LinearProject?)
                        }
                    }
                }
            }

            // Labels Selection
            if !labels.isEmpty {
                Section("Default Labels") {
                    ForEach(labels) { label in
                        Toggle(isOn: Binding(
                            get: { selectedLabelIds.contains(label.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedLabelIds.insert(label.id)
                                } else {
                                    selectedLabelIds.remove(label.id)
                                }
                            }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: label.color) ?? .gray)
                                    .frame(width: 12, height: 12)
                                Text(label.name)
                            }
                        }
                    }
                }
            }

            // Sync Options
            if selectedTeam != nil {
                Section("Sync Options") {
                    Toggle("Sync status changes", isOn: $syncStatus)
                    Toggle("Sync comments", isOn: $syncComments)
                }
            }

            // Current Configuration
            if project.isLinearConfigured {
                Section("Current Configuration") {
                    LabeledContent("Team", value: project.linearTeamName ?? "Unknown")
                    if let projectName = project.linearProjectName {
                        LabeledContent("Project", value: projectName)
                    }
                }
            }

            // Error display
            if let error = error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Linear Integration")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!hasChanges || isSaving)
            }
        }
        .onAppear {
            loadInitialState()
        }
    }

    private func loadInitialState() {
        token = project.linearToken ?? ""
        syncStatus = project.linearSyncStatus
        syncComments = project.linearSyncComments
        selectedLabelIds = Set(project.linearDefaultLabelIds ?? [])

        if !token.isEmpty {
            loadTeams()
        }
    }

    private func clearAll() {
        teams = []
        projects = []
        labels = []
        selectedTeam = nil
        selectedProject = nil
        selectedLabelIds = []
    }

    private func loadTeams() {
        guard !token.isEmpty else { return }
        isLoadingTeams = true
        error = nil

        Task {
            do {
                teams = try await apiClient.getLinearTeams(projectId: project.id)

                // Restore previous selection
                if let teamId = project.linearTeamId {
                    selectedTeam = teams.first { $0.id == teamId }
                    if let team = selectedTeam {
                        await loadProjects(teamId: team.id)
                        await loadLabels(teamId: team.id)
                    }
                }
            } catch {
                self.error = "Failed to load teams: \(error.localizedDescription)"
            }
            isLoadingTeams = false
        }
    }

    private func loadProjects(teamId: String) {
        isLoadingProjects = true
        Task {
            do {
                projects = try await apiClient.getLinearProjects(projectId: project.id, teamId: teamId)

                // Restore previous selection
                if let projectId = project.linearProjectId {
                    selectedProject = projects.first { $0.id == projectId }
                }
            } catch {
                self.error = "Failed to load projects: \(error.localizedDescription)"
            }
            isLoadingProjects = false
        }
    }

    private func loadLabels(teamId: String) {
        isLoadingLabels = true
        Task {
            do {
                labels = try await apiClient.getLinearLabels(projectId: project.id, teamId: teamId)
            } catch {
                self.error = "Failed to load labels: \(error.localizedDescription)"
            }
            isLoadingLabels = false
        }
    }

    private func save() {
        isSaving = true
        error = nil

        Task {
            do {
                let dto = UpdateProjectLinearDTO(
                    linearToken: token.isEmpty ? nil : token,
                    linearTeamId: selectedTeam?.id,
                    linearTeamName: selectedTeam?.name,
                    linearProjectId: selectedProject?.id,
                    linearProjectName: selectedProject?.name,
                    linearDefaultLabelIds: Array(selectedLabelIds),
                    linearSyncStatus: syncStatus,
                    linearSyncComments: syncComments
                )

                let updatedProject = try await apiClient.updateLinearSettings(
                    projectId: project.id,
                    dto: dto
                )

                await MainActor.run {
                    onSave(updatedProject)
                    dismiss()
                }
            } catch {
                self.error = "Failed to save: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}
```

### 3.6 Integration Badge on Feedback Cards

Add Linear badge to feedback card views:

```swift
// In FeedbackRowView / FeedbackCardView
if feedback.hasLinearIssue {
    Button {
        if let url = URL(string: feedback.linearIssueURL ?? "") {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }
    } label: {
        Image(systemName: "arrow.triangle.branch")
            .foregroundStyle(.purple)
    }
    .buttonStyle(.plain)
    .help("View in Linear")
}
```

### 3.7 Context Menu Actions

Add to feedback context menus:

```swift
// Push to Linear (when configured and not linked)
if project.isLinearConfigured && !feedback.hasLinearIssue {
    Button {
        pushToLinear(feedback)
    } label: {
        Label("Push to Linear", systemImage: "arrow.triangle.branch")
    }
}

// View in Linear (when linked)
if let url = feedback.linearIssueURL {
    Button {
        openURL(url)
    } label: {
        Label("View in Linear", systemImage: "arrow.up.forward.square")
    }
}
```

### 3.8 Bulk Action Bar

Add Linear bulk action button:

```swift
if project.isLinearConfigured {
    Button {
        bulkPushToLinear(selectedFeedbackIds)
    } label: {
        Label("Push to Linear", systemImage: "arrow.triangle.branch")
    }
}
```

### 3.9 ProjectDetailView Integration Display

Add to configured integrations section:

```swift
if project.isLinearConfigured {
    HStack {
        Image(systemName: "arrow.triangle.branch")
            .foregroundStyle(.purple)
        VStack(alignment: .leading) {
            Text("Linear")
                .font(.headline)
            Text(project.linearTeamName ?? "Connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

### 3.10 Project Menu - Linear Settings

Add to project menu:

```swift
Button {
    showLinearSettings = true
} label: {
    Label("Linear Integration", systemImage: "arrow.triangle.branch")
}
```

---

## 4. SDK Updates (SwiftlyFeedbackKit)

### 4.1 Feedback Model

Add to `Feedback.swift`:

```swift
public var linearIssueURL: String?
public var linearIssueId: String?

public var hasLinearIssue: Bool {
    linearIssueURL != nil
}
```

---

## 5. Implementation Order

### Phase 1: Server Foundation
1. Create migration file
2. Add fields to Project and Feedback models
3. Create LinearDTOs.swift
4. Create LinearService.swift with GraphQL client
5. Add FeedbackStatus.linearStateType extension

### Phase 2: Server Endpoints
6. Add routes to ProjectController
7. Implement settings update handler
8. Implement hierarchy picker handlers (teams, projects, labels)
9. Implement single issue creation
10. Implement bulk issue creation

### Phase 3: Server Sync
11. Add status sync to FeedbackController
12. Add comment sync to CommentController

### Phase 4: Admin App Models
13. Add Linear fields to ProjectModels
14. Add Linear fields to FeedbackModels
15. Create Linear DTOs
16. Add AdminAPIClient methods

### Phase 5: Admin App UI
17. Create LinearSettingsView
18. Add to project menu
19. Add integration badge to feedback cards
20. Add context menu actions
21. Add bulk action bar button
22. Add to ProjectDetailView integrations display

### Phase 6: SDK
23. Add Linear fields to SDK Feedback model

### Phase 7: Testing & Documentation
24. Test full flow: settings → create issue → status sync → comment sync
25. Update CLAUDE.md with Linear integration docs

---

## 6. Key Differences from ClickUp/Notion

| Aspect | ClickUp/Notion | Linear |
|--------|---------------|--------|
| API Type | REST | GraphQL |
| Hierarchy | Workspace → Space → Folder → List | Team → Project (optional) |
| Status | Custom per-list | Workflow states per-team |
| Labels | Tags (strings) | Labels (objects with IDs) |
| Issue ID | Custom ID | Identifier (e.g., "ENG-123") |

---

## 7. Linear-Specific Considerations

### 7.1 GraphQL vs REST
- All requests go through single `/graphql` endpoint
- Request body contains query/mutation and variables
- Response wrapped in `{ "data": {...}, "errors": [...] }`
- Need to handle GraphQL-specific error format

### 7.2 Workflow States
- States are team-scoped, not workspace-scoped
- States have types: `backlog`, `unstarted`, `started`, `completed`, `canceled`
- Map SwiftlyFeedback statuses to state types, then find matching state

### 7.3 Projects are Optional
- Unlike ClickUp lists which are required, Linear projects are optional
- Issues can belong to just a team without a project
- UI should allow "No project" selection

### 7.4 Labels
- Labels are team-scoped objects with IDs
- Labels have colors (hex strings)
- Store label IDs, not names
- Display label colors in picker UI

### 7.5 Issue Identifier
- Linear issues have human-readable identifiers like "ENG-123"
- Store both `id` (UUID) and `identifier` (string)
- Display identifier in UI for user reference

---

## 8. API Reference

### Authentication
```
Authorization: Bearer <API_KEY>
Content-Type: application/json
```

### Endpoint
```
POST https://api.linear.app/graphql
```

### Key Queries
- `teams` - List all teams
- `team(id:)` - Get team with projects
- `workflowStates(filter:)` - Get states for team
- `issueLabels(filter:)` - Get labels for team

### Key Mutations
- `issueCreate(input:)` - Create issue
- `issueUpdate(id:, input:)` - Update issue (status)
- `commentCreate(input:)` - Add comment

---

## Sources

- [Linear GraphQL API Documentation](https://linear.app/developers/graphql)
- [Linear API & Webhooks Overview](https://linear.app/docs/api-and-webhooks)
- [Working with the GraphQL API](https://developers.linear.app/docs/graphql/working-with-the-graphql-api)
