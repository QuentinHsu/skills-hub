import Foundation

/// A skill is a directory containing SKILL.md + optional rule files.
/// The SKILL.md has YAML frontmatter with name, description, metadata.
struct Skill: Identifiable, Hashable, Sendable {
    var id: String { directoryName }

    /// Directory name (e.g., "code-style")
    let directoryName: String

    /// Full path to the skill directory
    let directoryURL: URL

    /// Parsed from SKILL.md frontmatter
    let name: String
    let description: String
    let author: String?
    let version: String?

    /// Extended metadata (vercel-labs/skills compatible)
    let metadataInternal: Bool
    let pluginName: String?

    /// Raw content of SKILL.md (frontmatter stripped)
    let content: String

    /// Relative paths to rule files within the skill directory
    let ruleFiles: [String]

    /// Source git URL (if imported from remote)
    let sourceURL: URL?

    let createdAt: Date
    let modifiedAt: Date

    /// The SKILL.md file URL
    var skillMdURL: URL {
        directoryURL.appendingPathComponent("SKILL.md")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(directoryName)
    }

    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.directoryName == rhs.directoryName
    }
}

struct SkillRepositoryRemoteSkill: Identifiable, Hashable, Sendable {
    let id: String
    let directoryName: String
    let name: String
    let description: String
    let metadataInternal: Bool
    let pluginName: String?
    let relativePath: String
}

struct SkillRepositorySummary: Identifiable, Hashable, Sendable {
    let sourceURL: URL
    var importedSkills: [Skill]
    var remoteSkills: [SkillRepositoryRemoteSkill]
    var lastFetchedAt: Date?
    var errorMessage: String?

    var id: String { sourceURL.absoluteString }

    var notImportedSkills: [SkillRepositoryRemoteSkill] {
        remoteSkills.filter { remote in
            !importedSkills.contains { imported in
                imported.directoryName == remote.directoryName
                    || imported.name.caseInsensitiveCompare(remote.name) == .orderedSame
            }
        }
    }

    var displayName: String {
        sourceURL.absoluteString
    }
}

// MARK: - SKILL.md Parsing

struct SkillFrontmatter: Sendable {
    let name: String
    let description: String
    let author: String?
    let version: String?
    let metadataInternal: Bool
    let pluginName: String?
    let bodyContent: String

    /// Parses YAML frontmatter from SKILL.md content.
    /// Supports both `---\n...\n---\nbody` and `key: val\n---\nbody` (no opening ---).
    static func parse(_ raw: String) -> SkillFrontmatter? {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)

        let startsWithDelimiter = lines.first?.trimmingCharacters(in: .whitespaces) == "---"
        let searchStart = startsWithDelimiter ? 1 : 0
        guard let closingIndex = lines[searchStart...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            return nil
        }

        let frontmatterStart = startsWithDelimiter ? 1 : 0
        let frontmatterLines = lines[frontmatterStart..<closingIndex].map(String.init)

        // Body is everything after the closing ---
        let bodyStart = closingIndex + 1
        let bodyContent = bodyStart < lines.count
            ? lines[bodyStart...].joined(separator: "\n")
            : ""

        var name = Self.frontmatterValue(for: "name", in: frontmatterLines)
        var description = Self.frontmatterValue(for: "description", in: frontmatterLines)
        var author: String?
        var version: String?
        var metadataInternal = false
        var pluginName: String?

        // Track nested metadata block via indentation
        var inMetadata = false
        var metadataIndent = 0

        for line in frontmatterLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Calculate leading whitespace for indentation tracking
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            // Top-level keys
            if !inMetadata || leadingSpaces <= metadataIndent {
                inMetadata = false

                if trimmed.hasPrefix("name:"), name == nil {
                    name = Self.stripQuotes(trimmed.dropFirst(5))
                } else if trimmed.hasPrefix("description:"), description == nil {
                    description = Self.stripQuotes(trimmed.dropFirst(12))
                } else if trimmed == "metadata:" || trimmed.hasPrefix("metadata:") {
                    let afterKey = trimmed.dropFirst(9).trimmingCharacters(in: .whitespaces)
                    if afterKey.isEmpty {
                        inMetadata = true
                        metadataIndent = leadingSpaces
                    } else {
                        let inline = Self.parseInlineMap(String(afterKey))
                        if let val = inline["internal"]?.lowercased() {
                            metadataInternal = (val == "true" || val == "1")
                        }
                        author = inline["author"] ?? author
                        version = inline["version"] ?? version
                        pluginName = inline["pluginName"] ?? inline["plugin_name"] ?? pluginName
                    }
                }
            } else {
                // Inside metadata: block
                if trimmed.hasPrefix("internal:") {
                    let val = Self.stripQuotes(trimmed.dropFirst(9)).lowercased()
                    metadataInternal = (val == "true" || val == "1")
                } else if trimmed.hasPrefix("author:") {
                    author = Self.stripQuotes(trimmed.dropFirst(7))
                } else if trimmed.hasPrefix("version:") {
                    version = Self.stripQuotes(trimmed.dropFirst(8))
                } else if trimmed.hasPrefix("pluginName:") {
                    pluginName = Self.stripQuotes(trimmed.dropFirst(11))
                }
            }
        }

        guard let name, let description else { return nil }

        return SkillFrontmatter(
            name: name,
            description: description,
            author: author,
            version: version,
            metadataInternal: metadataInternal,
            pluginName: pluginName,
            bodyContent: bodyContent
        )
    }

    private static func stripQuotes(_ substring: Substring) -> String {
        substring.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func frontmatterValue(for key: String, in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            guard leadingSpaces == 0, trimmed.hasPrefix("\(key):") else { continue }

            let rawValue = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if rawValue == ">" || rawValue == "|", index + 1 < lines.count {
                let continuationLines = lines[(index + 1)...].prefix { nextLine in
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    let nextIndent = nextLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                    return nextTrimmed.isEmpty || nextIndent > 0
                }

                let values = continuationLines
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if rawValue == "|" {
                    return values.joined(separator: "\n")
                }

                return values.joined(separator: " ")
            }

            return rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }

        return nil
    }

    private static func parseInlineMap(_ raw: String) -> [String: String] {
        let trimmed = raw
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))

        return trimmed.split(separator: ",").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            guard parts.count == 2 else { return }
            result[parts[0]] = parts[1]
        }
    }
}
