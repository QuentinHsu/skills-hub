import SwiftUI
@preconcurrency import MarkdownUI

struct SkillDetailView: View {
    @Environment(LocalizationManager.self) private var lm
    let skill: Skill?

    var body: some View {
        if let skill {
            SkillDetailContent(skill: skill, lm: lm)
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
    let skill: Skill
    let lm: LocalizationManager
    @State private var isRenderingMarkdown = true

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

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if let author = skill.author {
                        MetadataText(label: L.string("ui.skill.author", using: lm), value: author)
                    }
                    if let version = skill.version {
                        MetadataText(label: L.string("ui.skill.version", using: lm), value: "v\(version)")
                    }
                    MetadataText(label: L.string("ui.skill.directory", using: lm), value: skill.directoryName)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    MetadataText(
                        label: L.string("ui.skill.modified_label", using: lm),
                        value: skill.modifiedAt.appTimestampString
                    )
                    if skill.sourceURL != nil, let sourceWebURL {
                        MetadataLink(
                            label: L.string("ui.skill.source", using: lm),
                            value: sourceWebURL.absoluteString,
                            destination: sourceWebURL
                        )
                        .help(sourceWebURL.absoluteString)
                    } else if let sourceURL = skill.sourceURL {
                        MetadataText(
                            label: L.string("ui.skill.source", using: lm),
                            value: sourceURL.absoluteString,
                            valueLineLimit: 1
                        )
                    }
                }
                .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
    }

    private var sourceWebURL: URL? {
        guard let sourceURL = skill.sourceURL else { return nil }
        return Self.webURL(for: sourceURL)
    }

    private static func webURL(for sourceURL: URL) -> URL? {
        if let info = try? GitService().parseURL(sourceURL.absoluteString) {
            return webURL(for: info)
        }

        guard let scheme = sourceURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }

        return sourceURL
    }

    private static func webURL(for info: GitRepoInfo) -> URL? {
        var base = info.cloneURL.absoluteString
        if base.hasSuffix(".git") {
            base = String(base.dropLast(4))
        }

        guard !info.branch.isEmpty else {
            return URL(string: base)
        }

        let treePath: String
        switch info.cloneURL.host?.lowercased() {
        case "gitlab.com":
            treePath = "-/tree"
        case "bitbucket.org":
            treePath = "src"
        default:
            treePath = "tree"
        }

        let pathSuffix = info.path.isEmpty ? "" : "/\(info.path)"
        return URL(string: "\(base)/\(treePath)/\(info.branch)\(pathSuffix)")
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

private struct MetadataText: View {
    let label: String
    let value: String
    var valueLineLimit: Int? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text("\(label):")
                .fontWeight(.medium)
            Text(value)
                .lineLimit(valueLineLimit)
                .truncationMode(.middle)
        }
        .lineLimit(1)
    }
}

private struct MetadataLink: View {
    let label: String
    let value: String
    let destination: URL

    var body: some View {
        HStack(spacing: 3) {
            Text("\(label):")
                .fontWeight(.medium)
            Link(destination: destination) {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .lineLimit(1)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, -10)
        .padding(.bottom, 2)
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
