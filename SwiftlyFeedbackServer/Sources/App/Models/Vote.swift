import Fluent
import Vapor

final class Vote: Model, Content, @unchecked Sendable {
    static let schema = "votes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: String

    @Parent(key: "feedback_id")
    var feedback: Feedback

    @OptionalField(key: "email")
    var email: String?

    @Field(key: "notify_status_change")
    var notifyStatusChange: Bool

    @OptionalField(key: "permission_key")
    var permissionKey: UUID?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {
        self.notifyStatusChange = false
    }

    init(
        id: UUID? = nil,
        userId: String,
        feedbackId: UUID,
        email: String? = nil,
        notifyStatusChange: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.$feedback.id = feedbackId
        self.email = email
        self.notifyStatusChange = notifyStatusChange
        // Generate permission key only if email is provided and notifications enabled
        if email != nil && notifyStatusChange {
            self.permissionKey = UUID()
        }
    }
}
