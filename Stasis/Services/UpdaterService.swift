import Defaults
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdaterService: NSObject {
    enum UpdateAutomationMode: String, CaseIterable, Defaults.Serializable {
        case notify
        case autoDownload
        case autoInstall

        var sparkleAutomaticallyDownloads: Bool {
            switch self {
            case .notify:
                return false
            case .autoDownload, .autoInstall:
                return true
            }
        }

        var sparkleAutomaticallyInstalls: Bool {
            switch self {
            case .autoInstall:
                return true
            case .notify, .autoDownload:
                return false
            }
        }
    }

    static let shared = UpdaterService()

    private override init() {
        super.init()
        applyPreferencesToSystemDefaults()
    }

    func applyPreferencesToSystemDefaults() {
        let mode = Defaults[.updateAutomationMode]
        UserDefaults.standard.set(Defaults[.automaticallyCheckForUpdates], forKey: "SUEnableAutomaticChecks")
        UserDefaults.standard.set(mode.sparkleAutomaticallyDownloads, forKey: "SUAutomaticallyUpdate")
        UserDefaults.standard.set(mode.sparkleAutomaticallyInstalls, forKey: "SUAllowsAutomaticUpdates")
    }

    func startIfAvailable() {
        #if canImport(Sparkle)
        _ = updaterController
        #endif
    }

    #if canImport(Sparkle)
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var updaterAvailable: Bool {
        true
    }
    #else
    func checkForUpdates() {
        // Sparkle is not linked yet. Keep API stable for the settings UI.
    }

    var updaterAvailable: Bool {
        false
    }
    #endif
}
