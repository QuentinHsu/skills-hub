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
            return manager.skills.first { $0.id == skill.id } ?? skill
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
                        await manager.updateAllFromSources()
                    }
                } label: {
                    Label(L.string("ui.action.update", using: lm), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(manager.isLoading)

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
            if manager.isLoading || manager.statusMessageKey != nil {
                VStack(spacing: 8) {
                    if manager.isLoading, manager.progressTotal > 0 {
                        ProgressView(
                            value: Double(manager.progressCurrent),
                            total: Double(manager.progressTotal)
                        )
                        .frame(width: 240)
                    } else if manager.isLoading {
                        ProgressView()
                    }

                    statusText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onChange(of: manager.statusMessageKey) { _, newValue in
            if newValue != nil {
                clearStatusMessageWhenIdle()
            }
        }
        .onChange(of: manager.isLoading) { _, isLoading in
            if !isLoading, manager.statusMessageKey != nil {
                clearStatusMessageWhenIdle()
            }
        }
        .onChange(of: manager.skillsRevision) {
            refreshSelectionFromLatestSkills()
        }
    }

    private var statusText: Text {
        if let key = manager.progressMessageKey,
           let item = manager.progressItemName,
           manager.progressTotal > 0
        {
            return L.text(key, manager.progressCurrent, manager.progressTotal, item, using: lm)
        }

        if let key = manager.statusMessageKey,
           let arg = manager.statusMessageArg,
           let arg2 = manager.statusMessageArg2
        {
            return L.text(key, arg, arg2, using: lm)
        }

        if let key = manager.statusMessageKey, let arg = manager.statusMessageArg {
            return L.text(key, arg, using: lm)
        }

        if let key = manager.statusMessageKey {
            return L.text(key, using: lm)
        }

        return L.text("ui.label.loading", using: lm)
    }

    private func clearStatusMessageWhenIdle() {
        guard !manager.isLoading else { return }

        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !manager.isLoading else { return }
            manager.statusMessageKey = nil
            manager.statusMessageArg = nil
            manager.statusMessageArg2 = nil
        }
    }

    private func refreshSelectionFromLatestSkills() {
        detailItem = refreshedItem(detailItem)
        selectedItems = Set(selectedItems.compactMap(refreshedItem))
    }

    private func refreshedItem(_ item: SidebarItem?) -> SidebarItem? {
        guard let item else { return nil }

        switch item {
        case .skill(let skill):
            guard let latest = manager.skills.first(where: { $0.id == skill.id }) else {
                return nil
            }
            return .skill(latest)
        case .agent(let agent):
            let latest = manager.agents.first(where: { $0.id == agent.id }) ?? agent
            return .agent(latest)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch detailItem {
        case .skill:
            SkillDetailView(manager: manager, skill: selectedSkill)
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
            .navigationTitle("Skills Hub")
        }
    }
}
