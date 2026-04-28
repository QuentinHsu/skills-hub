import SwiftUI

struct SkillDetailView: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    let skill: Skill?

    var body: some View {
        if let skill {
            SkillDetailContent(manager: manager, skill: skill, lm: lm)
        } else {
            ContentUnavailableView {
                Label(L.string("ui.label.no_skill_selected", using: lm), systemImage: "doc.text")
            } description: {
                L.text("ui.hint.select_skill_preview", using: lm)
            }
        }
    }
}

private struct SkillDetailContent: View {
    let manager: SkillManager
    let skill: Skill
    let lm: LocalizationManager

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                skillContent
                if !skill.ruleFiles.isEmpty {
                    Divider()
                    rulesSection
                }
            }
            .padding()
        }
        .navigationTitle(skill.name)
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    if let content = try? String(contentsOf: skill.skillMdURL, encoding: .utf8) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                    }
                } label: {
                    Label(L.string("ui.skill.copy_md", using: lm), systemImage: "doc.on.doc")
                }

                Button {
                    NSWorkspace.shared.selectFile(
                        skill.skillMdURL.path(),
                        inFileViewerRootedAtPath: skill.directoryURL.path()
                    )
                } label: {
                    Label(L.string("ui.skill.reveal_in_finder", using: lm), systemImage: "folder")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.name)
                .font(.title2.bold())

            Text(skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if let author = skill.author {
                    Label(author, systemImage: "person")
                }
                if let version = skill.version {
                    Label("v\(version)", systemImage: "tag")
                }
                Label(skill.directoryName, systemImage: "folder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label {
                    L.text("ui.skill.modified", Self.dateFormatter.string(from: skill.modifiedAt), using: lm)
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            if let sourceURL = skill.sourceURL {
                Label {
                    Text(sourceURL.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }

            // Linked agents
            if !manager.agents.isEmpty {
                let linked = manager.agents.filter { agent in
                    manager.skillService.linkStatus(for: skill, agent: agent) == .linked
                }
                HStack(spacing: 6) {
                    if linked.isEmpty {
                        Image(systemName: "link.badge.plus")
                            .foregroundStyle(.orange)
                        L.text("ui.hint.enable_agent", using: lm)
                    } else {
                        Image(systemName: "link")
                            .foregroundStyle(.green)
                        L.text("ui.skill.linked_to", linked.map(\.displayName).joined(separator: ", "), using: lm)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var skillContent: some View {
        Text(skill.content)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            L.text("ui.skill.rules_count", [Int64(skill.ruleFiles.count)], using: lm)
                .font(.headline)

            ForEach(skill.ruleFiles, id: \.self) { rulePath in
                HStack {
                    Image(systemName: "doc.plaintext")
                        .foregroundStyle(.secondary)
                    Text(rulePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)

                    Spacer()

                    Button {
                        let ruleURL = skill.directoryURL.appendingPathComponent(rulePath)
                        NSWorkspace.shared.selectFile(
                            ruleURL.path(),
                            inFileViewerRootedAtPath: skill.directoryURL.path()
                        )
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help(L.string("ui.skill.open_in_finder", using: lm))
                }
            }
        }
    }
}
