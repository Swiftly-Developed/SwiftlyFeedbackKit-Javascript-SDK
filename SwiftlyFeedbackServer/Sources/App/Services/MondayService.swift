import Vapor

struct MondayService {
    private let client: Client
    private let baseURL = "https://api.monday.com/v2"

    init(client: Client) {
        self.client = client
    }

    // MARK: - Response Types

    struct MondayItemResponse: Codable {
        let id: String
        let name: String
    }

    struct MondayBoard: Codable {
        let id: String
        let name: String
    }

    struct MondayGroup: Codable {
        let id: String
        let title: String
    }

    struct MondayColumn: Codable {
        let id: String
        let title: String
        let type: String
    }

    struct MondayUpdateResponse: Codable {
        let id: String
    }

    private struct GraphQLErrorResponse: Codable {
        let errors: [GraphQLError]?
        struct GraphQLError: Codable {
            let message: String
        }
    }

    // MARK: - GraphQL Helper

    private func executeGraphQL<T: Decodable>(
        token: String,
        query: String
    ) async throws -> T {
        let body: [String: Any] = ["query": query]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let response = try await client.post(URI(string: baseURL)) { req in
            req.headers.add(name: .authorization, value: token)
            req.headers.add(name: .contentType, value: "application/json")
            req.headers.add(name: "API-Version", value: "2024-10")
            req.body = ByteBuffer(data: jsonData)
        }

        guard let bodyData = response.body else {
            throw Abort(.badGateway, reason: "Monday.com API returned empty response")
        }
        let data = Data(buffer: bodyData)

        if let errorResponse = try? JSONDecoder().decode(GraphQLErrorResponse.self, from: data),
           let errors = errorResponse.errors, !errors.isEmpty {
            throw Abort(.badGateway, reason: "Monday.com API error: \(errors.first?.message ?? "Unknown error")")
        }

        guard response.status == .ok else {
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw Abort(.badGateway, reason: "Monday.com API error (\(response.status)): \(responseBody)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let responseBody = String(data: data, encoding: .utf8) ?? "decode failed"
            throw Abort(.badGateway, reason: "Failed to decode Monday.com response: \(error.localizedDescription). Body: \(responseBody)")
        }
    }

    // MARK: - Create Item

    func createItem(
        boardId: String,
        groupId: String?,
        token: String,
        name: String,
        columnValues: [String: Any]? = nil
    ) async throws -> MondayItemResponse {
        // Escape the item name for GraphQL
        let escapedName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        var mutation = "mutation { create_item( board_id: \(boardId) item_name: \"\(escapedName)\""

        if let groupId = groupId, !groupId.isEmpty {
            mutation += " group_id: \"\(groupId)\""
        }

        if let columnValues = columnValues, !columnValues.isEmpty {
            let columnValuesJson = try String(data: JSONSerialization.data(withJSONObject: columnValues), encoding: .utf8) ?? "{}"
            let escapedColumnValues = columnValuesJson
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            mutation += " column_values: \"\(escapedColumnValues)\""
        }

        mutation += " ) { id name } }"

        struct CreateItemResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let create_item: MondayItemResponse?
            }
        }

        let response: CreateItemResponse = try await executeGraphQL(token: token, query: mutation)

        guard let item = response.data.create_item else {
            throw Abort(.badGateway, reason: "Failed to create Monday.com item")
        }

        return item
    }

    // MARK: - Update Item Status

    func updateItemStatus(
        boardId: String,
        itemId: String,
        columnId: String,
        token: String,
        status: String
    ) async throws {
        // Status columns use label value
        let columnValue = ["label": status]
        let columnValueJson = try String(data: JSONSerialization.data(withJSONObject: columnValue), encoding: .utf8) ?? "{}"
        let escapedColumnValue = columnValueJson
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let mutation = """
        mutation { change_column_value( board_id: \(boardId) item_id: \(itemId) column_id: "\(columnId)" value: "\(escapedColumnValue)" ) { id } }
        """

        struct UpdateResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let change_column_value: IdWrapper?
            }
            struct IdWrapper: Codable {
                let id: String
            }
        }

        let _: UpdateResponse = try await executeGraphQL(token: token, query: mutation)
    }

    // MARK: - Update Item Number Column (Vote Count)

    func updateItemNumber(
        boardId: String,
        itemId: String,
        columnId: String,
        token: String,
        value: Int
    ) async throws {
        let mutation = """
        mutation { change_simple_column_value( board_id: \(boardId) item_id: \(itemId) column_id: "\(columnId)" value: "\(value)" ) { id } }
        """

        struct UpdateResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let change_simple_column_value: IdWrapper?
            }
            struct IdWrapper: Codable {
                let id: String
            }
        }

        let _: UpdateResponse = try await executeGraphQL(token: token, query: mutation)
    }

    // MARK: - Create Update (Comment)

    func createUpdate(
        itemId: String,
        token: String,
        body: String
    ) async throws -> MondayUpdateResponse {
        let escapedBody = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let mutation = """
        mutation { create_update( item_id: \(itemId) body: "\(escapedBody)" ) { id } }
        """

        struct CreateUpdateResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let create_update: MondayUpdateResponse?
            }
        }

        let response: CreateUpdateResponse = try await executeGraphQL(token: token, query: mutation)

        guard let update = response.data.create_update else {
            throw Abort(.badGateway, reason: "Failed to create Monday.com update")
        }

        return update
    }

    // MARK: - Get Boards

    func getBoards(token: String) async throws -> [MondayBoard] {
        let query = "query { boards(limit: 100) { id name } }"

        struct BoardsResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let boards: [MondayBoard]
            }
        }

        let response: BoardsResponse = try await executeGraphQL(token: token, query: query)
        return response.data.boards
    }

    // MARK: - Get Groups for Board

    func getGroups(boardId: String, token: String) async throws -> [MondayGroup] {
        let query = "query { boards(ids: [\(boardId)]) { groups { id title } } }"

        struct GroupsResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let boards: [BoardWrapper]
            }
            struct BoardWrapper: Codable {
                let groups: [MondayGroup]
            }
        }

        let response: GroupsResponse = try await executeGraphQL(token: token, query: query)
        return response.data.boards.first?.groups ?? []
    }

    // MARK: - Get Columns for Board

    func getColumns(boardId: String, token: String) async throws -> [MondayColumn] {
        let query = "query { boards(ids: [\(boardId)]) { columns { id title type } } }"

        struct ColumnsResponse: Codable {
            let data: DataWrapper
            struct DataWrapper: Codable {
                let boards: [BoardWrapper]
            }
            struct BoardWrapper: Codable {
                let columns: [MondayColumn]
            }
        }

        let response: ColumnsResponse = try await executeGraphQL(token: token, query: query)
        return response.data.boards.first?.columns ?? []
    }

    // MARK: - Build Item Description

    func buildItemDescription(
        feedback: Feedback,
        projectName: String,
        voteCount: Int,
        mrr: Double?
    ) -> String {
        var description = """
        \(feedback.category.displayName)

        \(feedback.description)

        ---

        Source: SwiftlyFeedback
        Project: \(projectName)
        Votes: \(voteCount)
        """

        if let mrr = mrr, mrr > 0 {
            description += "\nMRR: $\(String(format: "%.2f", mrr))"
        }

        if let userEmail = feedback.userEmail {
            description += "\nSubmitted by: \(userEmail)"
        }

        return description
    }

    // MARK: - Build Item URL

    func buildItemURL(boardId: String, itemId: String) -> String {
        "https://view.monday.com/boards/\(boardId)/pulses/\(itemId)"
    }
}

// MARK: - Request Extension

extension Request {
    var mondayService: MondayService {
        MondayService(client: self.client)
    }
}
