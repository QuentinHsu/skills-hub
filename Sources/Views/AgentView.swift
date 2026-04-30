import SwiftUI

struct AgentView: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddCustom = false

    var body: some View {
        NavigationStack {
            AgentManagementList(manager: manager, showingAddCustom: $showingAddCustom)
            .navigationTitle(L.string("ui.label.agents", using: lm))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("ui.action.done", using: lm)) { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomAgentView(manager: manager)
                    .environment(lm)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}

struct AgentManagementList: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    @Binding var showingAddCustom: Bool

    var body: some View {
        List {
            // Built-in agents with toggles
            Section {
                ForEach(BuiltInAgent.allCases) { agent in
                    BuiltInAgentRow(manager: manager, agent: agent)
                }
            } header: {
                L.text("ui.agent.preset_agents", using: lm)
            } footer: {
                L.text("ui.hint.preset_agents", using: lm)
            }

            // Custom agents
            Section {
                let customAgents = manager.agents.filter { agent in
                    !BuiltInAgent.allCases.contains { $0.rawValue == agent.id }
                }

                if customAgents.isEmpty {
                    L.text("ui.label.no_custom_agents", using: lm)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(customAgents) { agent in
                        CustomAgentRow(manager: manager, agent: agent)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            manager.removeAgent(customAgents[index])
                        }
                    }
                }
            } header: {
                HStack {
                    L.text("ui.agent.custom_agents", using: lm)
                    Spacer()
                    Button {
                        showingAddCustom = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

// MARK: - Built-in Agent Row

private struct BuiltInAgentRow: View {
    let manager: SkillManager
    let agent: BuiltInAgent
    @State private var isEnabled: Bool

    init(manager: SkillManager, agent: BuiltInAgent) {
        self.manager = manager
        self.agent = agent
        self._isEnabled = State(initialValue: manager.isBuiltInAgentEnabled(agent))
    }

    var body: some View {
        HStack(spacing: 12) {
            AgentLogo(builtInAgent: agent, size: 24, isEnabled: isEnabled)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                    .font(.headline)
                Text("~/\(agent.skillsDirectoryName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .onChange(of: isEnabled) { _, newValue in
            manager.toggleBuiltInAgent(agent, enabled: newValue)
        }
    }
}

// MARK: - Custom Agent Row

private struct CustomAgentRow: View {
    let manager: SkillManager
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            AgentLogo(agent: agent, size: 24)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                    .font(.headline)
                Text(agent.skillsDirectory.path())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                manager.removeAgent(agent)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Custom Agent

struct AddCustomAgentView: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case path
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    labeledTextField(
                        title: L.string("ui.agent.display_name", using: lm),
                        text: $name,
                        field: .name
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        L.text("ui.agent.skills_dir_path", using: lm)
                            .font(.subheadline.weight(.medium))

                        HStack(spacing: 8) {
                            TextField(L.string("ui.agent.skills_dir_path", using: lm), text: $path)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .focused($focusedField, equals: .path)

                            Button {
                                selectDirectory { url in
                                    path = displayPath(for: url)
                                }
                            } label: {
                                Label(L.string("ui.action.browse", using: lm), systemImage: "folder")
                            }
                            .labelStyle(.iconOnly)
                            .help(L.string("ui.action.browse", using: lm))
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    L.text("ui.agent.info", using: lm)
                }
            }
            .listStyle(.inset)
            .navigationTitle(L.string("ui.agent.add_custom", using: lm))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("ui.action.cancel", using: lm)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L.string("ui.action.add", using: lm), action: addCustomAgent)
                        .disabled(!canAdd)
                }
            }
            .onAppear {
                focusedField = .name
            }
        }
        .frame(width: 520, height: 260)
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty && !trimmedPath.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func labeledTextField(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))

            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
        }
        .padding(.vertical, 2)
    }

    private func addCustomAgent() {
        guard canAdd else { return }

        manager.addCustomAgent(name: trimmedName, directory: URL(fileURLWithPath: resolvedPath()))
        dismiss()
    }

    private func resolvedPath() -> String {
        NSString(string: trimmedPath).expandingTildeInPath
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
