import SwiftUI

struct SettingsView: View {
    @Environment(LocalizationManager.self) private var lm
    @Environment(\.dismiss) private var dismiss

    let manager: SkillManager

    @State private var configPath = ""
    @State private var showingAddCustomAgent = false

    var body: some View {
        NavigationStack {
            TabView {
                generalSettings
                    .tabItem {
                        Label(L.string("ui.settings.general", using: lm), systemImage: "gearshape")
                    }

                AgentManagementList(manager: manager, showingAddCustom: $showingAddCustomAgent)
                    .tabItem {
                        Label(L.string("ui.label.agents", using: lm), systemImage: "person.2")
                    }
            }
            .padding(.top, 8)
            .navigationTitle(L.string("ui.settings.title", using: lm))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("ui.action.done", using: lm)) { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCustomAgent) {
                AddCustomAgentView(manager: manager)
                    .environment(lm)
            }
            .onAppear {
                syncConfigPathFromManager()
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 520)
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker(L.string("ui.settings.language", using: lm), selection: Binding(
                    get: { lm.currentLanguage },
                    set: { lm.currentLanguage = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                L.text("ui.settings.appearance", using: lm)
            }

            Section {
                HStack {
                    TextField(L.string("ui.settings.config_path", using: lm), text: $configPath)
                        .textFieldStyle(.roundedBorder)

                    Button(L.string("ui.action.browse", using: lm)) {
                        selectDirectory { url in
                            configPath = displayPath(for: url)
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        L.text("ui.settings.skills_path", using: lm)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(displayPath(for: resolvedConfigDirectory().appendingPathComponent("skills")))
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(L.string("ui.action.reset", using: lm)) {
                        configPath = displayPath(for: ConfigService.defaultConfigDirectory)
                    }

                    Button(L.string("ui.action.apply", using: lm)) {
                        applyConfigPath()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplyConfigPath)
                }
            } header: {
                L.text("ui.settings.storage", using: lm)
            } footer: {
                L.text("ui.settings.config_path_footer", using: lm)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var canApplyConfigPath: Bool {
        guard !configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let candidate = resolvedConfigDirectory().standardizedFileURL.path()
        return !candidate.isEmpty && candidate != manager.configDirectory.standardizedFileURL.path()
    }

    private func syncConfigPathFromManager() {
        configPath = displayPath(for: manager.configDirectory)
    }

    private func applyConfigPath() {
        manager.updateConfigDirectory(resolvedConfigDirectory())
        syncConfigPathFromManager()
    }

    private func resolvedConfigDirectory() -> URL {
        let trimmed = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = NSString(string: trimmed).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    private func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path()

        if path == home {
            return "~"
        }

        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }

        return path
    }

    private func selectDirectory(_ handler: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            handler(url)
        }
    }
}
