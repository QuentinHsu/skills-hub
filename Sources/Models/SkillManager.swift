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
    var statusMessageArg2: Int64?
    var progressCurrent: Int64 = 0
    var progressTotal: Int64 = 0
    var progressItemName: String?
    var progressMessageKey: String?
    var skillsRevision: Int = 0
    var skillRepositories: [SkillRepositorySummary] = []
    var updatingRepositoryURLs: Set<String> = []
    private var knownSkillRepositoryURLs: Set<String> = []

    /// Discovery state for selective import
    var discoveredSkills: [GitService.DiscoveredSkill] = []
    var discoveryStagingURL: URL?
    var isDiscovering: Bool = false

    var skillService: SkillService
    let gitService: GitService
    var configService: ConfigService

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

    var configDirectory: URL {
        configService.configURL.deletingLastPathComponent()
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
        rebuildSkillRepositories()
        ensureAllSkillsLinkedToEnabledAgents()
        markSkillsChanged()
    }

    // MARK: - Add Skill

    func addSkill(fromDirectory dir: URL) throws {
        let skill = try skillService.addSkill(from: dir)
        skills.append(skill)
        sortSkills()
        rebuildSkillRepositories()
        ensureAllSkillsLinkedToEnabledAgents()
        saveConfig()
        markSkillsChanged()
    }

    func addSkills(fromGitURL gitURLString: String) async throws -> [Skill] {
        isLoading = true
        statusMessageKey = "status.cloning_repo"
        defer {
            isLoading = false
            statusMessageKey = nil
            statusMessageArg = nil
            statusMessageArg2 = nil
            resetProgress()
        }

        let info = try gitService.parseURL(gitURLString)
        rememberSkillRepository(urlString: gitURLString)
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
        rebuildSkillRepositories()
        ensureAllSkillsLinkedToEnabledAgents()
        saveConfig()
        markSkillsChanged()

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
            statusMessageArg2 = nil
            resetProgress()
        }

        let toImport = discoveredSkills.filter { selectedIDs.contains($0.id) }
        var addedSkills: [Skill] = []
        rememberSkillRepository(urlString: sourceGitURL)

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
        rebuildSkillRepositories()
        ensureAllSkillsLinkedToEnabledAgents()
        saveConfig()
        markSkillsChanged()

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
        if let sourceURL = skill.sourceURL {
            rememberSkillRepository(url: sourceURL)
        }
        try skillService.removeSkill(skill)
        skills.removeAll { $0.id == skill.id }
        rebuildSkillRepositories()
        saveConfig()
        markSkillsChanged()
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

    func updateAllFromSources() async {
        isLoading = true
        statusMessageKey = nil
        statusMessageArg = nil
        statusMessageArg2 = nil
        resetProgress()

        defer {
            isLoading = false
            resetProgress()
        }

        let sourceSkills = skills.filter { $0.sourceURL != nil }
        rebuildSkillRepositories()
        let sourceKeys = Set(sourceSkills.compactMap { $0.sourceURL?.absoluteString })
        updatingRepositoryURLs.formUnion(sourceKeys)
        defer {
            updatingRepositoryURLs.subtract(sourceKeys)
        }

        guard !sourceSkills.isEmpty else {
            statusMessageKey = "status.no_git_sources"
            return
        }

        statusMessageKey = "status.fetching_updates"
        progressTotal = Int64(sourceSkills.count)
        progressMessageKey = "status.updating_skill"

        var updatedCount = 0
        var failedCount = 0
        var processedCount: Int64 = 0
        let skillsBySource = Dictionary(grouping: sourceSkills) { $0.sourceURL!.absoluteString }

        for sourceKey in skillsBySource.keys.sorted() {
            guard let groupedSkills = skillsBySource[sourceKey],
                  let sourceURL = groupedSkills.first?.sourceURL
            else {
                continue
            }

            do {
                let info = try gitService.parseURL(sourceURL.absoluteString)
                let result = try await gitService.discoverSkills(from: info)
                defer {
                    try? FileManager.default.removeItem(at: result.stagingDirectory)
                }

                for skill in groupedSkills.sorted(by: { $0.name < $1.name }) {
                    processedCount += 1
                    progressCurrent = processedCount
                    progressItemName = skill.name

                    guard let discovered = matchingDiscoveredSkill(for: skill, in: result.skills) else {
                        failedCount += 1
                        continue
                    }

                    do {
                        let updatedSkill = try skillService.addSkill(
                            from: discovered.stagedDirectory,
                            sourceGitURL: sourceURL
                        )
                        if let idx = skills.firstIndex(where: { $0.directoryName == updatedSkill.directoryName }) {
                            skills[idx] = updatedSkill
                        } else {
                            skills.append(updatedSkill)
                        }
                        updatedCount += 1
                    } catch {
                        failedCount += 1
                    }
                }

                updateRepositorySnapshot(
                    sourceURL: sourceURL,
                    remoteSkills: repositoryRemoteSkills(from: result.skills),
                    errorMessage: nil
                )
            } catch {
                for skill in groupedSkills.sorted(by: { $0.name < $1.name }) {
                    processedCount += 1
                    progressCurrent = processedCount
                    progressItemName = skill.name
                    failedCount += 1
                }
                updateRepositorySnapshot(
                    sourceURL: sourceURL,
                    remoteSkills: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }

        sortSkills()
        ensureAllSkillsLinkedToEnabledAgents()
        scan()

        setUpdateStatus(updatedCount: updatedCount, failedCount: failedCount)
    }

    func syncAll() async {
        isLoading = true
        statusMessageKey = "status.syncing_links"
        statusMessageArg = nil
        statusMessageArg2 = nil
        defer {
            isLoading = false
            resetProgress()
        }

        do {
            let repairs = try skillService.syncAll(agents: agents)
            scan()
            if repairs.isEmpty {
                statusMessageKey = "status.all_links_valid"
            } else {
                statusMessageKey = "status.repaired_links"
                statusMessageArg = Int64(repairs.count)
            }
        } catch {
            statusMessageKey = "status.sync_failed"
        }
    }

    // MARK: - Skill Repositories

    func refreshSkillRepositories() async {
        rebuildSkillRepositories()
        let sourceURLs = skillRepositories.map(\.sourceURL)

        for sourceURL in sourceURLs {
            await refreshSkillRepositoryMetadata(sourceURL: sourceURL)
        }
    }

    func refreshSkillRepositoryMetadata(sourceURL: URL) async {
        let sourceKey = sourceURL.absoluteString
        updatingRepositoryURLs.insert(sourceKey)
        defer { updatingRepositoryURLs.remove(sourceKey) }

        do {
            let info = try gitService.parseURL(sourceURL.absoluteString)
            let result = try await gitService.discoverSkills(from: info)
            defer {
                try? FileManager.default.removeItem(at: result.stagingDirectory)
            }

            updateRepositorySnapshot(
                sourceURL: sourceURL,
                remoteSkills: repositoryRemoteSkills(from: result.skills),
                errorMessage: nil
            )
        } catch {
            updateRepositorySnapshot(
                sourceURL: sourceURL,
                remoteSkills: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    func updateSkillRepository(sourceURL: URL) async {
        let sourceKey = sourceURL.absoluteString
        updatingRepositoryURLs.insert(sourceKey)
        isLoading = true
        statusMessageKey = "status.fetching_updates"
        statusMessageArg = nil
        statusMessageArg2 = nil
        resetProgress()

        defer {
            updatingRepositoryURLs.remove(sourceKey)
            isLoading = false
            resetProgress()
        }

        let sourceSkills = skills
            .filter { $0.sourceURL?.absoluteString == sourceKey }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !sourceSkills.isEmpty else {
            statusMessageKey = "status.no_git_sources"
            rebuildSkillRepositories()
            return
        }

        progressTotal = Int64(sourceSkills.count)
        progressMessageKey = "status.updating_skill"

        do {
            let info = try gitService.parseURL(sourceURL.absoluteString)
            let result = try await gitService.discoverSkills(from: info)
            defer {
                try? FileManager.default.removeItem(at: result.stagingDirectory)
            }

            var updatedCount = 0
            var failedCount = 0

            for (index, skill) in sourceSkills.enumerated() {
                progressCurrent = Int64(index + 1)
                progressItemName = skill.name

                guard let discovered = matchingDiscoveredSkill(for: skill, in: result.skills) else {
                    failedCount += 1
                    continue
                }

                do {
                    let updatedSkill = try skillService.addSkill(
                        from: discovered.stagedDirectory,
                        sourceGitURL: sourceURL
                    )
                    if let idx = skills.firstIndex(where: { $0.directoryName == updatedSkill.directoryName }) {
                        skills[idx] = updatedSkill
                    } else {
                        skills.append(updatedSkill)
                    }
                    updatedCount += 1
                } catch {
                    failedCount += 1
                }
            }

            sortSkills()
            ensureAllSkillsLinkedToEnabledAgents()
            updateRepositorySnapshot(
                sourceURL: sourceURL,
                remoteSkills: repositoryRemoteSkills(from: result.skills),
                errorMessage: failedCount == 0
                    ? nil
                    : String(format: LocalizationManager.localize("status.update_failed"), Int64(failedCount))
            )
            rebuildSkillRepositories()
            markSkillsChanged()
            setUpdateStatus(updatedCount: updatedCount, failedCount: failedCount)
        } catch {
            updateRepositorySnapshot(
                sourceURL: sourceURL,
                remoteSkills: nil,
                errorMessage: error.localizedDescription
            )
            statusMessageKey = "status.update_failed"
            statusMessageArg = Int64(sourceSkills.count)
        }
    }

    @discardableResult
    func importSkillFromRepository(
        sourceURL: URL,
        remoteSkill: SkillRepositoryRemoteSkill
    ) async -> Skill? {
        let sourceKey = sourceURL.absoluteString
        updatingRepositoryURLs.insert(sourceKey)
        isLoading = true
        statusMessageKey = "status.importing_selected"
        statusMessageArg = nil
        statusMessageArg2 = nil
        resetProgress()
        rememberSkillRepository(url: sourceURL)

        defer {
            updatingRepositoryURLs.remove(sourceKey)
            isLoading = false
            resetProgress()
        }

        do {
            let info = try gitService.parseURL(sourceURL.absoluteString)
            let result = try await gitService.discoverSkills(from: info)
            defer {
                try? FileManager.default.removeItem(at: result.stagingDirectory)
            }

            guard let discovered = matchingDiscoveredSkill(for: remoteSkill, in: result.skills) else {
                updateRepositorySnapshot(
                    sourceURL: sourceURL,
                    remoteSkills: repositoryRemoteSkills(from: result.skills),
                    errorMessage: LocalizationManager.localize("error.no_valid_skills")
                )
                return nil
            }

            let skill = try skillService.addSkill(
                from: discovered.stagedDirectory,
                sourceGitURL: sourceURL
            )

            if let idx = skills.firstIndex(where: { $0.directoryName == skill.directoryName }) {
                skills[idx] = skill
            } else {
                skills.append(skill)
            }

            sortSkills()
            ensureAllSkillsLinkedToEnabledAgents()
            updateRepositorySnapshot(
                sourceURL: sourceURL,
                remoteSkills: repositoryRemoteSkills(from: result.skills),
                errorMessage: nil
            )
            rebuildSkillRepositories()
            saveConfig()
            markSkillsChanged()
            return skill
        } catch {
            updateRepositorySnapshot(
                sourceURL: sourceURL,
                remoteSkills: nil,
                errorMessage: error.localizedDescription
            )
            return nil
        }
    }

    // MARK: - Copy to Project

    func copySkill(_ skill: Skill, to directory: URL) throws {
        try skillService.copySkill(skill, to: directory)
    }

    // MARK: - Settings

    func updateConfigDirectory(_ directory: URL) {
        ConfigService.saveConfigDirectory(directory)
        configService = ConfigService(configDirectory: directory)
        skillService = SkillService(hubDirectory: directory.appendingPathComponent("skills"))

        if FileManager.default.fileExists(atPath: configService.configURL.path()) {
            loadAgentsFromConfig()
        } else {
            saveConfig()
        }

        scan()
    }

    // MARK: - Config Persistence

    private func loadAgentsFromConfig() {
        let config = configService.load()
        agents.removeAll()
        knownSkillRepositoryURLs = Set(config.skillRepositories.map(\.sourceURL))

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
        let skillRepositories = Array(knownSkillRepositoryURLs)
            .sorted()
            .map { SkillRepositoryEntry(sourceURL: $0) }

        let config = AgentConfig(
            enabledBuiltIn: enabledBuiltIn,
            customAgents: customAgents,
            skillRepositories: skillRepositories
        )
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

    private func matchingDiscoveredSkill(
        for skill: Skill,
        in discoveredSkills: [GitService.DiscoveredSkill]
    ) -> GitService.DiscoveredSkill? {
        discoveredSkills.first {
            $0.directoryName == skill.directoryName
        } ?? discoveredSkills.first {
            $0.name.caseInsensitiveCompare(skill.name) == .orderedSame
        } ?? (discoveredSkills.count == 1 ? discoveredSkills[0] : nil)
    }

    private func matchingDiscoveredSkill(
        for remoteSkill: SkillRepositoryRemoteSkill,
        in discoveredSkills: [GitService.DiscoveredSkill]
    ) -> GitService.DiscoveredSkill? {
        discoveredSkills.first {
            $0.relativePath == remoteSkill.relativePath
        } ?? discoveredSkills.first {
            $0.directoryName == remoteSkill.directoryName
        } ?? discoveredSkills.first {
            $0.name.caseInsensitiveCompare(remoteSkill.name) == .orderedSame
        }
    }

    private func rebuildSkillRepositories() {
        let previousBySource = Dictionary(uniqueKeysWithValues: skillRepositories.map { ($0.id, $0) })
        let sourceSkills = skills.filter { $0.sourceURL != nil }
        let grouped = Dictionary(grouping: sourceSkills) { $0.sourceURL!.absoluteString }
        knownSkillRepositoryURLs.formUnion(grouped.keys)

        skillRepositories = knownSkillRepositoryURLs.sorted().compactMap { sourceKey in
            let groupedSkills = grouped[sourceKey] ?? []
            let sourceURL = groupedSkills.first?.sourceURL ?? URL(string: sourceKey)
            guard let sourceURL else {
                return nil
            }

            var summary = previousBySource[sourceKey] ?? SkillRepositorySummary(
                sourceURL: sourceURL,
                importedSkills: [],
                remoteSkills: [],
                lastFetchedAt: nil,
                errorMessage: nil
            )
            summary.importedSkills = groupedSkills.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return summary
        }
    }

    private func rememberSkillRepository(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        rememberSkillRepository(url: url)
    }

    private func rememberSkillRepository(url: URL) {
        knownSkillRepositoryURLs.insert(url.absoluteString)
    }

    private func updateRepositorySnapshot(
        sourceURL: URL,
        remoteSkills: [SkillRepositoryRemoteSkill]?,
        errorMessage: String?
    ) {
        rebuildSkillRepositories()

        let sourceKey = sourceURL.absoluteString
        if let index = skillRepositories.firstIndex(where: { $0.id == sourceKey }) {
            if let remoteSkills {
                skillRepositories[index].remoteSkills = remoteSkills
                skillRepositories[index].lastFetchedAt = Date()
            }
            skillRepositories[index].errorMessage = errorMessage
        }
    }

    private func repositoryRemoteSkills(
        from discoveredSkills: [GitService.DiscoveredSkill]
    ) -> [SkillRepositoryRemoteSkill] {
        discoveredSkills
            .map { discovered in
                SkillRepositoryRemoteSkill(
                    id: discovered.relativePath,
                    directoryName: discovered.directoryName,
                    name: discovered.name,
                    description: discovered.description,
                    metadataInternal: discovered.metadataInternal,
                    pluginName: discovered.pluginName,
                    relativePath: discovered.relativePath
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func setUpdateStatus(updatedCount: Int, failedCount: Int) {
        if failedCount == 0 {
            statusMessageKey = "status.update_complete"
            statusMessageArg = Int64(updatedCount)
        } else if updatedCount == 0 {
            statusMessageKey = "status.update_failed"
            statusMessageArg = Int64(failedCount)
        } else {
            statusMessageKey = "status.update_complete_with_failures"
            statusMessageArg = Int64(updatedCount)
            statusMessageArg2 = Int64(failedCount)
        }
    }

    private func resetProgress() {
        progressCurrent = 0
        progressTotal = 0
        progressItemName = nil
        progressMessageKey = nil
    }

    private func markSkillsChanged() {
        skillsRevision += 1
    }

    // MARK: - Sort

    private func sortSkills() {
        skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sortAgents() {
        agents.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
