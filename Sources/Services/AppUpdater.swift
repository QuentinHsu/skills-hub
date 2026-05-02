import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    @objc(updater:shouldDownloadReleaseNotesForUpdate:)
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    @objc(standardUserDriverShouldShowVersionHistoryForAppcastItem:)
    nonisolated func standardUserDriverShouldShowVersionHistory(for item: SUAppcastItem) -> Bool {
        false
    }
}
