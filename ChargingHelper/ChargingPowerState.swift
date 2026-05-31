import Foundation
import os.log
import smc_power
import IOPMPrivate

@MainActor
enum ChargingPowerState {
    private static var chargingDisabled = false
    private static var powerDisabled = false
    
    private static var battery: SMCBattery?
    private static var adapter: SMCAdapter?

    private static let logger = Logger(subsystem: "com.dinanathdash.stasis.charging-helper", category: "ChargingPowerState")

    static func initialize(battery: SMCBattery, adapter: SMCAdapter) {
        self.battery = battery
        self.adapter = adapter
        
        do {
            if battery.capabilities.inhibitChargeControl {
                self.chargingDisabled = try battery.getChargingInhibited()
            }
            if battery.capabilities.forceDischargeControl {
                self.powerDisabled = try battery.getForceDischarging()
            }
        } catch {
            logger.error("Failed to read initial states: \(error.localizedDescription)")
        }
        
        GlobalSleep.restoreOnStart()
    }

    static func isChargingDisabled() -> Bool {
        return self.chargingDisabled
    }

    static func isPowerAdapterDisabled() -> Bool {
        return self.powerDisabled
    }

    static func disableCharging() -> Bool {
        guard !self.chargingDisabled else { return true }
        guard let battery = self.battery, battery.capabilities.inhibitChargeControl else { return false }

        do {
            try battery.setChargingInhibited(true)
            self.chargingDisabled = true
            logger.debug("SMC set charging inhibited to true")
            
            GlobalSleep.restore()
            let (percent, _) = IOKitHelper.getPercentRemaining()
            syncMagSafeState(percent: percent)
            return true
        } catch {
            logger.error("Failed to disable charging: \(error.localizedDescription)")
            return false
        }
    }

    static func enableCharging() -> Bool {
        guard self.chargingDisabled else { return true }
        guard let battery = self.battery, battery.capabilities.inhibitChargeControl else { return false }

        do {
            try battery.setChargingInhibited(false)
            self.chargingDisabled = false
            logger.debug("SMC set charging inhibited to false")
            
            if ChargingSettings.disableSleepUntilChargeLimit {
                GlobalSleep.disable()
            }
            let (percent, _) = IOKitHelper.getPercentRemaining()
            syncMagSafeState(percent: percent)
            return true
        } catch {
            logger.error("Failed to enable charging: \(error.localizedDescription)")
            return false
        }
    }

    static func disablePowerAdapter() -> Bool {
        guard !self.powerDisabled else { return true }
        guard let battery = self.battery, battery.capabilities.forceDischargeControl else { return false }

        do {
            try battery.setForceDischarging(true)
            self.powerDisabled = true
            logger.debug("SMC set force discharging to true")
            return true
        } catch {
            logger.error("Failed to disable power adapter: \(error.localizedDescription)")
            return false
        }
    }

    static func enablePowerAdapter() -> Bool {
        guard self.powerDisabled else { return true }
        guard let battery = self.battery, battery.capabilities.forceDischargeControl else { return false }

        do {
            try battery.setForceDischarging(false)
            self.powerDisabled = false
            logger.debug("SMC set force discharging to false")
            return true
        } catch {
            logger.error("Failed to enable power adapter: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func manageMagsafeLED(target: UInt8) -> Bool {
        guard ChargingSettings.manageMagSafeLED else { return false }
        guard let adapter = self.adapter, adapter.capabilities.magSafeControl else { return false }
        guard let ledState = MagSafeLEDState(rawValue: target) else { return false }

        do {
            try adapter.setMagSafeLEDState(ledState)
            logger.info("MagSafe LED set to \(target)")
            return true
        } catch {
            logger.error("Failed to set MagSafe LED: \(error.localizedDescription)")
            return false
        }
    }

    static func syncMagSafeState(percent: UInt8) {
        if self.powerDisabled || percent == 100 || self.chargingDisabled {
            manageMagsafeLED(target: MagSafeLEDState.green.rawValue)
        } else {
            manageMagsafeLED(target: MagSafeLEDState.orange.rawValue)
        }
    }

    static func restoreDefaults() {
        _ = enableCharging()
        _ = enablePowerAdapter()
        _ = manageMagsafeLED(target: MagSafeLEDState.reset.rawValue)
    }
}

@MainActor
enum GlobalSleep {
    private static let previousSleepDisabledKey = "PreviousSleepDisabled"
    private static var disabledCounter: UInt8 = 0
    private static var previousDisabled = false

    static func restoreOnStart() {
        guard let value = UserDefaults.standard.object(forKey: self.previousSleepDisabledKey) as? Bool else {
            return
        }
        
        self.setSleepDisabledIOPMValue(value: value as CFBoolean)
        UserDefaults.standard.removeObject(forKey: self.previousSleepDisabledKey)
    }

    static func forceRestore() {
        guard self.disabledCounter > 0 else { return }
        self.disabledCounter = 0
        self.restorePrevious()
    }

    static func restore() {
        guard self.disabledCounter > 0 else { return }
        self.disabledCounter -= 1
        guard self.disabledCounter == 0 else { return }
        self.restorePrevious()
    }

    static func disable() {
        assert(self.disabledCounter >= 0)
        self.disabledCounter += 1
        guard self.disabledCounter == 1 else { return }

        let sleepDisable = self.getSleepDisabledIOPMValue()
        self.previousDisabled = sleepDisable
        UserDefaults.standard.setValue(sleepDisable, forKey: self.previousSleepDisabledKey)

        guard !sleepDisable else { return }
        self.setSleepDisabledIOPMValue(value: kCFBooleanTrue)
    }

    private static func getSleepDisabledIOPMValue() -> Bool {
        guard let settingsRef = IOPMCopySystemPowerSettings() else { return false }
        guard let settings = settingsRef.takeUnretainedValue() as? [String: AnyObject] else { return false }
        guard let sleepDisable = settings[kIOPMSleepDisabledKey] as? Bool else { return false }
        return sleepDisable
    }

    private static func setSleepDisabledIOPMValue(value: CFBoolean) {
        let result = IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey as CFString, value)
        if result != kIOReturnSuccess {
            // logger.error(...)
        }
    }

    private static func restorePrevious() {
        guard !self.previousDisabled else {
            self.previousDisabled = false
            return
        }
        self.setSleepDisabledIOPMValue(value: kCFBooleanFalse)
        UserDefaults.standard.removeObject(forKey: self.previousSleepDisabledKey)
    }
}
