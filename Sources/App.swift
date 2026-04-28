import SwiftUI

@main
struct SkillsHubApp: App {
    @State private var localizationManager = LocalizationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(localizationManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
    }
}
