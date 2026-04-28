import Foundation

struct AgentConfig: Codable, Sendable {
    var enabledBuiltIn: [String]       // rawValue of BuiltInAgent
    var customAgents: [CustomAgentEntry]
}

struct CustomAgentEntry: Codable, Sendable {
    let name: String
    let displayName: String
    let path: String
}

struct ConfigService: Sendable {
    let configURL: URL

    init() {
        self.configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/config.json")
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
