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
    let manager: SkillManager
    @Binding var detailItem: SidebarItem?
    @Binding var isEditing: Bool
    @Binding var selectedItems: Set<SidebarItem>
    @State private var lastNonEditSelection = Set<SidebarItem>()

    var body: some View {
        List(selection: $selectedItems) {
            if manager.skills.isEmpty && manager.agents.isEmpty {
                ContentUnavailableView {
                    Label("No Skills", systemImage: "doc.text")
                } description: {
                    Text("Click + to add skills from local files or Git repositories.")
                }
            }

            if !manager.filteredSkills.isEmpty {
                Section("Skills (\(manager.filteredSkills.count))") {
                    ForEach(manager.filteredSkills) { skill in
                        let item = SidebarItem.skill(skill)
                        SkillRow(skill: skill)
                            .tag(item)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { try? manager.removeSkill(skill) }
                                }
                            }
                    }
                }
            }

            if !manager.agents.isEmpty {
                Section("Agents (\(manager.agents.count))") {
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
                    Text(skill.modifiedAt.relativeToMinute)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private extension Date {
    /// 精确到分钟的相对时间描述（如"3分钟前"、"2小时前"）
    var relativeToMinute: String {
        let interval = -timeIntervalSinceNow
        if interval < 0 { return "just now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}
