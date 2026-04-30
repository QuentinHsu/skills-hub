import AppKit
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
    @State private var showingSettings = false
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
            toolbarContent
        }
        .background(ToolbarCustomizationDisabler().frame(width: 0, height: 0))
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(manager: manager)
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing && selectedSkillCount > 0 {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBatchDeleteConfirm = true
                } label: {
                    Label(
                        L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm),
                        systemImage: "trash"
                    )
                }
                .tint(.red)
                .help(L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm))
                .accessibilityLabel(L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if isEditing {
                Button {
                    isEditing = false
                } label: {
                    Label(L.string("ui.action.done", using: lm), systemImage: "checkmark")
                }
                .help(L.string("ui.action.done", using: lm))
                .accessibilityLabel(L.string("ui.action.done", using: lm))
            } else {
                Button {
                    isEditing = true
                } label: {
                    Label(L.string("ui.action.edit", using: lm), systemImage: "checklist")
                }
                .help(L.string("ui.action.edit", using: lm))
                .accessibilityLabel(L.string("ui.action.edit", using: lm))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAddSkill = true
            } label: {
                Label(L.string("ui.action.add_skill", using: lm), systemImage: "plus")
            }
            .help(L.string("ui.action.add_skill", using: lm))
            .accessibilityLabel(L.string("ui.action.add_skill", using: lm))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task {
                    await manager.updateAllFromSources()
                }
            } label: {
                Label(L.string("ui.action.update", using: lm), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(manager.isLoading)
            .help(L.string("ui.action.update", using: lm))
            .accessibilityLabel(L.string("ui.action.update", using: lm))
        }

        if selectedSkill != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCopyPanel = true
                } label: {
                    Label(L.string("ui.action.copy_to_project", using: lm), systemImage: "folder.badge.plus")
                }
                .help(L.string("ui.hint.copy_to_project", using: lm))
                .accessibilityLabel(L.string("ui.action.copy_to_project", using: lm))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    copySelectedSkillMarkdown()
                } label: {
                    Label(L.string("ui.skill.copy_md", using: lm), systemImage: "doc.on.doc")
                }
                .help(L.string("ui.skill.copy_md", using: lm))
                .accessibilityLabel(L.string("ui.skill.copy_md", using: lm))
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    revealSelectedSkillInFinder()
                } label: {
                    Label(L.string("ui.skill.reveal_in_finder", using: lm), systemImage: "folder")
                }
                .help(L.string("ui.skill.reveal_in_finder", using: lm))
                .accessibilityLabel(L.string("ui.skill.reveal_in_finder", using: lm))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showingSettings = true
            } label: {
                Label(L.string("ui.settings.title", using: lm), systemImage: "gearshape")
            }
            .help(L.string("ui.settings.title", using: lm))
            .accessibilityLabel(L.string("ui.settings.title", using: lm))
        }
    }

    private func copySelectedSkillMarkdown() {
        guard let selectedSkill,
              let content = try? String(contentsOf: selectedSkill.skillMdURL, encoding: .utf8)
        else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func revealSelectedSkillInFinder() {
        guard let selectedSkill else { return }

        NSWorkspace.shared.selectFile(
            selectedSkill.skillMdURL.path(),
            inFileViewerRootedAtPath: selectedSkill.directoryURL.path()
        )
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

private struct ToolbarCustomizationDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarCustomizationView {
        ToolbarCustomizationView()
    }

    func updateNSView(_ nsView: ToolbarCustomizationView, context: Context) {
        nsView.configureToolbar()
        nsView.configureToolbarOnNextRunLoop()
    }
}

private final class ToolbarCustomizationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureToolbar()
        configureToolbarOnNextRunLoop()
    }

    func configureToolbar() {
        guard let toolbar = window?.toolbar else { return }

        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
    }

    func configureToolbarOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.configureToolbar()
        }
    }
}
