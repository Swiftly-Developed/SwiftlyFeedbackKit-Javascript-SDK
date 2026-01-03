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

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userId: String, feedbackId: UUID) {
        self.id = id
        self.userId = userId
        self.$feedback.id = feedbackId
    }
}
