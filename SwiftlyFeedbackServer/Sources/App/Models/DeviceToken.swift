import Fluent
import Vapor

final class DeviceToken: Model, Content, @unchecked Sendable {
    static let schema = "device_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token")
    var token: String

    @Field(key: "platform")
    var platform: String

    @OptionalField(key: "app_version")
    var appVersion: String?

    @OptionalField(key: "os_version")
    var osVersion: String?

    @Field(key: "is_active")
    var isActive: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "last_used_at")
    var lastUsedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        token: String,
        platform: String,
        appVersion: String? = nil,
        osVersion: String? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.token = token
        self.platform = platform
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.isActive = true
    }
}

// MARK: - Response DTO

extension DeviceToken {
    struct Public: Content {
        let id: UUID
        let platform: String
        let appVersion: String?
        let isActive: Bool
        let lastUsedAt: Date?
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, platform
            case appVersion = "app_version"
            case isActive = "is_active"
            case lastUsedAt = "last_used_at"
            case createdAt = "created_at"
        }
    }

    func asPublic() throws -> Public {
        Public(
            id: try requireID(),
            platform: platform,
            appVersion: appVersion,
            isActive: isActive,
            lastUsedAt: lastUsedAt,
            createdAt: createdAt
        )
    }
}
