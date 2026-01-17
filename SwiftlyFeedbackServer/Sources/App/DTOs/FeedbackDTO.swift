import Vapor

struct CreateFeedbackDTO: Content {
    let title: String
    let description: String
    let category: FeedbackCategory
    let userId: String
    let userEmail: String?
}

struct UpdateFeedbackDTO: Content {
    let title: String?
    let description: String?
    let status: FeedbackStatus?
    let category: FeedbackCategory?
    let rejectionReason: String?
}

struct FeedbackResponseDTO: Content {
    let id: UUID
    let title: String
    let description: String
    let status: FeedbackStatus
    let category: FeedbackCategory
    let userId: String
    let userEmail: String?
    let voteCount: Int
    let hasVoted: Bool
    let commentCount: Int
    /// Total MRR from the feedback creator plus all voters
    let totalMrr: Double?
    let createdAt: Date?
    let updatedAt: Date?
    // Merge-related fields
    let mergedIntoId: UUID?
    let mergedAt: Date?
    let mergedFeedbackIds: [UUID]?
    // GitHub integration fields
    let githubIssueUrl: String?
    let githubIssueNumber: Int?
    // ClickUp integration fields
    let clickupTaskUrl: String?
    let clickupTaskId: String?
    // Notion integration fields
    let notionPageUrl: String?
    let notionPageId: String?
    // Monday.com integration fields
    let mondayItemUrl: String?
    let mondayItemId: String?
    // Linear integration fields
    let linearIssueUrl: String?
    let linearIssueId: String?
    // Trello integration fields
    let trelloCardUrl: String?
    let trelloCardId: String?
    // Airtable integration fields
    let airtableRecordUrl: String?
    let airtableRecordId: String?
    // Asana integration fields
    let asanaTaskUrl: String?
    let asanaTaskId: String?
    // Basecamp integration fields
    let basecampTodoUrl: String?
    let basecampTodoId: String?
    let basecampBucketId: String?
    // Rejection reason
    let rejectionReason: String?

    init(feedback: Feedback, hasVoted: Bool = false, commentCount: Int = 0, totalMrr: Double? = nil) {
        self.id = feedback.id!
        self.title = feedback.title
        self.description = feedback.description
        self.status = feedback.status
        self.category = feedback.category
        self.userId = feedback.userId
        self.userEmail = feedback.userEmail
        self.voteCount = feedback.voteCount
        self.hasVoted = hasVoted
        self.commentCount = commentCount
        self.totalMrr = totalMrr
        self.createdAt = feedback.createdAt
        self.updatedAt = feedback.updatedAt
        self.mergedIntoId = feedback.mergedIntoId
        self.mergedAt = feedback.mergedAt
        self.mergedFeedbackIds = feedback.mergedFeedbackIds
        self.githubIssueUrl = feedback.githubIssueURL
        self.githubIssueNumber = feedback.githubIssueNumber
        self.clickupTaskUrl = feedback.clickupTaskURL
        self.clickupTaskId = feedback.clickupTaskId
        self.notionPageUrl = feedback.notionPageURL
        self.notionPageId = feedback.notionPageId
        self.mondayItemUrl = feedback.mondayItemURL
        self.mondayItemId = feedback.mondayItemId
        self.linearIssueUrl = feedback.linearIssueURL
        self.linearIssueId = feedback.linearIssueId
        self.trelloCardUrl = feedback.trelloCardURL
        self.trelloCardId = feedback.trelloCardId
        self.airtableRecordUrl = feedback.airtableRecordURL
        self.airtableRecordId = feedback.airtableRecordId
        self.asanaTaskUrl = feedback.asanaTaskURL
        self.asanaTaskId = feedback.asanaTaskId
        self.basecampTodoUrl = feedback.basecampTodoURL
        self.basecampTodoId = feedback.basecampTodoId
        self.basecampBucketId = feedback.basecampBucketId
        self.rejectionReason = feedback.rejectionReason
    }
}
