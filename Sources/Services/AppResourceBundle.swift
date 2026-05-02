import Foundation

enum AppResourceBundle {
    private static let bundleName = "SkillsHub_SkillsHub.bundle"

    static let bundle: Bundle = {
        for url in candidateURLs() {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent(bundleName))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls.append(executableDirectory.appendingPathComponent(bundleName))

            var directory = executableDirectory
            for _ in 0..<4 {
                directory.deleteLastPathComponent()
                urls.append(directory.appendingPathComponent(bundleName))
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}
