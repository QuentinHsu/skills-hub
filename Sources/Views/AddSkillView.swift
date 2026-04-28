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
                        "https://github.com/org/repo/tree/main/.claude/skills",
                        text: $gitURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button(L.string("ui.action.import", using: lm)) {
                        importFromGit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gitURL.isEmpty || isLoading)
                }
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    L.text("ui.add_skill.cloning", using: lm)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

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
                Text("github.com/{owner}/{repo}/tree/{branch}/{path}")
                Text("gitlab.com/{owner}/{repo}/-/tree/{branch}/{path}")
                Text("bitbucket.org/{owner}/{repo}/src/{branch}/{path}")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importFromGit() {
        errorMessage = nil
        importedSkills = []
        isLoading = true

        Task {
            do {
                let skills = try await manager.addSkills(fromGitURL: gitURL)
                importedSkills = skills
                if skills.isEmpty {
                    errorMessage = L.string("error.no_valid_skills", using: lm)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
