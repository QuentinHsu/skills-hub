import SwiftUI

struct ContentView: View {
    @State private var manager = SkillManager()
    @State private var selectedItem: SidebarItem?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showingAddSkill = false
    @State private var showingAgentManager = false
    @State private var showingCopyPanel = false

    private var selectedSkill: Skill? {
        if case .skill(let skill) = selectedItem {
            return skill
        }
        return nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(manager: manager, selectedItem: $selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $manager.searchText, placement: .sidebar, prompt: "Search skills...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddSkill = true
                } label: {
                    Label("Add Skill", systemImage: "plus")
                }

                Button {
                    showingAgentManager = true
                } label: {
                    Label("Agents", systemImage: "person.2")
                }

                Button {
                    Task {
                        try? await manager.syncAll()
                    }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }

                if selectedSkill != nil {
                    Button {
                        showingCopyPanel = true
                    } label: {
                        Label("Copy to Project", systemImage: "doc.on.doc")
                    }
                    .help("Copy this skill to a project directory")
                }
            }
        }
        .sheet(isPresented: $showingAddSkill) {
            AddSkillView(manager: manager)
        }
        .sheet(isPresented: $showingAgentManager) {
            AgentView(manager: manager)
        }
        .fileImporter(
            isPresented: $showingCopyPanel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let dir = urls.first,
               let skill = selectedSkill
            {
                Task {
                    try? manager.copySkill(skill, to: dir)
                }
            }
        }
        .onAppear {
            manager.scan()
        }
        .overlay {
            if manager.isLoading {
                VStack {
                    ProgressView()
                    Text(manager.statusMessage ?? "Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: manager.statusMessage) { _, newValue in
            if newValue != nil, !manager.isLoading {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    manager.statusMessage = nil
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .skill(let skill):
            SkillDetailView(manager: manager, skill: skill)
        case .agent:
            AgentDetailView(manager: manager)
        case .none:
            ContentUnavailableView {
                Label("No Selection", systemImage: "sidebar.left")
            } description: {
                Text("Select a skill or agent from the sidebar.")
            }
        }
    }
}
