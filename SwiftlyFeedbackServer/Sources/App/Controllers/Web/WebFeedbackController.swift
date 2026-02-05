import Vapor
import Fluent
import Leaf

struct WebFeedbackController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let feedback = routes.grouped("feedback")

        feedback.get(use: index)
        feedback.get("kanban", use: kanban)
        feedback.get(":feedbackId", use: show)
        feedback.post(":feedbackId", "status", use: updateStatus)
        feedback.post(":feedbackId", "category", use: updateCategory)
        feedback.post(":feedbackId", "comment", use: addComment)
        feedback.post(":feedbackId", "delete", use: delete)
        feedback.post(":feedbackId", "integrations", use: createIntegrationTasks)
    }

    // MARK: - Feedback List

    @Sendable
    func index(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        // Get filter parameters
        let projectIdParam = req.query[UUID.self, at: "project_id"]
        let statusParam = req.query[String.self, at: "status"]
        let categoryParam = req.query[String.self, at: "category"]
        let searchParam = req.query[String.self, at: "q"]

        // Get accessible projects
        let accessibleProjects = try await getAccessibleProjects(req: req, userId: userId)

        guard !accessibleProjects.isEmpty else {
            return try await req.view.render("feedback/index", FeedbackListContext(
                title: "Feedback",
                pageTitle: "Feedback",
                currentPage: "feedback",
                user: UserContext(from: user),
                feedbacks: [],
                projects: [],
                selectedProjectId: nil,
                selectedStatus: nil,
                selectedCategory: nil,
                searchQuery: nil,
                statuses: FeedbackStatus.allCases.map { StatusOption(value: $0.rawValue, label: $0.displayName) },
                categories: categoryOptions
            ))
        }

        // Determine which project(s) to query
        let projectIds: [UUID]
        if let projectId = projectIdParam, accessibleProjects.contains(where: { $0.id == projectId }) {
            projectIds = [projectId]
        } else {
            projectIds = accessibleProjects.compactMap { $0.id }
        }

        // Build query
        var query = Feedback.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .filter(\.$mergedIntoId == nil)
            .with(\.$project)

        if let status = statusParam, let feedbackStatus = FeedbackStatus(rawValue: status) {
            query = query.filter(\.$status == feedbackStatus)
        }

        if let category = categoryParam, let feedbackCategory = FeedbackCategory(rawValue: category) {
            query = query.filter(\.$category == feedbackCategory)
        }

        // Note: Search would require full-text search or LIKE queries
        // For simplicity, we'll filter in memory for small datasets
        var feedbacks = try await query.sort(\.$createdAt, .descending).all()

        if let search = searchParam, !search.isEmpty {
            let searchLower = search.lowercased()
            feedbacks = feedbacks.filter {
                $0.title.lowercased().contains(searchLower) ||
                $0.description.lowercased().contains(searchLower)
            }
        }

        let feedbackItems = try feedbacks.map { feedback in
            FeedbackListItem(
                id: try feedback.requireID(),
                title: feedback.title,
                description: String(feedback.description.prefix(150)),
                status: feedback.status.rawValue,
                statusDisplay: feedback.status.displayName,
                statusColor: feedback.status.colorClass,
                category: feedback.category.rawValue,
                categoryDisplay: feedback.category.displayName,
                voteCount: feedback.voteCount,
                projectName: feedback.$project.value?.name ?? "Unknown",
                projectColor: projectColors[(feedback.$project.value?.colorIndex ?? 0) % projectColors.count].bgClass,
                createdAt: formatRelativeDate(feedback.createdAt)
            )
        }

        let projectOptions = accessibleProjects.map { project in
            ProjectOption(
                id: project.id ?? UUID(),
                name: project.name,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass
            )
        }

        return try await req.view.render("feedback/index", FeedbackListContext(
            title: "Feedback",
            pageTitle: "Feedback",
            currentPage: "feedback",
            user: UserContext(from: user),
            feedbacks: feedbackItems,
            projects: projectOptions,
            selectedProjectId: projectIdParam,
            selectedStatus: statusParam,
            selectedCategory: categoryParam,
            searchQuery: searchParam,
            statuses: FeedbackStatus.allCases.map { StatusOption(value: $0.rawValue, label: $0.displayName) },
            categories: categoryOptions
        ))
    }

    // MARK: - Kanban Board

    @Sendable
    func kanban(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        let projectIdParam = req.query[UUID.self, at: "project_id"]

        let accessibleProjects = try await getAccessibleProjects(req: req, userId: userId)

        guard !accessibleProjects.isEmpty else {
            return try await req.view.render("feedback/kanban", KanbanContext(
                title: "Kanban",
                pageTitle: "Kanban Board",
                currentPage: "feedback",
                user: UserContext(from: user),
                columns: [],
                projects: [],
                selectedProjectId: nil
            ))
        }

        let projectIds: [UUID]
        if let projectId = projectIdParam, accessibleProjects.contains(where: { $0.id == projectId }) {
            projectIds = [projectId]
        } else {
            projectIds = accessibleProjects.compactMap { $0.id }
        }

        let feedbacks = try await Feedback.query(on: req.db)
            .filter(\.$project.$id ~~ projectIds)
            .filter(\.$mergedIntoId == nil)
            .with(\.$project)
            .sort(\.$voteCount, .descending)
            .all()

        // Group by status
        var feedbacksByStatus: [FeedbackStatus: [Feedback]] = [:]
        for status in FeedbackStatus.allCases {
            feedbacksByStatus[status] = []
        }
        for feedback in feedbacks {
            feedbacksByStatus[feedback.status, default: []].append(feedback)
        }

        let columns = try FeedbackStatus.allCases.map { status in
            KanbanColumn(
                status: status.rawValue,
                name: status.displayName,
                colorClass: status.colorClass,
                feedbacks: try feedbacksByStatus[status]!.map { feedback in
                    KanbanCard(
                        id: try feedback.requireID(),
                        title: feedback.title,
                        category: feedback.category.displayName,
                        voteCount: feedback.voteCount,
                        projectName: feedback.$project.value?.name ?? ""
                    )
                }
            )
        }

        let projectOptions = accessibleProjects.map { project in
            ProjectOption(
                id: project.id ?? UUID(),
                name: project.name,
                colorClass: projectColors[project.colorIndex % projectColors.count].bgClass
            )
        }

        return try await req.view.render("feedback/kanban", KanbanContext(
            title: "Kanban",
            pageTitle: "Kanban Board",
            currentPage: "feedback",
            user: UserContext(from: user),
            columns: columns,
            projects: projectOptions,
            selectedProjectId: projectIdParam
        ))
    }

    // MARK: - Feedback Detail

    @Sendable
    func show(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.query(on: req.db)
            .filter(\.$id == feedbackId)
            .with(\.$project)
            .with(\.$comments)
            .first() else {
            throw Abort(.notFound)
        }

        // Check access
        let projectId = feedback.$project.id
        let hasAccess = try await checkProjectAccess(req: req, userId: userId, projectId: projectId)
        guard hasAccess else {
            throw Abort(.forbidden)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: projectId)

        let comments = feedback.comments.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
        let commentItems = comments.map { comment in
            CommentItem(
                id: comment.id ?? UUID(),
                content: comment.content,
                userId: comment.userId,
                isAdmin: comment.isAdmin,
                createdAt: formatRelativeDate(comment.createdAt)
            )
        }

        let feedbackDetail = FeedbackDetail(
            id: try feedback.requireID(),
            title: feedback.title,
            description: feedback.description,
            status: feedback.status.rawValue,
            statusDisplay: feedback.status.displayName,
            statusColor: feedback.status.colorClass,
            category: feedback.category.rawValue,
            categoryDisplay: feedback.category.displayName,
            voteCount: feedback.voteCount,
            userId: feedback.userId,
            userEmail: feedback.userEmail,
            projectId: projectId,
            projectName: feedback.$project.value?.name ?? "Unknown",
            createdAt: formatDate(feedback.createdAt),
            updatedAt: formatDate(feedback.updatedAt),
            rejectionReason: feedback.rejectionReason,
            isMerged: feedback.isMerged,
            hasMergedFeedback: feedback.hasMergedFeedback,
            mergedFeedbackCount: feedback.mergedFeedbackIds?.count ?? 0
        )

        // Get project for integration availability
        let project = feedback.$project.value!

        let integrations = IntegrationAvailability(
            // Available (configured and active)
            clickup: project.clickupToken != nil && project.clickupListId != nil && project.clickupIsActive,
            github: project.githubToken != nil && project.githubOwner != nil && project.githubRepo != nil && project.githubIsActive,
            linear: project.linearToken != nil && project.linearTeamId != nil && project.linearIsActive,
            notion: project.notionToken != nil && project.notionDatabaseId != nil && project.notionIsActive,
            trello: project.trelloToken != nil && project.trelloBoardId != nil && project.trelloListId != nil && project.trelloIsActive,
            monday: project.mondayToken != nil && project.mondayBoardId != nil && project.mondayIsActive,
            airtable: project.airtableToken != nil && project.airtableBaseId != nil && project.airtableTableId != nil && project.airtableIsActive,
            asana: project.asanaToken != nil && project.asanaProjectId != nil && project.asanaIsActive,
            basecamp: project.basecampAccessToken != nil && project.basecampProjectId != nil && project.basecampTodolistId != nil && project.basecampIsActive,
            // Already linked to this feedback
            clickupLinked: feedback.clickupTaskId != nil,
            githubLinked: feedback.githubIssueNumber != nil,
            linearLinked: feedback.linearIssueId != nil,
            notionLinked: feedback.notionPageId != nil,
            trelloLinked: feedback.trelloCardId != nil,
            mondayLinked: feedback.mondayItemId != nil,
            airtableLinked: feedback.airtableRecordId != nil,
            asanaLinked: feedback.asanaTaskId != nil,
            basecampLinked: feedback.basecampTodoId != nil
        )

        return try await req.view.render("feedback/show", FeedbackDetailContext(
            title: feedback.title,
            pageTitle: "Feedback Details",
            currentPage: "feedback",
            user: UserContext(from: user),
            feedback: feedbackDetail,
            comments: commentItems,
            canEdit: role == .owner || role == .admin,
            canDelete: role == .owner || role == .admin,
            statuses: FeedbackStatus.allCases.map { StatusOption(value: $0.rawValue, label: $0.displayName) },
            categories: categoryOptions,
            success: req.query[String.self, at: "success"],
            error: req.query[String.self, at: "error"],
            integrations: integrations
        ))
    }

    // MARK: - Update Status

    @Sendable
    func updateStatus(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let form = try req.content.decode(UpdateStatusForm.self)
        if let newStatus = FeedbackStatus(rawValue: form.status) {
            feedback.status = newStatus
            if newStatus == .rejected {
                feedback.rejectionReason = form.rejectionReason
            } else {
                feedback.rejectionReason = nil
            }
            try await feedback.save(on: req.db)
        }

        return req.redirect(to: "/admin/feedback/\(feedbackId)?success=status_updated")
    }

    // MARK: - Update Category

    @Sendable
    func updateCategory(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let form = try req.content.decode(UpdateCategoryForm.self)
        if let newCategory = FeedbackCategory(rawValue: form.category) {
            feedback.category = newCategory
            try await feedback.save(on: req.db)
        }

        return req.redirect(to: "/admin/feedback/\(feedbackId)?success=category_updated")
    }

    // MARK: - Add Comment

    @Sendable
    func addComment(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        // Check access
        let hasAccess = try await checkProjectAccess(req: req, userId: userId, projectId: feedback.$project.id)
        guard hasAccess else {
            throw Abort(.forbidden)
        }

        // Check if project is archived
        if let project = try await Project.find(feedback.$project.id, on: req.db), project.isArchived {
            return req.redirect(to: "/admin/feedback/\(feedbackId)?error=project_archived")
        }

        let form = try req.content.decode(AddCommentForm.self)

        let comment = Comment(
            content: form.content.trimmingCharacters(in: .whitespacesAndNewlines),
            userId: userId.uuidString,
            isAdmin: true,
            feedbackId: feedbackId
        )
        try await comment.save(on: req.db)

        return req.redirect(to: "/admin/feedback/\(feedbackId)?success=comment_added")
    }

    // MARK: - Delete Feedback

    @Sendable
    func delete(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.find(feedbackId, on: req.db) else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let projectId = feedback.$project.id
        try await feedback.delete(on: req.db)

        return req.redirect(to: "/admin/feedback?project_id=\(projectId)")
    }

    // MARK: - Create Integration Tasks

    struct CreateIntegrationsForm: Content {
        var clickup: String?
        var github: String?
        var linear: String?
        var notion: String?
        var trello: String?
        var monday: String?
        var airtable: String?
        var asana: String?
        var basecamp: String?
    }

    @Sendable
    func createIntegrationTasks(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let feedbackId = req.parameters.get("feedbackId", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard let feedback = try await Feedback.query(on: req.db)
            .filter(\.$id == feedbackId)
            .with(\.$project)
            .first() else {
            throw Abort(.notFound)
        }

        let role = try await getProjectRole(req: req, userId: userId, projectId: feedback.$project.id)
        guard role == .owner || role == .admin else {
            throw Abort(.forbidden)
        }

        let form = try req.content.decode(CreateIntegrationsForm.self)
        let project = feedback.$project.value!

        var createdCount = 0
        var errors: [String] = []

        // ClickUp
        if form.clickup == "on" && project.clickupToken != nil && project.clickupListId != nil && feedback.clickupTaskId == nil {
            do {
                let description = req.clickupService.buildTaskDescription(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let tags = project.clickupDefaultTags ?? []
                let result = try await req.clickupService.createTask(
                    listId: project.clickupListId!,
                    token: project.clickupToken!,
                    name: feedback.title,
                    markdownDescription: description,
                    tags: tags.isEmpty ? nil : tags
                )
                feedback.clickupTaskId = result.id
                feedback.clickupTaskURL = result.url
                createdCount += 1
            } catch {
                errors.append("ClickUp: \(error.localizedDescription)")
            }
        }

        // GitHub
        if form.github == "on" && project.githubToken != nil && project.githubOwner != nil && project.githubRepo != nil && feedback.githubIssueNumber == nil {
            do {
                let body = req.githubService.buildIssueBody(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let labels = project.githubDefaultLabels ?? []
                let result = try await req.githubService.createIssue(
                    owner: project.githubOwner!,
                    repo: project.githubRepo!,
                    token: project.githubToken!,
                    title: feedback.title,
                    body: body,
                    labels: labels.isEmpty ? nil : labels
                )
                feedback.githubIssueNumber = result.number
                feedback.githubIssueURL = result.htmlUrl
                createdCount += 1
            } catch {
                errors.append("GitHub: \(error.localizedDescription)")
            }
        }

        // Linear
        if form.linear == "on" && project.linearToken != nil && project.linearTeamId != nil && feedback.linearIssueId == nil {
            do {
                let description = req.linearService.buildIssueDescription(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let labelIds = project.linearDefaultLabelIds ?? []
                let result = try await req.linearService.createIssue(
                    teamId: project.linearTeamId!,
                    projectId: project.linearProjectId,
                    title: feedback.title,
                    description: description,
                    labelIds: labelIds.isEmpty ? nil : labelIds,
                    token: project.linearToken!
                )
                feedback.linearIssueId = result.id
                feedback.linearIssueURL = result.url
                createdCount += 1
            } catch {
                errors.append("Linear: \(error.localizedDescription)")
            }
        }

        // Notion
        if form.notion == "on" && project.notionToken != nil && project.notionDatabaseId != nil && feedback.notionPageId == nil {
            do {
                let content = req.notionService.buildPageContent(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let properties = req.notionService.buildPageProperties(
                    feedback: feedback,
                    voteCount: feedback.voteCount,
                    mrr: nil,
                    statusProperty: project.notionStatusProperty,
                    votesProperty: project.notionVotesProperty
                )
                let result = try await req.notionService.createPage(
                    databaseId: project.notionDatabaseId!,
                    token: project.notionToken!,
                    title: feedback.title,
                    properties: properties,
                    content: content
                )
                feedback.notionPageId = result.id
                feedback.notionPageURL = result.url
                createdCount += 1
            } catch {
                errors.append("Notion: \(error.localizedDescription)")
            }
        }

        // Trello
        if form.trello == "on" && project.trelloToken != nil && project.trelloListId != nil && feedback.trelloCardId == nil {
            do {
                let description = req.trelloService.buildCardDescription(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let result = try await req.trelloService.createCard(
                    token: project.trelloToken!,
                    listId: project.trelloListId!,
                    name: feedback.title,
                    description: description
                )
                feedback.trelloCardId = result.id
                feedback.trelloCardURL = result.url
                createdCount += 1
            } catch {
                errors.append("Trello: \(error.localizedDescription)")
            }
        }

        // Monday
        if form.monday == "on" && project.mondayToken != nil && project.mondayBoardId != nil && feedback.mondayItemId == nil {
            do {
                let item = try await req.mondayService.createItem(
                    boardId: project.mondayBoardId!,
                    groupId: project.mondayGroupId,
                    token: project.mondayToken!,
                    name: feedback.title
                )
                let itemUrl = req.mondayService.buildItemURL(boardId: project.mondayBoardId!, itemId: item.id)
                feedback.mondayItemId = item.id
                feedback.mondayItemURL = itemUrl
                createdCount += 1

                // Create update with description (fire and forget)
                let description = req.mondayService.buildItemDescription(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                Task {
                    _ = try? await req.mondayService.createUpdate(
                        itemId: item.id,
                        token: project.mondayToken!,
                        body: description
                    )
                }
            } catch {
                errors.append("Monday: \(error.localizedDescription)")
            }
        }

        // Airtable
        if form.airtable == "on" && project.airtableToken != nil && project.airtableBaseId != nil && project.airtableTableId != nil && feedback.airtableRecordId == nil {
            do {
                let fields = req.airtableService.buildRecordFields(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil,
                    titleFieldName: project.airtableTitleFieldId,
                    descriptionFieldName: project.airtableDescriptionFieldId,
                    categoryFieldName: project.airtableCategoryFieldId,
                    statusFieldName: project.airtableStatusFieldId,
                    votesFieldName: project.airtableVotesFieldId
                )
                let record = try await req.airtableService.createRecord(
                    baseId: project.airtableBaseId!,
                    tableId: project.airtableTableId!,
                    token: project.airtableToken!,
                    fields: fields
                )
                let recordUrl = req.airtableService.buildRecordURL(
                    baseId: project.airtableBaseId!,
                    tableId: project.airtableTableId!,
                    recordId: record.id
                )
                feedback.airtableRecordId = record.id
                feedback.airtableRecordURL = recordUrl
                createdCount += 1
            } catch {
                errors.append("Airtable: \(error.localizedDescription)")
            }
        }

        // Asana
        if form.asana == "on" && project.asanaToken != nil && project.asanaProjectId != nil && feedback.asanaTaskId == nil {
            do {
                let notes = req.asanaService.buildTaskNotes(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let task = try await req.asanaService.createTask(
                    projectId: project.asanaProjectId!,
                    sectionId: project.asanaSectionId,
                    token: project.asanaToken!,
                    name: feedback.title,
                    notes: notes,
                    customFields: nil
                )
                let taskUrl = task.permalinkUrl ?? req.asanaService.buildTaskURL(projectId: project.asanaProjectId!, taskId: task.gid)
                feedback.asanaTaskId = task.gid
                feedback.asanaTaskURL = taskUrl
                createdCount += 1
            } catch {
                errors.append("Asana: \(error.localizedDescription)")
            }
        }

        // Basecamp
        if form.basecamp == "on" && project.basecampAccessToken != nil && project.basecampProjectId != nil && project.basecampTodolistId != nil && feedback.basecampTodoId == nil {
            do {
                let description = req.basecampService.buildTodoDescription(
                    feedback: feedback,
                    projectName: project.name,
                    voteCount: feedback.voteCount,
                    mrr: nil
                )
                let todo = try await req.basecampService.createTodo(
                    accountId: project.basecampAccountId!,
                    projectId: project.basecampProjectId!,
                    todolistId: project.basecampTodolistId!,
                    token: project.basecampAccessToken!,
                    title: feedback.title,
                    description: description
                )
                feedback.basecampTodoId = String(todo.id)
                feedback.basecampTodoURL = todo.appUrl
                feedback.basecampBucketId = project.basecampProjectId
                createdCount += 1
            } catch {
                errors.append("Basecamp: \(error.localizedDescription)")
            }
        }

        // Save feedback with linked IDs
        try await feedback.save(on: req.db)

        if errors.isEmpty {
            return req.redirect(to: "/admin/feedback/\(feedbackId)?success=integrations_created")
        } else {
            return req.redirect(to: "/admin/feedback/\(feedbackId)?error=some_integrations_failed")
        }
    }

    // MARK: - Helpers

    private func getAccessibleProjects(req: Request, userId: UUID) async throws -> [Project] {
        let ownedProjects = try await Project.query(on: req.db)
            .filter(\.$owner.$id == userId)
            .filter(\.$isArchived == false)
            .all()

        let memberProjects = try await Project.query(on: req.db)
            .join(ProjectMember.self, on: \Project.$id == \ProjectMember.$project.$id)
            .filter(ProjectMember.self, \.$user.$id == userId)
            .filter(\.$isArchived == false)
            .all()

        return ownedProjects + memberProjects
    }

    private func checkProjectAccess(req: Request, userId: UUID, projectId: UUID) async throws -> Bool {
        if let project = try await Project.find(projectId, on: req.db) {
            if project.$owner.id == userId {
                return true
            }
        }

        let member = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == userId)
            .first()

        return member != nil
    }

    private func getProjectRole(req: Request, userId: UUID, projectId: UUID) async throws -> WebProjectRole {
        if let project = try await Project.find(projectId, on: req.db) {
            if project.$owner.id == userId {
                return .owner
            }
        }

        if let member = try await ProjectMember.query(on: req.db)
            .filter(\.$project.$id == projectId)
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

    private func formatRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h ago"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d ago"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            return dateFormatter.string(from: date)
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Form DTOs

struct UpdateStatusForm: Content {
    let status: String
    let rejectionReason: String?
}

struct UpdateCategoryForm: Content {
    let category: String
}

struct AddCommentForm: Content {
    let content: String
}

// MARK: - View Contexts

struct FeedbackListContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let feedbacks: [FeedbackListItem]
    let projects: [ProjectOption]
    let selectedProjectId: UUID?
    let selectedStatus: String?
    let selectedCategory: String?
    let searchQuery: String?
    let statuses: [StatusOption]
    let categories: [CategoryOption]
}

struct FeedbackListItem: Encodable {
    let id: UUID
    let title: String
    let description: String
    let status: String
    let statusDisplay: String
    let statusColor: String
    let category: String
    let categoryDisplay: String
    let voteCount: Int
    let projectName: String
    let projectColor: String
    let createdAt: String
}

struct KanbanContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let columns: [KanbanColumn]
    let projects: [ProjectOption]
    let selectedProjectId: UUID?
}

struct KanbanColumn: Encodable {
    let status: String
    let name: String
    let colorClass: String
    let feedbacks: [KanbanCard]
}

struct KanbanCard: Encodable {
    let id: UUID
    let title: String
    let category: String
    let voteCount: Int
    let projectName: String
}

struct FeedbackDetailContext: Encodable {
    let title: String
    let pageTitle: String
    let currentPage: String
    let user: UserContext
    let feedback: FeedbackDetail
    let comments: [CommentItem]
    let canEdit: Bool
    let canDelete: Bool
    let statuses: [StatusOption]
    let categories: [CategoryOption]
    let success: String?
    let error: String?
    let integrations: IntegrationAvailability
}

struct IntegrationAvailability: Encodable {
    let clickup: Bool
    let github: Bool
    let linear: Bool
    let notion: Bool
    let trello: Bool
    let monday: Bool
    let airtable: Bool
    let asana: Bool
    let basecamp: Bool

    // Already linked
    let clickupLinked: Bool
    let githubLinked: Bool
    let linearLinked: Bool
    let notionLinked: Bool
    let trelloLinked: Bool
    let mondayLinked: Bool
    let airtableLinked: Bool
    let asanaLinked: Bool
    let basecampLinked: Bool
}

struct FeedbackDetail: Encodable {
    let id: UUID
    let title: String
    let description: String
    let status: String
    let statusDisplay: String
    let statusColor: String
    let category: String
    let categoryDisplay: String
    let voteCount: Int
    let userId: String
    let userEmail: String?
    let projectId: UUID
    let projectName: String
    let createdAt: String
    let updatedAt: String
    let rejectionReason: String?
    let isMerged: Bool
    let hasMergedFeedback: Bool
    let mergedFeedbackCount: Int
}

struct CommentItem: Encodable {
    let id: UUID
    let content: String
    let userId: String
    let isAdmin: Bool
    let createdAt: String
}

struct ProjectOption: Encodable {
    let id: UUID
    let name: String
    let colorClass: String
}

struct StatusOption: Encodable {
    let value: String
    let label: String
}

struct CategoryOption: Encodable {
    let value: String
    let label: String
}

let categoryOptions: [CategoryOption] = [
    CategoryOption(value: "feature_request", label: "Feature Request"),
    CategoryOption(value: "bug_report", label: "Bug Report"),
    CategoryOption(value: "improvement", label: "Improvement"),
    CategoryOption(value: "other", label: "Other")
]
