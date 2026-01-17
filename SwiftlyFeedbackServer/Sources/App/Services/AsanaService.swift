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

        // Check for rate limiting
        if response.status == .tooManyRequests {
            throw Abort(.tooManyRequests, reason: "Asana rate limit exceeded. Please try again.")
        }

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

    // MARK: - URL Building

    func buildTaskURL(projectId: String, taskId: String) -> String {
        "https://app.asana.com/0/\(projectId)/\(taskId)"
    }
}

// MARK: - Request Extension

extension Request {
    var asanaService: AsanaService {
        AsanaService(client: self.client)
    }
}
