import Vapor

struct BasecampService {
    private let client: Client

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct BasecampAuthorization: Codable {
        let identity: Identity
        let accounts: [Account]

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

        struct Account: Codable {
            let id: Int
            let name: String
            let product: String
            let href: String
        }
    }

    struct BasecampProject: Codable {
        let id: Int
        let name: String
        let dock: [Dock]?

        struct Dock: Codable {
            let id: Int
            let title: String
            let name: String
            let url: String
        }

        var todosetId: String? {
            guard let dock = dock else { return nil }
            return dock.first { $0.name == "todoset" }.map { String($0.id) }
        }
    }

    struct BasecampTodolist: Codable {
        let id: Int
        let name: String
        let todosUrl: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case todosUrl = "todos_url"
        }
    }

    struct BasecampTodo: Codable {
        let id: Int
        let title: String
        let content: String?
        let completed: Bool
        let appUrl: String

        enum CodingKeys: String, CodingKey {
            case id, title, content, completed
            case appUrl = "app_url"
        }
    }

    struct BasecampComment: Codable {
        let id: Int
        let content: String
    }

    private struct BasecampErrorResponse: Codable {
        let error: String?
    }

    // MARK: - HTTP Helper

    private func request<T: Codable>(
        method: HTTPMethod,
        url: String,
        token: String,
        body: [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        let uri = URI(string: url)

        let response: ClientResponse
        switch method {
        case .GET:
            response = try await client.get(uri) { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
                req.headers.add(name: .accept, value: "application/json")
                req.headers.add(name: "User-Agent", value: "FeedbackKit (ben@swiftly-developed.com)")
            }
        case .POST:
            response = try await client.post(uri) { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
                req.headers.add(name: .contentType, value: "application/json")
                req.headers.add(name: .accept, value: "application/json")
                req.headers.add(name: "User-Agent", value: "FeedbackKit (ben@swiftly-developed.com)")
                if let body = body {
                    let jsonData = try JSONSerialization.data(withJSONObject: body)
                    req.body = ByteBuffer(data: jsonData)
                }
            }
        case .PUT:
            response = try await client.put(uri) { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
                req.headers.add(name: .contentType, value: "application/json")
                req.headers.add(name: .accept, value: "application/json")
                req.headers.add(name: "User-Agent", value: "FeedbackKit (ben@swiftly-developed.com)")
                if let body = body {
                    let jsonData = try JSONSerialization.data(withJSONObject: body)
                    req.body = ByteBuffer(data: jsonData)
                }
            }
        default:
            throw Abort(.badRequest, reason: "Unsupported HTTP method")
        }

        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Basecamp API returned empty response")
        }
        let data = Data(buffer: bodyData)

        // Check for rate limiting
        if response.status == .tooManyRequests {
            throw Abort(.tooManyRequests, reason: "Basecamp rate limit exceeded. Please try again.")
        }

        // Check for errors
        if response.status.code >= 400 {
            if let errorResponse = try? JSONDecoder().decode(BasecampErrorResponse.self, from: data),
               let error = errorResponse.error {
                throw Abort(.badGateway, reason: "Basecamp API error: \(error)")
            }
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Basecamp API error (\(response.status)): \(responseBody)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "decode failed"
            throw Abort(.badGateway, reason: "Failed to decode Basecamp response: \(error.localizedDescription). Body: \(responseBody)")
        }
    }

    // MARK: - Authorization

    func getAuthorization(token: String) async throws -> BasecampAuthorization {
        try await request(
            method: .GET,
            url: "https://launchpad.37signals.com/authorization.json",
            token: token,
            responseType: BasecampAuthorization.self
        )
    }

    // MARK: - Projects

    func getProjects(accountId: String, token: String) async throws -> [BasecampProject] {
        try await request(
            method: .GET,
            url: "https://3.basecampapi.com/\(accountId)/projects.json",
            token: token,
            responseType: [BasecampProject].self
        )
    }

    func getProject(accountId: String, projectId: String, token: String) async throws -> BasecampProject {
        try await request(
            method: .GET,
            url: "https://3.basecampapi.com/\(accountId)/projects/\(projectId).json",
            token: token,
            responseType: BasecampProject.self
        )
    }

    // MARK: - Todolists

    func getTodolists(accountId: String, projectId: String, todosetId: String, token: String) async throws -> [BasecampTodolist] {
        try await request(
            method: .GET,
            url: "https://3.basecampapi.com/\(accountId)/buckets/\(projectId)/todosets/\(todosetId)/todolists.json",
            token: token,
            responseType: [BasecampTodolist].self
        )
    }

    // MARK: - Todo Creation

    func createTodo(
        accountId: String,
        projectId: String,
        todolistId: String,
        token: String,
        title: String,
        description: String
    ) async throws -> BasecampTodo {
        let body: [String: Any] = [
            "content": title,
            "description": description
        ]

        return try await request(
            method: .POST,
            url: "https://3.basecampapi.com/\(accountId)/buckets/\(projectId)/todolists/\(todolistId)/todos.json",
            token: token,
            body: body,
            responseType: BasecampTodo.self
        )
    }

    // MARK: - Todo Update

    func updateTodo(
        accountId: String,
        bucketId: String,
        todoId: String,
        token: String,
        completed: Bool
    ) async throws -> BasecampTodo {
        let body: [String: Any] = [
            "completed": completed
        ]

        return try await request(
            method: .PUT,
            url: "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/todos/\(todoId).json",
            token: token,
            body: body,
            responseType: BasecampTodo.self
        )
    }

    // MARK: - Comments

    func createComment(
        accountId: String,
        bucketId: String,
        todoId: String,
        token: String,
        content: String
    ) async throws -> BasecampComment {
        let body: [String: Any] = [
            "content": content
        ]

        return try await request(
            method: .POST,
            url: "https://3.basecampapi.com/\(accountId)/buckets/\(bucketId)/recordings/\(todoId)/comments.json",
            token: token,
            body: body,
            responseType: BasecampComment.self
        )
    }

    // MARK: - Content Building

    func buildTodoDescription(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var description = """
        <strong>\(feedback.category.displayName)</strong>

        \(feedback.description)

        ---

        <em>Source: FeedbackKit</em><br>
        <em>Project: \(projectName)</em><br>
        <em>Votes: \(voteCount)</em>
        """

        if let mrr = mrr, mrr > 0 {
            description += "<br><em>MRR: $\(String(format: "%.2f", mrr))</em>"
        }

        if let userEmail = feedback.userEmail {
            description += "<br><em>Submitted by: \(userEmail)</em>"
        }

        return description
    }
}

// MARK: - Request Extension

extension Request {
    var basecampService: BasecampService {
        BasecampService(client: self.client)
    }
}
