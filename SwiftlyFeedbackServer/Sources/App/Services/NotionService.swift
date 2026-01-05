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

        // Build properties dictionary with title
        var propsDict: [String: Any] = [
            "Name": [
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
            return
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
            return
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
