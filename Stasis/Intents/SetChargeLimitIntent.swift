import AppIntents
import Defaults
import Foundation

struct SetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Charge Limit"
    static let description = IntentDescription("Set the maximum battery charging limit in Stasis.")
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Limit (%)",
        description: "Charge limit percentage (50 to 100)",
        default: 80
    )
    var limit: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let appDelegate = AppDelegate.shared,
              let (_, chargeManager, _, _) = await appDelegate.ensureServicesReady() else {
            throw CustomIntentError.stasisNotReady
        }

        let clampedLimit = min(max(limit, 50), 100)
        Defaults[.chargeLimit] = clampedLimit
        Defaults[.manageCharging] = true
        chargeManager.forceSyncSettings()

        let message: String
        if limit < 50 {
            message = "Charge limit set to \(0.5, format: .percent.precision(.fractionLength(0))) (minimum allowed is \(0.5, format: .percent.precision(.fractionLength(0)))). Managed Charging enabled."
        } else if limit > 100 {
            message = "Charge limit set to \(1.0, format: .percent.precision(.fractionLength(0))) (maximum allowed is \(1.0, format: .percent.precision(.fractionLength(0)))). Managed Charging enabled."
        } else {
            message = "Charge limit set to \(Double(clampedLimit) / 100.0, format: .percent.precision(.fractionLength(0))) (Managed Charging enabled)."
        }

        return .result(value: message, dialog: "\(message)")
    }
}
