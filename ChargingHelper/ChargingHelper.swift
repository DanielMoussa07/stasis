import Foundation
import os.log
import smc_power

private enum Constants {
    static let subsystem = "com.dinanathdash.stasis.charging-helper"
}

final class ChargingHelper: NSObject, ChargingHelperProtocol, @unchecked Sendable {
    private let logger = Logger(
        subsystem: Constants.subsystem,
        category: "ChargingHelper"
    )

    init(battery: SMCBattery, adapter: SMCAdapter) {
        super.init()
        Task { @MainActor in
            ChargingPowerState.initialize(battery: battery, adapter: adapter)
            ChargingPowerEvents.start()
        }
        
        logger.info(
            "Initialized (charging=\(battery.capabilities.inhibitChargeControl), discharge=\(battery.capabilities.forceDischargeControl), magSafe=\(adapter.capabilities.magSafeControl))"
        )
    }

    func setSettings(settings: [String: NSObject & Sendable], reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            ChargingSettings.setSettings(settings: settings)
            ChargingPowerEvents.settingsChanged()
            reply(true, nil)
        }
    }

    func getSettings(reply: @escaping @Sendable ([String: NSObject & Sendable]) -> Void) {
        Task { @MainActor in
            reply(ChargingSettings.getSettings())
        }
    }

    func chargeToLimit(reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            let success = ChargingPowerEvents.chargeToLimit()
            reply(success, nil)
        }
    }

    func chargeToFull(reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            let success = ChargingPowerEvents.chargeToFull()
            reply(success, nil)
        }
    }

    func disableCharging(reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            let success = ChargingPowerEvents.disableCharging()
            reply(success, nil)
        }
    }

    func disablePowerAdapter(reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            let success = ChargingPowerState.disablePowerAdapter()
            reply(success, nil)
        }
    }

    func enablePowerAdapter(reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            let success = ChargingPowerState.enablePowerAdapter()
            reply(success, nil)
        }
    }

    func manageMagsafeLED(target: UInt8, reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            let success = ChargingPowerState.manageMagsafeLED(target: target)
            reply(success, nil)
        }
    }

    func resetToDefaults(reply: @escaping @Sendable (Bool, String?) -> Void) {
        Task { @MainActor in
            ChargingPowerEvents.chargingMode = .standard
            ChargingPowerState.restoreDefaults()
            reply(true, nil)
        }
    }
}

