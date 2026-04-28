import SwiftUI

struct AddSkillView: View {
    let manager: SkillManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .local
    @State private var gitURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importedSkills: [Skill] = []
    @State private var showingFolderPicker = false

    enum Tab: String, CaseIterable {
        case local = "Local Directory"
        case git = "From Git URL"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch selectedTab {
                case .local:
                    localTab
                case .git:
                    gitTab
                }
            }
            .navigationTitle("Add Skill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 360)
    }

    // MARK: - Local Tab

    private var localTab: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Import a Skill Directory")
                .font(.title3)

            Text("Select a directory containing SKILL.md.\nThe entire directory will be copied to your skill hub.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose Directory...") {
                showingFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Git Tab

    private var gitTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Import from Git Repository")
                .font(.title3)

            Text("Paste a URL to a skills directory.\nDirectories with SKILL.md will be imported.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                TextField(
                    "https://github.com/org/repo/tree/main/.claude/skills",
                    text: $gitURL
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button("Import") {
                    importFromGit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(gitURL.isEmpty || isLoading)
            }
            .padding(.horizontal, 32)

            if isLoading {
                ProgressView("Cloning and discovering skills...")
                    .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !importedSkills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Imported \(importedSkills.count) skill(s):")
                        .font(.caption.bold())
                    ForEach(importedSkills) { skill in
                        HStack {
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
                .padding()
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("Supported URL formats:")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                Text("github.com/{owner}/{repo}/tree/{branch}/{path}")
                Text("gitlab.com/{owner}/{repo}/-/tree/{branch}/{path}")
                Text("bitbucket.org/{owner}/{repo}/src/{branch}/{path}")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
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
                    errorMessage = "No valid skills found in the specified path."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
