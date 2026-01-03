import Fluent
import Vapor

final class Comment: Model, Content, @unchecked Sendable {
    static let schema = "comments"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "content")
    var content: String

    @Field(key: "user_id")
    var userId: String

    @Field(key: "is_admin")
    var isAdmin: Bool

    @Parent(key: "feedback_id")
    var feedback: Feedback

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, content: String, userId: String, isAdmin: Bool = false, feedbackId: UUID) {
        self.id = id
        self.content = content
        self.userId = userId
        self.isAdmin = isAdmin
        self.$feedback.id = feedbackId
    }
}
