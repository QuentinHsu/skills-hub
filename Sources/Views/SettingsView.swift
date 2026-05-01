import SwiftUI

struct SettingsView: View {
    @Environment(LocalizationManager.self) private var lm

    let manager: SkillManager

    @State private var selectedSection: SettingsSection? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var configPath = ""
    @State private var showingAddCustomAgent = false

    private var currentSection: SettingsSection {
        selectedSection ?? .general
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSection) {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title(using: lm), systemImage: section.systemImage)
                            .tag(section)
                    }
                } header: {
                    L.text("ui.settings.title", using: lm)
                }
            }
            .navigationTitle(L.string("ui.settings.title", using: lm))
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
                .navigationTitle(currentSection.title(using: lm))
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingAddCustomAgent) {
            AddCustomAgentView(manager: manager)
                .environment(lm)
        }
        .onAppear {
            syncConfigPathFromManager()
            selectedSection = currentSection
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460, idealHeight: 520)
    }

    @ViewBuilder
    private var detailView: some View {
        switch currentSection {
        case .general:
            generalSettings
        case .agents:
            AgentManagementList(manager: manager, showingAddCustom: $showingAddCustomAgent)
                .listStyle(.inset)
        }
    }

    private var generalSettings: some View {
        List {
            Section {
                HStack {
                    L.text("ui.settings.language", using: lm)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { lm.currentLanguage },
                        set: { lm.currentLanguage = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                .padding(.vertical, 2)
            } header: {
                L.text("ui.settings.appearance", using: lm)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    L.text("ui.settings.config_path", using: lm)
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        TextField(L.string("ui.settings.config_path", using: lm), text: $configPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            selectDirectory { url in
                                configPath = displayPath(for: url)
                            }
                        } label: {
                            Label(L.string("ui.action.browse", using: lm), systemImage: "folder")
                        }
                        .labelStyle(.iconOnly)
                        .help(L.string("ui.action.browse", using: lm))
                    }
                }
                .padding(.vertical, 2)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        L.text("ui.settings.skills_path", using: lm)
                            .font(.subheadline.weight(.medium))

                        Text(displayPath(for: resolvedConfigDirectory().appendingPathComponent("skills")))
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 12)

                    Button {
                        configPath = displayPath(for: ConfigService.defaultConfigDirectory)
                    } label: {
                        Label(L.string("ui.action.reset", using: lm), systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        applyConfigPath()
                    } label: {
                        Label(L.string("ui.action.apply", using: lm), systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplyConfigPath)
                }
                .padding(.vertical, 2)
            } header: {
                L.text("ui.settings.storage", using: lm)
            } footer: {
                L.text("ui.settings.config_path_footer", using: lm)
            }
        }
        .listStyle(.inset)
    }

    private var canApplyConfigPath: Bool {
        let trimmed = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case agents

    var id: Self { self }

    @MainActor
    func title(using lm: LocalizationManager) -> String {
        switch self {
        case .general:
            L.string("ui.settings.general", using: lm)
        case .agents:
            L.string("ui.label.agents", using: lm)
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .agents:
            "person.2"
        }
    }
}
