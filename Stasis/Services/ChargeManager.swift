import Defaults
import Foundation
import IOKit.pwr_mgt
import Observation
import UserNotifications
import os.log
import smc_power

@MainActor
@Observable
class ChargeManager {
    private let batteryService: BatteryService

    private var settingsObservation: Task<Void, Never>?

    private(set) var chargeLimitOverrideActive = false
    private(set) var forceDischargeActive = false

    private let logger = Logger(
        subsystem: "com.dinanathdash.stasis",
        category: "ChargeManager"
    )

    init(batteryService: BatteryService) {
        self.batteryService = batteryService
        startObservingSettings()
    }

    private func startObservingSettings() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [
                    .manageCharging, .sailingMode, .automaticDischarge,
                    .enableHeatProtectionMode, .manageMagSafeLED,
                    .chargeLimit, .sailingModeLimit, .heatProtectionLimit,
                    .disableSleepUntilChargeLimit, .chargingOnHoldMagSafeLEDState,
                    .heatProtectionMagSafeLEDState
                ],
                initial: true
            ) {
                guard let self else { return }
                self.syncSettingsToDaemon()
            }
        }
    }

    private func syncSettingsToDaemon() {
        let settings: [String: NSObject & Sendable] = [
            "manageCharging": Defaults[.manageCharging] as NSNumber,
            "chargeLimit": Defaults[.chargeLimit] as NSNumber,
            "sailingMode": Defaults[.sailingMode] as NSNumber,
            "sailingModeLimit": Defaults[.sailingModeLimit] as NSNumber,
            "automaticDischarge": Defaults[.automaticDischarge] as NSNumber,
            "enableHeatProtectionMode": Defaults[.enableHeatProtectionMode] as NSNumber,
            "heatProtectionLimit": Defaults[.heatProtectionLimit] as NSNumber,
            "disableSleepUntilChargeLimit": Defaults[.disableSleepUntilChargeLimit] as NSNumber,
            "manageMagSafeLED": Defaults[.manageMagSafeLED] as NSNumber,
            "chargingOnHoldMagSafeLEDState": Defaults[.chargingOnHoldMagSafeLEDState].rawValue as NSNumber,
            "heatProtectionMagSafeLEDState": Defaults[.heatProtectionMagSafeLEDState].rawValue as NSNumber
        ]

        Task {
            let maxRetries = 5
            for attempt in 1...maxRetries {
                do {
                    try await batteryService.setSettings(settings: settings)
                    logger.info("Successfully synced settings to daemon on attempt \(attempt)")
                    // Once settings are synced, trigger a single poll to update UI immediately
                    batteryService.scheduleSinglePoll(delay: .milliseconds(500))
                    break
                } catch {
                    logger.error("Failed to sync settings to daemon (attempt \(attempt)): \(error.localizedDescription)")
                    if attempt < maxRetries {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
        }
    }

    func toggleChargeLimitOverride() {
        chargeLimitOverrideActive.toggle()
        Task {
            do {
                if chargeLimitOverrideActive {
                    try await batteryService.chargeToFull()
                } else {
                    try await batteryService.disableCharging()
                }
                batteryService.scheduleSinglePoll()
            } catch {
                logger.error("Failed to toggle charge limit override: \(error.localizedDescription)")
                chargeLimitOverrideActive.toggle() // revert on failure
            }
        }
    }

    func toggleForceDischarge() {
        forceDischargeActive.toggle()
        Task {
            do {
                if forceDischargeActive {
                    try await batteryService.disablePowerAdapter()
                } else {
                    try await batteryService.enablePowerAdapter()
                }
                batteryService.scheduleSinglePoll()
            } catch {
                logger.error("Failed to toggle force discharge: \(error.localizedDescription)")
                forceDischargeActive.toggle() // revert on failure
            }
        }
    }

    func stop() {
        settingsObservation?.cancel()
        settingsObservation = nil
    }
}
