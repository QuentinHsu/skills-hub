import Foundation
import SwiftUI
import SVGPath

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
            if let logoName, let document = AgentLogoLoader.document(named: logoName) {
                logoView(document)
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

    private func logoView(_ document: SVGLogoDocument) -> some View {
        ZStack {
            ForEach(Array(document.paths.enumerated()), id: \.offset) { _, element in
                SVGShape(pathData: element.pathData, viewBox: document.viewBox)
                    .fill(logoForegroundColor, style: FillStyle(eoFill: element.usesEvenOddFill))
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var logoForegroundColor: Color {
        colorScheme == .dark ? .white : Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    }
}

private struct SVGShape: Shape {
    let pathData: String
    let viewBox: CGRect

    func path(in rect: CGRect) -> Path {
        guard var path = try? Path(svgPath: pathData) else {
            return Path()
        }

        path = path.applying(transformForViewBox(from: viewBox, to: rect))
        return path
    }

    private func transformForViewBox(from viewBox: CGRect, to rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let scaledWidth = viewBox.width * scale
        let scaledHeight = viewBox.height * scale
        let xOffset = rect.minX + (rect.width - scaledWidth) / 2 - viewBox.minX * scale
        let yOffset = rect.minY + (rect.height - scaledHeight) / 2 - viewBox.minY * scale

        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: xOffset, ty: yOffset)
    }
}

private struct SVGLogoDocument {
    let viewBox: CGRect
    let paths: [SVGLogoPath]
}

private struct SVGLogoPath {
    let pathData: String
    let usesEvenOddFill: Bool
}

@MainActor
private enum AgentLogoLoader {
    private static var cache: [String: SVGLogoDocument] = [:]

    static func document(named name: String) -> SVGLogoDocument? {
        if let cached = cache[name] {
            return cached
        }

        guard let url = resourceURL(named: name),
              let data = try? Data(contentsOf: url),
              let xml = try? XMLDocument(data: data),
              let root = xml.rootElement(),
              let viewBoxString = root.attribute(forName: "viewBox")?.stringValue,
              let viewBox = parseViewBox(viewBoxString) else {
            return nil
        }

        let nodes = (try? root.nodes(forXPath: ".//*[local-name()='path']")) as? [XMLElement] ?? []
        let paths = nodes.compactMap { element -> SVGLogoPath? in
            guard let rawPathData = element.attribute(forName: "d")?.stringValue else {
                return nil
            }

            let fillRule = element.attribute(forName: "fill-rule")?.stringValue?.lowercased()
            let clipRule = element.attribute(forName: "clip-rule")?.stringValue?.lowercased()
            let usesEvenOddFill = fillRule == "evenodd" || clipRule == "evenodd"
            return SVGLogoPath(
                pathData: normalizePathData(rawPathData),
                usesEvenOddFill: usesEvenOddFill
            )
        }

        guard !paths.isEmpty else {
            return nil
        }

        let document = SVGLogoDocument(viewBox: viewBox, paths: paths)
        cache[name] = document
        return document
    }

    private static func resourceURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "AgentLogos")
            ?? Bundle.module.url(forResource: name, withExtension: "svg")
    }

    private static func parseViewBox(_ string: String) -> CGRect? {
        let values = string
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }

        guard values.count == 4 else {
            return nil
        }

        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    // LobeHub exports compact SVG path data that may omit separators inside arc
    // commands, e.g. `a6.105 6.105 0 013.046-.415`. SVGPath expects explicit
    // token boundaries, so we normalize the stream before parsing.
    private static func normalizePathData(_ string: String) -> String {
        var tokens: [String] = []
        var index = string.startIndex
        var currentCommand: Character?
        var commandArgumentIndex = 0

        func isCommand(_ character: Character) -> Bool {
            character.isLetter
        }

        func isSeparator(_ character: Character) -> Bool {
            character.isWhitespace || character == ","
        }

        func arcArgumentLength(for command: Character?) -> Int {
            switch command {
            case "A", "a": 7
            default: 0
            }
        }

        while index < string.endIndex {
            let character = string[index]

            if isSeparator(character) {
                index = string.index(after: index)
                continue
            }

            if isCommand(character) {
                currentCommand = character
                commandArgumentIndex = 0
                tokens.append(String(character))
                index = string.index(after: index)
                continue
            }

            if let command = currentCommand,
               arcArgumentLength(for: command) == 7,
               commandArgumentIndex % 7 == 3 || commandArgumentIndex % 7 == 4,
               character == "0" || character == "1" {
                tokens.append(String(character))
                commandArgumentIndex += 1
                index = string.index(after: index)
                continue
            }

            let start = index
            var previous: Character?
            var seenDecimalPoint = false
            var seenExponentMarker = false

            while index < string.endIndex {
                let current = string[index]

                if isSeparator(current) || isCommand(current) {
                    break
                }

                if current == "-" || current == "+" {
                    if let previous,
                       previous != "e",
                       previous != "E",
                       index != start {
                        break
                    }
                }

                if current == "." {
                    if seenDecimalPoint, index != start {
                        break
                    }
                    seenDecimalPoint = true
                } else if current == "e" || current == "E" {
                    if seenExponentMarker {
                        break
                    }
                    seenExponentMarker = true
                    seenDecimalPoint = false
                }

                previous = current
                index = string.index(after: index)
            }

            tokens.append(String(string[start ..< index]))
            commandArgumentIndex += 1
        }

        return tokens.joined(separator: " ")
    }
}
