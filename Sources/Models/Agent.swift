import Foundation

struct Agent: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let displayName: String
    let skillsDirectory: URL
    let iconName: String

    init(name: String, displayName: String? = nil, skillsDirectory: URL, iconName: String = "app.connected.to.app.below.fill") {
        self.name = name
        self.displayName = displayName ?? name
        self.skillsDirectory = skillsDirectory
        self.iconName = iconName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Built-in Agent Presets

enum BuiltInAgent: String, CaseIterable, Identifiable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case vscode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .vscode: "VS Code (Copilot)"
        }
    }

    var iconName: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "terminal.fill"
        case .cursor: "cursorarrow.rays"
        case .vscode: "chevron.left.forwardslash.chevron.right"
        }
    }

    var skillsDirectoryName: String {
        switch self {
        case .claudeCode: ".claude/skills"
        case .codex: ".codex/skills"
        case .cursor: ".cursor/skills"
        case .vscode: ".copilot/skills"
        }
    }

    var skillsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(skillsDirectoryName)
    }

    func toAgent() -> Agent {
        Agent(
            name: rawValue,
            displayName: displayName,
            skillsDirectory: skillsDirectory,
            iconName: iconName
        )
    }
}

enum LinkStatus: Sendable {
    case linked
    case broken
    case notLinked
}
