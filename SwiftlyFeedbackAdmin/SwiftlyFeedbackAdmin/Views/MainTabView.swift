import SwiftUI

struct MainTabView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var projectViewModel = ProjectViewModel()
    @State private var hasLoadedProjects = false

    var body: some View {
        #if os(macOS)
        MacNavigationView(authViewModel: authViewModel, projectViewModel: projectViewModel)
            .task {
                await loadProjectsOnce()
            }
        #else
        TabView {
            ProjectListView(viewModel: projectViewModel)
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }

            SettingsView(authViewModel: authViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await loadProjectsOnce()
        }
        #endif
    }

    private func loadProjectsOnce() async {
        guard !hasLoadedProjects else { return }
        hasLoadedProjects = true
        await projectViewModel.loadProjects()
    }
}

// MARK: - macOS Navigation View

#if os(macOS)
struct MacNavigationView: View {
    @Bindable var authViewModel: AuthViewModel
    @Bindable var projectViewModel: ProjectViewModel
    @State private var selectedSection: SidebarSection? = .projects

    enum SidebarSection: String, CaseIterable, Identifiable {
        case projects = "Projects"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .projects: return "folder"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                switch selectedSection {
                case .projects:
                    ProjectListView(viewModel: projectViewModel)
                case .settings:
                    SettingsView(authViewModel: authViewModel)
                case nil:
                    ContentUnavailableView("Select a Section", systemImage: "sidebar.left", description: Text("Choose a section from the sidebar"))
                }
            }
        }
    }
}
#endif

#Preview {
    MainTabView(authViewModel: AuthViewModel())
}
