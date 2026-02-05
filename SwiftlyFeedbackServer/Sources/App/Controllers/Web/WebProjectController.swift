import Vapor
import Fluent
import Leaf

struct WebProjectController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let projects = routes.grouped("projects")

        projects.get(use: index)
        projects.post(use: create)
        projects.get(":projectId", use: show)
        projects.get(":projectId", "settings", use: settings)
        projects.post(":projectId", "settings", use: updateSettings)
        projects.post(":projectId", "delete", use: delete)
        projects.post(":projectId", "archive", use: archive)
        projects.post(":projectId", "unarchive", use: unarchive)
        projects.post(":projectId", "regenerate-key", use: regenerateKey)
        projects.post(":projectId", "transfer", use: transfer)

        // Members
        projects.get(":projectId", "members", use: members)
        projects.post(":projectId", "members", use: addMember)
        projects.post(":projectId", "members", ":memberId", "update", use: updateMember)
        projects.post(":projectId", "members", ":memberId", "remove", use: removeMember)

        // Email Settings
        projects.get(":projectId", "email-settings", use: getEmailSettings)
        projects.post(":projectId", "email-settings", use: updateEmailSettings)

        // Status Settings
        projects.get(":projectId", "status-settings", use: getStatusSettings)
        projects.post(":projectId", "status-settings", use: updateStatusSettings)
    }

    // MARK: - Project List

    @Sendable
    func index(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        let showArchived = req.query[Bool.self, at: "archived"] ?? false

        // Get owned projects
        var ownedQuery = Project.query(on: req.db)
            .filter(\.$owner.$id == userId)

        if !showArchived {
            ownedQuery = ownedQuery.filter(\.$isArchived == false)
        }

        let ownedProjects = try await ownedQuery.all()

        // Get member projects
        var memberQuery = Project.query(on: req.db)
            .join(ProjectMember.self, on: \Project.$id == \ProjectMember.$project.$id)
            .filter(ProjectMember.self, \.$user.$id == userId)

        if !showArchived {
            memberQuery = memberQuery.filter(\.$isArchived == false)
        }

        let memberProjects = try await memberQuery.all()

        let allProjects = ownedProjects + memberProjects

        let projectItems = try allProjects.map { project in
            ProjectListItem(
                id: try project.requireID(),
                name: project.name,
                description: project.description,
                colorIndex: project.colorIndex,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass,
                isArchived: project.isArchived,
                isOwner: project.$owner.id == userId
            )
        }

        return try await req.view.render("projects/index", ProjectListContext(
            title: "Projects",
            pageTitle: "Projects",
            currentPage: "projects",
            user: UserContext(from: user),
            projects: projectItems,
            showArchived: showArchived,
            canCreateProject: canUserCreateProject(user: user, currentCount: ownedProjects.count)
        ))
    }

    // MARK: - Create Project

    @Sendable
    func create(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(CreateProjectForm.self)

        // Check project limit
        let ownedCount = try await Project.query(on: req.db)
            .filter(\.$owner.$id == user.requireID())
            .count()

        if let maxProjects = user.subscriptionTier.maxProjects, ownedCount >= maxProjects {
            // Redirect back with error
            return req.redirect(to: "/admin/projects?error=project_limit")
        }

        // Create project
        let project = Project(
            name: form.name.trimmingCharacters(in: .whitespaces),
            apiKey: UUID().uuidString,
            description: form.description?.trimmingCharacters(in: .whitespaces),
            ownerId: try user.requireID(),
            colorIndex: form.colorIndex ?? 0
        )

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())")
    }

    // MARK: - Project Detail

    @Sendable
    func show(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user)
        let role = try await getUserRole(req: req, user: user, project: project)

        // Get feedback stats
        let feedbackCount = try await Feedback.query(on: req.db)
            .filter(\.$project.$id == project.requireID())
            .filter(\.$mergedIntoId == nil)
            .count()

        let feedbackByStatus = try await getFeedbackByStatus(req: req, projectId: project.requireID())

        return try await req.view.render("projects/show", ProjectDetailContext(
            title: project.name,
            pageTitle: project.name,
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            feedbackCount: feedbackCount,
            feedbackByStatus: feedbackByStatus
        ))
    }

    // MARK: - Project Settings

    @Sendable
    func settings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/settings", ProjectSettingsContext(
            title: "Settings - \(project.name)",
            pageTitle: "Project Settings",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            colors: projectColors,
            error: req.query[String.self, at: "error"],
            success: req.query[String.self, at: "success"]
        ))
    }

    @Sendable
    func updateSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(UpdateProjectForm.self)

        req.logger.info("📝 Project Settings Update:")
        req.logger.info("   - Name: \(form.name)")
        req.logger.info("   - Description: \(form.description ?? "nil")")
        req.logger.info("   - ColorIndex from form: \(form.colorIndex.map { String($0) } ?? "nil")")
        req.logger.info("   - Current project colorIndex: \(project.colorIndex)")

        project.name = form.name.trimmingCharacters(in: .whitespaces)
        project.description = form.description?.trimmingCharacters(in: .whitespaces)
        project.colorIndex = form.colorIndex ?? project.colorIndex

        req.logger.info("   - New project colorIndex: \(project.colorIndex)")

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/settings?success=updated")
    }

    // MARK: - Delete Project

    @Sendable
    func delete(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireOwner: true)

        try await project.delete(on: req.db)

        return req.redirect(to: "/admin/projects")
    }

    // MARK: - Archive/Unarchive

    @Sendable
    func archive(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireOwner: true)

        project.isArchived = true
        project.archivedAt = Date()
        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())")
    }

    @Sendable
    func unarchive(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireOwner: true)

        project.isArchived = false
        project.archivedAt = nil
        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())")
    }

    // MARK: - Regenerate API Key

    @Sendable
    func regenerateKey(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireOwner: true)

        project.apiKey = UUID().uuidString
        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/settings?success=key_regenerated")
    }

    // MARK: - Transfer Ownership

    @Sendable
    func transfer(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireOwner: true)
        let form = try req.content.decode(TransferOwnershipForm.self)

        let currentOwnerId = try user.requireID()
        let projectId = try project.requireID()

        // Find the new owner by email
        guard let newOwner = try await User.query(on: req.db)
            .filter(\.$email == form.email.lowercased())
            .first() else {
            return req.redirect(to: "/admin/projects/\(projectId)/settings?error=user_not_found")
        }

        let newOwnerId = try newOwner.requireID()

        // Cannot transfer to self
        guard newOwnerId != currentOwnerId else {
            return req.redirect(to: "/admin/projects/\(projectId)/settings?error=cannot_transfer_to_self")
        }

        // Check tier requirements if project has members
        let memberCount = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .count()

        if memberCount > 0 && !newOwner.subscriptionTier.meetsRequirement(.team) {
            return req.redirect(to: "/admin/projects/\(projectId)/settings?error=new_owner_needs_team")
        }

        // Execute transfer in transaction
        try await req.db.transaction { database in
            // Check if new owner is currently a member
            if let existingMembership = try await ProjectMember.query(on: database)
                .filter(\.$project.$id == projectId)
                .filter(\.$user.$id == newOwnerId)
                .first() {
                // Remove their membership (they're becoming owner)
                try await existingMembership.delete(on: database)
            }

            // Update project owner
            project.$owner.id = newOwnerId
            try await project.save(on: database)

            // Add previous owner as Admin member
            let adminMember = ProjectMember(
                projectId: projectId,
                userId: currentOwnerId,
                role: .admin
            )
            try await adminMember.save(on: database)
        }

        // Send notification email (outside transaction)
        Task {
            do {
                try await req.emailService.sendOwnershipTransferNotification(
                    to: newOwner.email,
                    newOwnerName: newOwner.name,
                    projectName: project.name,
                    previousOwnerName: user.name
                )
            } catch {
                req.logger.error("Failed to send ownership transfer email: \(error)")
            }
        }

        // Redirect to projects list since user is no longer owner
        return req.redirect(to: "/admin/projects")
    }

    // MARK: - Members

    @Sendable
    func members(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        let members = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == project.requireID())
            .with(\.$user)
            .all()

        let memberItems = try members.map { member in
            MemberItem(
                id: try member.requireID(),
                name: member.user.name,
                email: member.user.email,
                role: member.role.rawValue,
                roleDisplay: member.role.displayName,
                createdAt: formatDate(member.createdAt)
            )
        }

        // Get owner info
        let owner = try await User.find(project.$owner.id, on: req.db)

        return try await req.view.render("projects/members", ProjectMembersContext(
            title: "Members - \(project.name)",
            pageTitle: "Team Members",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            members: memberItems,
            owner: owner.map { OwnerItem(name: $0.name, email: $0.email) },
            canManageMembers: role == .owner || role == .admin,
            isTeamTier: user.subscriptionTier == .team,
            error: req.query[String.self, at: "error"],
            success: req.query[String.self, at: "success"]
        ))
    }

    @Sendable
    func addMember(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(AddMemberForm.self)

        // Check Team tier
        guard user.subscriptionTier == .team else {
            return req.redirect(to: "/admin/projects/\(try project.requireID())/members?error=team_required")
        }

        // Find user by email
        guard let memberUser = try await User.query(on: req.db)
            .filter(\.$email == form.email.lowercased())
            .first() else {
            return req.redirect(to: "/admin/projects/\(try project.requireID())/members?error=user_not_found")
        }

        // Check if already a member
        let existingMember = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == project.requireID())
            .filter(\.$user.$id == memberUser.requireID())
            .first()

        if existingMember != nil {
            return req.redirect(to: "/admin/projects/\(try project.requireID())/members?error=already_member")
        }

        // Check if they're the owner
        if project.$owner.id == memberUser.id {
            return req.redirect(to: "/admin/projects/\(try project.requireID())/members?error=is_owner")
        }

        // Add member
        let role = ProjectRole(rawValue: form.role) ?? .member
        let member = ProjectMember(
            projectId: try project.requireID(),
            userId: try memberUser.requireID(),
            role: role
        )
        try await member.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/members?success=member_added")
    }

    @Sendable
    func updateMember(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let memberId = req.parameters.get("memberId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let member = try await ProjectMember.query(on: req.db)
            .filter(\.$id == memberId)
            .filter(\.$project.$id == project.requireID())
            .first() else {
            throw Abort(.notFound)
        }

        let form = try req.content.decode(UpdateMemberForm.self)
        if let newRole = ProjectRole(rawValue: form.role) {
            member.role = newRole
            try await member.save(on: req.db)
        }

        return req.redirect(to: "/admin/projects/\(try project.requireID())/members?success=member_updated")
    }

    @Sendable
    func removeMember(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let memberId = req.parameters.get("memberId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        try await ProjectMember.query(on: req.db)
            .filter(\.$id == memberId)
            .filter(\.$project.$id == project.requireID())
            .delete()

        return req.redirect(to: "/admin/projects/\(try project.requireID())/members?success=member_removed")
    }

    // MARK: - Helpers

    private func getProjectWithAccess(req: Request, user: User, requireOwner: Bool = false, requireAdmin: Bool = false) async throws -> Project {
        guard let projectId = req.parameters.get("projectId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let project = try await Project.find(projectId, on: req.db) else {
            throw Abort(.notFound)
        }

        let userId = try user.requireID()
        let isOwner = project.$owner.id == userId

        if requireOwner && !isOwner {
            throw Abort(.forbidden)
        }

        if requireAdmin {
            if !isOwner {
                // Check if user is admin member
                let member = try await ProjectMember.query(on: req.db)
                    .filter(\.$project.$id == projectId)
                    .filter(\.$user.$id == userId)
                    .first()

                guard let member = member, member.role == .admin else {
                    throw Abort(.forbidden)
                }
            }
        } else {
            // Just need any access
            if !isOwner {
                let member = try await ProjectMember.query(on: req.db)
                    .filter(\.$project.$id == projectId)
                    .filter(\.$user.$id == userId)
                    .first()

                if member == nil {
                    throw Abort(.forbidden)
                }
            }
        }

        return project
    }

    private func getUserRole(req: Request, user: User, project: Project) async throws -> WebProjectRole {
        let userId = try user.requireID()

        if project.$owner.id == userId {
            return .owner
        }

        if let member = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == project.requireID())
            .filter(\.$user.$id == userId)
            .first() {
            switch member.role {
            case .admin: return .admin
            case .member: return .member
            case .viewer: return .viewer
            }
        }

        return .viewer
    }

    private func canUserCreateProject(user: User, currentCount: Int) -> Bool {
        if let maxProjects = user.subscriptionTier.maxProjects {
            return currentCount < maxProjects
        }
        return true
    }

    private func getFeedbackByStatus(req: Request, projectId: UUID) async throws -> [StatusCount] {
        let feedbacks = try await Feedback.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .filter(\.$mergedIntoId == nil)
            .all()

        var counts: [FeedbackStatus: Int] = [:]
        for feedback in feedbacks {
            counts[feedback.status, default: 0] += 1
        }

        return FeedbackStatus.allCases.map { status in
            StatusCount(
                status: status.rawValue,
                name: status.displayName,
                count: counts[status] ?? 0,
                colorClass: status.colorClass
            )
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Email Settings

    @Sendable
    func getEmailSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user)

        let response = EmailSettingsResponse(emailNotifyStatuses: project.emailNotifyStatuses)
        return try await response.encodeResponse(for: req)
    }

    @Sendable
    func updateEmailSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        let form = try req.content.decode(UpdateEmailSettingsForm.self)

        // Validate statuses
        let validStatuses = FeedbackStatus.allCases.map { $0.rawValue }
        for status in form.statuses {
            guard validStatuses.contains(status) else {
                throw Abort(.badRequest, reason: "Invalid status: \(status)")
            }
        }

        project.emailNotifyStatuses = form.statuses
        try await project.save(on: req.db)

        return Response(status: .ok)
    }

    // MARK: - Status Settings

    @Sendable
    func getStatusSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user)

        let response = StatusSettingsResponse(allowedStatuses: project.allowedStatuses)
        return try await response.encodeResponse(for: req)
    }

    @Sendable
    func updateStatusSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        let form = try req.content.decode(UpdateStatusSettingsForm.self)

        // Validate statuses
        let validStatuses = FeedbackStatus.allCases.map { $0.rawValue }
        for status in form.statuses {
            guard validStatuses.contains(status) else {
                throw Abort(.badRequest, reason: "Invalid status: \(status)")
            }
        }

        // Ensure pending is always included
        var statuses = form.statuses
        if !statuses.contains("pending") {
            statuses.insert("pending", at: 0)
        }

        project.allowedStatuses = statuses
        try await project.save(on: req.db)

        return Response(status: .ok)
    }
}

// MARK: - Email Settings DTOs

struct EmailSettingsResponse: Content {
    let emailNotifyStatuses: [String]
}

struct UpdateEmailSettingsForm: Content {
    let statuses: [String]
}

// MARK: - Status Settings DTOs

struct StatusSettingsResponse: Content {
    let allowedStatuses: [String]
}

struct UpdateStatusSettingsForm: Content {
    let statuses: [String]
}

// MARK: - Form DTOs

struct CreateProjectForm: Content {
    let name: String
    let description: String?
    let colorIndex: Int?
}

struct UpdateProjectForm: Content {
    let name: String
    let description: String?
    let colorIndex: Int?
}

struct AddMemberForm: Content {
    let email: String
    let role: String
}

struct UpdateMemberForm: Content {
    let role: String
}

struct TransferOwnershipForm: Content {
    let email: String
}

// MARK: - View Contexts

enum WebProjectRole: String {
    case owner, admin, member, viewer
}

struct ProjectListContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let projects: [ProjectListItem]
    let showArchived: Bool
    let canCreateProject: Bool
}

struct ProjectListItem: Encodable {
    let id: UUID
    let name: String
    let description: String?
    let colorIndex: Int
    let colorClass: String
    let isArchived: Bool
    let isOwner: Bool
}

struct ProjectDetailContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let feedbackCount: Int
    let feedbackByStatus: [StatusCount]
}

struct ProjectSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let colors: [ProjectColor]
    let error: String?
    let success: String?
}

struct ProjectMembersContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let members: [MemberItem]
    let owner: OwnerItem?
    let canManageMembers: Bool
    let isTeamTier: Bool
    let error: String?
    let success: String?
}

struct ProjectContext: Encodable {
    let id: UUID
    let name: String
    let description: String?
    let apiKey: String
    let colorIndex: Int
    let colorClass: String
    let isArchived: Bool
    let role: String
    let isOwner: Bool
    let isAdmin: Bool

    init(from project: Project, role: WebProjectRole) {
        self.id = project.id ?? UUID()
        self.name = project.name
        self.description = project.description
        self.apiKey = project.apiKey
        self.colorIndex = project.colorIndex
        self.colorClass = projectColors[project.colorIndex % projectColors.count].bgClass
        self.isArchived = project.isArchived
        self.role = role.rawValue
        self.isOwner = role == .owner
        self.isAdmin = role == .owner || role == .admin
    }
}

struct MemberItem: Encodable {
    let id: UUID
    let name: String
    let email: String
    let role: String
    let roleDisplay: String
    let createdAt: String
    let initials: String

    init(id: UUID, name: String, email: String, role: String, roleDisplay: String, createdAt: String) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.roleDisplay = roleDisplay
        self.createdAt = createdAt
        self.initials = String(name.prefix(1)).uppercased()
    }
}

struct OwnerItem: Encodable {
    let name: String
    let email: String
    let initials: String

    init(name: String, email: String) {
        self.name = name
        self.email = email
        self.initials = String(name.prefix(1)).uppercased()
    }
}

struct StatusCount: Encodable {
    let status: String
    let name: String
    let count: Int
    let colorClass: String
}

struct ProjectColor: Encodable {
    let index: Int
    let name: String
    let bgClass: String
    let textClass: String
}

let projectColors: [ProjectColor] = [
    ProjectColor(index: 0, name: "Blue", bgClass: "bg-blue-500", textClass: "text-blue-500"),
    ProjectColor(index: 1, name: "Green", bgClass: "bg-green-500", textClass: "text-green-500"),
    ProjectColor(index: 2, name: "Purple", bgClass: "bg-purple-500", textClass: "text-purple-500"),
    ProjectColor(index: 3, name: "Orange", bgClass: "bg-orange-500", textClass: "text-orange-500"),
    ProjectColor(index: 4, name: "Pink", bgClass: "bg-pink-500", textClass: "text-pink-500"),
    ProjectColor(index: 5, name: "Cyan", bgClass: "bg-cyan-500", textClass: "text-cyan-500"),
    ProjectColor(index: 6, name: "Yellow", bgClass: "bg-yellow-500", textClass: "text-yellow-500"),
    ProjectColor(index: 7, name: "Red", bgClass: "bg-red-500", textClass: "text-red-500"),
]

extension ProjectRole {
    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .member: return "Member"
        case .viewer: return "Viewer"
        }
    }
}
