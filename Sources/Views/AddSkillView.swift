import SwiftUI

struct AddSkillView: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .git
    @State private var gitURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importedSkills: [Skill] = []
    @State private var showingFolderPicker = false
    @State private var selectedSkillIDs = Set<String>()

    enum Tab: String, CaseIterable, Identifiable {
        case local
        case git

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            SettingsPage {
                Picker("", selection: $selectedTab) {
                    Text(L.string("ui.add_skill.local_tab", using: lm)).tag(Tab.local)
                    Text(L.string("ui.add_skill.git_tab", using: lm)).tag(Tab.git)
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .local:
                    localTab
                case .git:
                    gitTab
                }
            }
            .navigationTitle(L.string("ui.add_skill.title", using: lm))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("ui.action.cancel", using: lm)) { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .onDisappear {
            manager.cleanupDiscovery()
        }
    }

    // MARK: - Local Tab

    private var localTab: some View {
        SettingsCard {
            SettingsRow {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        L.text("ui.add_skill.import_dir_title", using: lm)
                            .font(.subheadline.weight(.semibold))
                        L.text("ui.add_skill.import_dir_hint", using: lm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } trailing: {
                Button(L.string("ui.action.choose_directory", using: lm)) {
                    showingFolderPicker = true
                }
                .buttonStyle(.borderedProminent)
                .fileImporter(
                    isPresented: $showingFolderPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        do {
                            try manager.addSkill(fromDirectory: url)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }

            if let errorMessage {
                SettingsDivider()

                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Git Tab

    private var gitTab: some View {
        Group {
            SettingsCard {
                SettingsRow {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            L.text("ui.add_skill.import_git_title", using: lm)
                                .font(.subheadline.weight(.semibold))
                            L.text("ui.add_skill.import_git_hint", using: lm)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 6) {
                    L.text("ui.add_skill.repository_url", using: lm)
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        TextField(
                            "owner/repo or https://github.com/org/repo",
                            text: $gitURL
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button(L.string("ui.action.discover", using: lm)) {
                            discoverFromGit()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gitURL.isEmpty || manager.isDiscovering)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if manager.isDiscovering {
                    SettingsDivider()

                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        L.text("ui.add_skill.discovering", using: lm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                if let errorMessage {
                    SettingsDivider()

                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }

            if !manager.discoveredSkills.isEmpty {
                discoveredSkillsCard
            }

            if !importedSkills.isEmpty {
                importResultCard
            }

            supportedFormatsCard
        }
    }

    private var discoveredSkillsCard: some View {
        SettingsCard {
            HStack {
                L.text("ui.add_skill.discovered_count", Int64(manager.discoveredSkills.count), using: lm)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(L.string("ui.action.select_all", using: lm)) {
                    selectedSkillIDs = Set(manager.discoveredSkills.map(\.id))
                }
                .font(.caption)

                Button(L.string("ui.action.deselect_all", using: lm)) {
                    selectedSkillIDs.removeAll()
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 5)

            SettingsDivider()

            ForEach(manager.discoveredSkills) { discovered in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { selectedSkillIDs.contains(discovered.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedSkillIDs.insert(discovered.id)
                            } else {
                                selectedSkillIDs.remove(discovered.id)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(discovered.name)
                                .font(.subheadline.weight(.medium))
                            if discovered.metadataInternal {
                                Text(L.string("ui.badge.internal", using: lm))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(discovered.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let pluginName = discovered.pluginName {
                            Text(pluginName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(discovered.relativePath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            SettingsDivider()

            HStack {
                Spacer()
                Button(L.string("ui.action.import_selected", using: lm)) {
                    importSelectedFromGit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSkillIDs.isEmpty || isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var importResultCard: some View {
        SettingsCard {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                L.text("ui.add_skill.imported_count", Int64(importedSkills.count), using: lm)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 5)

            SettingsDivider()

            ForEach(importedSkills) { skill in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(skill.name)
                        .font(.subheadline)
                    if skill.version != nil {
                        Text("v\(skill.version!)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private var supportedFormatsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 2) {
                L.text("ui.add_skill.supported_formats", using: lm)
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 4)
                Text("owner/repo")
                Text("github.com/{owner}/{repo}")
                Text("github.com/{owner}/{repo}/tree/{branch}/{path}")
                Text("gitlab.com/{owner}/{repo}/-/tree/{branch}/{path}")
                Text("bitbucket.org/{owner}/{repo}/src/{branch}/{path}")
                Text("git@github.com:{owner}/{repo}.git")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
    }

    private func discoverFromGit() {
        errorMessage = nil
        importedSkills = []
        selectedSkillIDs.removeAll()

        Task {
            await manager.discoverSkills(fromGitURL: gitURL)
            // Select all by default
            selectedSkillIDs = Set(manager.discoveredSkills.map(\.id))
            if manager.discoveredSkills.isEmpty {
                errorMessage = L.string("error.no_skills_found", using: lm)
            }
        }
    }

    private func importSelectedFromGit() {
        errorMessage = nil
        importedSkills = []
        isLoading = true

        Task {
            let skills = await manager.importDiscoveredSkills(
                selectedIDs: selectedSkillIDs,
                sourceGitURL: gitURL
            )
            importedSkills = skills
            selectedSkillIDs.removeAll()
            isLoading = false
            if skills.isEmpty {
                errorMessage = L.string("error.no_valid_skills", using: lm)
            }
        }
    }
}
