import Vapor

struct SlackService {
    private let client: Client

    init(client: Client) {
        self.client = client
    }

    // MARK: - New Feedback Notification

    func sendNewFeedbackNotification(
        webhookURL: String,
        projectName: String,
        feedbackTitle: String,
        feedbackCategory: String,
        feedbackDescription: String,
        userName: String?
    ) async throws {
        let truncatedDescription = feedbackDescription.count > 200
            ? String(feedbackDescription.prefix(200)) + "..."
            : feedbackDescription

        let categoryDisplay = feedbackCategory
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let payload = SlackMessage(
            text: "New feedback in \(projectName): \(feedbackTitle)",
            blocks: [
                .header(text: "New Feedback Received"),
                .section(text: "*\(projectName)*"),
                .divider,
                .sectionWithFields(fields: [
                    "*Category:*\n\(categoryDisplay)",
                    "*Submitted by:*\n\(userName ?? "Anonymous")"
                ]),
                .section(text: "*\(feedbackTitle)*\n\(truncatedDescription)"),
                .context(text: "Open Swiftly Feedback to respond")
            ]
        )

        try await sendMessage(to: webhookURL, payload: payload)
    }

    // MARK: - New Comment Notification

    func sendNewCommentNotification(
        webhookURL: String,
        projectName: String,
        feedbackTitle: String,
        commentContent: String,
        commenterName: String,
        isAdmin: Bool
    ) async throws {
        let truncatedComment = commentContent.count > 300
            ? String(commentContent.prefix(300)) + "..."
            : commentContent

        let commenterLabel = isAdmin ? "Admin" : "User"

        let payload = SlackMessage(
            text: "New comment on \(feedbackTitle) in \(projectName)",
            blocks: [
                .header(text: "New Comment"),
                .section(text: "*\(projectName)* · \(feedbackTitle)"),
                .divider,
                .section(text: ">\(truncatedComment)\n— _\(commenterName)_ (\(commenterLabel))"),
                .context(text: "Open Swiftly Feedback to respond")
            ]
        )

        try await sendMessage(to: webhookURL, payload: payload)
    }

    // MARK: - Status Change Notification

    func sendFeedbackStatusChangeNotification(
        webhookURL: String,
        projectName: String,
        feedbackTitle: String,
        oldStatus: String,
        newStatus: String
    ) async throws {
        let statusEmoji = switch newStatus {
        case "approved": ":white_check_mark:"
        case "in_progress": ":arrows_counterclockwise:"
        case "completed": ":tada:"
        case "rejected": ":x:"
        default: ":clipboard:"
        }

        let formattedOldStatus = oldStatus
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        let formattedNewStatus = newStatus
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let payload = SlackMessage(
            text: "Status update: \(feedbackTitle) is now \(formattedNewStatus)",
            blocks: [
                .header(text: "\(statusEmoji) Status Update"),
                .section(text: "*\(projectName)*"),
                .divider,
                .section(text: "*\(feedbackTitle)*"),
                .section(text: "~\(formattedOldStatus)~ → *\(formattedNewStatus)*"),
                .context(text: "Open Swiftly Feedback for details")
            ]
        )

        try await sendMessage(to: webhookURL, payload: payload)
    }

    // MARK: - Private

    private func sendMessage(to webhookURL: String, payload: SlackMessage) async throws {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(payload)

        let response = try await client.post(URI(string: webhookURL)) { req in
            req.headers.add(name: .contentType, value: "application/json")
            req.body = .init(data: jsonData)
        }

        guard response.status == .ok else {
            let errorBody = response.body.map { String(buffer: $0) } ?? "Unknown error"
            throw Abort(.internalServerError, reason: "Slack webhook failed: \(errorBody)")
        }
    }
}

// MARK: - Slack Message Types

struct SlackMessage: Encodable {
    let text: String
    let blocks: [SlackBlock]
}

enum SlackBlock: Encodable {
    case header(text: String)
    case section(text: String)
    case sectionWithFields(fields: [String])
    case divider
    case context(text: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .header(let text):
            try container.encode("header", forKey: .type)
            try container.encode(TextObject(type: "plain_text", text: text), forKey: .text)

        case .section(text: let text):
            try container.encode("section", forKey: .type)
            try container.encode(TextObject(type: "mrkdwn", text: text), forKey: .text)

        case .sectionWithFields(fields: let fields):
            try container.encode("section", forKey: .type)
            let fieldObjects = fields.map { TextObject(type: "mrkdwn", text: $0) }
            try container.encode(fieldObjects, forKey: .fields)

        case .divider:
            try container.encode("divider", forKey: .type)

        case .context(let text):
            try container.encode("context", forKey: .type)
            let elements = [TextObject(type: "mrkdwn", text: text)]
            try container.encode(elements, forKey: .elements)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text, fields, elements
    }
}

struct TextObject: Content {
    let type: String
    let text: String
}

// MARK: - Request Extension

extension Request {
    var slackService: SlackService {
        SlackService(client: self.client)
    }
}
