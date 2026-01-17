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
    }

    struct BulkCreateResponse: Codable {
        let records: [CreateRecordResponse]
    }

    // MARK: - API Helper

    private func request<T: Decodable>(
        method: HTTPMethod,
        url: String,
        token: String,
        body: (any Content)? = nil
    ) async throws -> T {
        let uri = URI(string: url)

        let response = try await client.send(method, to: uri) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.add(name: .contentType, value: "application/json")

            if let body = body {
                try req.content.encode(body)
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
            // Airtable uses camelCase, but our decoder uses snake_case
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
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

    struct CreateRecordRequest: Content {
        let fields: [String: String]
        let typecast: Bool

        init(fields: [String: String]) {
            self.fields = fields
            self.typecast = true
        }
    }

    func createRecord(
        baseId: String,
        tableId: String,
        token: String,
        fields: [String: String]
    ) async throws -> CreateRecordResponse {
        let body = CreateRecordRequest(fields: fields)

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
        fields: [String: String]
    ) async throws {
        struct UpdateRequest: Content {
            let fields: [String: String]
            let typecast: Bool

            init(fields: [String: String]) {
                self.fields = fields
                self.typecast = true
            }
        }

        struct UpdateResponse: Codable {
            let id: String
        }

        let body = UpdateRequest(fields: fields)

        let _: UpdateResponse = try await request(
            method: .PATCH,
            url: "\(baseURL)/\(baseId)/\(tableId)/\(recordId)",
            token: token,
            body: body
        )
    }

    // MARK: - Update Record with Number Fields

    struct UpdateRecordMixedRequest: Content {
        struct FieldValue: Codable {
            let stringValue: String?
            let intValue: Int?

            init(string: String) {
                self.stringValue = string
                self.intValue = nil
            }

            init(int: Int) {
                self.stringValue = nil
                self.intValue = int
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                if let stringValue = stringValue {
                    try container.encode(stringValue)
                } else if let intValue = intValue {
                    try container.encode(intValue)
                }
            }
        }

        let fields: [String: FieldValue]
        let typecast: Bool

        init(fields: [String: FieldValue]) {
            self.fields = fields
            self.typecast = true
        }
    }

    func updateRecordWithVotes(
        baseId: String,
        tableId: String,
        recordId: String,
        token: String,
        votesFieldId: String,
        voteCount: Int
    ) async throws {
        struct UpdateResponse: Codable {
            let id: String
        }

        let fields: [String: UpdateRecordMixedRequest.FieldValue] = [
            votesFieldId: .init(int: voteCount)
        ]
        let body = UpdateRecordMixedRequest(fields: fields)

        let _: UpdateResponse = try await request(
            method: .PATCH,
            url: "\(baseURL)/\(baseId)/\(tableId)/\(recordId)",
            token: token,
            body: body
        )
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
        titleFieldName: String?,
        descriptionFieldName: String?,
        categoryFieldName: String?,
        statusFieldName: String?,
        votesFieldName: String?
    ) -> [String: String] {
        var fields: [String: String] = [:]

        // Use field names if configured, otherwise use default field names
        let titleKey = titleFieldName ?? "Title"
        let descriptionKey = descriptionFieldName ?? "Description"
        let categoryKey = categoryFieldName ?? "Category"

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
        if let statusFieldName = statusFieldName {
            fields[statusFieldName] = feedback.status.airtableStatusName
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
