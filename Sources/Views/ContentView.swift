import SwiftUI

struct ContentView: View {
    @Environment(LocalizationManager.self) private var lm
    @State private var manager = SkillManager()
    @State private var detailItem: SidebarItem?
    @State private var selectedItems = Set<SidebarItem>()
    @State private var isEditing = false
    @State private var showBatchDeleteConfirm = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showingAddSkill = false
    @State private var showingAgentManager = false
    @State private var showingCopyPanel = false

    private var selectedSkill: Skill? {
        if case .skill(let skill) = detailItem {
            return skill
        }
        return nil
    }

    private var selectedSkillCount: Int {
        selectedItems.filter {
            if case .skill = $0 { return true }
            return false
        }.count
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                manager: manager,
                detailItem: $detailItem,
                isEditing: $isEditing,
                selectedItems: $selectedItems
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $manager.searchText, placement: .sidebar, prompt: L.string("ui.search.placeholder", using: lm))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isEditing && selectedSkillCount > 0 {
                    Button {
                        showBatchDeleteConfirm = true
                    } label: {
                        Label(L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm), systemImage: "trash")
                    }
                    .tint(.red)
                }

                if isEditing {
                    Button {
                        isEditing = false
                    } label: {
                        L.text("ui.action.done", using: lm)
                    }
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Label(L.string("ui.action.edit", using: lm), systemImage: "checklist")
                    }
                }

                Button {
                    showingAddSkill = true
                } label: {
                    Label(L.string("ui.action.add_skill", using: lm), systemImage: "plus")
                }

                Button {
                    showingAgentManager = true
                } label: {
                    Label(L.string("ui.label.agents", using: lm), systemImage: "person.2")
                }

                Button {
                    Task {
                        try? await manager.syncAll()
                    }
                } label: {
                    Label(L.string("ui.action.sync", using: lm), systemImage: "arrow.triangle.2.circlepath")
                }

                if selectedSkill != nil {
                    Button {
                        showingCopyPanel = true
                    } label: {
                        Label(L.string("ui.action.copy_to_project", using: lm), systemImage: "doc.on.doc")
                    }
                    .help(L.string("ui.hint.copy_to_project", using: lm))
                }

                // Language picker
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            lm.currentLanguage = lang
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                if lm.currentLanguage == lang {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                }
            }
        }
        .alert(L.string("alert.delete.title", Int64(selectedSkillCount), using: lm), isPresented: $showBatchDeleteConfirm) {
            Button(L.string("ui.action.cancel", using: lm), role: .cancel) {}
            Button(L.string("ui.action.delete", using: lm), role: .destructive) {
                let skillsToDelete = selectedItems.compactMap { item -> Skill? in
                    if case .skill(let skill) = item { return skill }
                    return nil
                }
                manager.removeSkills(skillsToDelete)
                selectedItems.removeAll()
            }
        } message: {
            L.text("alert.delete.message", using: lm)
        }
        .sheet(isPresented: $showingAddSkill) {
            AddSkillView(manager: manager)
                .environment(lm)
        }
        .sheet(isPresented: $showingAgentManager) {
            AgentView(manager: manager)
                .environment(lm)
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
                    if let key = manager.statusMessageKey, let arg = manager.statusMessageArg {
                        L.text(key, arg, using: lm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let key = manager.statusMessageKey {
                        L.text(key, using: lm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        L.text("ui.label.loading", using: lm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: manager.statusMessageKey) { _, newValue in
            if newValue != nil, !manager.isLoading {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    manager.statusMessageKey = nil
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch detailItem {
        case .skill(let skill):
            SkillDetailView(manager: manager, skill: skill)
                .environment(lm)
        case .agent:
            AgentDetailView(manager: manager)
                .environment(lm)
        case .none:
            ContentUnavailableView {
                Label(L.string("ui.label.no_selection", using: lm), systemImage: "sidebar.left")
            } description: {
                L.text("ui.hint.select_from_sidebar", using: lm)
            }
        }
    }
}
