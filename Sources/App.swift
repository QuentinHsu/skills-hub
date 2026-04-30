import SwiftUI

@main
struct SkillsHubApp: App {
    @State private var localizationManager = LocalizationManager()
    @State private var manager = SkillManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .environment(localizationManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)

        Window(L.string("ui.settings.title", using: localizationManager), id: AppWindowID.settings) {
            SettingsView(manager: manager)
                .environment(localizationManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 680, height: 520)
    }
}

enum AppWindowID {
    static let settings = "settings"
}
