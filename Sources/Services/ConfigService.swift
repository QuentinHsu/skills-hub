import Foundation

struct AgentConfig: Codable, Sendable {
    var enabledBuiltIn: [String]       // rawValue of BuiltInAgent
    var customAgents: [CustomAgentEntry]
    var skillRepositories: [SkillRepositoryEntry]

    init(
        enabledBuiltIn: [String],
        customAgents: [CustomAgentEntry],
        skillRepositories: [SkillRepositoryEntry] = []
    ) {
        self.enabledBuiltIn = enabledBuiltIn
        self.customAgents = customAgents
        self.skillRepositories = skillRepositories
    }

    private enum CodingKeys: String, CodingKey {
        case enabledBuiltIn
        case customAgents
        case skillRepositories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabledBuiltIn = try container.decodeIfPresent([String].self, forKey: .enabledBuiltIn) ?? []
        customAgents = try container.decodeIfPresent([CustomAgentEntry].self, forKey: .customAgents) ?? []
        skillRepositories = try container.decodeIfPresent([SkillRepositoryEntry].self, forKey: .skillRepositories) ?? []
    }
}

struct CustomAgentEntry: Codable, Sendable {
    let name: String
    let displayName: String
    let path: String
}

struct SkillRepositoryEntry: Codable, Sendable {
    let sourceURL: String
}

struct ConfigService: Sendable {
    private static let configDirectoryDefaultsKey = "configDirectoryPath"

    static var defaultConfigDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents")
    }

    static var savedConfigDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: configDirectoryDefaultsKey),
           !path.isEmpty
        {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }

        return defaultConfigDirectory
    }

    static func saveConfigDirectory(_ directory: URL) {
        UserDefaults.standard.set(directory.path(), forKey: configDirectoryDefaultsKey)
    }

    let configURL: URL

    init(configDirectory: URL? = nil) {
        self.configURL = (configDirectory ?? Self.savedConfigDirectory)
            .appendingPathComponent("config.json")
    }

    func load() -> AgentConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AgentConfig.self, from: data)
        else {
            return AgentConfig(enabledBuiltIn: [], customAgents: [])
        }
        return config
    }

    func save(_ config: AgentConfig) throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }
}
