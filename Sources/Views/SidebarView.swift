import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case skill(Skill)

    var id: String {
        switch self {
        case .skill(let skill): "skill-\(skill.id)"
        }
    }
}

struct SidebarView: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    @Binding var detailItem: SidebarItem?
    @Binding var isEditing: Bool
    @Binding var selectedBatchItems: Set<SidebarItem>
    let onDeleteSelectedSkills: () -> Void

    private var selectedSkillCount: Int {
        selectedBatchItems.count
    }

    var body: some View {
        Group {
            if isEditing {
                List {
                    sidebarContent
                }
            } else {
                List(selection: detailSelection) {
                    sidebarContent
                }
            }
        }
        .listStyle(.sidebar)
        .id(manager.skillsRevision)
        .onChange(of: isEditing) {
            if isEditing {
                selectedBatchItems = currentDetailSkillSelection
            } else {
                selectedBatchItems.removeAll()
            }
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if manager.skills.isEmpty {
            ContentUnavailableView {
                Label(L.string("ui.label.no_skills", using: lm), systemImage: "doc.text")
            } description: {
                L.text("ui.hint.no_skills", using: lm)
            }
        }

        if isEditing || !manager.skills.isEmpty {
            Section {
                ForEach(manager.filteredSkills) { skill in
                    let item = SidebarItem.skill(skill)
                    skillRow(skill: skill, item: item)
                }
            } header: {
                skillsSectionHeader
            }
        }
    }

    @ViewBuilder
    private func skillRow(skill: Skill, item: SidebarItem) -> some View {
        if isEditing {
            HStack(spacing: 8) {
                Image(systemName: selectedBatchItems.contains(item) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedBatchItems.contains(item) ? Color.accentColor : .secondary)
                    .imageScale(.medium)
                    .frame(width: 16)

                SkillRow(skill: skill, lm: lm)
            }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedBatchItems.toggle(item)
                }
                .contextMenu {
                    Button(L.string("ui.action.delete", using: lm), role: .destructive) {
                        Task { try? manager.removeSkill(skill) }
                    }
                }
        } else {
            SkillRow(skill: skill, lm: lm)
                .tag(item)
                .contextMenu {
                    Button(L.string("ui.action.delete", using: lm), role: .destructive) {
                        Task { try? manager.removeSkill(skill) }
                    }
                }
        }
    }

    private var detailSelection: Binding<Set<SidebarItem>> {
        Binding {
            currentDetailSelection
        } set: { newSelection in
            updateDetailSelection(with: newSelection)
        }
    }

    private var currentDetailSelection: Set<SidebarItem> {
        detailItem.map { [$0] } ?? []
    }

    private var currentDetailSkillSelection: Set<SidebarItem> {
        guard let detailItem, case .skill = detailItem else { return [] }
        return [detailItem]
    }

    private func updateDetailSelection(with newSelection: Set<SidebarItem>) {
        if let detailItem, newSelection.contains(detailItem) {
            return
        }

        detailItem = newSelection.first
    }

    private var skillsSectionHeader: some View {
        HStack {
            Text(L.string("ui.sidebar.skills_count", Int64(manager.filteredSkills.count), using: lm))
            Spacer()
            if isEditing && selectedSkillCount > 0 {
                Button {
                    onDeleteSelectedSkills()
                } label: {
                    Label(
                        L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm),
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
                .help(L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm))
                .accessibilityLabel(L.string("ui.action.delete_count", Int64(selectedSkillCount), using: lm))
            }
            Button {
                isEditing.toggle()
            } label: {
                Label(
                    L.string(isEditing ? "ui.action.done" : "ui.action.edit", using: lm),
                    systemImage: isEditing ? "checkmark" : "checklist"
                )
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(L.string(isEditing ? "ui.action.done" : "ui.action.edit", using: lm))
            .accessibilityLabel(L.string(isEditing ? "ui.action.done" : "ui.action.edit", using: lm))
        }
    }
}

private extension Set where Element == SidebarItem {
    mutating func toggle(_ item: SidebarItem) {
        if contains(item) {
            remove(item)
        } else {
            insert(item)
        }
    }
}

private struct SkillRow: View {
    let skill: Skill
    let lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name)
                .font(.headline)
                .lineLimit(1)
            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(skill.sourceRepositoryDisplayName(using: lm))
                Text("·")
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(skill.modifiedAt.localizedRelative())
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private extension Skill {
    @MainActor
    func sourceRepositoryDisplayName(using lm: LocalizationManager) -> String {
        guard let sourceURL else {
            return L.string("ui.sidebar.local_source", using: lm)
        }

        var raw = sourceURL.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^ssh://"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^git@"#, with: "", options: .regularExpression)

        raw = raw.replacingOccurrences(of: ":", with: "/")

        let path = raw.split(separator: "?").first.map(String.init) ?? raw
        let parts = path.split(separator: "/").map(String.init)
        let hostOffset = parts.first?.contains(".") == true ? 1 : 0

        guard parts.count >= hostOffset + 2 else {
            return sourceURL.lastPathComponent.isEmpty ? raw : sourceURL.lastPathComponent
        }

        let owner = parts[hostOffset]
        let repo = parts[hostOffset + 1].removingGitSuffix()
        return "\(owner)/\(repo)"
    }
}

private extension String {
    func removingGitSuffix() -> String {
        hasSuffix(".git") ? String(dropLast(4)) : self
    }
}

private extension Date {
    func localizedRelative() -> String {
        let lang = LocalizationManager.currentLang()
        let interval = -timeIntervalSinceNow
        if interval < 0 { return LocalizationManager.t("time.just_now", lang: lang) }
        let minutes = Int(interval / 60)
        if minutes < 60 { return String(format: LocalizationManager.t("time.minutes_ago", lang: lang), Int64(minutes)) }
        let hours = minutes / 60
        if hours < 24 { return String(format: LocalizationManager.t("time.hours_ago", lang: lang), Int64(hours)) }
        let days = hours / 24
        return String(format: LocalizationManager.t("time.days_ago", lang: lang), Int64(days))
    }
}
