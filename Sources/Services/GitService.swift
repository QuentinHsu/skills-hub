import Foundation

struct GitRepoInfo: Sendable {
    let owner: String
    let repo: String
    let branch: String
    let path: String
    let cloneURL: URL
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
        let normalized = urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString

        guard let components = URLComponents(string: normalized),
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
            return GitRepoInfo(owner: owner, repo: repo, branch: "main", path: "", cloneURL: cloneURL)
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

        return GitRepoInfo(owner: owner, repo: repo, branch: branch, path: path, cloneURL: cloneURL)
    }

    // MARK: - Fetch + Discover Skills

    /// Fetches repo source, discovers directories with SKILL.md, returns staged URLs.
    func fetchSkillDirectories(from info: GitRepoInfo) async throws -> [URL] {
        let host = info.cloneURL.host ?? ""

        if info.path.isEmpty && (host == "github.com" || host.hasSuffix(".github.com")) {
            // GitHub bare repo → tarball (lighter, no git required)
            return try await fetchViaTarball(info: info)
        } else {
            // URL with specific path, or non-GitHub host → git clone
            return try await fetchViaGitClone(info: info)
        }
    }

    // MARK: - Tarball Download (bare repo)

    private func fetchViaTarball(info: GitRepoInfo) async throws -> [URL] {
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

    private func fetchViaGitClone(info: GitRepoInfo) async throws -> [URL] {
        guard gitExists() else {
            throw GitServiceError.gitNotFound
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Step 1: Shallow clone
        try await runGit([
            "clone", "--depth", "1", "--filter=blob:none", "--sparse",
            "--branch", info.branch,
            info.cloneURL.absoluteString,
            tmpDir.path()
        ])

        // Step 2: Sparse checkout
        if !info.path.isEmpty {
            try await runGitInDir(tmpDir, ["sparse-checkout", "set", info.path])
        }

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

    private func stageDirectories(_ dirs: [URL]) throws -> [URL] {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var result: [URL] = []
        for dir in dirs {
            let staged = stagingDir.appendingPathComponent(dir.lastPathComponent)
            try FileManager.default.copyItem(at: dir, to: staged)
            result.append(staged)
        }
        return result
    }

    /// Recursively finds directories that contain SKILL.md
    private func findSkillDirectories(in directory: URL) -> [URL] {
        var results: [URL] = []

        let skillMd = directory.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: skillMd.path()) {
            results.append(directory)
        }

        // Always recurse subdirectories to find nested skills
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for entry in entries {
            let resourceValues = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues?.isDirectory == true {
                results.append(contentsOf: findSkillDirectories(in: entry))
            }
        }

        return results
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
