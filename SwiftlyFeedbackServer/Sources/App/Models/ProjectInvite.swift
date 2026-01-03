import Fluent
import Vapor

final class ProjectInvite: Model, Content, @unchecked Sendable {
    static let schema = "project_invites"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "invited_by_id")
    var invitedBy: User

    @Field(key: "email")
    var email: String

    @Enum(key: "role")
    var role: ProjectRole

    @Field(key: "token")
    var token: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "accepted_at")
    var acceptedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        invitedById: UUID,
        email: String,
        role: ProjectRole,
        expiresInDays: Int = 7
    ) {
        self.id = id
        self.$project.id = projectId
        self.$invitedBy.id = invitedById
        self.email = email.lowercased()
        self.role = role
        self.token = Self.generateInviteCode()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresInDays * 24 * 60 * 60))
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isAccepted: Bool {
        acceptedAt != nil
    }

    /// Generates a user-friendly 8-character invite code (uppercase letters and numbers, no ambiguous chars)
    static func generateInviteCode() -> String {
        // Exclude ambiguous characters: 0, O, I, 1, L
        let chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}

extension ProjectInvite {
    struct Public: Content {
        let id: UUID
        let email: String
        let role: ProjectRole
        let projectName: String
        let invitedByName: String
        let expiresAt: Date
        let createdAt: Date?

        init(invite: ProjectInvite, project: Project, invitedBy: User) throws {
            self.id = try invite.requireID()
            self.email = invite.email
            self.role = invite.role
            self.projectName = project.name
            self.invitedByName = invitedBy.name
            self.expiresAt = invite.expiresAt
            self.createdAt = invite.createdAt
        }
    }
}
