import Vapor

// MARK: - Request DTOs

struct TrackViewEventDTO: Content {
    let eventName: String
    let userId: String
    let properties: [String: String]?
}

// MARK: - Response DTOs

struct ViewEventResponseDTO: Content {
    let id: UUID
    let eventName: String
    let userId: String
    let properties: [String: String]?
    let createdAt: Date?

    init(viewEvent: ViewEvent) {
        self.id = viewEvent.id!
        self.eventName = viewEvent.eventName
        self.userId = viewEvent.userId
        self.properties = viewEvent.properties
        self.createdAt = viewEvent.createdAt
    }
}

struct ViewEventStatsDTO: Content {
    let eventName: String
    let totalCount: Int
    let uniqueUsers: Int
}

struct ViewEventsOverviewDTO: Content {
    let totalEvents: Int
    let uniqueUsers: Int
    let eventBreakdown: [ViewEventStatsDTO]
    let recentEvents: [ViewEventResponseDTO]
    let dailyStats: [DailyEventStatsDTO]
}

struct DailyEventStatsDTO: Content {
    let date: String  // ISO date string (YYYY-MM-DD)
    let totalCount: Int
    let uniqueUsers: Int
    let eventBreakdown: [String: Int]  // eventName -> count
}
