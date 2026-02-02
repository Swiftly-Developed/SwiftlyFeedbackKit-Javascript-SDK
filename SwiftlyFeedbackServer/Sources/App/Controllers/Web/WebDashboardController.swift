import Vapor
import Fluent
import Leaf

struct WebDashboardController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("dashboard", use: dashboard)
    }

    @Sendable
    func dashboard(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        // Get all projects the user has access to
        let ownedProjects = try await Project.query(on: req.db)
            .filter(\.$owner.$id == userId)
            .filter(\.$isArchived == false)
            .all()

        let memberProjects = try await Project.query(on: req.db)
            .join(ProjectMember.self, on: \Project.$id == \ProjectMember.$project.$id)
            .filter(ProjectMember.self, \.$user.$id == userId)
            .filter(\.$isArchived == false)
            .all()

        let allProjects = ownedProjects + memberProjects

        // Calculate statistics
        var totalFeedback = 0
        var totalVotes = 0
        var completedCount = 0
        var feedbackByStatus: [String: Int] = [:]
        var feedbackByCategory: [String: Int] = [:]
        var recentFeedbackItems: [Feedback] = []

        for project in allProjects {
            let projectId = try project.requireID()

            let feedbacks = try await Feedback.query(on: req.db)
                .filter(\.$project.$id == projectId)
                .filter(\.$mergedIntoId == nil) // Exclude merged feedback
                .all()

            totalFeedback += feedbacks.count

            for feedback in feedbacks {
                totalVotes += feedback.voteCount

                // Count by status
                let statusKey = feedback.status.rawValue
                feedbackByStatus[statusKey, default: 0] += 1

                if feedback.status == .completed {
                    completedCount += 1
                }

                // Count by category
                let categoryKey = feedback.category.rawValue
                feedbackByCategory[categoryKey, default: 0] += 1
            }
        }

        // Get recent feedback
        if let firstProject = allProjects.first {
            let projectIds = try allProjects.map { try $0.requireID() }
            recentFeedbackItems = try await Feedback.query(on: req.db)
                .filter(\.$project.$id ~~ projectIds)
                .filter(\.$mergedIntoId == nil)
                .with(\.$project)
                .sort(\.$createdAt, .descending)
                .limit(5)
                .all()
        }

        // Calculate completion rate
        let completionRate = totalFeedback > 0 ? Int((Double(completedCount) / Double(totalFeedback)) * 100) : 0

        // Build status stats
        let statusStats = FeedbackStatus.allCases.map { status in
            StatusStat(
                name: status.displayName,
                count: feedbackByStatus[status.rawValue] ?? 0,
                colorClass: status.colorClass
            )
        }

        // Build category stats
        let allCategories: [FeedbackCategory] = [.featureRequest, .bugReport, .improvement, .other]
        let categoryStats = allCategories.map { category in
            CategoryStat(
                name: category.displayName,
                count: feedbackByCategory[category.rawValue] ?? 0,
                colorClass: category.colorClass
            )
        }

        // Build recent feedback for display
        let recentFeedback = try recentFeedbackItems.map { feedback in
            RecentFeedbackItem(
                id: try feedback.requireID(),
                title: feedback.title,
                description: String(feedback.description.prefix(100)),
                status: feedback.status.displayName,
                statusColorClass: feedback.status.colorClass,
                projectName: feedback.$project.value?.name ?? "Unknown",
                votes: feedback.voteCount,
                createdAt: formatDate(feedback.createdAt)
            )
        }

        let stats = DashboardStats(
            totalProjects: allProjects.count,
            totalFeedback: totalFeedback,
            totalVotes: totalVotes,
            completionRate: completionRate,
            feedbackByStatus: statusStats,
            feedbackByCategory: categoryStats
        )

        return try await req.view.render("dashboard/index", DashboardContext(
            title: "Dashboard",
            pageTitle: "Dashboard",
            currentPage: "dashboard",
            user: UserContext(from: user),
            stats: stats,
            recentFeedback: recentFeedback.isEmpty ? nil : recentFeedback
        ))
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - View Contexts

struct DashboardContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let stats: DashboardStats
    let recentFeedback: [RecentFeedbackItem]?
}

struct UserContext: Encodable {
    let id: UUID
    let name: String
    let email: String
    let subscriptionTier: String
    let initials: String

    init(from user: User) {
        self.id = user.id ?? UUID()
        self.name = user.name
        self.email = user.email
        self.subscriptionTier = user.subscriptionTier.rawValue
        // Generate initials from name (e.g., "John Doe" -> "JD")
        let components = user.name.split(separator: " ")
        if components.count >= 2 {
            self.initials = String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else if let first = components.first {
            self.initials = String(first.prefix(2)).uppercased()
        } else {
            self.initials = "?"
        }
    }
}

struct DashboardStats: Encodable {
    let totalProjects: Int
    let totalFeedback: Int
    let totalVotes: Int
    let completionRate: Int
    let feedbackByStatus: [StatusStat]
    let feedbackByCategory: [CategoryStat]
}

struct StatusStat: Encodable {
    let name: String
    let count: Int
    let colorClass: String
}

struct CategoryStat: Encodable {
    let name: String
    let count: Int
    let colorClass: String
}

struct RecentFeedbackItem: Encodable {
    let id: UUID
    let title: String
    let description: String
    let status: String
    let statusColorClass: String
    let projectName: String
    let votes: Int
    let createdAt: String
}

// MARK: - Helpers

extension FeedbackStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .inProgress: return "In Progress"
        case .testflight: return "TestFlight"
        case .completed: return "Completed"
        case .rejected: return "Rejected"
        }
    }

    var colorClass: String {
        switch self {
        case .pending: return "bg-gray-500"
        case .approved: return "bg-blue-500"
        case .inProgress: return "bg-orange-500"
        case .testflight: return "bg-cyan-500"
        case .completed: return "bg-green-500"
        case .rejected: return "bg-red-500"
        }
    }
}

extension FeedbackCategory {
    var colorClass: String {
        switch self {
        case .featureRequest: return "bg-purple-500"
        case .bugReport: return "bg-red-500"
        case .improvement: return "bg-blue-500"
        case .other: return "bg-gray-500"
        }
    }
}
