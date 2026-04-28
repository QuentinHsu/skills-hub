import SwiftUI

struct AgentView: View {
    let manager: SkillManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddCustom = false

    var body: some View {
        NavigationStack {
            List {
                // Built-in agents with toggles
                Section {
                    ForEach(BuiltInAgent.allCases) { agent in
                        BuiltInAgentRow(manager: manager, agent: agent)
                    }
                } header: {
                    Text("Preset Agents")
                } footer: {
                    Text("Enable an agent to link skills to its directory via symlink.")
                }

                // Custom agents
                Section {
                    let customAgents = manager.agents.filter { agent in
                        !BuiltInAgent.allCases.contains { $0.rawValue == agent.id }
                    }

                    if customAgents.isEmpty {
                        Text("No custom agents")
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
                        Text("Custom Agents")
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
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomAgentView(manager: manager)
            }
        }
        .frame(minWidth: 480, minHeight: 400)
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
            Image(systemName: agent.iconName)
                .font(.title2)
                .foregroundStyle(isEnabled ? .blue : .secondary)
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
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
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

private struct AddCustomAgentView: View {
    let manager: SkillManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent Info") {
                    TextField("Display Name", text: $name)
                    HStack {
                        TextField("Skills Directory Path", text: $path)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            selectDirectory { url in
                                path = url.path()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle("Add Custom Agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        let resolved = path.hasPrefix("~")
                            ? path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path())
                            : path
                        manager.addCustomAgent(name: name, directory: URL(fileURLWithPath: resolved))
                        dismiss()
                    }
                    .disabled(name.isEmpty || path.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 200)
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
