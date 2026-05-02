import SwiftUI

@main
struct SkillsHubApp: App {
    @State private var localizationManager = LocalizationManager()
    @State private var manager = SkillManager()
    @StateObject private var appUpdater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .environment(localizationManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L.string("ui.app.check_for_updates", using: localizationManager)) {
                    appUpdater.checkForUpdates()
                }
            }
        }

        Window(L.string("ui.settings.title", using: localizationManager), id: AppWindowID.settings) {
            SettingsView(manager: manager, appUpdater: appUpdater)
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
