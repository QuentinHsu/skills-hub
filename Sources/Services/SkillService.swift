import Foundation

struct SkillService: Sendable {
    let hubDirectory: URL

    init(hubDirectory: URL? = nil) {
        self.hubDirectory = hubDirectory ?? ConfigService.savedConfigDirectory
            .appendingPathComponent("skills")
    }

    // MARK: - Hub Management

    func ensureHubDirectory() throws {
        try FileManager.default.createDirectory(at: hubDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Scan

    func scan() -> [Skill] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: hubDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .compactMap { url -> Skill? in
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard resourceValues?.isDirectory == true else { return nil }
                return loadSkill(from: url)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loadSkill(from directory: URL) -> Skill? {
        let skillMdURL = directory.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillMdURL.path()),
              let rawContent = try? String(contentsOf: skillMdURL, encoding: .utf8),
              let frontmatter = SkillFrontmatter.parse(rawContent)
        else {
            return nil
        }

        let resourceValues = try? directory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])

        // Find rule files
        let rulesDir = directory.appendingPathComponent("rules")
        var ruleFiles: [String] = []
        if let ruleEntries = try? FileManager.default.contentsOfDirectory(
            at: rulesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            ruleFiles = ruleEntries
                .filter { $0.pathExtension == "md" }
                .map { "rules/\($0.lastPathComponent)" }
                .sorted()
        }

        // Read persisted source URL
        let sourceURL: URL? = readSourceURL(from: directory)

        return Skill(
            directoryName: directory.lastPathComponent,
            directoryURL: directory,
            name: frontmatter.name,
            description: frontmatter.description,
            author: frontmatter.author,
            version: frontmatter.version,
            metadataInternal: frontmatter.metadataInternal,
            pluginName: frontmatter.pluginName,
            content: frontmatter.bodyContent,
            ruleFiles: ruleFiles,
            sourceURL: sourceURL,
            createdAt: resourceValues?.creationDate ?? .distantPast,
            modifiedAt: resourceValues?.contentModificationDate ?? .distantPast
        )
    }

    // MARK: - Source URL Persistence

    private static let sourceFileName = ".source"

    private func readSourceURL(from directory: URL) -> URL? {
        let fileURL = directory.appendingPathComponent(Self.sourceFileName)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            return nil
        }
        return URL(string: content)
    }

    private func writeSourceURL(_ url: URL, to directory: URL) {
        let fileURL = directory.appendingPathComponent(Self.sourceFileName)
        try? url.absoluteString.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Find existing skill directory that was imported from the given source URL.
    func findExistingSkill(fromSourceURL sourceURL: URL) -> Skill? {
        let allSkills = scan()
        // Normalize for comparison: strip trailing slash and .git suffix
        let normalized = normalizeSourceURL(sourceURL)
        return allSkills.first { skill in
            guard let existing = skill.sourceURL else { return false }
            return normalizeSourceURL(existing) == normalized
        }
    }

    private func normalizeSourceURL(_ url: URL) -> String {
        var str = url.absoluteString
        if str.hasSuffix("/") { str = String(str.dropLast()) }
        if str.hasSuffix(".git") { str = String(str.dropLast(4)) }
        return str.lowercased()
    }

    // MARK: - Add (from directory)

    func addSkill(from sourceDir: URL, sourceGitURL: URL? = nil) throws -> Skill {
        try ensureHubDirectory()

        let dirName = sourceDir.lastPathComponent
        let destination = hubDirectory.appendingPathComponent(dirName)

        // Same directory name already exists → overwrite (re-import from same source)
        if FileManager.default.fileExists(atPath: destination.path()) {
            let symlinks = findSymlinks(for: Skill(
                directoryName: dirName,
                directoryURL: destination,
                name: "", description: "", author: nil, version: nil,
                metadataInternal: false, pluginName: nil,
                content: "", ruleFiles: [], sourceURL: nil,
                createdAt: .distantPast, modifiedAt: .distantPast
            ))

            try FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceDir, to: destination)
            if let sourceGitURL { writeSourceURL(sourceGitURL, to: destination) }

            guard let skill = loadSkill(from: destination) else {
                try? FileManager.default.removeItem(at: destination)
                throw SkillServiceError.invalidSkill
            }

            // Restore symlinks
            for symlink in symlinks {
                let agentSkillsDir = symlink.deletingLastPathComponent()
                let newLinkPath = agentSkillsDir.appendingPathComponent(skill.directoryName)
                if symlink.path() != newLinkPath.path() {
                    try? FileManager.default.removeItem(at: symlink)
                }
                try? FileManager.default.createSymbolicLink(
                    atPath: newLinkPath.path(),
                    withDestinationPath: skill.directoryURL.path()
                )
            }

            return skill
        }

        // New skill
        try FileManager.default.copyItem(at: sourceDir, to: destination)
        if let sourceGitURL { writeSourceURL(sourceGitURL, to: destination) }

        guard let skill = loadSkill(from: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw SkillServiceError.invalidSkill
        }

        return skill
    }

    // MARK: - Remove

    func removeSkill(_ skill: Skill) throws {
        // Remove all symlinks pointing to this skill directory first
        for symlink in findSymlinks(for: skill) {
            try FileManager.default.removeItem(at: symlink)
        }
        try FileManager.default.removeItem(at: skill.directoryURL)
    }

    // MARK: - Symlink Operations (directory-level)

    func linkSkill(_ skill: Skill, to agent: Agent) throws {
        try FileManager.default.createDirectory(at: agent.skillsDirectory, withIntermediateDirectories: true)

        let linkPath = agent.skillsDirectory.appendingPathComponent(skill.directoryName)

        // Remove existing item, including broken symlinks that `fileExists` does not report.
        if itemOrSymlinkExists(at: linkPath) {
            try FileManager.default.removeItem(at: linkPath)
        }

        try FileManager.default.createSymbolicLink(
            atPath: linkPath.path(),
            withDestinationPath: skill.directoryURL.path()
        )
    }

    func unlinkSkill(_ skill: Skill, from agent: Agent) throws {
        let linkPath = agent.skillsDirectory.appendingPathComponent(skill.directoryName)
        if itemOrSymlinkExists(at: linkPath) {
            try FileManager.default.removeItem(at: linkPath)
        }
    }

    func linkStatus(for skill: Skill, agent: Agent) -> LinkStatus {
        let linkPath = agent.skillsDirectory.appendingPathComponent(skill.directoryName)

        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath.path()) else {
            return itemOrSymlinkExists(at: linkPath) ? .broken : .notLinked
        }

        return destination == skill.directoryURL.path() ? .linked : .broken
    }

    func linkedAgents(for skill: Skill, agents: [Agent]) -> [Agent] {
        agents.filter { linkStatus(for: skill, agent: $0) == .linked }
    }

    func findSymlinks(for skill: Skill) -> [URL] {
        var results: [URL] = []
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let agentPaths = [
            homeDir.appendingPathComponent(".claude/skills"),
            homeDir.appendingPathComponent(".config/claude/skills"),
            homeDir.appendingPathComponent(".agents/skills"),
        ]

        for dir in agentPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path()),
                   dest == skill.directoryURL.path()
                {
                    results.append(url)
                }
            }
        }

        return results
    }

    // MARK: - Copy to Project

    func copySkill(_ skill: Skill, to directory: URL) throws {
        let destination = directory.appendingPathComponent(skill.directoryName)
        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: skill.directoryURL, to: destination)
    }

    // MARK: - Sync

    func syncAll(agents: [Agent]) throws -> [String] {
        var repairs: [String] = []
        let skills = scan()

        for agent in agents {
            for skill in skills where linkStatus(for: skill, agent: agent) != .linked {
                try linkSkill(skill, to: agent)
                repairs.append("\(agent.name)/\(skill.directoryName)")
            }
        }

        for agent in agents {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: agent.skillsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for linkURL in contents {
                guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path()) else {
                    continue
                }

                if !FileManager.default.fileExists(atPath: dest) {
                    let linkName = linkURL.lastPathComponent
                    let hubSkill = hubDirectory.appendingPathComponent(linkName)
                    if FileManager.default.fileExists(atPath: hubSkill.path()) {
                        if itemOrSymlinkExists(at: linkURL) {
                            try FileManager.default.removeItem(at: linkURL)
                        }
                        try FileManager.default.createSymbolicLink(
                            atPath: linkURL.path(),
                            withDestinationPath: hubSkill.path()
                        )
                        repairs.append("\(agent.name)/\(linkName)")
                    }
                }
            }
        }

        return repairs
    }

    private func itemOrSymlinkExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path())
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path())) != nil
    }

    // MARK: - Search

    func search(_ query: String) -> [Skill] {
        guard !query.isEmpty else { return scan() }

        let allSkills = scan()
        let lowercased = query.lowercased()

        return allSkills.filter { skill in
            skill.name.lowercased().contains(lowercased) ||
            skill.directoryName.lowercased().contains(lowercased) ||
            skill.description.lowercased().contains(lowercased) ||
            skill.content.lowercased().contains(lowercased)
        }
    }
}

enum SkillServiceError: LocalizedError {
    case invalidSkill

    var errorDescription: String? {
        switch self {
        case .invalidSkill:
            return LocalizationManager.localize("error.no_valid_skill_md")
        }
    }
}
