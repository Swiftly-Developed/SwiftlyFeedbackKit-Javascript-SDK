import Fluent
import Vapor

/// Represents a user's membership/access to a project
final class ProjectMember: Model, Content, @unchecked Sendable {
    static let schema = "project_members"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "user_id")
    var user: User

    @Enum(key: "role")
    var role: ProjectRole

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, projectId: UUID, userId: UUID, role: ProjectRole = .member) {
        self.id = id
        self.$project.id = projectId
        self.$user.id = userId
        self.role = role
    }
}

enum ProjectRole: String, Codable, CaseIterable {
    case admin    // Can manage project settings and members
    case member   // Can view feedback and respond
    case viewer   // Can only view feedback
}

extension ProjectMember {
    struct Public: Content {
        let id: UUID
        let userId: UUID
        let userEmail: String
        let userName: String
        let role: ProjectRole
        let createdAt: Date?

        init(member: ProjectMember, user: User) throws {
            self.id = try member.requireID()
            self.userId = try user.requireID()
            self.userEmail = user.email
            self.userName = user.name
            self.role = member.role
            self.createdAt = member.createdAt
        }
    }
}
