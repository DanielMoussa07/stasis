import Defaults
import Foundation
import smc_power

extension MagSafeLEDState: Defaults.Serializable {}

enum OutputVisualizationMode: String, CaseIterable, Defaults.Serializable {
    case off
    case powerOnly
    case batteryOnly
    case always
}

enum BatteryPercentageVisibility: String, CaseIterable, Defaults.Serializable, Identifiable {
    case hidden = "Hidden"
    case nextToIcon = "Next to icon"
    case insideIcon = "Inside icon"
    case insideIconAndNextToItWhenPowered = "Inside (Outside on power)"
    
    var id: Self { self }
}

enum NotchHUDSound: String, CaseIterable, Defaults.Serializable, Identifiable {
    case basso = "Basso"
    case frog = "Frog"
    case glass = "Glass"
    case hero = "Hero"
    case pop = "Pop"
    case tink = "Tink"
    case none = "None"
    
    var id: Self { self }
}

enum NotchHUDDisplayMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case macDisplayOnly = "Mac Display Only"
    case allDisplays = "All Displays"
    
    var id: Self { self }
}

enum CalibrationStatus: String, Defaults.Serializable, Equatable {
    case idle
    case discharging
    case charging
    case resting
}

extension Defaults.Keys {
    // General
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let storedAppVersion = Key<String>("storedAppVersion", default: "")
    static let firstRun = Key<Bool>("firstRun", default: false)

    // Status Icon
    static let batteryPercentageVisibility = Key<BatteryPercentageVisibility>(
        "batteryPercentageVisibility",
        default: .nextToIcon
    )
    static let showBatteryStateInStatusIcon = Key<Bool>(
        "showBatteryStateInStatusIcon",
        default: true
    )

    // Notifications
    static let disableNotifications = Key<Bool>(
        "disableNotifications",
        default: false
    )
    static let showChargingStatusChangedNotification = Key<Bool>(
        "showChargingStatusChangedNotification",
        default: true
    )
    static let enableNotchHUD = Key<Bool>(
        "enableNotchHUD",
        default: true
    )
    static let showNotchHUDOnLockScreen = Key<Bool>(
        "showNotchHUDOnLockScreen",
        default: true
    )
    static let notchHUDDisplayMode = Key<NotchHUDDisplayMode>(
        "notchHUDDisplayMode",
        default: .macDisplayOnly
    )
    static let notchHUDDisplayDuration = Key<Double>(
        "notchHUDDisplayDuration",
        default: 3.0
    )
    static let notchHUDSound = Key<NotchHUDSound>(
        "notchHUDSound",
        default: .frog
    )

    // Menu Dashboard
    static let showTimeTillDischarge = Key<Bool>(
        "showTimeTillDischarge",
        default: true
    )
    static let showBatteryCycleCount = Key<Bool>(
        "showBatteryCycleCount",
        default: true
    )
    static let showBatteryHealth = Key<Bool>("showBatteryHealth", default: true)
    static let showBatteryTemperature = Key<Bool>(
        "showBatteryTemperature",
        default: false
    )
    static let showPowerSource = Key<Bool>("showPowerSource", default: true)
    static let showUptime = Key<Bool>("showUptime", default: true)
    static let showBatteryMode = Key<Bool>("showBatteryMode", default: true)
    static let showInternalPower = Key<Bool>("showInternalPower", default: true)
    static let showExternalPower = Key<Bool>("showExternalPower", default: true)
    static let showPowerDistribution = Key<Bool>(
        "showPowerDistribution",
        default: true
    )
    static let showOutputPortsText = Key<Bool>(
        "showOutputPortsText",
        default: false
    )
    static let outputVisualizationMode = Key<OutputVisualizationMode>(
        "outputVisualizationMode",
        default: .always
    )
    static let showAdvancedChargingControls = Key<Bool>(
        "showAdvancedChargingControls",
        default: false
    )

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: false)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    static let sailingMode = Key<Bool>("sailingMode", default: true)
    static let sailingModeLimit = Key<Int>("sailingModeLimit", default: 5)
    static let automaticDischarge = Key<Bool>(
        "automaticDischarge",
        default: true
    )
    static let disableSleepUntilChargeLimit = Key<Bool>(
        "disableSleepUntilChargeLimit",
        default: false
    )

    // Charging - Heat Protection
    static let enableHeatProtectionMode = Key<Bool>(
        "enableHeatProtectionMode",
        default: true
    )
    static let heatProtectionLimit = Key<Int>(
        "heatProtectionLimit",
        default: 40
    )

    // Charging - MagSafe LED Control
    static let manageMagSafeLED = Key<Bool>("manageMagSafeLED", default: true)
    static let heatProtectionMagSafeLEDState = Key<MagSafeLEDState>(
        "heatProtectionMagSafeLEDState",
        default: MagSafeLEDState.blinkOrangeSlow
    )
    static let chargingOnHoldMagSafeLEDState = Key<MagSafeLEDState>(
        "chargingOnHoldMagSafeLEDState",
        default: MagSafeLEDState.orange
    )
    // Advanced
    static let useHardwarePercentage = Key<Bool>(
        "useHardwarePercentage",
        default: false
    )
    static let useRawHardwareHealth = Key<Bool>(
        "useRawHardwareHealth",
        default: false
    )

    // Calibration
    static let enableAutomaticCalibration = Key<Bool>(
        "enableAutomaticCalibration",
        default: false
    )
    static let calibrationIntervalDays = Key<Int>(
        "calibrationIntervalDays",
        default: 30
    )
    static let calibrationTimeOfDay = Key<Date>(
        "calibrationTimeOfDay",
        default: {
            var components = DateComponents()
            components.hour = 9
            components.minute = 0
            return Calendar.current.date(from: components) ?? Date()
        }()
    )
    static let lastCalibrationDate = Key<Date?>(
        "lastCalibrationDate",
        default: nil
    )
    static let calibrationStatus = Key<CalibrationStatus>(
        "calibrationStatus",
        default: .idle
    )
    static let calibrationStepStartTime = Key<Date?>(
        "calibrationStepStartTime",
        default: nil
    )
    static let calibrationSnoozeUntil = Key<Date?>(
        "calibrationSnoozeUntil",
        default: nil
    )
}
