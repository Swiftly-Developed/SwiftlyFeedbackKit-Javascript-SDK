import Vapor

struct LinearService {
    private let client: Client
    private let baseURL = "https://api.linear.app/graphql"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct LinearTeam: Codable {
        let id: String
        let name: String
        let key: String
    }

    struct LinearProject: Codable {
        let id: String
        let name: String
        let state: String
    }

    struct LinearWorkflowState: Codable {
        let id: String
        let name: String
        let type: String
        let position: Double
    }

    struct LinearLabel: Codable {
        let id: String
        let name: String
        let color: String
    }

    struct LinearIssue: Codable {
        let id: String
        let identifier: String
        let title: String
        let url: String
    }

    struct GraphQLError: Codable {
        let message: String
    }

    private struct GraphQLResponse<D: Decodable>: Decodable {
        let data: D?
        let errors: [GraphQLError]?
    }

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

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.post(URI(string: baseURL)) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .contentType, value: "application/json")
            req.body = ByteBuffer(data: jsonData)
        }

        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Linear API returned empty response")
        }
        let data = Data(buffer: bodyData)

        guard response.status == .ok else {
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Linear API error (\(response.status)): \(responseBody)")
        }

        let graphQLResponse = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data)
        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw Abort(.badGateway, reason: "Linear GraphQL error: \(errors.first?.message ?? "Unknown error")")
        }
        guard let responseData = graphQLResponse.data else {
            throw Abort(.badGateway, reason: "No data in Linear response")
        }
        return responseData
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

        struct TeamsResponse: Decodable {
            let teams: NodesWrapper<LinearTeam>
        }

        struct NodesWrapper<T: Decodable>: Decodable {
            let nodes: [T]
        }

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

        struct TeamProjectsResponse: Decodable {
            let team: TeamProjects

            struct TeamProjects: Decodable {
                let projects: NodesWrapper<LinearProject>
            }
        }

        struct NodesWrapper<T: Decodable>: Decodable {
            let nodes: [T]
        }

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

        struct WorkflowStatesResponse: Decodable {
            let workflowStates: NodesWrapper<LinearWorkflowState>
        }

        struct NodesWrapper<T: Decodable>: Decodable {
            let nodes: [T]
        }

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

        struct LabelsResponse: Decodable {
            let issueLabels: NodesWrapper<LinearLabel>
        }

        struct NodesWrapper<T: Decodable>: Decodable {
            let nodes: [T]
        }

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
        if let projectId = projectId, !projectId.isEmpty {
            input["projectId"] = projectId
        }
        if let labelIds = labelIds, !labelIds.isEmpty {
            input["labelIds"] = labelIds
        }

        struct IssueCreateResponse: Decodable {
            let issueCreate: IssueCreateResult

            struct IssueCreateResult: Decodable {
                let success: Bool
                let issue: LinearIssue
            }
        }

        let response = try await execute(
            query: query,
            variables: ["input": input],
            token: token,
            responseType: IssueCreateResponse.self
        )

        guard response.issueCreate.success else {
            throw Abort(.badGateway, reason: "Failed to create Linear issue")
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

        struct IssueUpdateResponse: Decodable {
            let issueUpdate: SuccessResult

            struct SuccessResult: Decodable {
                let success: Bool
            }
        }

        let response = try await execute(
            query: query,
            variables: ["issueId": issueId, "stateId": stateId],
            token: token,
            responseType: IssueUpdateResponse.self
        )

        guard response.issueUpdate.success else {
            throw Abort(.badGateway, reason: "Failed to update Linear issue state")
        }
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

        struct CommentCreateResponse: Decodable {
            let commentCreate: SuccessResult

            struct SuccessResult: Decodable {
                let success: Bool
            }
        }

        let response = try await execute(
            query: query,
            variables: ["issueId": issueId, "body": body],
            token: token,
            responseType: CommentCreateResponse.self
        )

        guard response.commentCreate.success else {
            throw Abort(.badGateway, reason: "Failed to create Linear comment")
        }
    }

    // MARK: - Content Building

    func buildIssueDescription(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var description = """
        ## \(feedback.category.displayName)

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
}

// MARK: - Request Extension

extension Request {
    var linearService: LinearService {
        LinearService(client: self.client)
    }
}
