import Fluent
import Vapor

final class ProjectMemberPreference: Model, Content, @unchecked Sendable {
    static let schema = "project_member_preferences"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "project_id")
    var project: Project

    // Push notification overrides (nil = use personal preference)
    @OptionalField(key: "push_notify_new_feedback")
    var pushNotifyNewFeedback: Bool?

    @OptionalField(key: "push_notify_new_comments")
    var pushNotifyNewComments: Bool?

    @OptionalField(key: "push_notify_votes")
    var pushNotifyVotes: Bool?

    @OptionalField(key: "push_notify_status_changes")
    var pushNotifyStatusChanges: Bool?

    @Field(key: "push_muted")
    var pushMuted: Bool

    // Email notification overrides (future expansion)
    @OptionalField(key: "email_notify_new_feedback")
    var emailNotifyNewFeedback: Bool?

    @OptionalField(key: "email_notify_new_comments")
    var emailNotifyNewComments: Bool?

    @Field(key: "email_muted")
    var emailMuted: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: UUID, projectID: UUID) {
        self.$user.id = userID
        self.$project.id = projectID
        self.pushMuted = false
        self.emailMuted = false
    }
}

// MARK: - Response DTO

struct ProjectNotificationPreferencesDTO: Content {
    let projectId: UUID
    let userId: UUID

    struct PushSettings: Content {
        let muted: Bool
        let newFeedback: Bool?
        let newComments: Bool?
        let votes: Bool?
        let statusChanges: Bool?

        enum CodingKeys: String, CodingKey {
            case muted
            case newFeedback = "new_feedback"
            case newComments = "new_comments"
            case votes
            case statusChanges = "status_changes"
        }
    }

    struct EmailSettings: Content {
        let muted: Bool
        let newFeedback: Bool?
        let newComments: Bool?

        enum CodingKeys: String, CodingKey {
            case muted
            case newFeedback = "new_feedback"
            case newComments = "new_comments"
        }
    }

    struct EffectivePreferences: Content {
        struct PushEffective: Content {
            let newFeedback: Bool
            let newComments: Bool
            let votes: Bool
            let statusChanges: Bool

            enum CodingKeys: String, CodingKey {
                case newFeedback = "new_feedback"
                case newComments = "new_comments"
                case votes
                case statusChanges = "status_changes"
            }
        }
        let push: PushEffective
    }

    let push: PushSettings
    let email: EmailSettings
    let effectivePreferences: EffectivePreferences

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case push, email
        case effectivePreferences = "effective_preferences"
    }
}

// MARK: - Request DTOs

struct UpdateProjectNotificationPreferencesDTO: Content {
    struct PushPreferences: Content {
        let muted: Bool?
        let newFeedback: Bool?
        let newComments: Bool?
        let votes: Bool?
        let statusChanges: Bool?

        enum CodingKeys: String, CodingKey {
            case muted
            case newFeedback = "new_feedback"
            case newComments = "new_comments"
            case votes
            case statusChanges = "status_changes"
        }
    }

    struct EmailPreferences: Content {
        let muted: Bool?
        let newFeedback: Bool?
        let newComments: Bool?

        enum CodingKeys: String, CodingKey {
            case muted
            case newFeedback = "new_feedback"
            case newComments = "new_comments"
        }
    }

    let push: PushPreferences?
    let email: EmailPreferences?
}
