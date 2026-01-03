import Vapor

struct CreateVoteDTO: Content {
    let userId: String
}

struct VoteResponseDTO: Content {
    let feedbackId: UUID
    let voteCount: Int
    let hasVoted: Bool
}
