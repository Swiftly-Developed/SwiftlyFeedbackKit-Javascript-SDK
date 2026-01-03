import Vapor

struct CreateCommentDTO: Content {
    let content: String
    let userId: String
    let isAdmin: Bool?
}

struct CommentResponseDTO: Content {
    let id: UUID
    let content: String
    let userId: String
    let isAdmin: Bool
    let createdAt: Date?

    init(comment: Comment) {
        self.id = comment.id!
        self.content = comment.content
        self.userId = comment.userId
        self.isAdmin = comment.isAdmin
        self.createdAt = comment.createdAt
    }
}
