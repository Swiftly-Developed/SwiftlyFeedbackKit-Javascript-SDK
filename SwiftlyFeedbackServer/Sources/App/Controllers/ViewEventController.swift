import Vapor
import Fluent
import Foundation

struct ViewEventController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let events = routes.grouped("events")

        // Public API routes (for SDK) - require API key
        events.post("track", use: trackEvent)

        // Admin routes - require authentication
        let protected = events.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.get("project", ":projectId", use: getProjectEvents)
        protected.get("project", ":projectId", "stats", use: getProjectEventStats)
        protected.get("all", "stats", use: getAllEventStats)
    }

    /// Get the project from API key
    private func getProjectFromApiKey(req: Request) async throws -> Project {
        guard let apiKey = req.headers.first(name: "X-API-Key") else {
            throw Abort(.unauthorized, reason: "API key required")
        }

        guard let project = try await Project.query(on: req.db)
            .filter(\.$apiKey == apiKey)
            .first() else {
            throw Abort(.unauthorized, reason: "Invalid API key")
        }

        return project
    }

    /// Track a view event from SDK
    @Sendable
    func trackEvent(req: Request) async throws -> ViewEventResponseDTO {
        let project = try await getProjectFromApiKey(req: req)
        let dto = try req.content.decode(TrackViewEventDTO.self)

        guard !dto.eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "Event name cannot be empty")
        }

        guard !dto.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "User ID cannot be empty")
        }

        let projectId = try project.requireID()

        let viewEvent = ViewEvent(
            eventName: dto.eventName.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: dto.userId.trimmingCharacters(in: .whitespacesAndNewlines),
            projectId: projectId,
            properties: dto.properties
        )
        try await viewEvent.save(on: req.db)

        return ViewEventResponseDTO(viewEvent: viewEvent)
    }

    /// Get all view events for a project (admin only)
    @Sendable
    func getProjectEvents(req: Request) async throws -> [ViewEventResponseDTO] {
        let user = try req.auth.require(User.self)

        guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid project ID")
        }

        guard let project = try await Project.find(projectId, on: req.db) else {
            throw Abort(.notFound, reason: "Project not found")
        }

        // Verify user has access to this project
        let userId = try user.requireID()
        guard try await project.userHasAccess(userId, on: req.db) else {
            throw Abort(.forbidden, reason: "You don't have access to this project")
        }

        // Get recent events (limit to last 100)
        let events = try await ViewEvent.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .sort(\.$createdAt, .descending)
            .limit(100)
            .all()

        return events.map { ViewEventResponseDTO(viewEvent: $0) }
    }

    /// Get view event statistics for a project (admin only)
    @Sendable
    func getProjectEventStats(req: Request) async throws -> ViewEventsOverviewDTO {
        let user = try req.auth.require(User.self)

        guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid project ID")
        }

        guard let project = try await Project.find(projectId, on: req.db) else {
            throw Abort(.notFound, reason: "Project not found")
        }

        // Verify user has access to this project
        let userId = try user.requireID()
        guard try await project.userHasAccess(userId, on: req.db) else {
            throw Abort(.forbidden, reason: "You don't have access to this project")
        }

        // Get all events for this project
        let allEvents = try await ViewEvent.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .all()

        // Calculate totals
        let totalEvents = allEvents.count
        let uniqueUsers = Set(allEvents.map { $0.userId }).count

        // Group by event name for breakdown
        let groupedByName = Dictionary(grouping: allEvents) { $0.eventName }
        let eventBreakdown = groupedByName.map { eventName, events in
            ViewEventStatsDTO(
                eventName: eventName,
                totalCount: events.count,
                uniqueUsers: Set(events.map { $0.userId }).count
            )
        }.sorted { $0.totalCount > $1.totalCount }

        // Get recent events (last 10)
        let recentEvents = try await ViewEvent.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .sort(\.$createdAt, .descending)
            .limit(10)
            .all()
            .map { ViewEventResponseDTO(viewEvent: $0) }

        // Calculate daily stats (last 30 days)
        let dailyStats = calculateDailyStats(events: allEvents, days: 30)

        return ViewEventsOverviewDTO(
            totalEvents: totalEvents,
            uniqueUsers: uniqueUsers,
            eventBreakdown: eventBreakdown,
            recentEvents: recentEvents,
            dailyStats: dailyStats
        )
    }

    /// Get view event statistics across all projects the user has access to (admin only)
    @Sendable
    func getAllEventStats(req: Request) async throws -> ViewEventsOverviewDTO {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        // Get all projects the user has access to
        let memberships = try await ProjectMember.query(on: req.db)
            .filter(\.$user.$id == userId)
            .all()
        let projectIds = memberships.map { $0.$project.id }

        // Get all events for these projects
        let allEvents = try await ViewEvent.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .all()

        // Calculate totals
        let totalEvents = allEvents.count
        let uniqueUsers = Set(allEvents.map { $0.userId }).count

        // Group by event name for breakdown
        let groupedByName = Dictionary(grouping: allEvents) { $0.eventName }
        let eventBreakdown = groupedByName.map { eventName, events in
            ViewEventStatsDTO(
                eventName: eventName,
                totalCount: events.count,
                uniqueUsers: Set(events.map { $0.userId }).count
            )
        }.sorted { $0.totalCount > $1.totalCount }

        // Get recent events (last 10) across all projects
        let recentEvents = try await ViewEvent.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .sort(\.$createdAt, .descending)
            .limit(10)
            .all()
            .map { ViewEventResponseDTO(viewEvent: $0) }

        // Calculate daily stats (last 30 days)
        let dailyStats = calculateDailyStats(events: allEvents, days: 30)

        return ViewEventsOverviewDTO(
            totalEvents: totalEvents,
            uniqueUsers: uniqueUsers,
            eventBreakdown: eventBreakdown,
            recentEvents: recentEvents,
            dailyStats: dailyStats
        )
    }

    /// Calculate daily event statistics for the last N days
    private func calculateDailyStats(events: [ViewEvent], days: Int) -> [DailyEventStatsDTO] {
        let calendar = Calendar.current
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        // Create a date formatter for grouping
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")

        // Get the date range
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }

        // Group events by date
        var eventsByDate: [String: [ViewEvent]] = [:]
        for event in events {
            guard let createdAt = event.createdAt else { continue }
            let dateKey = dayFormatter.string(from: createdAt)
            eventsByDate[dateKey, default: []].append(event)
        }

        // Generate stats for each day in the range
        var dailyStats: [DailyEventStatsDTO] = []
        var currentDate = startDate

        while currentDate <= today {
            let dateKey = dayFormatter.string(from: currentDate)
            let dayEvents = eventsByDate[dateKey] ?? []

            // Calculate event breakdown for this day
            let eventBreakdown = Dictionary(grouping: dayEvents) { $0.eventName }
                .mapValues { $0.count }

            let stats = DailyEventStatsDTO(
                date: dateKey,
                totalCount: dayEvents.count,
                uniqueUsers: Set(dayEvents.map { $0.userId }).count,
                eventBreakdown: eventBreakdown
            )
            dailyStats.append(stats)

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return dailyStats
    }
}
