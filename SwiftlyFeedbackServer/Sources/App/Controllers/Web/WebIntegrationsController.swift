import Vapor
import Fluent
import Leaf

struct WebIntegrationsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let integrations = routes.grouped("projects", ":projectId", "integrations")

        // Index page - list all integrations
        integrations.get(use: index)

        // Slack
        integrations.get("slack", use: slackSettings)
        integrations.post("slack", use: updateSlackSettings)

        // GitHub
        integrations.get("github", use: githubSettings)
        integrations.post("github", use: updateGitHubSettings)

        // Email Notifications
        integrations.get("email", use: emailSettings)
        integrations.post("email", use: updateEmailSettings)

        // Trello
        integrations.get("trello", use: trelloSettings)
        integrations.post("trello", use: updateTrelloSettings)

        // ClickUp
        integrations.get("clickup", use: clickupSettings)
        integrations.post("clickup", use: updateClickUpSettings)

        // Notion
        integrations.get("notion", use: notionSettings)
        integrations.post("notion", use: updateNotionSettings)

        // Monday.com
        integrations.get("monday", use: mondaySettings)
        integrations.post("monday", use: updateMondaySettings)

        // Linear
        integrations.get("linear", use: linearSettings)
        integrations.post("linear", use: updateLinearSettings)

        // Airtable
        integrations.get("airtable", use: airtableSettings)
        integrations.post("airtable", use: updateAirtableSettings)

        // Asana
        integrations.get("asana", use: asanaSettings)
        integrations.post("asana", use: updateAsanaSettings)

        // Basecamp
        integrations.get("basecamp", use: basecampSettings)
        integrations.post("basecamp", use: updateBasecampSettings)

        // AJAX endpoints for dynamic pickers
        let ajax = integrations.grouped("ajax")

        // ClickUp AJAX
        ajax.get("clickup", "workspaces", use: ajaxClickUpWorkspaces)
        ajax.get("clickup", "spaces", ":workspaceId", use: ajaxClickUpSpaces)
        ajax.get("clickup", "folders", ":spaceId", use: ajaxClickUpFolders)
        ajax.get("clickup", "lists", ":folderId", use: ajaxClickUpLists)
        ajax.get("clickup", "folderless-lists", ":spaceId", use: ajaxClickUpFolderlessLists)
        ajax.get("clickup", "custom-fields", use: ajaxClickUpCustomFields)

        // Notion AJAX
        ajax.get("notion", "databases", use: ajaxNotionDatabases)
        ajax.get("notion", "database", ":databaseId", "properties", use: ajaxNotionDatabaseProperties)

        // Monday AJAX
        ajax.get("monday", "boards", use: ajaxMondayBoards)
        ajax.get("monday", "boards", ":boardId", "groups", use: ajaxMondayGroups)
        ajax.get("monday", "boards", ":boardId", "columns", use: ajaxMondayColumns)

        // Linear AJAX
        ajax.get("linear", "teams", use: ajaxLinearTeams)
        ajax.get("linear", "projects", ":teamId", use: ajaxLinearProjects)
        ajax.get("linear", "labels", ":teamId", use: ajaxLinearLabels)

        // Trello AJAX
        ajax.get("trello", "boards", use: ajaxTrelloBoards)
        ajax.get("trello", "boards", ":boardId", "lists", use: ajaxTrelloLists)

        // Airtable AJAX
        ajax.get("airtable", "bases", use: ajaxAirtableBases)
        ajax.get("airtable", "tables", ":baseId", use: ajaxAirtableTables)
        ajax.get("airtable", "fields", use: ajaxAirtableFields)

        // Asana AJAX
        ajax.get("asana", "workspaces", use: ajaxAsanaWorkspaces)
        ajax.get("asana", "projects", ":workspaceId", use: ajaxAsanaProjects)
        ajax.get("asana", "sections", ":asanaProjectId", use: ajaxAsanaSections)
        ajax.get("asana", "custom-fields", ":asanaProjectId", use: ajaxAsanaCustomFields)

        // Basecamp AJAX
        ajax.get("basecamp", "accounts", use: ajaxBasecampAccounts)
        ajax.get("basecamp", "projects", ":accountId", use: ajaxBasecampProjects)
        ajax.get("basecamp", "todolists", ":accountId", ":basecampProjectId", use: ajaxBasecampTodolists)
    }

    // MARK: - Index

    @Sendable
    func index(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        let integrations = buildIntegrationsList(from: project)

        return try await req.view.render("projects/integrations/index", IntegrationsIndexContext(
            title: "Integrations - \(project.name)",
            pageTitle: "Integrations",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            integrations: integrations,
            isProTier: user.subscriptionTier.meetsRequirement(.pro)
        ))
    }

    // MARK: - Slack

    @Sendable
    func slackSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/slack", SlackSettingsContext(
            title: "Slack Integration - \(project.name)",
            pageTitle: "Slack Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            slackWebhookURL: project.slackWebhookURL ?? "",
            slackNotifyNewFeedback: project.slackNotifyNewFeedback,
            slackNotifyNewComments: project.slackNotifyNewComments,
            slackNotifyStatusChanges: project.slackNotifyStatusChanges,
            slackIsActive: project.slackIsActive,
            isConfigured: project.slackWebhookURL != nil && !project.slackWebhookURL!.isEmpty,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateSlackSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/slack?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(SlackSettingsForm.self)

        // Validate webhook URL format if provided
        if let webhookURL = form.slackWebhookUrl, !webhookURL.isEmpty {
            guard webhookURL.hasPrefix("https://hooks.slack.com/") else {
                return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/slack?error=invalid_webhook")
            }
            project.slackWebhookURL = webhookURL
        } else {
            project.slackWebhookURL = nil
        }

        project.slackNotifyNewFeedback = form.slackNotifyNewFeedback ?? false
        project.slackNotifyNewComments = form.slackNotifyNewComments ?? false
        project.slackNotifyStatusChanges = form.slackNotifyStatusChanges ?? false
        project.slackIsActive = form.slackIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/slack?success=updated")
    }

    // MARK: - GitHub

    @Sendable
    func githubSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/github", GitHubSettingsContext(
            title: "GitHub Integration - \(project.name)",
            pageTitle: "GitHub Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            githubOwner: project.githubOwner ?? "",
            githubRepo: project.githubRepo ?? "",
            githubToken: project.githubToken ?? "",
            githubDefaultLabels: project.githubDefaultLabels?.joined(separator: ", ") ?? "",
            githubSyncStatus: project.githubSyncStatus,
            githubIsActive: project.githubIsActive,
            isConfigured: project.githubOwner != nil && project.githubRepo != nil && project.githubToken != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateGitHubSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/github?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(GitHubSettingsForm.self)

        project.githubOwner = form.githubOwner?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : form.githubOwner?.trimmingCharacters(in: .whitespaces)
        project.githubRepo = form.githubRepo?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : form.githubRepo?.trimmingCharacters(in: .whitespaces)
        project.githubToken = form.githubToken?.isEmpty == true ? nil : form.githubToken
        project.githubDefaultLabels = parseCommaSeparated(form.githubDefaultLabels)
        project.githubSyncStatus = form.githubSyncStatus ?? false
        project.githubIsActive = form.githubIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/github?success=updated")
    }

    // MARK: - Email Notifications

    @Sendable
    func emailSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        let allStatuses = FeedbackStatus.allCases.map { status in
            StatusCheckbox(
                status: status.rawValue,
                name: status.displayName,
                isChecked: project.emailNotifyStatuses.contains(status.rawValue)
            )
        }

        return try await req.view.render("projects/integrations/email", EmailSettingsContext(
            title: "Email Notifications - \(project.name)",
            pageTitle: "Email Notifications",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            statuses: allStatuses,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateEmailSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/email?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(EmailSettingsForm.self)

        // Collect checked statuses
        var selectedStatuses: [String] = []
        for status in FeedbackStatus.allCases {
            let formFieldName = "status_\(status.rawValue)"
            if let isChecked = try? req.content.get(String.self, at: formFieldName), isChecked == "on" {
                selectedStatuses.append(status.rawValue)
            }
        }

        project.emailNotifyStatuses = selectedStatuses

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/email?success=updated")
    }

    // MARK: - Trello

    @Sendable
    func trelloSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/trello", TrelloSettingsContext(
            title: "Trello Integration - \(project.name)",
            pageTitle: "Trello Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            trelloToken: project.trelloToken ?? "",
            trelloBoardId: project.trelloBoardId ?? "",
            trelloBoardName: project.trelloBoardName ?? "",
            trelloListId: project.trelloListId ?? "",
            trelloListName: project.trelloListName ?? "",
            trelloSyncStatus: project.trelloSyncStatus,
            trelloSyncComments: project.trelloSyncComments,
            trelloIsActive: project.trelloIsActive,
            isConfigured: project.trelloToken != nil && project.trelloListId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateTrelloSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/trello?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(TrelloSettingsForm.self)

        project.trelloToken = form.trelloToken?.isEmpty == true ? nil : form.trelloToken
        project.trelloBoardId = form.trelloBoardId?.isEmpty == true ? nil : form.trelloBoardId
        project.trelloBoardName = form.trelloBoardName?.isEmpty == true ? nil : form.trelloBoardName
        project.trelloListId = form.trelloListId?.isEmpty == true ? nil : form.trelloListId
        project.trelloListName = form.trelloListName?.isEmpty == true ? nil : form.trelloListName
        project.trelloSyncStatus = form.trelloSyncStatus ?? false
        project.trelloSyncComments = form.trelloSyncComments ?? false
        project.trelloIsActive = form.trelloIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/trello?success=updated")
    }

    // MARK: - ClickUp

    @Sendable
    func clickupSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/clickup", ClickUpSettingsContext(
            title: "ClickUp Integration - \(project.name)",
            pageTitle: "ClickUp Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            clickupToken: project.clickupToken ?? "",
            clickupListId: project.clickupListId ?? "",
            clickupWorkspaceName: project.clickupWorkspaceName ?? "",
            clickupListName: project.clickupListName ?? "",
            clickupDefaultTags: project.clickupDefaultTags?.joined(separator: ", ") ?? "",
            clickupSyncStatus: project.clickupSyncStatus,
            clickupSyncComments: project.clickupSyncComments,
            clickupVotesFieldId: project.clickupVotesFieldId ?? "",
            clickupIsActive: project.clickupIsActive,
            isConfigured: project.clickupToken != nil && project.clickupListId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateClickUpSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/clickup?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(ClickUpSettingsForm.self)

        project.clickupToken = form.clickupToken?.isEmpty == true ? nil : form.clickupToken
        project.clickupListId = form.clickupListId?.isEmpty == true ? nil : form.clickupListId
        project.clickupWorkspaceName = form.clickupWorkspaceName?.isEmpty == true ? nil : form.clickupWorkspaceName
        project.clickupListName = form.clickupListName?.isEmpty == true ? nil : form.clickupListName
        project.clickupDefaultTags = parseCommaSeparated(form.clickupDefaultTags)
        project.clickupSyncStatus = form.clickupSyncStatus ?? false
        project.clickupSyncComments = form.clickupSyncComments ?? false
        project.clickupVotesFieldId = form.clickupVotesFieldId?.isEmpty == true ? nil : form.clickupVotesFieldId
        project.clickupIsActive = form.clickupIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/clickup?success=updated")
    }

    // MARK: - Notion

    @Sendable
    func notionSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/notion", NotionSettingsContext(
            title: "Notion Integration - \(project.name)",
            pageTitle: "Notion Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            notionToken: project.notionToken ?? "",
            notionDatabaseId: project.notionDatabaseId ?? "",
            notionDatabaseName: project.notionDatabaseName ?? "",
            notionSyncStatus: project.notionSyncStatus,
            notionSyncComments: project.notionSyncComments,
            notionStatusProperty: project.notionStatusProperty ?? "",
            notionVotesProperty: project.notionVotesProperty ?? "",
            notionIsActive: project.notionIsActive,
            isConfigured: project.notionToken != nil && project.notionDatabaseId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateNotionSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/notion?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(NotionSettingsForm.self)

        project.notionToken = form.notionToken?.isEmpty == true ? nil : form.notionToken
        project.notionDatabaseId = form.notionDatabaseId?.isEmpty == true ? nil : form.notionDatabaseId
        project.notionDatabaseName = form.notionDatabaseName?.isEmpty == true ? nil : form.notionDatabaseName
        project.notionSyncStatus = form.notionSyncStatus ?? false
        project.notionSyncComments = form.notionSyncComments ?? false
        project.notionStatusProperty = form.notionStatusProperty?.isEmpty == true ? nil : form.notionStatusProperty
        project.notionVotesProperty = form.notionVotesProperty?.isEmpty == true ? nil : form.notionVotesProperty
        project.notionIsActive = form.notionIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/notion?success=updated")
    }

    // MARK: - Monday.com

    @Sendable
    func mondaySettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/monday", MondaySettingsContext(
            title: "Monday.com Integration - \(project.name)",
            pageTitle: "Monday.com Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            mondayToken: project.mondayToken ?? "",
            mondayBoardId: project.mondayBoardId ?? "",
            mondayBoardName: project.mondayBoardName ?? "",
            mondayGroupId: project.mondayGroupId ?? "",
            mondayGroupName: project.mondayGroupName ?? "",
            mondaySyncStatus: project.mondaySyncStatus,
            mondaySyncComments: project.mondaySyncComments,
            mondayStatusColumnId: project.mondayStatusColumnId ?? "",
            mondayVotesColumnId: project.mondayVotesColumnId ?? "",
            mondayIsActive: project.mondayIsActive,
            isConfigured: project.mondayToken != nil && project.mondayBoardId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateMondaySettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/monday?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(MondaySettingsForm.self)

        project.mondayToken = form.mondayToken?.isEmpty == true ? nil : form.mondayToken
        project.mondayBoardId = form.mondayBoardId?.isEmpty == true ? nil : form.mondayBoardId
        project.mondayBoardName = form.mondayBoardName?.isEmpty == true ? nil : form.mondayBoardName
        project.mondayGroupId = form.mondayGroupId?.isEmpty == true ? nil : form.mondayGroupId
        project.mondayGroupName = form.mondayGroupName?.isEmpty == true ? nil : form.mondayGroupName
        project.mondaySyncStatus = form.mondaySyncStatus ?? false
        project.mondaySyncComments = form.mondaySyncComments ?? false
        project.mondayStatusColumnId = form.mondayStatusColumnId?.isEmpty == true ? nil : form.mondayStatusColumnId
        project.mondayVotesColumnId = form.mondayVotesColumnId?.isEmpty == true ? nil : form.mondayVotesColumnId
        project.mondayIsActive = form.mondayIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/monday?success=updated")
    }

    // MARK: - Linear

    @Sendable
    func linearSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/linear", LinearSettingsContext(
            title: "Linear Integration - \(project.name)",
            pageTitle: "Linear Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            linearToken: project.linearToken ?? "",
            linearTeamId: project.linearTeamId ?? "",
            linearTeamName: project.linearTeamName ?? "",
            linearProjectId: project.linearProjectId ?? "",
            linearProjectName: project.linearProjectName ?? "",
            linearDefaultLabelIds: project.linearDefaultLabelIds?.joined(separator: ",") ?? "",
            linearSyncStatus: project.linearSyncStatus,
            linearSyncComments: project.linearSyncComments,
            linearIsActive: project.linearIsActive,
            isConfigured: project.linearToken != nil && project.linearTeamId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateLinearSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/linear?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(LinearSettingsForm.self)

        project.linearToken = form.linearToken?.isEmpty == true ? nil : form.linearToken
        project.linearTeamId = form.linearTeamId?.isEmpty == true ? nil : form.linearTeamId
        project.linearTeamName = form.linearTeamName?.isEmpty == true ? nil : form.linearTeamName
        project.linearProjectId = form.linearProjectId?.isEmpty == true ? nil : form.linearProjectId
        project.linearProjectName = form.linearProjectName?.isEmpty == true ? nil : form.linearProjectName
        project.linearDefaultLabelIds = form.linearDefaultLabelIds?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        project.linearSyncStatus = form.linearSyncStatus ?? false
        project.linearSyncComments = form.linearSyncComments ?? false
        project.linearIsActive = form.linearIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/linear?success=updated")
    }

    // MARK: - Airtable

    @Sendable
    func airtableSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/airtable", AirtableSettingsContext(
            title: "Airtable Integration - \(project.name)",
            pageTitle: "Airtable Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            airtableToken: project.airtableToken ?? "",
            airtableBaseId: project.airtableBaseId ?? "",
            airtableBaseName: project.airtableBaseName ?? "",
            airtableTableId: project.airtableTableId ?? "",
            airtableTableName: project.airtableTableName ?? "",
            airtableSyncStatus: project.airtableSyncStatus,
            airtableSyncComments: project.airtableSyncComments,
            airtableStatusFieldId: project.airtableStatusFieldId ?? "",
            airtableVotesFieldId: project.airtableVotesFieldId ?? "",
            airtableTitleFieldId: project.airtableTitleFieldId ?? "",
            airtableDescriptionFieldId: project.airtableDescriptionFieldId ?? "",
            airtableCategoryFieldId: project.airtableCategoryFieldId ?? "",
            airtableIsActive: project.airtableIsActive,
            isConfigured: project.airtableToken != nil && project.airtableBaseId != nil && project.airtableTableId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateAirtableSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/airtable?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(AirtableSettingsForm.self)

        project.airtableToken = form.airtableToken?.isEmpty == true ? nil : form.airtableToken
        project.airtableBaseId = form.airtableBaseId?.isEmpty == true ? nil : form.airtableBaseId
        project.airtableBaseName = form.airtableBaseName?.isEmpty == true ? nil : form.airtableBaseName
        project.airtableTableId = form.airtableTableId?.isEmpty == true ? nil : form.airtableTableId
        project.airtableTableName = form.airtableTableName?.isEmpty == true ? nil : form.airtableTableName
        project.airtableSyncStatus = form.airtableSyncStatus ?? false
        project.airtableSyncComments = form.airtableSyncComments ?? false
        project.airtableStatusFieldId = form.airtableStatusFieldId?.isEmpty == true ? nil : form.airtableStatusFieldId
        project.airtableVotesFieldId = form.airtableVotesFieldId?.isEmpty == true ? nil : form.airtableVotesFieldId
        project.airtableTitleFieldId = form.airtableTitleFieldId?.isEmpty == true ? nil : form.airtableTitleFieldId
        project.airtableDescriptionFieldId = form.airtableDescriptionFieldId?.isEmpty == true ? nil : form.airtableDescriptionFieldId
        project.airtableCategoryFieldId = form.airtableCategoryFieldId?.isEmpty == true ? nil : form.airtableCategoryFieldId
        project.airtableIsActive = form.airtableIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/airtable?success=updated")
    }

    // MARK: - Asana

    @Sendable
    func asanaSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/asana", AsanaSettingsContext(
            title: "Asana Integration - \(project.name)",
            pageTitle: "Asana Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            asanaToken: project.asanaToken ?? "",
            asanaWorkspaceId: project.asanaWorkspaceId ?? "",
            asanaWorkspaceName: project.asanaWorkspaceName ?? "",
            asanaProjectId: project.asanaProjectId ?? "",
            asanaProjectName: project.asanaProjectName ?? "",
            asanaSectionId: project.asanaSectionId ?? "",
            asanaSectionName: project.asanaSectionName ?? "",
            asanaSyncStatus: project.asanaSyncStatus,
            asanaSyncComments: project.asanaSyncComments,
            asanaStatusFieldId: project.asanaStatusFieldId ?? "",
            asanaVotesFieldId: project.asanaVotesFieldId ?? "",
            asanaIsActive: project.asanaIsActive,
            isConfigured: project.asanaToken != nil && project.asanaProjectId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateAsanaSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/asana?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(AsanaSettingsForm.self)

        project.asanaToken = form.asanaToken?.isEmpty == true ? nil : form.asanaToken
        project.asanaWorkspaceId = form.asanaWorkspaceId?.isEmpty == true ? nil : form.asanaWorkspaceId
        project.asanaWorkspaceName = form.asanaWorkspaceName?.isEmpty == true ? nil : form.asanaWorkspaceName
        project.asanaProjectId = form.asanaProjectId?.isEmpty == true ? nil : form.asanaProjectId
        project.asanaProjectName = form.asanaProjectName?.isEmpty == true ? nil : form.asanaProjectName
        project.asanaSectionId = form.asanaSectionId?.isEmpty == true ? nil : form.asanaSectionId
        project.asanaSectionName = form.asanaSectionName?.isEmpty == true ? nil : form.asanaSectionName
        project.asanaSyncStatus = form.asanaSyncStatus ?? false
        project.asanaSyncComments = form.asanaSyncComments ?? false
        project.asanaStatusFieldId = form.asanaStatusFieldId?.isEmpty == true ? nil : form.asanaStatusFieldId
        project.asanaVotesFieldId = form.asanaVotesFieldId?.isEmpty == true ? nil : form.asanaVotesFieldId
        project.asanaIsActive = form.asanaIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/asana?success=updated")
    }

    // MARK: - Basecamp

    @Sendable
    func basecampSettings(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let role = try await getUserRole(req: req, user: user, project: project)

        return try await req.view.render("projects/integrations/basecamp", BasecampSettingsContext(
            title: "Basecamp Integration - \(project.name)",
            pageTitle: "Basecamp Integration",
            currentPage: "projects",
            user: UserContext(from: user),
            project: ProjectContext(from: project, role: role),
            basecampAccessToken: project.basecampAccessToken ?? "",
            basecampAccountId: project.basecampAccountId ?? "",
            basecampAccountName: project.basecampAccountName ?? "",
            basecampProjectId: project.basecampProjectId ?? "",
            basecampProjectName: project.basecampProjectName ?? "",
            basecampTodosetId: project.basecampTodosetId ?? "",
            basecampTodolistId: project.basecampTodolistId ?? "",
            basecampTodolistName: project.basecampTodolistName ?? "",
            basecampSyncStatus: project.basecampSyncStatus,
            basecampSyncComments: project.basecampSyncComments,
            basecampIsActive: project.basecampIsActive,
            isConfigured: project.basecampAccessToken != nil && project.basecampTodolistId != nil,
            isProTier: user.subscriptionTier.meetsRequirement(.pro),
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"]
        ))
    }

    @Sendable
    func updateBasecampSettings(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        guard user.subscriptionTier.meetsRequirement(.pro) else {
            return req.redirect(to: "/admin/projects/\(req.parameters.get("projectId")!)/integrations/basecamp?error=pro_required")
        }

        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)
        let form = try req.content.decode(BasecampSettingsForm.self)

        project.basecampAccessToken = form.basecampAccessToken?.isEmpty == true ? nil : form.basecampAccessToken
        project.basecampAccountId = form.basecampAccountId?.isEmpty == true ? nil : form.basecampAccountId
        project.basecampAccountName = form.basecampAccountName?.isEmpty == true ? nil : form.basecampAccountName
        project.basecampProjectId = form.basecampProjectId?.isEmpty == true ? nil : form.basecampProjectId
        project.basecampProjectName = form.basecampProjectName?.isEmpty == true ? nil : form.basecampProjectName
        project.basecampTodosetId = form.basecampTodosetId?.isEmpty == true ? nil : form.basecampTodosetId
        project.basecampTodolistId = form.basecampTodolistId?.isEmpty == true ? nil : form.basecampTodolistId
        project.basecampTodolistName = form.basecampTodolistName?.isEmpty == true ? nil : form.basecampTodolistName
        project.basecampSyncStatus = form.basecampSyncStatus ?? false
        project.basecampSyncComments = form.basecampSyncComments ?? false
        project.basecampIsActive = form.basecampIsActive ?? false

        try await project.save(on: req.db)

        return req.redirect(to: "/admin/projects/\(try project.requireID())/integrations/basecamp?success=updated")
    }

    // MARK: - AJAX Endpoints (ClickUp)

    @Sendable
    func ajaxClickUpWorkspaces(req: Request) async throws -> [ClickUpWorkspaceDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.clickupToken else {
            throw Abort(.badRequest, reason: "ClickUp token not configured")
        }

        let workspaces = try await req.clickupService.getWorkspaces(token: token)
        return workspaces.map { ClickUpWorkspaceDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxClickUpSpaces(req: Request) async throws -> [ClickUpSpaceDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.clickupToken else {
            throw Abort(.badRequest, reason: "ClickUp token not configured")
        }

        guard let workspaceId = req.parameters.get("workspaceId") else {
            throw Abort(.badRequest, reason: "Workspace ID required")
        }

        let spaces = try await req.clickupService.getSpaces(workspaceId: workspaceId, token: token)
        return spaces.map { ClickUpSpaceDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxClickUpFolders(req: Request) async throws -> [ClickUpFolderDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.clickupToken else {
            throw Abort(.badRequest, reason: "ClickUp token not configured")
        }

        guard let spaceId = req.parameters.get("spaceId") else {
            throw Abort(.badRequest, reason: "Space ID required")
        }

        let folders = try await req.clickupService.getFolders(spaceId: spaceId, token: token)
        return folders.map { ClickUpFolderDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxClickUpLists(req: Request) async throws -> [ClickUpListDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.clickupToken else {
            throw Abort(.badRequest, reason: "ClickUp token not configured")
        }

        guard let folderId = req.parameters.get("folderId") else {
            throw Abort(.badRequest, reason: "Folder ID required")
        }

        let lists = try await req.clickupService.getLists(folderId: folderId, token: token)
        return lists.map { ClickUpListDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxClickUpFolderlessLists(req: Request) async throws -> [ClickUpListDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.clickupToken else {
            throw Abort(.badRequest, reason: "ClickUp token not configured")
        }

        guard let spaceId = req.parameters.get("spaceId") else {
            throw Abort(.badRequest, reason: "Space ID required")
        }

        let lists = try await req.clickupService.getFolderlessLists(spaceId: spaceId, token: token)
        return lists.map { ClickUpListDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxClickUpCustomFields(req: Request) async throws -> [ClickUpCustomFieldDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.clickupToken,
              let listId = project.clickupListId else {
            throw Abort(.badRequest, reason: "ClickUp integration not configured")
        }

        let fields = try await req.clickupService.getListCustomFields(listId: listId, token: token)
        return fields
            .filter { $0.type == "number" }
            .map { ClickUpCustomFieldDTO(id: $0.id, name: $0.name, type: $0.type) }
    }

    // MARK: - AJAX Endpoints (Notion)

    @Sendable
    func ajaxNotionDatabases(req: Request) async throws -> [NotionDatabaseDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.notionToken else {
            throw Abort(.badRequest, reason: "Notion token not configured")
        }

        let databases = try await req.notionService.searchDatabases(token: token)
        return databases.map { NotionDatabaseDTO(id: $0.id, name: $0.name, properties: []) }
    }

    @Sendable
    func ajaxNotionDatabaseProperties(req: Request) async throws -> [NotionPropertyDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.notionToken else {
            throw Abort(.badRequest, reason: "Notion token not configured")
        }

        guard let databaseId = req.parameters.get("databaseId") else {
            throw Abort(.badRequest, reason: "Database ID required")
        }

        let database = try await req.notionService.getDatabase(databaseId: databaseId, token: token)
        return database.properties.values.map { NotionPropertyDTO(id: $0.id, name: $0.name, type: $0.type) }
    }

    // MARK: - AJAX Endpoints (Monday)

    @Sendable
    func ajaxMondayBoards(req: Request) async throws -> [MondayBoardDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.mondayToken else {
            throw Abort(.badRequest, reason: "Monday token not configured")
        }

        let boards = try await req.mondayService.getBoards(token: token)
        return boards.map { MondayBoardDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxMondayGroups(req: Request) async throws -> [MondayGroupDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.mondayToken else {
            throw Abort(.badRequest, reason: "Monday token not configured")
        }

        guard let boardId = req.parameters.get("boardId") else {
            throw Abort(.badRequest, reason: "Board ID required")
        }

        let groups = try await req.mondayService.getGroups(boardId: boardId, token: token)
        return groups.map { MondayGroupDTO(id: $0.id, title: $0.title) }
    }

    @Sendable
    func ajaxMondayColumns(req: Request) async throws -> [MondayColumnDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.mondayToken else {
            throw Abort(.badRequest, reason: "Monday token not configured")
        }

        guard let boardId = req.parameters.get("boardId") else {
            throw Abort(.badRequest, reason: "Board ID required")
        }

        let columns = try await req.mondayService.getColumns(boardId: boardId, token: token)
        return columns.map { MondayColumnDTO(id: $0.id, title: $0.title, type: $0.type) }
    }

    // MARK: - AJAX Endpoints (Linear)

    @Sendable
    func ajaxLinearTeams(req: Request) async throws -> [LinearTeamDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.linearToken else {
            throw Abort(.badRequest, reason: "Linear token not configured")
        }

        let teams = try await req.linearService.getTeams(token: token)
        return teams.map { LinearTeamDTO(id: $0.id, name: $0.name, key: $0.key) }
    }

    @Sendable
    func ajaxLinearProjects(req: Request) async throws -> [LinearProjectDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.linearToken else {
            throw Abort(.badRequest, reason: "Linear token not configured")
        }

        guard let teamId = req.parameters.get("teamId") else {
            throw Abort(.badRequest, reason: "Team ID required")
        }

        let projects = try await req.linearService.getProjects(teamId: teamId, token: token)
        return projects.map { LinearProjectDTO(id: $0.id, name: $0.name, state: $0.state) }
    }

    @Sendable
    func ajaxLinearLabels(req: Request) async throws -> [LinearLabelDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.linearToken else {
            throw Abort(.badRequest, reason: "Linear token not configured")
        }

        guard let teamId = req.parameters.get("teamId") else {
            throw Abort(.badRequest, reason: "Team ID required")
        }

        let labels = try await req.linearService.getLabels(teamId: teamId, token: token)
        return labels.map { LinearLabelDTO(id: $0.id, name: $0.name, color: $0.color) }
    }

    // MARK: - AJAX Endpoints (Trello)

    @Sendable
    func ajaxTrelloBoards(req: Request) async throws -> [TrelloBoardDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.trelloToken else {
            throw Abort(.badRequest, reason: "Trello token not configured")
        }

        let boards = try await req.trelloService.getBoards(token: token)
        return boards.map { TrelloBoardDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxTrelloLists(req: Request) async throws -> [TrelloListDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.trelloToken else {
            throw Abort(.badRequest, reason: "Trello token not configured")
        }

        guard let boardId = req.parameters.get("boardId") else {
            throw Abort(.badRequest, reason: "Board ID required")
        }

        let lists = try await req.trelloService.getLists(token: token, boardId: boardId)
        return lists.map { TrelloListDTO(id: $0.id, name: $0.name) }
    }

    // MARK: - AJAX Endpoints (Airtable)

    @Sendable
    func ajaxAirtableBases(req: Request) async throws -> [AirtableBaseDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.airtableToken else {
            throw Abort(.badRequest, reason: "Airtable token not configured")
        }

        let bases = try await req.airtableService.getBases(token: token)
        return bases.map { AirtableBaseDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxAirtableTables(req: Request) async throws -> [AirtableTableDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.airtableToken else {
            throw Abort(.badRequest, reason: "Airtable token not configured")
        }

        guard let baseId = req.parameters.get("baseId") else {
            throw Abort(.badRequest, reason: "Base ID required")
        }

        let tables = try await req.airtableService.getTables(baseId: baseId, token: token)
        return tables.map { AirtableTableDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxAirtableFields(req: Request) async throws -> [AirtableFieldDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.airtableToken,
              let baseId = project.airtableBaseId,
              let tableId = project.airtableTableId else {
            throw Abort(.badRequest, reason: "Airtable integration not configured")
        }

        let fields = try await req.airtableService.getFields(baseId: baseId, tableId: tableId, token: token)
        return fields.map { AirtableFieldDTO(id: $0.id, name: $0.name, type: $0.type) }
    }

    // MARK: - AJAX Endpoints (Asana)

    @Sendable
    func ajaxAsanaWorkspaces(req: Request) async throws -> [AsanaWorkspaceDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.asanaToken else {
            throw Abort(.badRequest, reason: "Asana token not configured")
        }

        let workspaces = try await req.asanaService.getWorkspaces(token: token)
        return workspaces.map { AsanaWorkspaceDTO(gid: $0.gid, name: $0.name) }
    }

    @Sendable
    func ajaxAsanaProjects(req: Request) async throws -> [AsanaProjectDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.asanaToken else {
            throw Abort(.badRequest, reason: "Asana token not configured")
        }

        guard let workspaceId = req.parameters.get("workspaceId") else {
            throw Abort(.badRequest, reason: "Workspace ID required")
        }

        let projects = try await req.asanaService.getProjects(workspaceId: workspaceId, token: token)
        return projects.map { AsanaProjectDTO(gid: $0.gid, name: $0.name) }
    }

    @Sendable
    func ajaxAsanaSections(req: Request) async throws -> [AsanaSectionDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.asanaToken else {
            throw Abort(.badRequest, reason: "Asana token not configured")
        }

        guard let asanaProjectId = req.parameters.get("asanaProjectId") else {
            throw Abort(.badRequest, reason: "Project ID required")
        }

        let sections = try await req.asanaService.getSections(projectId: asanaProjectId, token: token)
        return sections.map { AsanaSectionDTO(gid: $0.gid, name: $0.name) }
    }

    @Sendable
    func ajaxAsanaCustomFields(req: Request) async throws -> [AsanaCustomFieldDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.asanaToken else {
            throw Abort(.badRequest, reason: "Asana token not configured")
        }

        guard let asanaProjectId = req.parameters.get("asanaProjectId") else {
            throw Abort(.badRequest, reason: "Project ID required")
        }

        let fields = try await req.asanaService.getCustomFields(projectId: asanaProjectId, token: token)
        return fields.map { field in
            AsanaCustomFieldDTO(
                gid: field.gid,
                name: field.name,
                type: field.type,
                enumOptions: field.enumOptions?.map { option in
                    AsanaEnumOptionDTO(gid: option.gid, name: option.name, enabled: option.enabled, color: option.color)
                }
            )
        }
    }

    // MARK: - AJAX Endpoints (Basecamp)

    @Sendable
    func ajaxBasecampAccounts(req: Request) async throws -> [BasecampAccountDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.basecampAccessToken else {
            throw Abort(.badRequest, reason: "Basecamp token not configured")
        }

        let authorization = try await req.basecampService.getAuthorization(token: token)
        return authorization.accounts.map { BasecampAccountDTO(id: $0.id, name: $0.name) }
    }

    @Sendable
    func ajaxBasecampProjects(req: Request) async throws -> [BasecampProjectDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.basecampAccessToken else {
            throw Abort(.badRequest, reason: "Basecamp token not configured")
        }

        guard let accountId = req.parameters.get("accountId") else {
            throw Abort(.badRequest, reason: "Account ID required")
        }

        let projects = try await req.basecampService.getProjects(accountId: accountId, token: token)
        return projects.map { BasecampProjectDTO(id: $0.id, name: $0.name, todosetId: $0.todosetId) }
    }

    @Sendable
    func ajaxBasecampTodolists(req: Request) async throws -> [BasecampTodolistDTO] {
        let user = try req.auth.require(User.self)
        let project = try await getProjectWithAccess(req: req, user: user, requireAdmin: true)

        guard let token = project.basecampAccessToken else {
            throw Abort(.badRequest, reason: "Basecamp token not configured")
        }

        guard let accountId = req.parameters.get("accountId"),
              let basecampProjectId = req.parameters.get("basecampProjectId") else {
            throw Abort(.badRequest, reason: "Account ID and Project ID required")
        }

        // First get the todoset ID from the project
        let projects = try await req.basecampService.getProjects(accountId: accountId, token: token)
        guard let basecampProject = projects.first(where: { String($0.id) == basecampProjectId }),
              let todosetId = basecampProject.todosetId else {
            throw Abort(.notFound, reason: "Project or todoset not found")
        }

        let todolists = try await req.basecampService.getTodolists(
            accountId: accountId,
            projectId: basecampProjectId,
            todosetId: String(todosetId),
            token: token
        )
        return todolists.map { BasecampTodolistDTO(id: $0.id, name: $0.name) }
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
                let member = try await ProjectMember.query(on: req.db)
                    .filter(\.$project.$id == projectId)
                    .filter(\.$user.$id == userId)
                    .first()

                guard let member = member, member.role == .admin else {
                    throw Abort(.forbidden)
                }
            }
        } else {
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

    private func buildIntegrationsList(from project: Project) -> [IntegrationItem] {
        [
            IntegrationItem(
                id: "slack",
                name: "Slack",
                description: "Get notifications in Slack channels",
                icon: "slack",
                isConfigured: project.slackWebhookURL != nil && !project.slackWebhookURL!.isEmpty,
                isActive: project.slackIsActive
            ),
            IntegrationItem(
                id: "github",
                name: "GitHub",
                description: "Create issues from feedback",
                icon: "github",
                isConfigured: project.githubOwner != nil && project.githubRepo != nil && project.githubToken != nil,
                isActive: project.githubIsActive
            ),
            IntegrationItem(
                id: "email",
                name: "Email Notifications",
                description: "Email voters when status changes",
                icon: "email",
                isConfigured: !project.emailNotifyStatuses.isEmpty,
                isActive: !project.emailNotifyStatuses.isEmpty
            ),
            IntegrationItem(
                id: "trello",
                name: "Trello",
                description: "Create cards from feedback",
                icon: "trello",
                isConfigured: project.trelloToken != nil && project.trelloListId != nil,
                isActive: project.trelloIsActive
            ),
            IntegrationItem(
                id: "clickup",
                name: "ClickUp",
                description: "Create tasks from feedback",
                icon: "clickup",
                isConfigured: project.clickupToken != nil && project.clickupListId != nil,
                isActive: project.clickupIsActive
            ),
            IntegrationItem(
                id: "notion",
                name: "Notion",
                description: "Sync feedback to a database",
                icon: "notion",
                isConfigured: project.notionToken != nil && project.notionDatabaseId != nil,
                isActive: project.notionIsActive
            ),
            IntegrationItem(
                id: "monday",
                name: "Monday.com",
                description: "Create items from feedback",
                icon: "monday",
                isConfigured: project.mondayToken != nil && project.mondayBoardId != nil,
                isActive: project.mondayIsActive
            ),
            IntegrationItem(
                id: "linear",
                name: "Linear",
                description: "Create issues from feedback",
                icon: "linear",
                isConfigured: project.linearToken != nil && project.linearTeamId != nil,
                isActive: project.linearIsActive
            ),
            IntegrationItem(
                id: "airtable",
                name: "Airtable",
                description: "Sync feedback to a base",
                icon: "airtable",
                isConfigured: project.airtableToken != nil && project.airtableBaseId != nil && project.airtableTableId != nil,
                isActive: project.airtableIsActive
            ),
            IntegrationItem(
                id: "asana",
                name: "Asana",
                description: "Create tasks from feedback",
                icon: "asana",
                isConfigured: project.asanaToken != nil && project.asanaProjectId != nil,
                isActive: project.asanaIsActive
            ),
            IntegrationItem(
                id: "basecamp",
                name: "Basecamp",
                description: "Create todos from feedback",
                icon: "basecamp",
                isConfigured: project.basecampAccessToken != nil && project.basecampTodolistId != nil,
                isActive: project.basecampIsActive
            )
        ]
    }

    private func parseCommaSeparated(_ value: String?) -> [String]? {
        guard let value = value, !value.isEmpty else { return nil }
        let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }
}

// MARK: - Form DTOs

struct SlackSettingsForm: Content {
    var slackWebhookUrl: String?
    var slackNotifyNewFeedback: Bool?
    var slackNotifyNewComments: Bool?
    var slackNotifyStatusChanges: Bool?
    var slackIsActive: Bool?
}

struct GitHubSettingsForm: Content {
    var githubOwner: String?
    var githubRepo: String?
    var githubToken: String?
    var githubDefaultLabels: String?
    var githubSyncStatus: Bool?
    var githubIsActive: Bool?
}

struct EmailSettingsForm: Content {
    var emailNotifyStatuses: [String]?
}

struct TrelloSettingsForm: Content {
    var trelloToken: String?
    var trelloBoardId: String?
    var trelloBoardName: String?
    var trelloListId: String?
    var trelloListName: String?
    var trelloSyncStatus: Bool?
    var trelloSyncComments: Bool?
    var trelloIsActive: Bool?
}

struct ClickUpSettingsForm: Content {
    var clickupToken: String?
    var clickupListId: String?
    var clickupWorkspaceName: String?
    var clickupListName: String?
    var clickupDefaultTags: String?
    var clickupSyncStatus: Bool?
    var clickupSyncComments: Bool?
    var clickupVotesFieldId: String?
    var clickupIsActive: Bool?
}

struct NotionSettingsForm: Content {
    var notionToken: String?
    var notionDatabaseId: String?
    var notionDatabaseName: String?
    var notionSyncStatus: Bool?
    var notionSyncComments: Bool?
    var notionStatusProperty: String?
    var notionVotesProperty: String?
    var notionIsActive: Bool?
}

struct MondaySettingsForm: Content {
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

struct LinearSettingsForm: Content {
    var linearToken: String?
    var linearTeamId: String?
    var linearTeamName: String?
    var linearProjectId: String?
    var linearProjectName: String?
    var linearDefaultLabelIds: String?
    var linearSyncStatus: Bool?
    var linearSyncComments: Bool?
    var linearIsActive: Bool?
}

struct AirtableSettingsForm: Content {
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

struct AsanaSettingsForm: Content {
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

struct BasecampSettingsForm: Content {
    var basecampAccessToken: String?
    var basecampAccountId: String?
    var basecampAccountName: String?
    var basecampProjectId: String?
    var basecampProjectName: String?
    var basecampTodosetId: String?
    var basecampTodolistId: String?
    var basecampTodolistName: String?
    var basecampSyncStatus: Bool?
    var basecampSyncComments: Bool?
    var basecampIsActive: Bool?
}

// MARK: - View Contexts

struct IntegrationsIndexContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let integrations: [IntegrationItem]
    let isProTier: Bool
}

struct IntegrationItem: Encodable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let isConfigured: Bool
    let isActive: Bool
}

struct SlackSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let slackWebhookURL: String
    let slackNotifyNewFeedback: Bool
    let slackNotifyNewComments: Bool
    let slackNotifyStatusChanges: Bool
    let slackIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct GitHubSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let githubOwner: String
    let githubRepo: String
    let githubToken: String
    let githubDefaultLabels: String
    let githubSyncStatus: Bool
    let githubIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct EmailSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let statuses: [StatusCheckbox]
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct StatusCheckbox: Encodable {
    let status: String
    let name: String
    let isChecked: Bool
}

struct TrelloSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let trelloToken: String
    let trelloBoardId: String
    let trelloBoardName: String
    let trelloListId: String
    let trelloListName: String
    let trelloSyncStatus: Bool
    let trelloSyncComments: Bool
    let trelloIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct ClickUpSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let clickupToken: String
    let clickupListId: String
    let clickupWorkspaceName: String
    let clickupListName: String
    let clickupDefaultTags: String
    let clickupSyncStatus: Bool
    let clickupSyncComments: Bool
    let clickupVotesFieldId: String
    let clickupIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct NotionSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let notionToken: String
    let notionDatabaseId: String
    let notionDatabaseName: String
    let notionSyncStatus: Bool
    let notionSyncComments: Bool
    let notionStatusProperty: String
    let notionVotesProperty: String
    let notionIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct MondaySettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let mondayToken: String
    let mondayBoardId: String
    let mondayBoardName: String
    let mondayGroupId: String
    let mondayGroupName: String
    let mondaySyncStatus: Bool
    let mondaySyncComments: Bool
    let mondayStatusColumnId: String
    let mondayVotesColumnId: String
    let mondayIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct LinearSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let linearToken: String
    let linearTeamId: String
    let linearTeamName: String
    let linearProjectId: String
    let linearProjectName: String
    let linearDefaultLabelIds: String
    let linearSyncStatus: Bool
    let linearSyncComments: Bool
    let linearIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct AirtableSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let airtableToken: String
    let airtableBaseId: String
    let airtableBaseName: String
    let airtableTableId: String
    let airtableTableName: String
    let airtableSyncStatus: Bool
    let airtableSyncComments: Bool
    let airtableStatusFieldId: String
    let airtableVotesFieldId: String
    let airtableTitleFieldId: String
    let airtableDescriptionFieldId: String
    let airtableCategoryFieldId: String
    let airtableIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct AsanaSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let asanaToken: String
    let asanaWorkspaceId: String
    let asanaWorkspaceName: String
    let asanaProjectId: String
    let asanaProjectName: String
    let asanaSectionId: String
    let asanaSectionName: String
    let asanaSyncStatus: Bool
    let asanaSyncComments: Bool
    let asanaStatusFieldId: String
    let asanaVotesFieldId: String
    let asanaIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}

struct BasecampSettingsContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let project: ProjectContext
    let basecampAccessToken: String
    let basecampAccountId: String
    let basecampAccountName: String
    let basecampProjectId: String
    let basecampProjectName: String
    let basecampTodosetId: String
    let basecampTodolistId: String
    let basecampTodolistName: String
    let basecampSyncStatus: Bool
    let basecampSyncComments: Bool
    let basecampIsActive: Bool
    let isConfigured: Bool
    let isProTier: Bool
    let success: String?
    let error: String?
}
