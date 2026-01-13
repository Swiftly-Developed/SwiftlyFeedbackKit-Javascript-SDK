import Vapor

struct CreateProjectDTO: Content, Validatable {
    let name: String
    let description: String?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: !.empty && .count(1...100))
    }
}

struct UpdateProjectDTO: Content, Validatable {
    let name: String?
    let description: String?
    let colorIndex: Int?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String?.self, is: .nil || !.empty && .count(1...100), required: false)
        validations.add("colorIndex", as: Int?.self, is: .nil || .range(0...7), required: false)
    }
}

struct UpdateProjectSlackDTO: Content {
    var slackWebhookUrl: String?
    var slackNotifyNewFeedback: Bool?
    var slackNotifyNewComments: Bool?
    var slackNotifyStatusChanges: Bool?
    var slackIsActive: Bool?
}

struct UpdateProjectStatusesDTO: Content {
    var allowedStatuses: [String]
}

// MARK: - GitHub Integration DTOs

struct UpdateProjectGitHubDTO: Content {
    var githubOwner: String?
    var githubRepo: String?
    var githubToken: String?
    var githubDefaultLabels: [String]?
    var githubSyncStatus: Bool?
    var githubIsActive: Bool?
}

struct CreateGitHubIssueDTO: Content {
    var feedbackId: UUID
    var additionalLabels: [String]?
}

struct CreateGitHubIssueResponseDTO: Content {
    var feedbackId: UUID
    var issueUrl: String
    var issueNumber: Int
}

struct BulkCreateGitHubIssuesDTO: Content {
    var feedbackIds: [UUID]
    var additionalLabels: [String]?
}

struct BulkCreateGitHubIssuesResponseDTO: Content {
    var created: [CreateGitHubIssueResponseDTO]
    var failed: [UUID]
}

// MARK: - ClickUp Integration DTOs

struct UpdateProjectClickUpDTO: Content {
    var clickupToken: String?
    var clickupListId: String?
    var clickupWorkspaceName: String?
    var clickupListName: String?
    var clickupDefaultTags: [String]?
    var clickupSyncStatus: Bool?
    var clickupSyncComments: Bool?
    var clickupVotesFieldId: String?
    var clickupIsActive: Bool?
}

struct CreateClickUpTaskDTO: Content, Validatable {
    var feedbackId: UUID
    var additionalTags: [String]?

    static func validations(_ validations: inout Validations) {
        validations.add("feedbackId", as: UUID.self, is: .valid)
    }
}

struct CreateClickUpTaskResponseDTO: Content {
    var feedbackId: UUID
    var taskUrl: String
    var taskId: String
}

struct BulkCreateClickUpTasksDTO: Content {
    var feedbackIds: [UUID]
    var additionalTags: [String]?
}

struct BulkCreateClickUpTasksResponseDTO: Content {
    var created: [CreateClickUpTaskResponseDTO]
    var failed: [UUID]
}

// ClickUp hierarchy DTOs for settings UI
struct ClickUpWorkspaceDTO: Content {
    var id: String
    var name: String
}

struct ClickUpSpaceDTO: Content {
    var id: String
    var name: String
}

struct ClickUpFolderDTO: Content {
    var id: String
    var name: String
}

struct ClickUpListDTO: Content {
    var id: String
    var name: String
}

struct ClickUpCustomFieldDTO: Content {
    var id: String
    var name: String
    var type: String
}

// MARK: - Notion Integration DTOs

struct UpdateProjectNotionDTO: Content {
    var notionToken: String?
    var notionDatabaseId: String?
    var notionDatabaseName: String?
    var notionSyncStatus: Bool?
    var notionSyncComments: Bool?
    var notionStatusProperty: String?
    var notionVotesProperty: String?
    var notionIsActive: Bool?
}

struct CreateNotionPageDTO: Content {
    var feedbackId: UUID
}

struct CreateNotionPageResponseDTO: Content {
    var feedbackId: UUID
    var pageUrl: String
    var pageId: String
}

struct BulkCreateNotionPagesDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateNotionPagesResponseDTO: Content {
    var created: [CreateNotionPageResponseDTO]
    var failed: [UUID]
}

struct NotionDatabaseDTO: Content {
    var id: String
    var name: String
    var properties: [NotionPropertyDTO]
}

struct NotionPropertyDTO: Content {
    var id: String
    var name: String
    var type: String
}

// MARK: - Monday.com Integration DTOs

struct UpdateProjectMondayDTO: Content {
    var mondayToken: String?
    var mondayBoardId: String?
    var mondayBoardName: String?
    var mondayGroupId: String?
    var mondayGroupName: String?
    var mondaySyncStatus: Bool?
    var mondaySyncComments: Bool?
    var mondayStatusColumnId: String?
    var mondayVotesColumnId: String?
    var mondayIsActive: Bool?
}

struct CreateMondayItemDTO: Content {
    var feedbackId: UUID
}

struct CreateMondayItemResponseDTO: Content {
    var feedbackId: UUID
    var itemUrl: String
    var itemId: String
}

struct BulkCreateMondayItemsDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateMondayItemsResponseDTO: Content {
    var created: [CreateMondayItemResponseDTO]
    var failed: [UUID]
}

struct MondayBoardDTO: Content {
    var id: String
    var name: String
}

struct MondayGroupDTO: Content {
    var id: String
    var title: String
}

struct MondayColumnDTO: Content {
    var id: String
    var title: String
    var type: String
}

// MARK: - Linear Integration DTOs

struct UpdateProjectLinearDTO: Content {
    var linearToken: String?
    var linearTeamId: String?
    var linearTeamName: String?
    var linearProjectId: String?
    var linearProjectName: String?
    var linearDefaultLabelIds: [String]?
    var linearSyncStatus: Bool?
    var linearSyncComments: Bool?
    var linearIsActive: Bool?
}

struct CreateLinearIssueDTO: Content {
    var feedbackId: UUID
    var additionalLabelIds: [String]?
}

struct CreateLinearIssueResponseDTO: Content {
    var feedbackId: UUID
    var issueUrl: String
    var issueId: String
    var identifier: String
}

struct BulkCreateLinearIssuesDTO: Content {
    var feedbackIds: [UUID]
    var additionalLabelIds: [String]?
}

struct BulkCreateLinearIssuesResponseDTO: Content {
    var created: [CreateLinearIssueResponseDTO]
    var failed: [UUID]
}

// Linear hierarchy DTOs for settings UI
struct LinearTeamDTO: Content {
    var id: String
    var name: String
    var key: String
}

struct LinearProjectDTO: Content {
    var id: String
    var name: String
    var state: String
}

struct LinearWorkflowStateDTO: Content {
    var id: String
    var name: String
    var type: String
    var position: Double
}

struct LinearLabelDTO: Content {
    var id: String
    var name: String
    var color: String
}

// MARK: - Trello Integration DTOs

struct UpdateProjectTrelloDTO: Content {
    var trelloToken: String?
    var trelloBoardId: String?
    var trelloBoardName: String?
    var trelloListId: String?
    var trelloListName: String?
    var trelloSyncStatus: Bool?
    var trelloSyncComments: Bool?
    var trelloIsActive: Bool?
}

struct CreateTrelloCardDTO: Content {
    var feedbackId: UUID
}

struct CreateTrelloCardResponseDTO: Content {
    var feedbackId: UUID
    var cardUrl: String
    var cardId: String
}

struct BulkCreateTrelloCardsDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateTrelloCardsResponseDTO: Content {
    var created: [CreateTrelloCardResponseDTO]
    var failed: [UUID]
}

// Trello hierarchy DTOs for settings UI
struct TrelloBoardDTO: Content {
    var id: String
    var name: String
}

struct TrelloListDTO: Content {
    var id: String
    var name: String
}

// MARK: - Airtable Integration DTOs

struct UpdateProjectAirtableDTO: Content {
    var airtableToken: String?
    var airtableBaseId: String?
    var airtableBaseName: String?
    var airtableTableId: String?
    var airtableTableName: String?
    var airtableSyncStatus: Bool?
    var airtableSyncComments: Bool?
    var airtableStatusFieldId: String?
    var airtableVotesFieldId: String?
    var airtableTitleFieldId: String?
    var airtableDescriptionFieldId: String?
    var airtableCategoryFieldId: String?
    var airtableIsActive: Bool?
}

struct CreateAirtableRecordDTO: Content {
    var feedbackId: UUID
}

struct CreateAirtableRecordResponseDTO: Content {
    var feedbackId: UUID
    var recordUrl: String
    var recordId: String
}

struct BulkCreateAirtableRecordsDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateAirtableRecordsResponseDTO: Content {
    var created: [CreateAirtableRecordResponseDTO]
    var failed: [UUID]
}

// Airtable hierarchy DTOs for settings UI
struct AirtableBaseDTO: Content {
    var id: String
    var name: String
}

struct AirtableTableDTO: Content {
    var id: String
    var name: String
}

struct AirtableFieldDTO: Content {
    var id: String
    var name: String
    var type: String
}

// MARK: - Asana Integration DTOs

struct UpdateProjectAsanaDTO: Content {
    var asanaToken: String?
    var asanaWorkspaceId: String?
    var asanaWorkspaceName: String?
    var asanaProjectId: String?
    var asanaProjectName: String?
    var asanaSectionId: String?
    var asanaSectionName: String?
    var asanaSyncStatus: Bool?
    var asanaSyncComments: Bool?
    var asanaStatusFieldId: String?
    var asanaVotesFieldId: String?
    var asanaIsActive: Bool?
}

struct CreateAsanaTaskDTO: Content {
    var feedbackId: UUID
}

struct CreateAsanaTaskResponseDTO: Content {
    var feedbackId: UUID
    var taskUrl: String
    var taskId: String
}

struct BulkCreateAsanaTasksDTO: Content {
    var feedbackIds: [UUID]
}

struct BulkCreateAsanaTasksResponseDTO: Content {
    var created: [CreateAsanaTaskResponseDTO]
    var failed: [UUID]
}

// Asana hierarchy DTOs for settings UI
struct AsanaWorkspaceDTO: Content {
    var gid: String
    var name: String
}

struct AsanaProjectDTO: Content {
    var gid: String
    var name: String
}

struct AsanaSectionDTO: Content {
    var gid: String
    var name: String
}

struct AsanaCustomFieldDTO: Content {
    var gid: String
    var name: String
    var type: String
    var enumOptions: [AsanaEnumOptionDTO]?
}

struct AsanaEnumOptionDTO: Content {
    var gid: String
    var name: String
    var enabled: Bool
    var color: String?
}

struct AddMemberDTO: Content, Validatable {
    let email: String
    let role: ProjectRole

    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email)
    }
}

struct UpdateMemberRoleDTO: Content {
    let role: ProjectRole
}

struct ProjectResponseDTO: Content {
    let id: UUID
    let name: String
    let apiKey: String
    let description: String?
    let ownerId: UUID
    let ownerEmail: String?
    let isArchived: Bool
    let archivedAt: Date?
    let colorIndex: Int
    let feedbackCount: Int
    let memberCount: Int
    let createdAt: Date?
    let updatedAt: Date?
    let slackWebhookURL: String?
    let slackNotifyNewFeedback: Bool
    let slackNotifyNewComments: Bool
    let slackNotifyStatusChanges: Bool
    let slackIsActive: Bool
    let allowedStatuses: [String]
    // GitHub integration fields
    let githubOwner: String?
    let githubRepo: String?
    let githubToken: String?
    let githubDefaultLabels: [String]?
    let githubSyncStatus: Bool
    let githubIsActive: Bool
    // ClickUp integration fields
    let clickupToken: String?
    let clickupListId: String?
    let clickupWorkspaceName: String?
    let clickupListName: String?
    let clickupDefaultTags: [String]?
    let clickupSyncStatus: Bool
    let clickupSyncComments: Bool
    let clickupVotesFieldId: String?
    let clickupIsActive: Bool
    // Notion integration fields
    let notionToken: String?
    let notionDatabaseId: String?
    let notionDatabaseName: String?
    let notionSyncStatus: Bool
    let notionSyncComments: Bool
    let notionStatusProperty: String?
    let notionVotesProperty: String?
    let notionIsActive: Bool
    // Monday.com integration fields
    let mondayToken: String?
    let mondayBoardId: String?
    let mondayBoardName: String?
    let mondayGroupId: String?
    let mondayGroupName: String?
    let mondaySyncStatus: Bool
    let mondaySyncComments: Bool
    let mondayStatusColumnId: String?
    let mondayVotesColumnId: String?
    let mondayIsActive: Bool
    // Linear integration fields
    let linearToken: String?
    let linearTeamId: String?
    let linearTeamName: String?
    let linearProjectId: String?
    let linearProjectName: String?
    let linearDefaultLabelIds: [String]?
    let linearSyncStatus: Bool
    let linearSyncComments: Bool
    let linearIsActive: Bool
    // Trello integration fields
    let trelloToken: String?
    let trelloBoardId: String?
    let trelloBoardName: String?
    let trelloListId: String?
    let trelloListName: String?
    let trelloSyncStatus: Bool
    let trelloSyncComments: Bool
    let trelloIsActive: Bool
    // Airtable integration fields
    let airtableToken: String?
    let airtableBaseId: String?
    let airtableBaseName: String?
    let airtableTableId: String?
    let airtableTableName: String?
    let airtableSyncStatus: Bool
    let airtableSyncComments: Bool
    let airtableStatusFieldId: String?
    let airtableVotesFieldId: String?
    let airtableTitleFieldId: String?
    let airtableDescriptionFieldId: String?
    let airtableCategoryFieldId: String?
    let airtableIsActive: Bool
    // Asana integration fields
    let asanaToken: String?
    let asanaWorkspaceId: String?
    let asanaWorkspaceName: String?
    let asanaProjectId: String?
    let asanaProjectName: String?
    let asanaSectionId: String?
    let asanaSectionName: String?
    let asanaSyncStatus: Bool
    let asanaSyncComments: Bool
    let asanaStatusFieldId: String?
    let asanaVotesFieldId: String?
    let asanaIsActive: Bool

    init(project: Project, feedbackCount: Int = 0, memberCount: Int = 0, ownerEmail: String? = nil) {
        self.id = project.id!
        self.name = project.name
        self.apiKey = project.apiKey
        self.description = project.description
        self.ownerId = project.$owner.id
        self.ownerEmail = ownerEmail
        self.isArchived = project.isArchived
        self.archivedAt = project.archivedAt
        self.colorIndex = project.colorIndex
        self.feedbackCount = feedbackCount
        self.memberCount = memberCount
        self.createdAt = project.createdAt
        self.updatedAt = project.updatedAt
        self.slackWebhookURL = project.slackWebhookURL
        self.slackNotifyNewFeedback = project.slackNotifyNewFeedback
        self.slackNotifyNewComments = project.slackNotifyNewComments
        self.slackNotifyStatusChanges = project.slackNotifyStatusChanges
        self.slackIsActive = project.slackIsActive
        self.allowedStatuses = project.allowedStatuses
        self.githubOwner = project.githubOwner
        self.githubRepo = project.githubRepo
        self.githubToken = project.githubToken
        self.githubDefaultLabels = project.githubDefaultLabels
        self.githubSyncStatus = project.githubSyncStatus
        self.githubIsActive = project.githubIsActive
        self.clickupToken = project.clickupToken
        self.clickupListId = project.clickupListId
        self.clickupWorkspaceName = project.clickupWorkspaceName
        self.clickupListName = project.clickupListName
        self.clickupDefaultTags = project.clickupDefaultTags
        self.clickupSyncStatus = project.clickupSyncStatus
        self.clickupSyncComments = project.clickupSyncComments
        self.clickupVotesFieldId = project.clickupVotesFieldId
        self.clickupIsActive = project.clickupIsActive
        self.notionToken = project.notionToken
        self.notionDatabaseId = project.notionDatabaseId
        self.notionDatabaseName = project.notionDatabaseName
        self.notionSyncStatus = project.notionSyncStatus
        self.notionSyncComments = project.notionSyncComments
        self.notionStatusProperty = project.notionStatusProperty
        self.notionVotesProperty = project.notionVotesProperty
        self.notionIsActive = project.notionIsActive
        self.mondayToken = project.mondayToken
        self.mondayBoardId = project.mondayBoardId
        self.mondayBoardName = project.mondayBoardName
        self.mondayGroupId = project.mondayGroupId
        self.mondayGroupName = project.mondayGroupName
        self.mondaySyncStatus = project.mondaySyncStatus
        self.mondaySyncComments = project.mondaySyncComments
        self.mondayStatusColumnId = project.mondayStatusColumnId
        self.mondayVotesColumnId = project.mondayVotesColumnId
        self.mondayIsActive = project.mondayIsActive
        self.linearToken = project.linearToken
        self.linearTeamId = project.linearTeamId
        self.linearTeamName = project.linearTeamName
        self.linearProjectId = project.linearProjectId
        self.linearProjectName = project.linearProjectName
        self.linearDefaultLabelIds = project.linearDefaultLabelIds
        self.linearSyncStatus = project.linearSyncStatus
        self.linearSyncComments = project.linearSyncComments
        self.linearIsActive = project.linearIsActive
        self.trelloToken = project.trelloToken
        self.trelloBoardId = project.trelloBoardId
        self.trelloBoardName = project.trelloBoardName
        self.trelloListId = project.trelloListId
        self.trelloListName = project.trelloListName
        self.trelloSyncStatus = project.trelloSyncStatus
        self.trelloSyncComments = project.trelloSyncComments
        self.trelloIsActive = project.trelloIsActive
        self.airtableToken = project.airtableToken
        self.airtableBaseId = project.airtableBaseId
        self.airtableBaseName = project.airtableBaseName
        self.airtableTableId = project.airtableTableId
        self.airtableTableName = project.airtableTableName
        self.airtableSyncStatus = project.airtableSyncStatus
        self.airtableSyncComments = project.airtableSyncComments
        self.airtableStatusFieldId = project.airtableStatusFieldId
        self.airtableVotesFieldId = project.airtableVotesFieldId
        self.airtableTitleFieldId = project.airtableTitleFieldId
        self.airtableDescriptionFieldId = project.airtableDescriptionFieldId
        self.airtableCategoryFieldId = project.airtableCategoryFieldId
        self.airtableIsActive = project.airtableIsActive
        self.asanaToken = project.asanaToken
        self.asanaWorkspaceId = project.asanaWorkspaceId
        self.asanaWorkspaceName = project.asanaWorkspaceName
        self.asanaProjectId = project.asanaProjectId
        self.asanaProjectName = project.asanaProjectName
        self.asanaSectionId = project.asanaSectionId
        self.asanaSectionName = project.asanaSectionName
        self.asanaSyncStatus = project.asanaSyncStatus
        self.asanaSyncComments = project.asanaSyncComments
        self.asanaStatusFieldId = project.asanaStatusFieldId
        self.asanaVotesFieldId = project.asanaVotesFieldId
        self.asanaIsActive = project.asanaIsActive
    }
}

struct ProjectListItemDTO: Content {
    let id: UUID
    let name: String
    let description: String?
    let isArchived: Bool
    let isOwner: Bool
    let role: ProjectRole?
    let colorIndex: Int
    let feedbackCount: Int
    let createdAt: Date?
}

struct AddMemberResponse: Content {
    let member: ProjectMember.Public?
    let invite: ProjectInviteDTO?
    let inviteSent: Bool

    init(member: ProjectMember.Public, inviteSent: Bool) {
        self.member = member
        self.invite = nil
        self.inviteSent = inviteSent
    }

    init(invite: ProjectInvite, inviteSent: Bool) {
        self.member = nil
        self.invite = ProjectInviteDTO(invite: invite)
        self.inviteSent = inviteSent
    }
}

struct ProjectInviteDTO: Content {
    let id: UUID
    let email: String
    let role: ProjectRole
    let code: String
    let expiresAt: Date
    let createdAt: Date?

    init(invite: ProjectInvite) {
        self.id = invite.id!
        self.email = invite.email
        self.role = invite.role
        self.code = invite.token
        self.expiresAt = invite.expiresAt
        self.createdAt = invite.createdAt
    }
}

struct AcceptInviteDTO: Content {
    let code: String
}

struct InvitePreviewDTO: Content {
    let projectName: String
    let projectDescription: String?
    let invitedByName: String
    let role: ProjectRole
    let expiresAt: Date
    let emailMatches: Bool
    let inviteEmail: String
}

struct AcceptInviteResponseDTO: Content {
    let projectId: UUID
    let projectName: String
    let role: ProjectRole
}
