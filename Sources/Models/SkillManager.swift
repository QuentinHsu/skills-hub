import Foundation
import Observation

@Observable
@MainActor
final class SkillManager {
    var skills: [Skill] = []
    var agents: [Agent] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var statusMessageKey: String?
    var statusMessageArg: Int64?

    /// Discovery state for selective import
    var discoveredSkills: [GitService.DiscoveredSkill] = []
    var discoveryStagingURL: URL?
    var isDiscovering: Bool = false

    let skillService: SkillService
    let gitService: GitService
    let configService: ConfigService

    init() {
        self.skillService = SkillService()
        self.gitService = GitService()
        self.configService = ConfigService()
        loadAgentsFromConfig()
    }

    // MARK: - Computed

    var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return skills }
        return skillService.search(searchText)
    }

    var hubDirectory: URL {
        skillService.hubDirectory
    }

    // MARK: - Built-in Agents

    func isBuiltInAgentEnabled(_ agent: BuiltInAgent) -> Bool {
        agents.contains { $0.id == agent.rawValue }
    }

    func toggleBuiltInAgent(_ agent: BuiltInAgent, enabled: Bool) {
        if enabled {
            let newAgent = agent.toAgent()
            if !agents.contains(where: { $0.id == newAgent.id }) {
                agents.append(newAgent)
                sortAgents()
                linkAllSkills(to: newAgent)
            }
        } else {
            let a = agent.toAgent()
            unlinkAllSkills(from: a)
            agents.removeAll { $0.id == agent.rawValue }
        }
        saveConfig()
    }

    // MARK: - Scan

    func scan() {
        skills = skillService.scan()
        ensureAllSkillsLinkedToEnabledAgents()
    }

    // MARK: - Add Skill

    func addSkill(fromDirectory dir: URL) throws {
        let skill = try skillService.addSkill(from: dir)
        skills.append(skill)
        sortSkills()
        ensureAllSkillsLinkedToEnabledAgents()
    }

    func addSkills(fromGitURL gitURLString: String) async throws -> [Skill] {
        isLoading = true
        statusMessageKey = "status.cloning_repo"
        defer {
            isLoading = false
            statusMessageKey = nil
            statusMessageArg = nil
        }

        let info = try gitService.parseURL(gitURLString)
        let stagedDirs = try await gitService.fetchSkillDirectories(from: info)

        var addedSkills: [Skill] = []
        for dir in stagedDirs {
            do {
                let skill = try skillService.addSkill(from: dir, sourceGitURL: URL(string: gitURLString))
                addedSkills.append(skill)
            } catch {
                continue
            }
        }

        if let stagingParent = stagedDirs.first?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: stagingParent)
        }

        // Replace overwritten skills in the array (match by directoryName)
        for skill in addedSkills {
            if let idx = skills.firstIndex(where: { $0.directoryName == skill.directoryName }) {
                skills[idx] = skill
            } else {
                skills.append(skill)
            }
        }
        sortSkills()
        ensureAllSkillsLinkedToEnabledAgents()

        return addedSkills
    }

    // MARK: - Discovery (list before import)

    /// Discover skills from a remote repo without importing. Results stored in `discoveredSkills`.
    func discoverSkills(fromGitURL gitURLString: String) async {
        isDiscovering = true
        statusMessageKey = "status.discovering"
        discoveredSkills = []
        cleanupDiscovery()

        defer {
            isDiscovering = false
            statusMessageKey = nil
        }

        do {
            let info = try gitService.parseURL(gitURLString)
            let result = try await gitService.discoverSkills(from: info)
            discoveredSkills = result.skills
            discoveryStagingURL = result.stagingDirectory

            if result.skills.isEmpty {
                statusMessageKey = "error.no_skills_found"
            }
        } catch {
            statusMessageKey = "error.discovery_failed"
        }
    }

    /// Import selected skills from the previously discovered set.
    func importDiscoveredSkills(selectedIDs: Set<String>, sourceGitURL: String) async -> [Skill] {
        isLoading = true
        statusMessageKey = "status.importing_selected"
        defer {
            isLoading = false
            statusMessageKey = nil
            statusMessageArg = nil
        }

        let toImport = discoveredSkills.filter { selectedIDs.contains($0.id) }
        var addedSkills: [Skill] = []

        for discovered in toImport {
            do {
                let skill = try skillService.addSkill(
                    from: discovered.stagedDirectory,
                    sourceGitURL: URL(string: sourceGitURL)
                )
                addedSkills.append(skill)
            } catch {
                continue
            }
        }

        cleanupDiscovery()

        for skill in addedSkills {
            if let idx = skills.firstIndex(where: { $0.directoryName == skill.directoryName }) {
                skills[idx] = skill
            } else {
                skills.append(skill)
            }
        }
        sortSkills()
        ensureAllSkillsLinkedToEnabledAgents()

        return addedSkills
    }

    /// Clean up the discovery staging directory.
    func cleanupDiscovery() {
        if let url = discoveryStagingURL {
            try? FileManager.default.removeItem(at: url)
            discoveryStagingURL = nil
        }
        discoveredSkills = []
    }

    // MARK: - Remove Skill

    func removeSkill(_ skill: Skill) throws {
        try skillService.removeSkill(skill)
        skills.removeAll { $0.id == skill.id }
    }

    @discardableResult
    func removeSkills(_ skillsToRemove: [Skill]) -> [Skill: Error] {
        var errors: [Skill: Error] = [:]
        for skill in skillsToRemove {
            do {
                try removeSkill(skill)
            } catch {
                errors[skill] = error
            }
        }
        return errors
    }

    // MARK: - Custom Agent

    func addCustomAgent(name: String, directory: URL) {
        let agent = Agent(name: name, displayName: name, skillsDirectory: directory)
        if !agents.contains(where: { $0.id == agent.id }) {
            agents.append(agent)
            sortAgents()
            linkAllSkills(to: agent)
            saveConfig()
        }
    }

    func removeAgent(_ agent: Agent) {
        unlinkAllSkills(from: agent)
        agents.removeAll { $0.id == agent.id }
        saveConfig()
    }

    // MARK: - Sync

    func syncAll() async throws {
        isLoading = true
        statusMessageKey = "status.syncing_links"
        defer {
            isLoading = false
            statusMessageKey = nil
            statusMessageArg = nil
        }

        let repairs = try skillService.syncAll(agents: agents)
        scan()
        if repairs.isEmpty {
            statusMessageKey = "status.all_links_valid"
        } else {
            statusMessageKey = "status.repaired_links"
            statusMessageArg = Int64(repairs.count)
        }
    }

    // MARK: - Copy to Project

    func copySkill(_ skill: Skill, to directory: URL) throws {
        try skillService.copySkill(skill, to: directory)
    }

    // MARK: - Config Persistence

    private func loadAgentsFromConfig() {
        let config = configService.load()

        // Restore built-in agents
        for id in config.enabledBuiltIn {
            if let agent = BuiltInAgent(rawValue: id) {
                agents.append(agent.toAgent())
            }
        }

        // Restore custom agents
        for entry in config.customAgents {
            let agent = Agent(
                name: entry.name,
                displayName: entry.displayName,
                skillsDirectory: URL(fileURLWithPath: entry.path)
            )
            agents.append(agent)
        }

        sortAgents()
    }

    private func saveConfig() {
        let enabledBuiltIn = agents.compactMap { agent -> String? in
            BuiltInAgent(rawValue: agent.id) != nil ? agent.id : nil
        }
        let customAgents = agents.compactMap { agent -> CustomAgentEntry? in
            guard BuiltInAgent(rawValue: agent.id) == nil else { return nil }
            return CustomAgentEntry(
                name: agent.name,
                displayName: agent.displayName,
                path: agent.skillsDirectory.path()
            )
        }

        let config = AgentConfig(enabledBuiltIn: enabledBuiltIn, customAgents: customAgents)
        try? configService.save(config)
    }

    // MARK: - Link Helpers

    private func linkSkillsToAllAgents(_ skills: [Skill]) {
        for agent in agents {
            for skill in skills {
                try? skillService.linkSkill(skill, to: agent)
            }
        }
    }

    private func linkAllSkills(to agent: Agent) {
        for skill in skills {
            try? skillService.linkSkill(skill, to: agent)
        }
    }

    private func ensureAllSkillsLinkedToEnabledAgents() {
        guard !agents.isEmpty, !skills.isEmpty else { return }
        linkSkillsToAllAgents(skills)
    }

    private func unlinkAllSkills(from agent: Agent) {
        for skill in skills {
            try? skillService.unlinkSkill(skill, from: agent)
        }
    }

    // MARK: - Sort

    private func sortSkills() {
        skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sortAgents() {
        agents.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
