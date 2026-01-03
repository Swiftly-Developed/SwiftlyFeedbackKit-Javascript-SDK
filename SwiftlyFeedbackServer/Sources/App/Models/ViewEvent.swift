import Fluent
import Vapor

/// Represents a view/event tracked from the SDK.
/// Used for analytics on user behavior and feature usage.
final class ViewEvent: Model, Content, @unchecked Sendable {
    static let schema = "view_events"

    @ID(key: .id)
    var id: UUID?

    /// The name of the event (e.g., "feedback_list", "feature_details")
    @Field(key: "event_name")
    var eventName: String

    /// The user identifier from the SDK
    @Field(key: "user_id")
    var userId: String

    /// The project this event belongs to
    @Parent(key: "project_id")
    var project: Project

    /// Optional key-value properties for additional context
    @OptionalField(key: "properties")
    var properties: [String: String]?

    /// When this event was tracked
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        eventName: String,
        userId: String,
        projectId: UUID,
        properties: [String: String]? = nil
    ) {
        self.id = id
        self.eventName = eventName
        self.userId = userId
        self.$project.id = projectId
        self.properties = properties
    }
}
