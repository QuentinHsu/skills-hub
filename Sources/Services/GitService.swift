import Foundation

struct GitRepoInfo: Sendable {
    let owner: String
    let repo: String
    let branch: String
    let path: String
    let cloneURL: URL
    /// Optional skill name filter (from `owner/repo@skill-name` syntax)
    let skillFilter: String?
}

private struct PluginManifest: Decodable {
    let name: String?
    let skills: [String]

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case skills
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? []
    }
}

private struct MarketplaceManifest: Decodable {
    let plugins: [MarketplacePlugin]
}

private struct MarketplacePlugin: Decodable {
    let name: String?
    let displayName: String?
    let source: MarketplacePluginSource?
    let skills: [String]?
}

private struct MarketplacePluginSource: Decodable {
    let name: String?
    let skills: [String]?

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            name = value
            skills = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        skills = try container.decodeIfPresent([String].self, forKey: .skills)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case skills
    }
}

enum GitServiceError: LocalizedError {
    case invalidURL
    case gitNotFound
    case downloadFailed(statusCode: Int)
    case commandFailed(command: String, exitCode: Int32, stdout: String, stderr: String)
    case noSkillsFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return LocalizationManager.localize("error.invalid_git_url")
        case .gitNotFound:
            return LocalizationManager.localize("error.git_not_found")
        case .downloadFailed(let code):
            return "Download failed (HTTP \(code))"
        case .commandFailed(let cmd, let code, let stdout, let stderr):
            var msg = "Command failed (exit \(code)): \(cmd)"
            if !stderr.isEmpty { msg += "\n\(stderr)" }
            if !stdout.isEmpty { msg += "\n\(stdout)" }
            return msg
        case .noSkillsFound:
            return LocalizationManager.localize("error.no_skills_found")
        }
    }
}

struct GitService: Sendable {

    // MARK: - URL Parsing

    func parseURL(_ urlString: String) throws -> GitRepoInfo {
        // Normalize: strip trailing slash
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let knownHostPrefixes = ["github.com/", "gitlab.com/", "bitbucket.org/"]
        let parseTarget = knownHostPrefixes.contains(where: { normalized.hasPrefix($0) })
            ? "https://\(normalized)"
            : normalized

        // SSH URL: git@github.com:owner/repo.git
        if parseTarget.hasPrefix("git@") {
            return try parseSSHURL(parseTarget)
        }

        // GitHub shorthand: owner/repo or owner/repo@skill-name (no scheme, no host)
        if !parseTarget.contains("://") && !parseTarget.hasPrefix("/") && !parseTarget.hasPrefix(".") {
            return try parseShorthand(parseTarget)
        }

        guard let components = URLComponents(string: parseTarget),
              let host = components.host,
              let scheme = components.scheme
        else {
            throw GitServiceError.invalidURL
        }

        let pathParts = components.path.split(separator: "/").map(String.init)

        // Bare repo URL: https://github.com/owner/repo (exactly 2 path parts, no tree keyword)
        if pathParts.count == 2 {
            let owner = pathParts[0]
            let repo = pathParts[1].hasSuffix(".git") ? String(pathParts[1].dropLast(4)) : pathParts[1]
            let cloneURL = URL(string: "\(scheme)://\(host)/\(owner)/\(repo).git")!
            return GitRepoInfo(owner: owner, repo: repo, branch: "", path: "", cloneURL: cloneURL, skillFilter: nil)
        }

        let treeKeyword: String
        let separator: String?

        switch host {
        case "gitlab.com":
            treeKeyword = "tree"
            separator = "-"
        case "bitbucket.org":
            treeKeyword = "src"
            separator = nil
        default: // github.com and others
            treeKeyword = "tree"
            separator = nil
        }

        return try parseTreeURL(
            components, pathParts: pathParts, scheme: scheme, host: host,
            treeKeyword: treeKeyword, separator: separator
        )
    }

    /// Parse SSH URLs: git@github.com:owner/repo.git[@skill-name]
    private func parseSSHURL(_ urlString: String) throws -> GitRepoInfo {
        // git@host:owner/repo.git
        guard let atRange = urlString.range(of: "@"),
              let colonRange = urlString.range(of: ":", range: atRange.upperBound..<urlString.endIndex)
        else {
            throw GitServiceError.invalidURL
        }

        let host = String(urlString[atRange.upperBound..<colonRange.lowerBound])
        var pathPart = String(urlString[colonRange.upperBound...])

        // Handle @skill-name filter
        var skillFilter: String? = nil
        if let atIndex = pathPart.firstIndex(of: "@") {
            skillFilter = String(pathPart[pathPart.index(after: atIndex)...])
            pathPart = String(pathPart[..<atIndex])
        }

        if pathPart.hasSuffix(".git") {
            pathPart = String(pathPart.dropLast(4))
        }

        let parts = pathPart.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw GitServiceError.invalidURL
        }

        let owner = parts[0]
        let repo = parts[1]
        let path = parts.count > 2 ? parts[2...].joined(separator: "/") : ""
        let cloneURL = URL(string: "https://\(host)/\(owner)/\(repo).git")!

        return GitRepoInfo(owner: owner, repo: repo, branch: "", path: path, cloneURL: cloneURL, skillFilter: skillFilter)
    }

    /// Parse GitHub shorthand: owner/repo[@skill-name] or owner/repo/path[@skill-name]
    private func parseShorthand(_ input: String) throws -> GitRepoInfo {
        var working = input

        // Handle @skill-name filter
        var skillFilter: String? = nil
        if let atIndex = working.firstIndex(of: "@") {
            skillFilter = String(working[working.index(after: atIndex)...])
            working = String(working[..<atIndex])
        }

        let parts = working.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw GitServiceError.invalidURL
        }

        let owner = parts[0]
        let repo = parts[1]
        let path = parts.count > 2 ? parts[2...].joined(separator: "/") : ""
        let cloneURL = URL(string: "https://github.com/\(owner)/\(repo).git")!

        return GitRepoInfo(owner: owner, repo: repo, branch: "", path: path, cloneURL: cloneURL, skillFilter: skillFilter)
    }

    private func parseTreeURL(
        _ components: URLComponents,
        pathParts: [String],
        scheme: String,
        host: String,
        treeKeyword: String,
        separator: String?
    ) throws -> GitRepoInfo {
        guard let treeIndex = pathParts.firstIndex(of: treeKeyword),
              treeIndex >= 2
        else {
            throw GitServiceError.invalidURL
        }

        if let separator, treeIndex < 1 || pathParts[safe: treeIndex - 1] != separator {
            throw GitServiceError.invalidURL
        }

        let owner = pathParts[0]
        let repo = pathParts[1]
        let branch = pathParts[safe: treeIndex + 1] ?? "main"
        let path = treeIndex + 2 < pathParts.count
            ? pathParts[(treeIndex + 2)...].joined(separator: "/")
            : ""
        let cloneURL = URL(string: "\(scheme)://\(host)/\(owner)/\(repo).git")!

        return GitRepoInfo(owner: owner, repo: repo, branch: branch, path: path, cloneURL: cloneURL, skillFilter: nil)
    }

    // MARK: - Fetch + Discover Skills

    /// Fetches repo source, discovers directories with SKILL.md, returns staged URLs.
    func fetchSkillDirectories(from info: GitRepoInfo) async throws -> [URL] {
        let stagedDirs = try await fetchStagedSkillDirectories(from: info)
        return stagedDirs.map(\.directory)
    }

    private func fetchStagedSkillDirectories(from info: GitRepoInfo) async throws -> [StagedSkillDirectory] {
        try await fetchViaGitClone(info: info)
    }

    private struct LocatedSkillDirectory {
        let directory: URL
        let pluginName: String?
        let relativePath: String
    }

    private struct StagedSkillDirectory {
        let directory: URL
        let pluginName: String?
        let relativePath: String
    }

    private var discoverySparseCheckoutPaths: [String] {
        [
            ".claude/skills",
            "skills",
            "skills/.curated",
            ".codex/skills",
            ".agents/skills",
            "agents/skills",
            "agent/skills",
            "claude/skills",
            "codex/skills",
            ".claude-plugin",
            "SKILL.md",
        ]
    }

    /// Result of a skill discovery operation. The staging directory must be cleaned up by the caller.
    struct DiscoveryResult: Sendable {
        let skills: [DiscoveredSkill]
        let stagingDirectory: URL
    }

    /// A skill discovered from a remote repo, parsed but not yet imported.
    struct DiscoveredSkill: Sendable, Identifiable {
        let id: String
        let name: String
        let description: String
        let metadataInternal: Bool
        let pluginName: String?
        let relativePath: String
        let stagedDirectory: URL
    }

    /// Discover skills from a remote repo without importing them.
    /// Returns parsed skill metadata + staging directory. Caller must clean up stagingDirectory.
    func discoverSkills(from info: GitRepoInfo) async throws -> DiscoveryResult {
        let stagedDirs = try await fetchStagedSkillDirectories(from: info)

        var discovered: [DiscoveredSkill] = []
        var seenNames = Set<String>()
        for staged in stagedDirs {
            let skillMdURL = staged.directory.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillMdURL.path()),
                  let rawContent = try? String(contentsOf: skillMdURL, encoding: .utf8),
                  let frontmatter = SkillFrontmatter.parse(rawContent)
            else { continue }

            if frontmatter.metadataInternal && info.skillFilter == nil {
                continue
            }

            if let filter = info.skillFilter,
               !matchesSkillFilter(filter, frontmatter: frontmatter, staged: staged) {
                continue
            }

            let normalizedName = frontmatter.name.lowercased()
            guard !seenNames.contains(normalizedName) else { continue }
            seenNames.insert(normalizedName)

            discovered.append(DiscoveredSkill(
                id: staged.directory.path(),
                name: frontmatter.name,
                description: frontmatter.description,
                metadataInternal: frontmatter.metadataInternal,
                pluginName: frontmatter.pluginName ?? staged.pluginName,
                relativePath: staged.relativePath,
                stagedDirectory: staged.directory
            ))
        }

        // Get the staging parent directory (shared by all staged dirs)
        let stagingDir = stagedDirs.first?.directory.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory

        return DiscoveryResult(skills: discovered, stagingDirectory: stagingDir)
    }

    private func matchesSkillFilter(
        _ filter: String,
        frontmatter: SkillFrontmatter,
        staged: StagedSkillDirectory
    ) -> Bool {
        let normalizedFilter = filter.lowercased()
        return frontmatter.name.lowercased() == normalizedFilter
            || staged.directory.lastPathComponent.lowercased() == normalizedFilter
            || staged.relativePath.lowercased() == normalizedFilter
            || staged.relativePath.lowercased().hasSuffix("/\(normalizedFilter)")
    }

    // MARK: - Tarball Download (bare repo)

    private func fetchViaTarball(info: GitRepoInfo) async throws -> [StagedSkillDirectory] {
        let tarURL = URL(string: "https://\(info.cloneURL.host!)/\(info.owner)/\(info.repo)/archive/refs/heads/\(info.branch).tar.gz")!

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-tarball-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Download tarball
        let (tarData, response) = try await URLSession.shared.data(from: tarURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GitServiceError.downloadFailed(statusCode: code)
        }

        // Write to temp file
        let tarFile = tmpDir.appendingPathComponent("archive.tar.gz")
        try tarData.write(to: tarFile)

        // Extract with tar
        try await runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["xzf", tarFile.path(), "-C", tmpDir.path()]
        )

        // GitHub tarballs extract to a single top-level directory (e.g. "repo-main/")
        let extractedContents = try FileManager.default.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard let repoDir = extractedContents.first(where: { $0.lastPathComponent != "archive.tar.gz" }),
              (try? repoDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else {
            throw GitServiceError.noSkillsFound
        }

        // Search for SKILL.md directories
        let skillDirs = findSkillDirectories(in: repoDir)
        guard !skillDirs.isEmpty else {
            throw GitServiceError.noSkillsFound
        }

        // Stage
        return try stageDirectories(skillDirs)
    }

    // MARK: - Git Clone (URL with specific path)

    private func fetchViaGitClone(info: GitRepoInfo) async throws -> [StagedSkillDirectory] {
        guard gitExists() else {
            throw GitServiceError.gitNotFound
        }

        let branch = try await resolveBranch(for: info)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Step 1: Shallow clone
        try await runGit([
            "clone", "--depth", "1", "--filter=blob:none", "--sparse",
            "--branch", branch,
            info.cloneURL.absoluteString,
            tmpDir.path()
        ])

        // Step 2: Sparse checkout
        let sparsePaths = info.path.isEmpty ? discoverySparseCheckoutPaths : [info.path]
        try await runGitInDir(tmpDir, ["sparse-checkout", "set", "--skip-checks"] + sparsePaths)

        // Step 3: Find SKILL.md directories
        let searchDir = info.path.isEmpty
            ? tmpDir
            : tmpDir.appendingPathComponent(info.path)

        guard FileManager.default.fileExists(atPath: searchDir.path()) else {
            throw GitServiceError.noSkillsFound
        }

        let skillDirs = findSkillDirectories(in: searchDir)
        guard !skillDirs.isEmpty else {
            throw GitServiceError.noSkillsFound
        }

        // Step 4: Stage
        return try stageDirectories(skillDirs)
    }

    // MARK: - Staging

    private func stageDirectories(_ dirs: [LocatedSkillDirectory]) throws -> [StagedSkillDirectory] {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var result: [StagedSkillDirectory] = []
        var usedDirectoryNames = Set<String>()
        for dir in dirs {
            var stagedName = dir.directory.lastPathComponent
            if usedDirectoryNames.contains(stagedName) {
                stagedName = "\(stagedName)-\(result.count + 1)"
            }
            usedDirectoryNames.insert(stagedName)

            let staged = stagingDir.appendingPathComponent(stagedName)
            try FileManager.default.copyItem(at: dir.directory, to: staged)
            result.append(StagedSkillDirectory(
                directory: staged,
                pluginName: dir.pluginName,
                relativePath: dir.relativePath
            ))
        }
        return result
    }

    /// Finds skill directories using the same shape as vercel-labs/skills:
    /// root skill first, then conventional skill folders, then a bounded recursive fallback.
    private func findSkillDirectories(in directory: URL) -> [LocatedSkillDirectory] {
        if containsSkillMD(directory) {
            return [LocatedSkillDirectory(
                directory: directory,
                pluginName: nil,
                relativePath: "."
            )]
        }

        let manifestSkillDirs = skillDirectoriesFromPluginManifests(in: directory)
        let priorityDirs = [
            directory,
            directory.appendingPathComponent("skills"),
            directory.appendingPathComponent("skills/.curated"),
            directory.appendingPathComponent(".claude/skills"),
            directory.appendingPathComponent(".codex/skills"),
            directory.appendingPathComponent(".agents/skills"),
            directory.appendingPathComponent("agents/skills"),
            directory.appendingPathComponent("agent/skills"),
            directory.appendingPathComponent("claude/skills"),
            directory.appendingPathComponent("codex/skills"),
        ] + manifestSkillDirs

        var results: [LocatedSkillDirectory] = []
        var seenPaths = Set<String>()

        for priorityDir in priorityDirs {
            guard directoryExists(priorityDir) else { continue }
            if containsSkillMD(priorityDir) {
                appendLocatedSkill(
                    priorityDir,
                    root: directory,
                    pluginName: pluginNameForSkill(at: priorityDir, root: directory),
                    to: &results,
                    seenPaths: &seenPaths
                )
            }

            for child in childDirectories(of: priorityDir) where containsSkillMD(child) {
                appendLocatedSkill(
                    child,
                    root: directory,
                    pluginName: pluginNameForSkill(at: child, root: directory),
                    to: &results,
                    seenPaths: &seenPaths
                )
            }
        }

        if !results.isEmpty {
            return results
        }

        findSkillDirectoriesRecursively(
            in: directory,
            root: directory,
            depth: 0,
            maxDepth: 5,
            results: &results,
            seenPaths: &seenPaths
        )

        return results
    }

    private func findSkillDirectoriesRecursively(
        in directory: URL,
        root: URL,
        depth: Int,
        maxDepth: Int,
        results: inout [LocatedSkillDirectory],
        seenPaths: inout Set<String>
    ) {
        guard depth <= maxDepth else { return }

        if depth > 0, containsSkillMD(directory) {
            appendLocatedSkill(
                directory,
                root: root,
                pluginName: pluginNameForSkill(at: directory, root: root),
                to: &results,
                seenPaths: &seenPaths
            )
            return
        }

        for child in childDirectories(of: directory) where !shouldSkipDirectory(child) {
            findSkillDirectoriesRecursively(
                in: child,
                root: root,
                depth: depth + 1,
                maxDepth: maxDepth,
                results: &results,
                seenPaths: &seenPaths
            )
        }
    }

    private func appendLocatedSkill(
        _ directory: URL,
        root: URL,
        pluginName: String?,
        to results: inout [LocatedSkillDirectory],
        seenPaths: inout Set<String>
    ) {
        let normalizedPath = directory.standardizedFileURL.path()
        guard !seenPaths.contains(normalizedPath) else { return }
        seenPaths.insert(normalizedPath)

        results.append(LocatedSkillDirectory(
            directory: directory,
            pluginName: pluginName,
            relativePath: relativePath(from: root, to: directory)
        ))
    }

    private func containsSkillMD(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("SKILL.md").path())
    }

    private func directoryExists(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path(), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func childDirectories(of directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.filter { entry in
            (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    private func shouldSkipDirectory(_ directory: URL) -> Bool {
        let skippedNames = Set([
            ".git", "node_modules", ".next", "dist", "build",
            ".cache", "coverage", "__pycache__",
        ])
        return skippedNames.contains(directory.lastPathComponent)
    }

    private func relativePath(from root: URL, to directory: URL) -> String {
        let rootPath = root.standardizedFileURL.path()
        let directoryPath = directory.standardizedFileURL.path()

        guard directoryPath != rootPath else { return "." }
        guard directoryPath.hasPrefix(rootPath + "/") else { return directory.lastPathComponent }

        return String(directoryPath.dropFirst(rootPath.count + 1))
    }

    private func skillDirectoriesFromPluginManifests(in root: URL) -> [URL] {
        let pluginJSON = root.appendingPathComponent(".claude-plugin/plugin.json")
        let marketplaceJSON = root.appendingPathComponent(".claude-plugin/marketplace.json")
        var directories: [URL] = []

        if let manifest = decodeJSON(PluginManifest.self, from: pluginJSON) {
            directories.append(contentsOf: manifest.skills.compactMap { relativeSkillParent($0, root: root) })
        }

        if let manifest = decodeJSON(MarketplaceManifest.self, from: marketplaceJSON) {
            for plugin in manifest.plugins {
                let skillPaths = plugin.skills ?? plugin.source?.skills ?? []
                directories.append(contentsOf: skillPaths.compactMap { relativeSkillParent($0, root: root) })
            }
        }

        return uniqueDirectories(directories)
    }

    private func pluginNameForSkill(at skillDirectory: URL, root: URL) -> String? {
        let skillPath = relativePath(from: root, to: skillDirectory)
        let pluginJSON = root.appendingPathComponent(".claude-plugin/plugin.json")
        let marketplaceJSON = root.appendingPathComponent(".claude-plugin/marketplace.json")

        if let manifest = decodeJSON(PluginManifest.self, from: pluginJSON),
           manifest.skills.contains(where: { normalizedSkillDirectoryPath($0) == skillPath }) {
            return manifest.name
        }

        if let manifest = decodeJSON(MarketplaceManifest.self, from: marketplaceJSON) {
            for plugin in manifest.plugins {
                let skillPaths = plugin.skills ?? plugin.source?.skills ?? []
                if skillPaths.contains(where: { normalizedSkillDirectoryPath($0) == skillPath }) {
                    return plugin.displayName ?? plugin.name ?? plugin.source?.name
                }
            }
        }

        return nil
    }

    private func relativeSkillParent(_ relativePath: String, root: URL) -> URL? {
        let normalized = normalizedRelativePath(relativePath)
        guard !normalized.isEmpty, !normalized.hasPrefix("../") else { return nil }

        let skillURL = root.appendingPathComponent(normalized).standardizedFileURL
        guard isContained(skillURL, in: root) else { return nil }

        let candidate = skillURL.lastPathComponent == "SKILL.md"
            ? skillURL.deletingLastPathComponent()
            : skillURL
        return directoryExists(candidate) ? candidate : nil
    }

    private func normalizedRelativePath(_ path: String) -> String {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasPrefix("./") {
            normalized = String(normalized.dropFirst(2))
        }
        while normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }

    private func normalizedSkillDirectoryPath(_ path: String) -> String {
        let normalized = normalizedRelativePath(path)
        return normalized.hasSuffix("/SKILL.md")
            ? String(normalized.dropLast("/SKILL.md".count))
            : normalized
    }

    private func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path()
        let urlPath = url.standardizedFileURL.path()
        return urlPath == rootPath || urlPath.hasPrefix(rootPath + "/")
    }

    private func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for directory in directories {
            let path = directory.standardizedFileURL.path()
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            result.append(directory)
        }

        return result
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path()),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func resolveBranch(for info: GitRepoInfo) async throws -> String {
        if !info.branch.isEmpty {
            return info.branch
        }

        let output = try await runGitOutput([
            "ls-remote", "--symref", info.cloneURL.absoluteString, "HEAD",
        ])

        for line in output.split(separator: "\n") {
            guard line.hasPrefix("ref: refs/heads/"),
                  let tabIndex = line.firstIndex(of: "\t")
            else {
                continue
            }

            let ref = line[line.index(line.startIndex, offsetBy: "ref: refs/heads/".count)..<tabIndex]
            if !ref.isEmpty {
                return String(ref)
            }
        }

        return "main"
    }

    // MARK: - Git Process

    private func gitExists() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func runGit(_ arguments: [String]) async throws {
        try await runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            environment: [
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_LFS_SKIP_SMUDGE": "1",
            ]
        )
    }

    private func runGitOutput(_ arguments: [String]) async throws -> String {
        try await runProcessOutput(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            environment: [
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_LFS_SKIP_SMUDGE": "1",
            ]
        )
    }

    private func runGitInDir(_ directory: URL, _ arguments: [String]) async throws {
        try await runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            currentDirectory: directory,
            environment: [
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_LFS_SKIP_SMUDGE": "1",
            ]
        )
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: GitServiceError.commandFailed(
                        command: ([executable.path()] + arguments).joined(separator: " "),
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runProcessOutput(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: GitServiceError.commandFailed(
                        command: ([executable.path()] + arguments).joined(separator: " "),
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
