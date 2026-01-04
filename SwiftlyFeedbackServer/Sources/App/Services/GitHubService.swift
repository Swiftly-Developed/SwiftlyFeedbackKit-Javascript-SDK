import Vapor

struct GitHubService {
    private let client: Client

    init(client: Client) {
        self.client = client
    }

    // MARK: - GitHub API Response Types

    struct GitHubIssueResponse: Codable {
        let id: Int
        let number: Int
        let htmlUrl: String
        let state: String
    }

    struct GitHubErrorResponse: Codable {
        let message: String
        let documentationUrl: String?
    }

    // MARK: - Create Issue

    /// Create a GitHub issue from feedback
    func createIssue(
        owner: String,
        repo: String,
        token: String,
        title: String,
        body: String,
        labels: [String]?
    ) async throws -> GitHubIssueResponse {
        let url = URI(string: "https://api.github.com/repos/\(owner)/\(repo)/issues")

        struct CreateIssueRequest: Content {
            let title: String
            let body: String
            let labels: [String]?
        }

        let requestBody = CreateIssueRequest(title: title, body: body, labels: labels)

        let response = try await client.post(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .accept, value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: .userAgent, value: "SwiftlyFeedback")
            try req.content.encode(requestBody)
        }

        // Get response body as Data first
        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "GitHub API returned empty response")
        }
        let data = Data(buffer: bodyData)

        guard response.status == .created else {
            // Try to decode GitHub error response
            if let errorResponse = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data) {
                throw Abort(.badGateway, reason: "GitHub API error: \(errorResponse.message)")
            }
            // Provide raw response for debugging
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "GitHub API error (\(response.status)): \(responseBody)")
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(GitHubIssueResponse.self, from: data)
        } catch {
            // Log the raw response for debugging decode failures
            let responseBody = String(data: data, encoding: .utf8) ?? "decode failed"
            throw Abort(.badGateway, reason: "Failed to decode GitHub response: \(error.localizedDescription). Body: \(responseBody)")
        }
    }

    // MARK: - Close Issue

    /// Close a GitHub issue (when feedback completed/rejected)
    func closeIssue(
        owner: String,
        repo: String,
        token: String,
        issueNumber: Int
    ) async throws {
        let url = URI(string: "https://api.github.com/repos/\(owner)/\(repo)/issues/\(issueNumber)")

        let response = try await client.patch(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .accept, value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: .userAgent, value: "SwiftlyFeedback")
            try req.content.encode(["state": "closed"])
        }

        guard response.status == .ok else {
            if let errorResponse = try? response.content.decode(GitHubErrorResponse.self) {
                throw Abort(.badGateway, reason: "GitHub API error: \(errorResponse.message)")
            }
            throw Abort(.badGateway, reason: "GitHub API error: \(response.status)")
        }
    }

    // MARK: - Reopen Issue

    /// Reopen a GitHub issue (when feedback status changed from completed/rejected)
    func reopenIssue(
        owner: String,
        repo: String,
        token: String,
        issueNumber: Int
    ) async throws {
        let url = URI(string: "https://api.github.com/repos/\(owner)/\(repo)/issues/\(issueNumber)")

        let response = try await client.patch(url) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .accept, value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: .userAgent, value: "SwiftlyFeedback")
            try req.content.encode(["state": "open"])
        }

        guard response.status == .ok else {
            if let errorResponse = try? response.content.decode(GitHubErrorResponse.self) {
                throw Abort(.badGateway, reason: "GitHub API error: \(errorResponse.message)")
            }
            throw Abort(.badGateway, reason: "GitHub API error: \(response.status)")
        }
    }

    // MARK: - Build Issue Body

    /// Build issue body from feedback
    func buildIssueBody(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var body = """
        ## \(feedback.category.displayName)

        \(feedback.description)

        ---

        **Source:** SwiftlyFeedback
        **Project:** \(projectName)
        **Votes:** \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            body += "\n**MRR:** $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            body += "\n**Submitted by:** \(userEmail)"
        }

        return body
    }
}

// MARK: - Request Extension

extension Request {
    var githubService: GitHubService {
        GitHubService(client: self.client)
    }
}

// MARK: - FeedbackCategory Display Name Extension

extension FeedbackCategory {
    var displayName: String {
        switch self {
        case .featureRequest: return "Feature Request"
        case .bugReport: return "Bug Report"
        case .improvement: return "Improvement"
        case .other: return "Other"
        }
    }
}
