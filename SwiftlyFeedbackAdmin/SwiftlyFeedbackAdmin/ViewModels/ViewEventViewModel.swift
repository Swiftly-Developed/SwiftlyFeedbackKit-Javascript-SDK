import Foundation
import SwiftUI
import OSLog

@MainActor
@Observable
final class ViewEventViewModel {
    var overview: ViewEventsOverview?
    var isLoading = false
    var showError = false
    var errorMessage: String?
    var searchText = ""
    var sortOrder: SortOrder = .totalCount

    enum SortOrder: String, CaseIterable {
        case totalCount = "Total Count"
        case uniqueUsers = "Unique Users"
        case eventName = "Event Name"

        var icon: String {
            switch self {
            case .totalCount: return "number"
            case .uniqueUsers: return "person.2"
            case .eventName: return "textformat"
            }
        }
    }

    private var currentProjectId: UUID?

    var filteredEvents: [ViewEventStats] {
        guard let overview = overview else { return [] }
        var result = overview.eventBreakdown

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { event in
                event.eventName.localizedCaseInsensitiveContains(searchText)
            }
            Logger.viewModel.debug("ViewEventViewModel: Filtered to \(result.count) events with search '\(self.searchText)'")
        }

        // Apply sort
        switch sortOrder {
        case .totalCount:
            result.sort { $0.totalCount > $1.totalCount }
        case .uniqueUsers:
            result.sort { $0.uniqueUsers > $1.uniqueUsers }
        case .eventName:
            result.sort { $0.eventName < $1.eventName }
        }

        return result
    }

    func loadEvents(projectId: UUID? = nil) async {
        Logger.viewModel.info("ViewEventViewModel: loadEvents called for projectId: \(projectId?.uuidString ?? "all")")

        guard !isLoading else {
            Logger.viewModel.warning("ViewEventViewModel: loadEvents skipped - already loading")
            return
        }

        currentProjectId = projectId
        isLoading = true
        Logger.viewModel.debug("ViewEventViewModel: Starting to load events...")

        do {
            Logger.viewModel.info("ViewEventViewModel: Fetching event stats...")

            let loadedOverview: ViewEventsOverview
            if let projectId = projectId {
                loadedOverview = try await AdminAPIClient.shared.getViewEventStats(projectId: projectId)
            } else {
                loadedOverview = try await AdminAPIClient.shared.getAllViewEventStats()
            }

            Logger.viewModel.info("ViewEventViewModel: Successfully loaded overview - totalEvents: \(loadedOverview.totalEvents), uniqueUsers: \(loadedOverview.uniqueUsers)")
            Logger.viewModel.info("ViewEventViewModel: Event breakdown count: \(loadedOverview.eventBreakdown.count)")

            overview = loadedOverview

            // Log first few events for debugging
            for (index, event) in loadedOverview.eventBreakdown.prefix(3).enumerated() {
                Logger.viewModel.debug("ViewEventViewModel: Event[\(index)] - name: \(event.eventName), count: \(event.totalCount), users: \(event.uniqueUsers)")
            }

        } catch let error as APIError {
            Logger.viewModel.error("ViewEventViewModel: APIError - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            Logger.viewModel.error("ViewEventViewModel: Unknown error - \(error.localizedDescription)")
            Logger.viewModel.error("ViewEventViewModel: Error type: \(type(of: error))")
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
        Logger.viewModel.debug("ViewEventViewModel: loadEvents completed, isLoading = false")
    }

    func refreshEvents() async {
        Logger.viewModel.info("ViewEventViewModel: refreshEvents called")
        await loadEvents(projectId: currentProjectId)
    }
}
