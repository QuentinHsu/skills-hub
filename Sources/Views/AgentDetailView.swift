import SwiftUI

struct AgentDetailView: View {
    let manager: SkillManager
    @State private var selectedAgent: Agent?

    var body: some View {
        if manager.agents.isEmpty {
            ContentUnavailableView {
                Label("No Agents", systemImage: "person.2.slash")
            } description: {
                Text("Click the Agents button to enable preset agents or add custom ones.")
            }
        } else {
            List(manager.agents, selection: $selectedAgent) { agent in
                AgentDetailRow(manager: manager, agent: agent)
                    .tag(agent)
            }
            .listStyle(.inset)
            .navigationTitle("Agents")
        }
    }
}

private struct AgentDetailRow: View {
    let manager: SkillManager
    let agent: Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: agent.iconName)
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(agent.displayName)
                        .font(.headline)
                    Text(agent.skillsDirectory.path())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            let linkedSkills = manager.skills.filter { skill in
                manager.skillService.linkStatus(for: skill, agent: agent) == .linked
            }

            if linkedSkills.isEmpty {
                Text("No skills linked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(linkedSkills) { skill in
                        Text(skill.name)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Simple horizontal flow layout for skill tags
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? .infinity, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions, sizes)
    }
}
