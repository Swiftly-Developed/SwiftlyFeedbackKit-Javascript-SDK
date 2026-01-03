import Fluent
import Vapor

final class Project: Model, Content, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "api_key")
    var apiKey: String

    @Field(key: "description")
    var description: String?

    @Parent(key: "owner_id")
    var owner: User

    @Field(key: "is_archived")
    var isArchived: Bool

    @OptionalField(key: "archived_at")
    var archivedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$project)
    var feedbacks: [Feedback]

    @Siblings(through: ProjectMember.self, from: \.$project, to: \.$user)
    var members: [User]

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        apiKey: String,
        description: String? = nil,
        ownerId: UUID,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.description = description
        self.$owner.id = ownerId
        self.isArchived = isArchived
    }
}

extension Project {
    /// Check if a user has access to this project (owner or member)
    func userHasAccess(_ userId: UUID, on db: Database) async throws -> Bool {
        // Owner always has access
        if $owner.id == userId {
            return true
        }

        // Check if user is a member
        let membership = try await ProjectMember.query(on: db)
            .filter(\.$project.$id == requireID())
            .filter(\.$user.$id == userId)
            .first()

        return membership != nil
    }

    /// Check if a user is the owner of this project
    func userIsOwner(_ userId: UUID) -> Bool {
        $owner.id == userId
    }
}
