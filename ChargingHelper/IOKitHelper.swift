import Foundation
import IOKit.ps
import IOKit.pwr_mgt

enum IOKitHelper {
    static func getPowerSourceInfo() -> CFDictionary? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        guard let source = sources.first else { return nil }
        return IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue()
    }

    static func getPercentRemaining() -> (UInt8, Bool) {
        guard let info = getPowerSourceInfo() as? [String: Any],
              let percent = info[kIOPSCurrentCapacityKey] as? Int,
              let isCharging = info[kIOPSIsChargingKey] as? Bool else {
            return (100, false)
        }
        return (UInt8(max(0, min(100, percent))), isCharging)
    }

    static func getBatteryTemperature() -> Double? {
        guard let info = getPowerSourceInfo() as? [String: Any],
              let tempDecikelvin = info[kIOPSTemperatureKey] as? Int,
              tempDecikelvin > 0 else {
            return nil
        }
        let celsius = (Double(tempDecikelvin) / 10.0) - 273.15
        return (0...80).contains(celsius) ? celsius : nil
    }

    static func isDrawingUnlimitedPower() -> Bool {
        guard let info = getPowerSourceInfo() as? [String: Any],
              let powerSourceState = info[kIOPSPowerSourceStateKey] as? String else {
            return false
        }
        return powerSourceState == kIOPSACPowerValue
    }
}
