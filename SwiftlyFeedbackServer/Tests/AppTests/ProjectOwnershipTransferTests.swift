import XCTVapor
import Fluent
@testable import SwiftlyFeedbackServer

/// Tests for project ownership transfer functionality
/// Note: These tests require a PostgreSQL database to be running.
/// Run with: cd SwiftlyFeedbackServer && swift test --filter ProjectOwnershipTransferTests
final class ProjectOwnershipTransferTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    // MARK: - Helper Methods

    private func createUser(
        name: String,
        email: String,
        subscriptionTier: SubscriptionTier = .free
    ) async throws -> User {
        let user = User(
            name: name,
            email: email,
            passwordHash: try Bcrypt.hash("password123"),
            subscriptionTier: subscriptionTier
        )
        try await user.save(on: app.db)
        return user
    }

    private func createProject(owner: User, name: String = "Test Project") async throws -> Project {
        let project = Project(
            name: name,
            description: "Test description",
            ownerId: try owner.requireID()
        )
        try await project.save(on: app.db)
        return project
    }

    private func addMember(project: Project, user: User, role: ProjectRole) async throws -> ProjectMember {
        let member = ProjectMember(
            projectId: try project.requireID(),
            userId: try user.requireID(),
            role: role
        )
        try await member.save(on: app.db)
        return member
    }

    private func createToken(for user: User) async throws -> UserToken {
        let token = try UserToken.generate(for: user)
        try await token.save(on: app.db)
        return token
    }

    // MARK: - Success Cases

    func testTransferToExistingMember() async throws {
        // Setup: Owner with Team tier, project with member
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)
        _ = try await addMember(project: project, user: newOwner, role: .admin)

        let token = try await createToken(for: owner)

        // Action: Transfer to member
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: newOwner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)

                // Verify response
                let response = try? res.content.decode(TransferOwnershipResponseDTO.self)
                XCTAssertNotNil(response)
                XCTAssertEqual(response?.newOwner.id, newOwner.id)
                XCTAssertEqual(response?.previousOwner.id, owner.id)
            })

        // Verify: New owner is now project owner
        let updatedProject = try await Project.find(project.id, on: app.db)
        XCTAssertEqual(updatedProject?.$owner.id, newOwner.id)

        // Verify: Previous owner is now an Admin member
        let ownerMembership = try await ProjectMember.query(on: app.db)
            .filter(\.$project.$id == project.id!)
            .filter(\.$user.$id == owner.id!)
            .first()
        XCTAssertNotNil(ownerMembership)
        XCTAssertEqual(ownerMembership?.role, .admin)

        // Verify: New owner's membership was removed (they're now owner)
        let newOwnerMembership = try await ProjectMember.query(on: app.db)
            .filter(\.$project.$id == project.id!)
            .filter(\.$user.$id == newOwner.id!)
            .first()
        XCTAssertNil(newOwnerMembership)
    }

    func testTransferToNonMemberUser() async throws {
        // Setup: Owner, project, separate user not in project
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Transfer to non-member
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: newOwner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
            })

        // Verify: New owner is now project owner
        let updatedProject = try await Project.find(project.id, on: app.db)
        XCTAssertEqual(updatedProject?.$owner.id, newOwner.id)

        // Verify: Previous owner is now Admin member
        let ownerMembership = try await ProjectMember.query(on: app.db)
            .filter(\.$project.$id == project.id!)
            .filter(\.$user.$id == owner.id!)
            .first()
        XCTAssertNotNil(ownerMembership)
        XCTAssertEqual(ownerMembership?.role, .admin)
    }

    func testTransferByEmail() async throws {
        // Setup: Owner, project, user with known email
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Transfer by email
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: nil, newOwnerEmail: "newowner@test.com"))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)

                let response = try? res.content.decode(TransferOwnershipResponseDTO.self)
                XCTAssertEqual(response?.newOwner.email, "newowner@test.com")
            })
    }

    func testTransferWithoutMembers_NoTierRequired() async throws {
        // Setup: Project without members, new owner with Free tier
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .free)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Transfer should succeed without Team tier since no members
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: newOwner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
            })
    }

    // MARK: - Error Cases

    func testCannotTransferToSelf() async throws {
        // Setup: Owner and project
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Attempt transfer to self
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: owner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .badRequest)
            })
    }

    func testCannotTransferToNonExistentUser() async throws {
        // Setup: Owner and project
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Transfer to random UUID
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: UUID(), newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .notFound)
            })
    }

    func testCannotTransferToNonExistentEmail() async throws {
        // Setup: Owner and project
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Transfer to non-existent email
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: nil, newOwnerEmail: "nobody@test.com"))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .notFound)
            })
    }

    func testNonOwnerCannotTransfer() async throws {
        // Setup: Owner, project, admin member
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let admin = try await createUser(name: "Admin", email: "admin@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)
        _ = try await addMember(project: project, user: admin, role: .admin)

        let adminToken = try await createToken(for: admin)

        // Action: Admin attempts transfer
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(adminToken.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: newOwner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .forbidden)
            })
    }

    func testTierRequirementWithMembers() async throws {
        // Setup: Project with members, new owner with Free tier
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let member = try await createUser(name: "Member", email: "member@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .free)
        let project = try await createProject(owner: owner)
        _ = try await addMember(project: project, user: member, role: .member)

        let token = try await createToken(for: owner)

        // Action: Attempt transfer to Free tier user with members
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: newOwner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .paymentRequired)
            })
    }

    func testUnauthorizedWithoutToken() async throws {
        // Setup: Owner and project
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let newOwner = try await createUser(name: "New Owner", email: "newowner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        // Action: Attempt transfer without auth token
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            beforeRequest: { req in
                try req.content.encode(TransferOwnershipDTO(newOwnerId: newOwner.id, newOwnerEmail: nil))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .unauthorized)
            })
    }

    func testMissingBothIdAndEmail() async throws {
        // Setup: Owner and project
        let owner = try await createUser(name: "Owner", email: "owner@test.com", subscriptionTier: .team)
        let project = try await createProject(owner: owner)

        let token = try await createToken(for: owner)

        // Action: Attempt transfer with neither ID nor email
        try await app.test(.POST, "api/v1/projects/\(project.id!)/transfer-ownership",
            headers: ["Authorization": "Bearer \(token.value)"],
            beforeRequest: { req in
                try req.content.encode(["newOwnerId": nil as UUID?, "newOwnerEmail": nil as String?] as [String: Any?])
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .badRequest)
            })
    }
}
