import Foundation

#if SPARKLE_ENABLED
import Sparkle
#endif

enum UpdateManager {
    #if SPARKLE_ENABLED
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    static var isSupported: Bool { true }
    static var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    static func start() { _ = controller }
    static func checkForUpdates() { controller.checkForUpdates(nil) }
    #else
    static var isSupported: Bool { false }
    static var canCheckForUpdates: Bool { false }
    static func start() {}
    static func checkForUpdates() {}
    #endif
}
