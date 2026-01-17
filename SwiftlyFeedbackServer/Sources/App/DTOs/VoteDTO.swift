import Vapor

struct CreateVoteDTO: Content {
    let userId: String
    let email: String?
    let notifyStatusChange: Bool?
}

struct VoteResponseDTO: Content {
    let feedbackId: UUID
    let voteCount: Int
    let hasVoted: Bool
}

struct UnsubscribeVoteResponseDTO: Content {
    let success: Bool
    let message: String
}
