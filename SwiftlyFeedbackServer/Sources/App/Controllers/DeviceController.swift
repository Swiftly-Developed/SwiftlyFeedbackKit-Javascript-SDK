import Vapor
import Fluent

struct DeviceController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let devices = routes.grouped("devices")

        // All device routes require authentication
        let protected = devices.grouped(UserToken.authenticator(), User.guardMiddleware())
        protected.post("register", use: register)
        protected.get(use: index)
        protected.delete(":deviceId", use: delete)
        protected.delete("token", ":token", use: deleteByToken)
    }

    /// Register a new device token
    /// POST /devices/register
    @Sendable
    func register(req: Request) async throws -> DeviceToken.Public {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()
        let dto = try req.content.decode(RegisterDeviceDTO.self)

        // Validate platform
        guard ["iOS", "macOS", "visionOS"].contains(dto.platform) else {
            throw Abort(.badRequest, reason: "Invalid platform. Must be iOS, macOS, or visionOS")
        }

        // Check if token already exists
        if let existingDevice = try await DeviceToken.query(on: req.db)
            .filter(\.$token == dto.token)
            .first() {

            // If token belongs to different user, reassign it
            if existingDevice.$user.id != userId {
                existingDevice.$user.id = userId
            }

            // Update device info
            existingDevice.platform = dto.platform
            existingDevice.appVersion = dto.appVersion
            existingDevice.osVersion = dto.osVersion
            existingDevice.isActive = true
            existingDevice.lastUsedAt = Date()

            try await existingDevice.save(on: req.db)
            return try existingDevice.asPublic()
        }

        // Create new device token
        let device = DeviceToken(
            userID: userId,
            token: dto.token,
            platform: dto.platform,
            appVersion: dto.appVersion,
            osVersion: dto.osVersion
        )
        device.lastUsedAt = Date()

        try await device.save(on: req.db)

        req.logger.info("Registered device token for user \(userId)")

        return try device.asPublic()
    }

    /// List all devices for the current user
    /// GET /devices
    @Sendable
    func index(req: Request) async throws -> DeviceListResponseDTO {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        let devices = try await DeviceToken.query(on: req.db)
            .filter(\.$user.$id == userId)
            .sort(\.$createdAt, .descending)
            .all()

        return DeviceListResponseDTO(
            devices: try devices.map { try $0.asPublic() }
        )
    }

    /// Delete a device by ID
    /// DELETE /devices/:deviceId
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let deviceId = req.parameters.get("deviceId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid device ID")
        }

        guard let device = try await DeviceToken.query(on: req.db)
            .filter(\.$id == deviceId)
            .filter(\.$user.$id == userId)
            .first() else {
            throw Abort(.notFound, reason: "Device not found")
        }

        try await device.delete(on: req.db)

        req.logger.info("Deleted device \(deviceId) for user \(userId)")

        return .noContent
    }

    /// Delete a device by token value
    /// DELETE /devices/token/:token
    @Sendable
    func deleteByToken(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Token required")
        }

        guard let device = try await DeviceToken.query(on: req.db)
            .filter(\.$token == token)
            .filter(\.$user.$id == userId)
            .first() else {
            throw Abort(.notFound, reason: "Device not found")
        }

        try await device.delete(on: req.db)

        req.logger.info("Deleted device by token for user \(userId)")

        return .noContent
    }
}

// MARK: - DTOs

struct RegisterDeviceDTO: Content {
    let token: String
    let platform: String
    let appVersion: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case token, platform
        case appVersion = "app_version"
        case osVersion = "os_version"
    }
}

struct DeviceListResponseDTO: Content {
    let devices: [DeviceToken.Public]
}
