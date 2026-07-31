import AppIntents
import Foundation

struct OpenMenuIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Menu Bar"
    static let description = IntentDescription("Open the Stasis menu bar dropdown dialog.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appDelegate = AppDelegate.shared else {
            throw CustomIntentError.stasisNotReady
        }
        appDelegate.openMenuBarMenu()
        return .result()
    }
}
