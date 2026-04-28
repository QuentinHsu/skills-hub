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

// MARK: - SKILL.md Parsing

struct SkillFrontmatter: Sendable {
    let name: String
    let description: String
    let author: String?
    let version: String?
    let bodyContent: String

    /// Parses YAML frontmatter from SKILL.md content.
    /// Supports both `---\n...\n---\nbody` and `key: val\n---\nbody` (no opening ---).
    static func parse(_ raw: String) -> SkillFrontmatter? {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)

        // Find the closing --- delimiter (use lastIndex to skip opening ---)
        guard let closingIndex = lines.lastIndex(of: "---") else {
            return nil
        }

        // Frontmatter is everything before the closing ---
        let frontmatterLines = lines[..<closingIndex]
            .map(String.init)
            // If opening --- exists, skip it
            .drop(while: { $0.trimmingCharacters(in: .whitespaces) == "---" })

        // Body is everything after the closing ---
        let bodyStart = closingIndex + 1
        let bodyContent = bodyStart < lines.count
            ? lines[bodyStart...].joined(separator: "\n")
            : ""

        var name: String?
        var description: String?
        var author: String?
        var version: String?

        var inMetadata = false

        for line in frontmatterLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("name:") {
                name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                inMetadata = false
            } else if trimmed.hasPrefix("description:") {
                description = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                inMetadata = false
            } else if trimmed == "metadata:" {
                inMetadata = true
            } else if inMetadata && trimmed.hasPrefix("author:") {
                author = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if inMetadata && trimmed.hasPrefix("version:") {
                version = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            } else if !trimmed.contains(":") || (!trimmed.hasPrefix(" ") && !inMetadata) {
                inMetadata = false
            }
        }

        guard let name, let description else { return nil }

        return SkillFrontmatter(
            name: name,
            description: description,
            author: author,
            version: version,
            bodyContent: bodyContent
        )
    }
}
