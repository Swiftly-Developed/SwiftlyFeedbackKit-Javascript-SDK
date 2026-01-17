import Vapor
import Fluent
import APNS
import APNSCore

// MARK: - Push Notification Service

struct PushNotificationService: Sendable {
    let app: Application
    let logger: Logger

    init(app: Application) {
        self.app = app
        self.logger = app.logger
    }

    // MARK: - Public Methods

    /// Send push notification for new feedback
    func sendNewFeedbackNotification(
        feedback: Feedback,
        project: Project,
        on db: Database
    ) async {
        do {
            let recipients = try await resolveRecipients(
                for: project,
                notificationType: .newFeedback,
                excludeUserIds: [],
                on: db
            )

            for recipient in recipients {
                await sendNotification(
                    to: recipient,
                    title: "New Feedback",
                    body: feedback.title,
                    payload: PushPayload(
                        type: .newFeedback,
                        feedbackId: feedback.id?.uuidString,
                        projectId: project.id?.uuidString
                    ),
                    on: db
                )
            }
        } catch {
            logger.error("Failed to send new feedback push notification: \(error)")
        }
    }

    /// Send push notification for new comment
    func sendNewCommentNotification(
        comment: Comment,
        feedback: Feedback,
        project: Project,
        authorId: UUID,
        on db: Database
    ) async {
        do {
            var recipients = try await resolveRecipients(
                for: project,
                notificationType: .newComment,
                excludeUserIds: [authorId],
                on: db
            )

            // Also notify feedback submitter if they're a registered user
            if let submitterEmail = feedback.userEmail,
               let submitter = try await User.query(on: db)
                .filter(\.$email == submitterEmail)
                .first(),
               submitter.id != authorId {

                let shouldNotify = try await shouldSendNotification(
                    to: submitter,
                    for: project,
                    type: .newComment,
                    on: db
                )

                if shouldNotify && !recipients.contains(where: { $0.id == submitter.id }) {
                    recipients.append(submitter)
                }
            }

            for recipient in recipients {
                await sendNotification(
                    to: recipient,
                    title: "New Comment",
                    body: "Comment on: \(feedback.title)",
                    payload: PushPayload(
                        type: .newComment,
                        feedbackId: feedback.id?.uuidString,
                        commentId: comment.id?.uuidString,
                        projectId: project.id?.uuidString
                    ),
                    on: db
                )
            }
        } catch {
            logger.error("Failed to send new comment push notification: \(error)")
        }
    }

    /// Send push notification for new vote
    func sendVoteNotification(
        feedback: Feedback,
        voteCount: Int,
        on db: Database
    ) async {
        do {
            // Notify feedback submitter
            guard let submitterEmail = feedback.userEmail,
                  let submitter = try await User.query(on: db)
                    .filter(\.$email == submitterEmail)
                    .first() else {
                return
            }

            let project = try await feedback.$project.get(on: db)

            let shouldNotify = try await shouldSendNotification(
                to: submitter,
                for: project,
                type: .newVote,
                on: db
            )

            guard shouldNotify else { return }

            await sendNotification(
                to: submitter,
                title: "New Vote",
                body: "\(feedback.title) now has \(voteCount) vote\(voteCount == 1 ? "" : "s")",
                payload: PushPayload(
                    type: .newVote,
                    feedbackId: feedback.id?.uuidString,
                    projectId: project.id?.uuidString,
                    voteCount: voteCount
                ),
                on: db
            )
        } catch {
            logger.error("Failed to send vote push notification: \(error)")
        }
    }

    /// Send push notification for status change
    func sendStatusChangeNotification(
        feedback: Feedback,
        oldStatus: FeedbackStatus,
        newStatus: FeedbackStatus,
        project: Project,
        on db: Database
    ) async {
        do {
            var notifiedUserIds: Set<UUID> = []

            // Notify feedback submitter
            if let submitterEmail = feedback.userEmail,
               let submitter = try await User.query(on: db)
                .filter(\.$email == submitterEmail)
                .first() {

                let shouldNotify = try await shouldSendNotification(
                    to: submitter,
                    for: project,
                    type: .statusChange,
                    on: db
                )

                if shouldNotify {
                    await sendNotification(
                        to: submitter,
                        title: "Status Updated",
                        body: "\(feedback.title) is now \(newStatus.rawValue.replacingOccurrences(of: "_", with: " "))",
                        payload: PushPayload(
                            type: .statusChange,
                            feedbackId: feedback.id?.uuidString,
                            projectId: project.id?.uuidString,
                            oldStatus: oldStatus.rawValue,
                            newStatus: newStatus.rawValue
                        ),
                        on: db
                    )
                    notifiedUserIds.insert(submitter.id!)
                }
            }

            // Notify voters who provided emails and opted in
            let votes = try await Vote.query(on: db)
                .filter(\.$feedback.$id == feedback.id!)
                .all()

            for vote in votes {
                guard let voterEmail = vote.email,
                      vote.notifyStatusChange,
                      let voter = try await User.query(on: db)
                        .filter(\.$email == voterEmail)
                        .first(),
                      !notifiedUserIds.contains(voter.id!) else {
                    continue
                }

                let shouldNotify = try await shouldSendNotification(
                    to: voter,
                    for: project,
                    type: .statusChange,
                    on: db
                )

                if shouldNotify {
                    await sendNotification(
                        to: voter,
                        title: "Status Updated",
                        body: "Feedback you voted on: \(newStatus.rawValue.replacingOccurrences(of: "_", with: " "))",
                        payload: PushPayload(
                            type: .statusChange,
                            feedbackId: feedback.id?.uuidString,
                            projectId: project.id?.uuidString,
                            newStatus: newStatus.rawValue
                        ),
                        on: db
                    )
                    notifiedUserIds.insert(voter.id!)
                }
            }
        } catch {
            logger.error("Failed to send status change push notification: \(error)")
        }
    }

    // MARK: - Private Methods

    private func resolveRecipients(
        for project: Project,
        notificationType: PushNotificationType,
        excludeUserIds: [UUID],
        on db: Database
    ) async throws -> [User] {
        var recipients: [User] = []

        // Load project owner
        try await project.$owner.load(on: db)
        if !excludeUserIds.contains(project.owner.id!) {
            let shouldNotify = try await shouldSendNotification(
                to: project.owner,
                for: project,
                type: notificationType,
                on: db
            )
            if shouldNotify {
                recipients.append(project.owner)
            }
        }

        // Load project members
        let members = try await ProjectMember.query(on: db)
            .filter(\.$project.$id == project.id!)
            .with(\.$user)
            .all()

        for member in members {
            guard !excludeUserIds.contains(member.user.id!) else { continue }
            guard !recipients.contains(where: { $0.id == member.user.id }) else { continue }

            let shouldNotify = try await shouldSendNotification(
                to: member.user,
                for: project,
                type: notificationType,
                on: db
            )

            if shouldNotify {
                recipients.append(member.user)
            }
        }

        return recipients
    }

    private func shouldSendNotification(
        to user: User,
        for project: Project,
        type: PushNotificationType,
        on db: Database
    ) async throws -> Bool {
        // Check global toggle first
        guard user.pushNotificationsEnabled else { return false }

        // Check personal preference for this type
        let personalEnabled: Bool
        switch type {
        case .newFeedback: personalEnabled = user.pushNotifyNewFeedback
        case .newComment: personalEnabled = user.pushNotifyNewComments
        case .newVote: personalEnabled = user.pushNotifyVotes
        case .statusChange: personalEnabled = user.pushNotifyStatusChanges
        }

        // Check for project-specific override
        if let projectPrefs = try await ProjectMemberPreference.query(on: db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$project.$id == project.id!)
            .first() {

            // Project muted = no notifications
            if projectPrefs.pushMuted { return false }

            // Check type-specific override
            let override: Bool?
            switch type {
            case .newFeedback: override = projectPrefs.pushNotifyNewFeedback
            case .newComment: override = projectPrefs.pushNotifyNewComments
            case .newVote: override = projectPrefs.pushNotifyVotes
            case .statusChange: override = projectPrefs.pushNotifyStatusChanges
            }

            // Override takes precedence if set
            if let override = override {
                return override
            }
        }

        // Fall back to personal preference
        return personalEnabled
    }

    private func sendNotification(
        to user: User,
        title: String,
        body: String,
        payload: PushPayload,
        on db: Database
    ) async {
        do {
            // Load active device tokens
            let devices = try await DeviceToken.query(on: db)
                .filter(\.$user.$id == user.id!)
                .filter(\.$isActive == true)
                .all()

            guard !devices.isEmpty else {
                logger.debug("No active devices for user \(user.id?.uuidString ?? "unknown")")
                return
            }

            // Check if APNs is configured
            guard app.apns.isConfigured,
                  let bundleId = Environment.get("APNS_BUNDLE_ID") else {
                logger.debug("APNs not configured, skipping push notification")
                return
            }

            for device in devices {
                do {
                    // Create APNs alert notification
                    let alert = APNSAlertNotificationContent(
                        title: .raw(title),
                        body: .raw(body)
                    )

                    let notification = APNSAlertNotification(
                        alert: alert,
                        expiration: .immediately,
                        priority: .immediately,
                        topic: bundleId,
                        payload: payload
                    )

                    // Send via APNs
                    try await app.apns.client.sendAlertNotification(
                        notification,
                        deviceToken: device.token
                    )

                    // Update last used timestamp
                    device.lastUsedAt = Date()
                    try await device.save(on: db)

                    // Log success
                    try await logNotification(
                        userId: user.id!,
                        deviceTokenId: device.id,
                        type: payload.type.rawValue,
                        status: .sent,
                        feedbackId: UUID(uuidString: payload.feedbackId ?? ""),
                        projectId: UUID(uuidString: payload.projectId ?? ""),
                        on: db
                    )

                    logger.info("Push notification sent to device \(device.id?.uuidString ?? "unknown")")

                } catch let error as APNSError {
                    // Handle specific APNs errors
                    logger.error("APNs error: \(error)")

                    // Check for token expiry errors
                    let isTokenExpired = handleAPNsError(error)
                    if isTokenExpired {
                        device.isActive = false
                        try? await device.save(on: db)

                        try? await logNotification(
                            userId: user.id!,
                            deviceTokenId: device.id,
                            type: payload.type.rawValue,
                            status: .tokenExpired,
                            errorMessage: error.localizedDescription,
                            on: db
                        )
                    } else {
                        try? await logNotification(
                            userId: user.id!,
                            deviceTokenId: device.id,
                            type: payload.type.rawValue,
                            status: .failed,
                            errorMessage: error.localizedDescription,
                            on: db
                        )
                    }
                } catch {
                    logger.error("Failed to send push notification: \(error)")
                    try? await logNotification(
                        userId: user.id!,
                        deviceTokenId: device.id,
                        type: payload.type.rawValue,
                        status: .failed,
                        errorMessage: error.localizedDescription,
                        on: db
                    )
                }
            }
        } catch {
            logger.error("Failed to load devices for push notification: \(error)")
        }
    }

    private func handleAPNsError(_ error: Error) -> Bool {
        // Check if the error indicates the token is invalid/expired
        let errorString = String(describing: error).lowercased()
        let tokenExpiredIndicators = ["baddevicetoken", "unregistered", "devicetokennotfortopic", "expired", "invalid"]
        return tokenExpiredIndicators.contains { errorString.contains($0) }
    }

    private func logNotification(
        userId: UUID,
        deviceTokenId: UUID?,
        type: String,
        status: PushNotificationStatus,
        feedbackId: UUID? = nil,
        projectId: UUID? = nil,
        errorMessage: String? = nil,
        on db: Database
    ) async throws {
        let log = PushNotificationLog(
            userId: userId,
            deviceTokenId: deviceTokenId,
            notificationType: type,
            status: status.rawValue,
            feedbackId: feedbackId,
            projectId: projectId,
            errorMessage: errorMessage
        )
        try await log.save(on: db)
    }
}

// MARK: - Push Payload

struct PushPayload: Codable, Sendable {
    let type: PushNotificationType
    let feedbackId: String?
    let commentId: String?
    let projectId: String?
    let voteCount: Int?
    let oldStatus: String?
    let newStatus: String?
    let actionUrl: String?

    init(
        type: PushNotificationType,
        feedbackId: String? = nil,
        commentId: String? = nil,
        projectId: String? = nil,
        voteCount: Int? = nil,
        oldStatus: String? = nil,
        newStatus: String? = nil
    ) {
        self.type = type
        self.feedbackId = feedbackId
        self.commentId = commentId
        self.projectId = projectId
        self.voteCount = voteCount
        self.oldStatus = oldStatus
        self.newStatus = newStatus

        // Build action URL for deep linking
        if let feedbackId = feedbackId {
            self.actionUrl = "feedbackkit://feedback/\(feedbackId)"
        } else if let projectId = projectId {
            self.actionUrl = "feedbackkit://project/\(projectId)"
        } else {
            self.actionUrl = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case feedbackId = "feedback_id"
        case commentId = "comment_id"
        case projectId = "project_id"
        case voteCount = "vote_count"
        case oldStatus = "old_status"
        case newStatus = "new_status"
        case actionUrl = "action_url"
    }
}

// MARK: - Request Extension

extension Request {
    var pushNotificationService: PushNotificationService {
        PushNotificationService(app: application)
    }
}

// MARK: - Application Extension for APNs Configuration

extension Application {
    struct APNsClientKey: StorageKey {
        typealias Value = APNSClient<JSONDecoder, JSONEncoder>
    }

    struct APNsConfiguredKey: StorageKey {
        typealias Value = Bool
    }

    var apns: APNs {
        .init(application: self)
    }

    struct APNs {
        let application: Application

        var isConfigured: Bool {
            application.storage[APNsConfiguredKey.self] ?? false
        }

        var client: APNSClient<JSONDecoder, JSONEncoder> {
            get {
                guard let client = application.storage[APNsClientKey.self] else {
                    fatalError("APNs client not configured. Call app.apns.configure() first.")
                }
                return client
            }
            nonmutating set {
                application.storage[APNsClientKey.self] = newValue
            }
        }

        func configure() throws {
            guard let keyId = Environment.get("APNS_KEY_ID"),
                  let teamId = Environment.get("APNS_TEAM_ID"),
                  let keyPath = Environment.get("APNS_KEY_PATH") else {
                application.logger.warning("APNs not configured - missing environment variables (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_PATH)")
                return
            }

            let isProduction = Environment.get("APNS_PRODUCTION") == "true"

            do {
                let privateKey = try P256.Signing.PrivateKey(pemRepresentation: try String(contentsOfFile: keyPath))

                let configuration = APNSClientConfiguration(
                    authenticationMethod: .jwt(
                        privateKey: privateKey,
                        keyIdentifier: keyId,
                        teamIdentifier: teamId
                    ),
                    environment: isProduction ? .production : .development
                )

                let client = APNSClient(
                    configuration: configuration,
                    eventLoopGroupProvider: .shared(application.eventLoopGroup),
                    responseDecoder: JSONDecoder(),
                    requestEncoder: JSONEncoder()
                )

                self.client = client
                application.storage[APNsConfiguredKey.self] = true

                application.logger.info("APNs client configured for \(isProduction ? "production" : "development") environment")
            } catch {
                application.logger.error("Failed to configure APNs client: \(error)")
                throw error
            }
        }
    }
}
