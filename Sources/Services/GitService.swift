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
    case commandFailed(command: String, exitCode: Int32, stdout: String, stderr: String)
    case noSkillsFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Git repository URL. Expected format: https://github.com/{owner}/{repo}/tree/{branch}/{path}"
        case .gitNotFound:
            return "Git is not installed. Please install Xcode Command Line Tools."
        case .commandFailed(let cmd, let code, let stdout, let stderr):
            var msg = "Command failed (exit \(code)): \(cmd)"
            if !stderr.isEmpty { msg += "\n\(stderr)" }
            if !stdout.isEmpty { msg += "\n\(stdout)" }
            return msg
        case .noSkillsFound:
            return "No skills (directories with SKILL.md) found in the specified path."
        }
    }
}

struct GitService: Sendable {

    // MARK: - URL Parsing

    func parseURL(_ urlString: String) throws -> GitRepoInfo {
        guard let components = URLComponents(string: urlString),
              let host = components.host,
              let scheme = components.scheme
        else {
            throw GitServiceError.invalidURL
        }

        let pathParts = components.path.split(separator: "/").map(String.init)

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

    // MARK: - Clone + Discover Skills

    /// Clones repo, discovers directories with SKILL.md, returns their URLs.
    func fetchSkillDirectories(from info: GitRepoInfo) async throws -> [URL] {
        guard gitExists() else {
            throw GitServiceError.gitNotFound
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // Step 1: Clone
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

        // Step 3: Find directories containing SKILL.md
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

        // Step 4: Copy to staging
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillhub-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var result: [URL] = []
        for dir in skillDirs {
            let staged = stagingDir.appendingPathComponent(dir.lastPathComponent)
            try FileManager.default.copyItem(at: dir, to: staged)
            result.append(staged)
        }

        return result
    }

    /// Recursively finds directories that contain SKILL.md
    private func findSkillDirectories(in directory: URL) -> [URL] {
        var results: [URL] = []

        // Check if this directory itself is a skill
        let skillMd = directory.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: skillMd.path()) {
            results.append(directory)
            // Don't recurse further — this is a skill directory
            return results
        }

        // Otherwise, search subdirectories
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
