import Vapor
import Fluent
import Leaf

struct WebFeatureRequestsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let featureRequests = routes.grouped("feature-requests")

        featureRequests.get(use: index)
        featureRequests.get(":id", use: show)
        featureRequests.get("submit", use: submitForm)
        featureRequests.post("submit", use: submit)
        featureRequests.post(":id", "vote", use: vote)
        featureRequests.post(":id", "comment", use: comment)
    }

    // MARK: - List Feature Requests

    @Sendable
    func index(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let env = AppEnvironment.shared

        let statusFilter = req.query[String.self, at: "status"]
        let categoryFilter = req.query[String.self, at: "category"]

        // Build API URL with filters
        var apiURL = "\(env.serverURL)/api/v1/feedbacks"
        var queryParams: [String] = []
        if let status = statusFilter, !status.isEmpty {
            queryParams.append("status=\(status)")
        }
        if let category = categoryFilter, !category.isEmpty {
            queryParams.append("category=\(category)")
        }
        if !queryParams.isEmpty {
            apiURL += "?" + queryParams.joined(separator: "&")
        }

        // Fetch feedbacks from API
        let response = try await req.client.get(URI(string: apiURL), headers: [
            "X-API-Key": env.feedbackKitAPIKey
        ])

        var feedbacks: [FeatureRequestItem] = []
        if response.status == .ok,
           let body = response.body {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let feedbackDTOs = try? decoder.decode([FeedbackResponseDTO].self, from: body) {
                feedbacks = feedbackDTOs.map { FeatureRequestItem(from: $0) }
            }
        }

        return try await req.view.render("feature-requests/index", FeatureRequestsListContext(
            title: "Feature Requests",
            pageTitle: "Feature Requests",
            currentPage: "feature-requests",
            user: UserContext(from: user),
            feedbacks: feedbacks,
            selectedStatus: statusFilter,
            selectedCategory: categoryFilter,
            statuses: FeedbackStatus.allCases.map { FeatureRequestStatusOption(value: $0.rawValue, label: $0.displayName) },
            categories: featureRequestCategoryOptions,
            message: req.query[String.self, at: "message"],
            error: req.query[String.self, at: "error"]
        ))
    }

    // MARK: - Show Feature Request

    @Sendable
    func show(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let env = AppEnvironment.shared

        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid feedback ID")
        }

        // Fetch feedback details
        let feedbackResponse = try await req.client.get(
            URI(string: "\(env.serverURL)/api/v1/feedbacks/\(id.uuidString)"),
            headers: ["X-API-Key": env.feedbackKitAPIKey]
        )

        guard feedbackResponse.status == .ok,
              let feedbackBody = feedbackResponse.body else {
            throw Abort(.notFound, reason: "Feature request not found")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feedbackDTO = try decoder.decode(FeedbackResponseDTO.self, from: feedbackBody)

        // Fetch comments
        let commentsResponse = try await req.client.get(
            URI(string: "\(env.serverURL)/api/v1/feedbacks/\(id.uuidString)/comments"),
            headers: ["X-API-Key": env.feedbackKitAPIKey]
        )

        var comments: [FeatureRequestComment] = []
        if commentsResponse.status == .ok,
           let commentsBody = commentsResponse.body {
            if let commentDTOs = try? decoder.decode([CommentResponseDTO].self, from: commentsBody) {
                comments = commentDTOs.map { FeatureRequestComment(from: $0) }
            }
        }

        return try await req.view.render("feature-requests/show", FeatureRequestDetailContext(
            title: feedbackDTO.title,
            pageTitle: "Feature Request",
            currentPage: "feature-requests",
            user: UserContext(from: user),
            feedback: FeatureRequestDetail(from: feedbackDTO),
            comments: comments,
            message: req.query[String.self, at: "message"],
            error: req.query[String.self, at: "error"]
        ))
    }

    // MARK: - Submit Form

    @Sendable
    func submitForm(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)

        return try await req.view.render("feature-requests/submit", FeatureRequestSubmitContext(
            title: "Submit Feature Request",
            pageTitle: "Submit Feature Request",
            currentPage: "feature-requests",
            user: UserContext(from: user),
            categories: featureRequestCategoryOptions,
            error: req.query[String.self, at: "error"]
        ))
    }

    // MARK: - Submit Feature Request

    @Sendable
    func submit(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let env = AppEnvironment.shared
        let form = try req.content.decode(FeatureRequestForm.self)

        // Validate
        guard !form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return req.redirect(to: "/admin/feature-requests/submit?error=Title is required")
        }
        guard !form.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return req.redirect(to: "/admin/feature-requests/submit?error=Description is required")
        }

        // Use the logged-in user's info
        let userId = try user.requireID().uuidString

        // Create the feedback via API
        struct CreateRequest: Content {
            let title: String
            let description: String
            let category: String
            let userId: String
            let userEmail: String?
        }

        let createRequest = CreateRequest(
            title: form.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: form.description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: form.category,
            userId: userId,
            userEmail: user.email
        )

        let response = try await req.client.post(
            URI(string: "\(env.serverURL)/api/v1/feedbacks"),
            headers: [
                "X-API-Key": env.feedbackKitAPIKey,
                "Content-Type": "application/json"
            ]
        ) { clientReq in
            try clientReq.content.encode(createRequest, as: .json)
        }

        if response.status == .ok || response.status == .created {
            return req.redirect(to: "/admin/feature-requests?message=Feature request submitted successfully!")
        } else {
            var errorMessage = "Failed to submit feature request"
            if let body = response.body {
                struct ErrorResponse: Codable {
                    let reason: String?
                }
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: body) {
                    errorMessage = errorResponse.reason ?? errorMessage
                }
            }
            return req.redirect(to: "/admin/feature-requests/submit?error=\(errorMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? errorMessage)")
        }
    }

    // MARK: - Vote

    @Sendable
    func vote(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let env = AppEnvironment.shared

        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid feedback ID")
        }

        let userId = try user.requireID().uuidString

        struct VoteRequest: Content {
            let userId: String
            let email: String?
            let notifyStatusChange: Bool
        }

        let voteRequest = VoteRequest(
            userId: userId,
            email: user.email,
            notifyStatusChange: true
        )

        let response = try await req.client.post(
            URI(string: "\(env.serverURL)/api/v1/feedbacks/\(id.uuidString)/votes"),
            headers: [
                "X-API-Key": env.feedbackKitAPIKey,
                "Content-Type": "application/json"
            ]
        ) { clientReq in
            try clientReq.content.encode(voteRequest, as: .json)
        }

        if response.status == .ok || response.status == .created {
            return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?message=Vote recorded!")
        } else if response.status == .conflict {
            // Already voted - try to unvote
            let unvoteResponse = try await req.client.delete(
                URI(string: "\(env.serverURL)/api/v1/feedbacks/\(id.uuidString)/votes"),
                headers: [
                    "X-API-Key": env.feedbackKitAPIKey,
                    "Content-Type": "application/json"
                ]
            ) { clientReq in
                try clientReq.content.encode(voteRequest, as: .json)
            }

            if unvoteResponse.status == .ok {
                return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?message=Vote removed!")
            }
            return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?error=Failed to toggle vote")
        } else {
            return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?error=Failed to vote")
        }
    }

    // MARK: - Comment

    @Sendable
    func comment(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let env = AppEnvironment.shared

        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid feedback ID")
        }

        let form = try req.content.decode(FeatureRequestCommentForm.self)

        guard !form.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?error=Comment cannot be empty")
        }

        let userId = try user.requireID().uuidString

        struct CommentRequest: Content {
            let content: String
            let userId: String
            let isAdmin: Bool
        }

        let commentRequest = CommentRequest(
            content: form.content.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: userId,
            isAdmin: false  // Regular user comment
        )

        let response = try await req.client.post(
            URI(string: "\(env.serverURL)/api/v1/feedbacks/\(id.uuidString)/comments"),
            headers: [
                "X-API-Key": env.feedbackKitAPIKey,
                "Content-Type": "application/json"
            ]
        ) { clientReq in
            try clientReq.content.encode(commentRequest, as: .json)
        }

        if response.status == .ok || response.status == .created {
            return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?message=Comment added!")
        } else {
            return req.redirect(to: "/admin/feature-requests/\(id.uuidString)?error=Failed to add comment")
        }
    }

    // MARK: - Helpers

    private func formatRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h ago"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d ago"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            return dateFormatter.string(from: date)
        }
    }
}

// MARK: - Form DTOs

struct FeatureRequestForm: Content {
    let title: String
    let description: String
    let category: String
}

struct FeatureRequestCommentForm: Content {
    let content: String
}

// MARK: - View Contexts

struct FeatureRequestsListContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let feedbacks: [FeatureRequestItem]
    let selectedStatus: String?
    let selectedCategory: String?
    let statuses: [FeatureRequestStatusOption]
    let categories: [FeatureRequestCategoryOption]
    let message: String?
    let error: String?
}

struct FeatureRequestDetailContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let feedback: FeatureRequestDetail
    let comments: [FeatureRequestComment]
    let message: String?
    let error: String?
}

struct FeatureRequestSubmitContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let categories: [FeatureRequestCategoryOption]
    let error: String?
}

struct FeatureRequestItem: Encodable {
    let id: String
    let title: String
    let description: String
    let status: String
    let statusDisplay: String
    let statusColor: String
    let category: String
    let categoryDisplay: String
    let voteCount: Int
    let commentCount: Int
    let createdAt: String

    init(from dto: FeedbackResponseDTO) {
        self.id = dto.id.uuidString
        self.title = dto.title
        self.description = String(dto.description.prefix(150))
        self.status = dto.status.rawValue
        self.statusDisplay = dto.status.displayName
        self.statusColor = dto.status.colorClass
        self.category = dto.category.rawValue
        self.categoryDisplay = dto.category.displayName
        self.voteCount = dto.voteCount
        self.commentCount = dto.commentCount
        if let date = dto.createdAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            self.createdAt = formatter.localizedString(for: date, relativeTo: Date())
        } else {
            self.createdAt = ""
        }
    }
}

struct FeatureRequestDetail: Encodable {
    let id: String
    let title: String
    let description: String
    let status: String
    let statusDisplay: String
    let statusColor: String
    let category: String
    let categoryDisplay: String
    let voteCount: Int
    let commentCount: Int
    let createdAt: String

    init(from dto: FeedbackResponseDTO) {
        self.id = dto.id.uuidString
        self.title = dto.title
        self.description = dto.description
        self.status = dto.status.rawValue
        self.statusDisplay = dto.status.displayName
        self.statusColor = dto.status.colorClass
        self.category = dto.category.rawValue
        self.categoryDisplay = dto.category.displayName
        self.voteCount = dto.voteCount
        self.commentCount = dto.commentCount
        if let date = dto.createdAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            self.createdAt = formatter.string(from: date)
        } else {
            self.createdAt = ""
        }
    }
}

struct FeatureRequestComment: Encodable {
    let id: String
    let content: String
    let isAdmin: Bool
    let createdAt: String

    init(from dto: CommentResponseDTO) {
        self.id = dto.id.uuidString
        self.content = dto.content
        self.isAdmin = dto.isAdmin
        if let date = dto.createdAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            self.createdAt = formatter.localizedString(for: date, relativeTo: Date())
        } else {
            self.createdAt = ""
        }
    }
}

struct FeatureRequestStatusOption: Encodable {
    let value: String
    let label: String
}

struct FeatureRequestCategoryOption: Encodable {
    let value: String
    let label: String
}

let featureRequestCategoryOptions: [FeatureRequestCategoryOption] = [
    FeatureRequestCategoryOption(value: "feature_request", label: "Feature Request"),
    FeatureRequestCategoryOption(value: "bug_report", label: "Bug Report"),
    FeatureRequestCategoryOption(value: "improvement", label: "Improvement"),
    FeatureRequestCategoryOption(value: "other", label: "Other")
]
