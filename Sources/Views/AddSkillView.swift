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
        VStack(spacing: 0) {
            // Title bar
            HStack {
                L.text("ui.add_skill.title", using: lm)
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Segmented picker
            Picker("", selection: $selectedTab) {
                Text(L.string("ui.add_skill.local_tab", using: lm)).tag(Tab.local)
                Text(L.string("ui.add_skill.git_tab", using: lm)).tag(Tab.git)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Divider()

            // Scrollable content
            ScrollView {
                switch selectedTab {
                case .local:
                    localTab
                case .git:
                    gitTab
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    L.text("ui.add_skill.import_dir_title", using: lm)
                        .font(.headline)
                    L.text("ui.add_skill.import_dir_hint", using: lm)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)

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

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Git Tab

    private var gitTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    L.text("ui.add_skill.import_git_title", using: lm)
                        .font(.headline)
                    L.text("ui.add_skill.import_git_hint", using: lm)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)

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

            if manager.isDiscovering {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    L.text("ui.add_skill.discovering", using: lm)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Discovered skills selection
            if !manager.discoveredSkills.isEmpty {
                discoveredSkillsList
            }

            // Import result
            if !importedSkills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    L.text("ui.add_skill.imported_count", [Int64(importedSkills.count)], using: lm)
                        .font(.caption.bold())
                    ForEach(importedSkills) { skill in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(skill.name)
                                .font(.caption)
                            if skill.version != nil {
                                Text("v\(skill.version!)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                L.text("ui.add_skill.supported_formats", using: lm)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("owner/repo")
                Text("github.com/{owner}/{repo}")
                Text("github.com/{owner}/{repo}/tree/{branch}/{path}")
                Text("gitlab.com/{owner}/{repo}/-/tree/{branch}/{path}")
                Text("bitbucket.org/{owner}/{repo}/src/{branch}/{path}")
                Text("git@github.com:{owner}/{repo}.git")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var discoveredSkillsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                L.text("ui.add_skill.discovered_count", [Int64(manager.discoveredSkills.count)], using: lm)
                    .font(.caption.bold())
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
                                    .background(.orange.opacity(0.2), in: Capsule())
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
                    }
                }
                .padding(.vertical, 2)
            }

            Button(L.string("ui.action.import_selected", using: lm)) {
                importSelectedFromGit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSkillIDs.isEmpty || isLoading)
        }
        .padding(10)
        .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
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
