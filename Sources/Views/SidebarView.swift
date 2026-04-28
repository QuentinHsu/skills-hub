import SwiftUI

enum SidebarItem: Hashable, Identifiable {
    case skill(Skill)
    case agent(Agent)

    var id: String {
        switch self {
        case .skill(let skill): "skill-\(skill.id)"
        case .agent(let agent): "agent-\(agent.id)"
        }
    }
}

struct SidebarView: View {
    @Environment(LocalizationManager.self) private var lm
    let manager: SkillManager
    @Binding var detailItem: SidebarItem?
    @Binding var isEditing: Bool
    @Binding var selectedItems: Set<SidebarItem>
    @State private var lastNonEditSelection = Set<SidebarItem>()

    var body: some View {
        List(selection: $selectedItems) {
            if manager.skills.isEmpty && manager.agents.isEmpty {
                ContentUnavailableView {
                    Label(L.string("ui.label.no_skills", using: lm), systemImage: "doc.text")
                } description: {
                    L.text("ui.hint.no_skills", using: lm)
                }
            }

            if !manager.filteredSkills.isEmpty {
                Section(L.string("ui.sidebar.skills_count", [Int64(manager.filteredSkills.count)], using: lm)) {
                    ForEach(manager.filteredSkills) { skill in
                        let item = SidebarItem.skill(skill)
                        SkillRow(skill: skill, lm: lm)
                            .tag(item)
                            .contextMenu {
                                Button(L.string("ui.action.delete", using: lm), role: .destructive) {
                                    Task { try? manager.removeSkill(skill) }
                                }
                            }
                    }
                }
            }

            if !manager.agents.isEmpty {
                Section(L.string("ui.sidebar.agents_count", [Int64(manager.agents.count)], using: lm)) {
                    ForEach(manager.agents) { agent in
                        Label(agent.displayName, systemImage: agent.iconName)
                            .tag(SidebarItem.agent(agent))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedItems) {
            syncSelection()
        }
        .onChange(of: isEditing) {
            if isEditing {
                lastNonEditSelection = selectedItems
            } else {
                selectedItems = lastNonEditSelection
                syncSelection()
            }
        }
    }

    private func syncSelection() {
        if isEditing { return }
        if selectedItems.count > 1 {
            if let current = detailItem, selectedItems.contains(current) {
                selectedItems = [current]
            } else {
                selectedItems = [selectedItems.first!]
            }
        }
        detailItem = selectedItems.first
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
                if let author = skill.author {
                    Text(author)
                }
                if skill.author != nil && skill.version != nil {
                    Text("·")
                }
                if let version = skill.version {
                    Text("v\(version)")
                }
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
