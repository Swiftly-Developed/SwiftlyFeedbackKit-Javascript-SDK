import Fluent
import Vapor

final class PushNotificationLog: Model, Content, @unchecked Sendable {
    static let schema = "push_notification_logs"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @OptionalParent(key: "device_token_id")
    var deviceToken: DeviceToken?

    @Field(key: "notification_type")
    var notificationType: String

    @Field(key: "status")
    var status: String

    @OptionalParent(key: "feedback_id")
    var feedback: Feedback?

    @OptionalParent(key: "project_id")
    var project: Project?

    @OptionalField(key: "payload")
    var payload: [String: String]?

    @OptionalField(key: "error_message")
    var errorMessage: String?

    @OptionalField(key: "apns_id")
    var apnsId: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userId: UUID,
        deviceTokenId: UUID? = nil,
        notificationType: String,
        status: String,
        feedbackId: UUID? = nil,
        projectId: UUID? = nil,
        payload: [String: String]? = nil,
        errorMessage: String? = nil,
        apnsId: String? = nil
    ) {
        self.id = id
        self.$user.id = userId
        self.$deviceToken.id = deviceTokenId
        self.notificationType = notificationType
        self.status = status
        self.$feedback.id = feedbackId
        self.$project.id = projectId
        self.payload = payload
        self.errorMessage = errorMessage
        self.apnsId = apnsId
    }
}

// MARK: - Notification Status

enum PushNotificationStatus: String {
    case sent
    case delivered
    case failed
    case tokenExpired = "token_expired"
}

// MARK: - Notification Type

enum PushNotificationType: String, Codable, Sendable {
    case newFeedback = "new_feedback"
    case newComment = "new_comment"
    case newVote = "new_vote"
    case statusChange = "status_change"
}
