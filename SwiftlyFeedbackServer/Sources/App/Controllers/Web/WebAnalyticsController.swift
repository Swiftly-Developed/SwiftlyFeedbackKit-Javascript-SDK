import Vapor
import Fluent
import Leaf

struct WebAnalyticsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let analytics = routes.grouped("analytics")

        analytics.get("users", use: users)
        analytics.get("events", use: events)
    }

    // MARK: - SDK Users

    @Sendable
    func users(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        let projectIdParam = req.query[UUID.self, at: "project_id"]

        // Get accessible projects
        let accessibleProjects = try await getAccessibleProjects(req: req, userId: userId)

        guard !accessibleProjects.isEmpty else {
            return try await req.view.render("analytics/users", SDKUsersContext(
                title: "Users",
                pageTitle: "SDK Users",
                currentPage: "users",
                user: UserContext(from: user),
                users: [],
                projects: [],
                selectedProjectId: nil,
                totalUsers: 0,
                totalMRR: "0"
            ))
        }

        let projectIds: [UUID]
        if let projectId = projectIdParam, accessibleProjects.contains(where: { $0.id == projectId }) {
            projectIds = [projectId]
        } else {
            projectIds = accessibleProjects.compactMap { $0.id }
        }

        // Get SDK users
        let sdkUsers = try await SDKUser.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .with(\.$project)
            .sort(\.$firstSeenAt, .descending)
            .all()

        let userItems = sdkUsers.map { sdkUser in
            SDKUserItem(
                id: sdkUser.id ?? UUID(),
                userId: sdkUser.userId,
                projectName: sdkUser.$project.value?.name ?? "Unknown",
                mrr: sdkUser.mrr?.description ?? "0",
                createdAt: formatRelativeDate(sdkUser.firstSeenAt)
            )
        }

        // Calculate totals
        let totalUsers = sdkUsers.count
        let totalMRR = sdkUsers.compactMap { $0.mrr }.reduce(0.0, +)

        let projectOptions = accessibleProjects.map { project in
            ProjectOption(
                id: project.id ?? UUID(),
                name: project.name,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass
            )
        }

        return try await req.view.render("analytics/users", SDKUsersContext(
            title: "Users",
            pageTitle: "SDK Users",
            currentPage: "users",
            user: UserContext(from: user),
            users: userItems,
            projects: projectOptions,
            selectedProjectId: projectIdParam,
            totalUsers: totalUsers,
            totalMRR: String(format: "%.2f", totalMRR)
        ))
    }

    // MARK: - Events

    @Sendable
    func events(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        let projectIdParam = req.query[UUID.self, at: "project_id"]
        let periodParam = req.query[String.self, at: "period"] ?? "week"

        // Get accessible projects
        let accessibleProjects = try await getAccessibleProjects(req: req, userId: userId)

        guard !accessibleProjects.isEmpty else {
            return try await req.view.render("analytics/events", EventsContext(
                title: "Events",
                pageTitle: "Event Analytics",
                currentPage: "events",
                user: UserContext(from: user),
                events: [],
                projects: [],
                selectedProjectId: nil,
                selectedPeriod: periodParam,
                totalEvents: 0,
                chartData: []
            ))
        }

        let projectIds: [UUID]
        if let projectId = projectIdParam, accessibleProjects.contains(where: { $0.id == projectId }) {
            projectIds = [projectId]
        } else {
            projectIds = accessibleProjects.compactMap { $0.id }
        }

        // Calculate date range based on period
        let now = Date()
        let startDate: Date
        switch periodParam {
        case "day":
            startDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        case "month":
            startDate = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        default: // week
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        }

        // Get events
        let events = try await ViewEvent.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .filter(\.$createdAt >= startDate)
            .with(\.$project)
            .sort(\.$createdAt, .descending)
            .all()

        let eventItems = events.prefix(100).map { event in
            EventItem(
                id: event.id ?? UUID(),
                eventName: event.eventName,
                userId: event.userId,
                projectName: event.$project.value?.name ?? "Unknown",
                createdAt: formatRelativeDate(event.createdAt)
            )
        }

        // Group events by date for chart
        var eventsByDate: [String: Int] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = periodParam == "day" ? "HH:00" : "MMM d"

        for event in events {
            if let createdAt = event.createdAt {
                let dateKey = dateFormatter.string(from: createdAt)
                eventsByDate[dateKey, default: 0] += 1
            }
        }

        let chartData = eventsByDate.map { ChartDataPoint(label: $0.key, value: $0.value) }
            .sorted { $0.label < $1.label }

        let projectOptions = accessibleProjects.map { project in
            ProjectOption(
                id: project.id ?? UUID(),
                name: project.name,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass
            )
        }

        return try await req.view.render("analytics/events", EventsContext(
            title: "Events",
            pageTitle: "Event Analytics",
            currentPage: "events",
            user: UserContext(from: user),
            events: Array(eventItems),
            projects: projectOptions,
            selectedProjectId: projectIdParam,
            selectedPeriod: periodParam,
            totalEvents: events.count,
            chartData: chartData
        ))
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

// MARK: - View Contexts

struct SDKUsersContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let users: [SDKUserItem]
    let projects: [ProjectOption]
    let selectedProjectId: UUID?
    let totalUsers: Int
    let totalMRR: String
}

struct SDKUserItem: Encodable {
    let id: UUID
    let userId: String
    let projectName: String
    let mrr: String
    let createdAt: String
}

struct EventsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let events: [EventItem]
    let projects: [ProjectOption]
    let selectedProjectId: UUID?
    let selectedPeriod: String
    let totalEvents: Int
    let chartData: [ChartDataPoint]
}

struct EventItem: Encodable {
    let id: UUID
    let eventName: String
    let userId: String?
    let projectName: String
    let createdAt: String
}

struct ChartDataPoint: Encodable {
    let label: String
    let value: Int
}
