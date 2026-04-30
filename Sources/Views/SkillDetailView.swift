import SwiftUI
@preconcurrency import MarkdownUI

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
            .navigationTitle("Skills Hub")
        }
    }
}

private struct SkillDetailContent: View {
    let manager: SkillManager
    let skill: Skill
    let lm: LocalizationManager
    @State private var isRenderingMarkdown = true

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
            .padding(.bottom, 48)
        }
        .overlay(alignment: .bottomTrailing) {
            renderModeButton
                .padding(20)
        }
        .navigationTitle("Skills Hub")
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

    private var renderModeButton: some View {
        Button {
            isRenderingMarkdown.toggle()
        } label: {
            Image(systemName: isRenderingMarkdown ? "chevron.left.forwardslash.chevron.right" : "doc.richtext")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.skillMarkdownBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .help(L.string(isRenderingMarkdown ? "ui.skill.show_source" : "ui.skill.render_markdown", using: lm))
        .accessibilityLabel(L.string(isRenderingMarkdown ? "ui.skill.show_source" : "ui.skill.render_markdown", using: lm))
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
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.green)
                    L.text("ui.skill.linked_to", manager.agents.map(\.displayName).joined(separator: ", "), using: lm)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.orange)
                    L.text("ui.hint.enable_agent", using: lm)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var skillContent: some View {
        if isRenderingMarkdown {
            MarkdownContentView(markdown: skill.content, baseURL: skill.directoryURL)
        } else {
            CodeContentView(code: skill.content)
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            L.text("ui.skill.rules_count", Int64(skill.ruleFiles.count), using: lm)
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

private struct MarkdownContentView: View {
    let markdown: String
    let baseURL: URL

    var body: some View {
        Markdown(markdown, baseURL: baseURL, imageBaseURL: baseURL)
            .markdownTheme(.skillDetail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}

private struct CodeContentView: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skillMarkdownBlockBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.skillMarkdownBorder, lineWidth: 1)
        }
    }
}

private extension Theme {
    @MainActor
    static var skillDetail: Theme {
        Theme()
        .text {
            ForegroundColor(.skillMarkdownText)
            BackgroundColor(nil)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            ForegroundColor(.skillMarkdownText)
            BackgroundColor(.skillMarkdownInlineCodeBackground)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(.skillMarkdownLink)
        }
        .heading1 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: 4, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.45))
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: 18, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.2))
                }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: 14, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                }
        }
        .heading5 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.95))
                }
        }
        .heading6 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.9))
                    ForegroundColor(.skillMarkdownSecondaryText)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.28))
                .markdownMargin(top: 0, bottom: 12)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.skillMarkdownAccent)
                    .relativeFrame(width: .em(0.16))

                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.skillMarkdownSecondaryText)
                        BackgroundColor(nil)
                    }
                    .relativePadding(.horizontal, length: .em(0.85))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            .background(Color.skillMarkdownBlockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: 0, bottom: 12)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.22))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                        BackgroundColor(nil)
                    }
                    .padding(12)
            }
            .background(Color.skillMarkdownBlockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.skillMarkdownBorder, lineWidth: 1)
            }
            .markdownMargin(top: 0, bottom: 12)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.skillMarkdownAccent, Color.skillMarkdownSecondaryText)
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: .skillMarkdownBorder))
                .markdownTableBackgroundStyle(
                    .alternatingRows(.clear, .skillMarkdownBlockBackground)
                )
                .markdownMargin(top: 0, bottom: 12)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .relativeLineSpacing(.em(0.22))
        }
        .thematicBreak {
            Divider()
                .overlay(Color.skillMarkdownBorder)
                .markdownMargin(top: 18, bottom: 18)
        }
    }
}

private extension Color {
    static var skillMarkdownBlockBackground: Color { Color(nsColor: .quaternaryLabelColor).opacity(0.12) }
    static var skillMarkdownInlineCodeBackground: Color { Color(nsColor: .quaternaryLabelColor).opacity(0.16) }
    static var skillMarkdownBorder: Color { Color(nsColor: .separatorColor).opacity(0.36) }
    static var skillMarkdownText: Color { Color(nsColor: .labelColor) }
    static var skillMarkdownSecondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    static var skillMarkdownLink: Color { Color(nsColor: .linkColor) }
    static var skillMarkdownAccent: Color { .accentColor }
}
