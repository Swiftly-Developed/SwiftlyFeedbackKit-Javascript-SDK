import Vapor
import Fluent
import Leaf

struct WebFeedbackController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let feedback = routes.grouped("feedback")

        feedback.get(use: index)
        feedback.get("kanban", use: kanban)
        feedback.get(":feedbackId", use: show)
        feedback.post(":feedbackId", "status", use: updateStatus)
        feedback.post(":feedbackId", "category", use: updateCategory)
        feedback.post(":feedbackId", "comment", use: addComment)
        feedback.post(":feedbackId", "delete", use: delete)
    }

    // MARK: - Feedback List

    @Sendable
    func index(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        // Get filter parameters
        let projectIdParam = req.query[UUID.self, at: "project_id"]
        let statusParam = req.query[String.self, at: "status"]
        let categoryParam = req.query[String.self, at: "category"]
        let searchParam = req.query[String.self, at: "q"]

        // Get accessible projects
        let accessibleProjects = try await getAccessibleProjects(req: req, userId: userId)

        guard !accessibleProjects.isEmpty else {
            return try await req.view.render("feedback/index", FeedbackListContext(
                title: "Feedback",
                pageTitle: "Feedback",
                currentPage: "feedback",
                user: UserContext(from: user),
                feedbacks: [],
                projects: [],
                selectedProjectId: nil,
                selectedStatus: nil,
                selectedCategory: nil,
                searchQuery: nil,
                statuses: FeedbackStatus.allCases.map { StatusOption(value: $0.rawValue, label: $0.displayName) },
                categories: categoryOptions
            ))
        }

        // Determine which project(s) to query
        let projectIds: [UUID]
        if let projectId = projectIdParam, accessibleProjects.contains(where: { $0.id == projectId }) {
            projectIds = [projectId]
        } else {
            projectIds = accessibleProjects.compactMap { $0.id }
        }

        // Build query
        var query = Feedback.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .filter(\.$mergedIntoId == nil)
            .with(\.$project)

        if let status = statusParam, let feedbackStatus = FeedbackStatus(rawValue: status) {
            query = query.filter(\.$status == feedbackStatus)
        }

        if let category = categoryParam, let feedbackCategory = FeedbackCategory(rawValue: category) {
            query = query.filter(\.$category == feedbackCategory)
        }

        // Note: Search would require full-text search or LIKE queries
        // For simplicity, we'll filter in memory for small datasets
        var feedbacks = try await query.sort(\.$createdAt, .descending).all()

        if let search = searchParam, !search.isEmpty {
            let searchLower = search.lowercased()
            feedbacks = feedbacks.filter {
                $0.title.lowercased().contains(searchLower) ||
                $0.description.lowercased().contains(searchLower)
            }
        }

        let feedbackItems = try feedbacks.map { feedback in
            FeedbackListItem(
                id: try feedback.requireID(),
                title: feedback.title,
                description: String(feedback.description.prefix(150)),
                status: feedback.status.rawValue,
                statusDisplay: feedback.status.displayName,
                statusColor: feedback.status.colorClass,
                category: feedback.category.rawValue,
                categoryDisplay: feedback.category.displayName,
                voteCount: feedback.voteCount,
                projectName: feedback.$project.value?.name ?? "Unknown",
                projectColor: projectColors[(feedback.$project.value?.colorIndex ?? 0) % projectColors.count].bgClass,
                createdAt: formatRelativeDate(feedback.createdAt)
            )
        }

        let projectOptions = accessibleProjects.map { project in
            ProjectOption(
                id: project.id ?? UUID(),
                name: project.name,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass
            )
        }

        return try await req.view.render("feedback/index", FeedbackListContext(
            title: "Feedback",
            pageTitle: "Feedback",
            currentPage: "feedback",
            user: UserContext(from: user),
            feedbacks: feedbackItems,
            projects: projectOptions,
            selectedProjectId: projectIdParam,
            selectedStatus: statusParam,
            selectedCategory: categoryParam,
            searchQuery: searchParam,
            statuses: FeedbackStatus.allCases.map { StatusOption(value: $0.rawValue, label: $0.displayName) },
            categories: categoryOptions
        ))
    }

    // MARK: - Kanban Board

    @Sendable
    func kanban(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        let projectIdParam = req.query[UUID.self, at: "project_id"]

        let accessibleProjects = try await getAccessibleProjects(req: req, userId: userId)

        guard !accessibleProjects.isEmpty else {
            return try await req.view.render("feedback/kanban", KanbanContext(
                title: "Kanban",
                pageTitle: "Kanban Board",
                currentPage: "feedback",
                user: UserContext(from: user),
                columns: [],
                projects: [],
                selectedProjectId: nil
            ))
        }

        let projectIds: [UUID]
        if let projectId = projectIdParam, accessibleProjects.contains(where: { $0.id == projectId }) {
            projectIds = [projectId]
        } else {
            projectIds = accessibleProjects.compactMap { $0.id }
        }

        let feedbacks = try await Feedback.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .filter(\.$mergedIntoId == nil)
            .with(\.$project)
            .sort(\.$voteCount, .descending)
            .all()

        // Group by status
        var feedbacksByStatus: [FeedbackStatus: [Feedback]] = [:]
        for status in FeedbackStatus.allCases {
            feedbacksByStatus[status] = []
        }
        for feedback in feedbacks {
            feedbacksByStatus[feedback.status, default: []].append(feedback)
        }

        let columns = try FeedbackStatus.allCases.map { status in
            KanbanColumn(
                status: status.rawValue,
                name: status.displayName,
                colorClass: status.colorClass,
                feedbacks: try feedbacksByStatus[status]!.map { feedback in
                    KanbanCard(
                        id: try feedback.requireID(),
                        title: feedback.title,
                        category: feedback.category.displayName,
                        voteCount: feedback.voteCount,
                        projectName: feedback.$project.value?.name ?? ""
                    )
                }
            )
        }

        let projectOptions = accessibleProjects.map { project in
            ProjectOption(
                id: project.id ?? UUID(),
                name: project.name,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass
            )
        }

        return try await req.view.render("feedback/kanban", KanbanContext(
            title: "Kanban",
            pageTitle: "Kanban Board",
            currentPage: "feedback",
            user: UserContext(from: user),
            columns: columns,
            projects: projectOptions,
            selectedProjectId: projectIdParam
        ))
    }

    // MARK: - Feedback Detail

    @Sendable
    func show(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.query(on: req.db)
            .filter(\.$id == feedbackId)
            .with(\.$project)
            .with(\.$comments)
            .first() else {
            throw Abort(.notFound)
        }

        // Check access
        let projectId = feedback.$project.id
        let hasAccess = try await checkProjectAccess(req: req, userId: userId, projectId: projectId)
        guard hasAccess else {
            throw Abort(.forbidden)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: projectId)

        let comments = feedback.comments.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
        let commentItems = comments.map { comment in
            CommentItem(
                id: comment.id ?? UUID(),
                content: comment.content,
                userId: comment.userId,
                isAdmin: comment.isAdmin,
                createdAt: formatRelativeDate(comment.createdAt)
            )
        }

        let feedbackDetail = FeedbackDetail(
            id: try feedback.requireID(),
            title: feedback.title,
            description: feedback.description,
            status: feedback.status.rawValue,
            statusDisplay: feedback.status.displayName,
            statusColor: feedback.status.colorClass,
            category: feedback.category.rawValue,
            categoryDisplay: feedback.category.displayName,
            voteCount: feedback.voteCount,
            userId: feedback.userId,
            userEmail: feedback.userEmail,
            projectId: projectId,
            projectName: feedback.$project.value?.name ?? "Unknown",
            createdAt: formatDate(feedback.createdAt),
            updatedAt: formatDate(feedback.updatedAt),
            rejectionReason: feedback.rejectionReason,
            isMerged: feedback.isMerged,
            hasMergedFeedback: feedback.hasMergedFeedback,
            mergedFeedbackCount: feedback.mergedFeedbackIds?.count ?? 0
        )

        return try await req.view.render("feedback/show", FeedbackDetailContext(
            title: feedback.title,
            pageTitle: "Feedback Details",
            currentPage: "feedback",
            user: UserContext(from: user),
            feedback: feedbackDetail,
            comments: commentItems,
            canEdit: role == .owner || role == .admin,
            canDelete: role == .owner || role == .admin,
            statuses: FeedbackStatus.allCases.map { StatusOption(value: $0.rawValue, label: $0.displayName) },
            categories: categoryOptions,
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    // MARK: - Update Status

    @Sendable
    func updateStatus(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let form = try req.content.decode(UpdateStatusForm.self)
        if let newStatus = FeedbackStatus(rawValue: form.status) {
            feedback.status = newStatus
            if newStatus == .rejected {
                feedback.rejectionReason = form.rejectionReason
            } else {
                feedback.rejectionReason = nil
            }
            try await feedback.save(on: req.db)
        }

        return req.redirect(to: "/admin/feedback/\(feedbackId)?success=status_updated")
    }

    // MARK: - Update Category

    @Sendable
    func updateCategory(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let form = try req.content.decode(UpdateCategoryForm.self)
        if let newCategory = FeedbackCategory(rawValue: form.category) {
            feedback.category = newCategory
            try await feedback.save(on: req.db)
        }

        return req.redirect(to: "/admin/feedback/\(feedbackId)?success=category_updated")
    }

    // MARK: - Add Comment

    @Sendable
    func addComment(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        // Check access
        let hasAccess = try await checkProjectAccess(req: req, userId: userId, projectId: feedback.$project.id)
        guard hasAccess else {
            throw Abort(.forbidden)
        }

        // Check if project is archived
        if let project = try await Project.find(feedback.$project.id, on: req.db), project.isArchived {
            return req.redirect(to: "/admin/feedback/\(feedbackId)?error=project_archived")
        }

        let form = try req.content.decode(AddCommentForm.self)

        let comment = Comment(
            content: form.content.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: userId.uuidString,
            isAdmin: true,
            feedbackId: feedbackId
        )
        try await comment.save(on: req.db)

        return req.redirect(to: "/admin/feedback/\(feedbackId)?success=comment_added")
    }

    // MARK: - Delete Feedback

    @Sendable
    func delete(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let projectId = feedback.$project.id
        try await feedback.delete(on: req.db)

        return req.redirect(to: "/admin/feedback?project_id=\(projectId)")
    }

    // MARK: - Helpers

    private func getAccessibleProjects(req: Request, userId: UUID) async throws -> [Project] {
        let ownedProjects = try await Project.query(on: req.db)
            .filter(\.$owner.$id == userId)
            .filter(\.$isArchived == false)
            .all()

        let memberProjects = try await Project.query(on: req.db)
            .join(ProjectMember.self, on: \Project.$id == \ProjectMember.$project.$id)
            .filter(ProjectMember.self, \.$user.$id == userId)
            .filter(\.$isArchived == false)
            .all()

        return ownedProjects + memberProjects
    }

    private func checkProjectAccess(req: Request, userId: UUID, projectId: UUID) async throws -> Bool {
        if let project = try await Project.find(projectId, on: req.db) {
            if project.$owner.id == userId {
                return true
            }
        }

        let member = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == userId)
            .first()

        return member != nil
    }

    private func getProjectRole(req: Request, userId: UUID, projectId: UUID) async throws -> WebProjectRole {
        if let project = try await Project.find(projectId, on: req.db) {
            if project.$owner.id == userId {
                return .owner
            }
        }

        if let member = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == userId)
            .first() {
            switch member.role {
            case .admin: return .admin
            case .member: return .member
            case .viewer: return .viewer
            }
        }

        return .viewer
    }

    private func formatRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Form DTOs

struct UpdateStatusForm: Content {
    let status: String
    let rejectionReason: String?
}

struct UpdateCategoryForm: Content {
    let category: String
}

struct AddCommentForm: Content {
    let content: String
}

// MARK: - View Contexts

struct FeedbackListContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let feedbacks: [FeedbackListItem]
    let projects: [ProjectOption]
    let selectedProjectId: UUID?
    let selectedStatus: String?
    let selectedCategory: String?
    let searchQuery: String?
    let statuses: [StatusOption]
    let categories: [CategoryOption]
}

struct FeedbackListItem: Encodable {
    let id: UUID
    let title: String
    let description: String
    let status: String
    let statusDisplay: String
    let statusColor: String
    let category: String
    let categoryDisplay: String
    let voteCount: Int
    let projectName: String
    let projectColor: String
    let createdAt: String
}

struct KanbanContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let columns: [KanbanColumn]
    let projects: [ProjectOption]
    let selectedProjectId: UUID?
}

struct KanbanColumn: Encodable {
    let status: String
    let name: String
    let colorClass: String
    let feedbacks: [KanbanCard]
}

struct KanbanCard: Encodable {
    let id: UUID
    let title: String
    let category: String
    let voteCount: Int
    let projectName: String
}

struct FeedbackDetailContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let feedback: FeedbackDetail
    let comments: [CommentItem]
    let canEdit: Bool
    let canDelete: Bool
    let statuses: [StatusOption]
    let categories: [CategoryOption]
    let success: String?
    let error: String?
}

struct FeedbackDetail: Encodable {
    let id: UUID
    let title: String
    let description: String
    let status: String
    let statusDisplay: String
    let statusColor: String
    let category: String
    let categoryDisplay: String
    let voteCount: Int
    let userId: String
    let userEmail: String?
    let projectId: UUID
    let projectName: String
    let createdAt: String
    let updatedAt: String
    let rejectionReason: String?
    let isMerged: Bool
    let hasMergedFeedback: Bool
    let mergedFeedbackCount: Int
}

struct CommentItem: Encodable {
    let id: UUID
    let content: String
    let userId: String
    let isAdmin: Bool
    let createdAt: String
}

struct ProjectOption: Encodable {
    let id: UUID
    let name: String
    let colorClass: String
}

struct StatusOption: Encodable {
    let value: String
    let label: String
}

struct CategoryOption: Encodable {
    let value: String
    let label: String
}

let categoryOptions: [CategoryOption] = [
    CategoryOption(value: "feature_request", label: "Feature Request"),
    CategoryOption(value: "bug_report", label: "Bug Report"),
    CategoryOption(value: "improvement", label: "Improvement"),
    CategoryOption(value: "other", label: "Other")
]
