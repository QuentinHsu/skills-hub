import SwiftUI
import AppKit

struct AgentLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    let logoName: String?
    let label: String
    let fallbackSystemImage: String
    var size: CGFloat = 24
    var isEnabled = true
    var fallbackColor: Color = .secondary

    init(agent: Agent, size: CGFloat = 24, isEnabled: Bool = true, fallbackColor: Color = .secondary) {
        let builtInAgent = BuiltInAgent(rawValue: agent.id)
        self.logoName = builtInAgent?.logoName
        self.label = agent.displayName
        self.fallbackSystemImage = agent.iconName
        self.size = size
        self.isEnabled = isEnabled
        self.fallbackColor = fallbackColor
    }

    init(builtInAgent: BuiltInAgent, size: CGFloat = 24, isEnabled: Bool = true, fallbackColor: Color = .secondary) {
        self.logoName = builtInAgent.logoName
        self.label = builtInAgent.displayName
        self.fallbackSystemImage = builtInAgent.iconName
        self.size = size
        self.isEnabled = isEnabled
        self.fallbackColor = fallbackColor
    }

    var body: some View {
        Group {
            if let logoName, let image = AgentLogoLoader.image(named: logoName) {
                logoImage(image)
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size * 0.78))
                    .foregroundStyle(isEnabled ? fallbackColor : .secondary)
                    .opacity(isEnabled ? 1 : 0.55)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func logoImage(_ image: NSImage) -> some View {
        let image = Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .opacity(isEnabled ? 1 : 0.45)

        if colorScheme == .dark {
            image.colorInvert()
        } else {
            image
        }
    }
}

private enum AgentLogoLoader {
    static func image(named name: String) -> NSImage? {
        let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "AgentLogos")
            ?? Bundle.module.url(forResource: name, withExtension: "svg")

        guard let url else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
