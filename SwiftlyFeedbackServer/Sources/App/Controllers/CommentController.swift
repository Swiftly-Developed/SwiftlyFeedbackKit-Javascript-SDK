import Vapor
import Fluent

struct CommentController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let comments = routes.grouped("feedbacks", ":feedbackId", "comments")

        comments.get(use: index)
        comments.post(use: create)
        comments.delete(":commentId", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [CommentResponseDTO] {
        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid feedback ID")
        }

        let comments = try await Comment.query(on: req.db)
            .filter(\.$feedback.$id == feedbackId)
            .sort(\.$createdAt, .ascending)
            .all()

        return comments.map { CommentResponseDTO(comment: $0) }
    }

    @Sendable
    func create(req: Request) async throws -> CommentResponseDTO {
        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid feedback ID")
        }

        guard let feedback = try await Feedback.query(on: req.db)
            .filter(\.$id == feedbackId)
            .with(\.$project)
            .first() else {
            throw Abort(.notFound, reason: "Feedback not found")
        }

        // Check if project is archived
        if feedback.project.isArchived {
            throw Abort(.forbidden, reason: "Cannot add comments to feedback for an archived project")
        }

        let dto = try req.content.decode(CreateCommentDTO.self)

        // Validate content
        guard !dto.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "Comment content cannot be empty")
        }

        // Validate userId
        guard !dto.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "User ID cannot be empty")
        }

        let comment = Comment(
            content: dto.content.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: dto.userId,
            isAdmin: dto.isAdmin ?? false,
            feedbackId: feedbackId
        )

        try await comment.save(on: req.db)
        return CommentResponseDTO(comment: comment)
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let commentId = req.parameters.get("commentId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid comment ID")
        }

        guard let comment = try await Comment.query(on: req.db)
            .filter(\.$id == commentId)
            .with(\.$feedback)
            .first() else {
            throw Abort(.notFound, reason: "Comment not found")
        }

        // Load feedback's project
        let feedback = try await Feedback.query(on: req.db)
            .filter(\.$id == comment.$feedback.id)
            .with(\.$project)
            .first()

        // Check if project is archived
        if feedback?.project.isArchived == true {
            throw Abort(.forbidden, reason: "Cannot delete comments from feedback for an archived project")
        }

        try await comment.delete(on: req.db)
        return .noContent
    }
}
