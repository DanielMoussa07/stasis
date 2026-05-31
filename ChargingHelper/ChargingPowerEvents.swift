import Dispatch
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import notify
import os.log

@MainActor
enum ChargingPowerEvents {
    enum ChargingMode {
        case standard
        case toLimit
        case toFull
    }

    static var chargingMode = ChargingMode.standard
    private static var powerToken: Int32 = 0
    private static var percentToken: Int32 = 0
    private static var isRunning = false

    private static let logger = Logger(subsystem: "com.dinanathdash.stasis.charging-helper", category: "ChargingPowerEvents")

    static func start() {
        guard !isRunning else { return }
        isRunning = true

        notify_register_dispatch(
            kIOPSNotifyPowerSource,
            &powerToken,
            DispatchQueue.main
        ) { _ in
            self.handlePowerEvent()
        }

        notify_register_dispatch(
            "com.apple.system.powersources.percent",
            &percentToken,
            DispatchQueue.main
        ) { _ in
            self.handlePercentEvent()
        }

        let callback: IOServiceInterestCallback = { refCon, service, messageType, messageArgument in
            if messageType == PowerEvents.kIOMessageCanSystemSleep ||
               messageType == PowerEvents.kIOMessageSystemWillSleep {
                IOAllowPowerChange(
                    PowerEvents.root_port,
                    Int(bitPattern: messageArgument)
                )
            } else if messageType == PowerEvents.kIOMessageSystemHasPoweredOn {
                Task { @MainActor in
                    ChargingPowerEvents.wakeFromSleep()
                }
            }
        }

        let success = PowerEvents.register(callback: callback)
        guard success else {
            logger.error("Error registering system power event")
            exit(-1)
        }

        handlePowerEvent()
    }

    static func wakeFromSleep() {
        // Force evaluation on wake
        _ = evaluateState()
    }

    static func stop() {
        guard isRunning else { return }
        isRunning = false
        notify_cancel(powerToken)
        notify_cancel(percentToken)
        PowerEvents.deregister()
    }

    static func chargeToLimit() -> Bool {
        self.chargingMode = .toLimit
        return evaluateState()
    }

    static func chargeToFull() -> Bool {
        self.chargingMode = .toFull
        return evaluateState()
    }

    static func disableCharging() -> Bool {
        self.chargingMode = .standard
        return ChargingPowerState.disableCharging()
    }

    static func settingsChanged() {
        _ = evaluateState()
    }

    private static func handlePowerEvent() {
        _ = evaluateState()
    }

    private static func handlePercentEvent() {
        _ = evaluateState()
    }

    @discardableResult
    private static func evaluateState() -> Bool {
        let (percent, _) = IOKitHelper.getPercentRemaining()
        
        // Heat Protection
        if ChargingSettings.enableHeatProtectionMode,
           let temp = IOKitHelper.getBatteryTemperature(),
           temp > Double(ChargingSettings.heatProtectionLimit) {
            logger.info("Heat protection engaged (Temp: \(temp)C). Disabling charging.")
            return ChargingPowerState.disableCharging()
        }

        if !ChargingSettings.manageCharging {
            // Respect the one-time overrides
            if self.chargingMode == .toLimit && percent < ChargingSettings.chargeLimit {
                return ChargingPowerState.enableCharging()
            } else if self.chargingMode == .toFull && percent < 100 {
                return ChargingPowerState.enableCharging()
            }
            return ChargingPowerState.enableCharging()
        }

        let limit = ChargingSettings.chargeLimit
        let isUnlimited = IOKitHelper.isDrawingUnlimitedPower()

        if !isUnlimited {
            // When disconnected, reset to standard so that next plug-in resumes normal limits
            self.chargingMode = .standard
            return ChargingPowerState.disableCharging()
        }

        // Hysteresis logic
        if percent >= limit {
            if self.chargingMode == .toFull && percent < 100 {
                return ChargingPowerState.enableCharging()
            } else {
                if ChargingSettings.automaticDischarge && percent > limit {
                    _ = ChargingPowerState.disablePowerAdapter()
                } else {
                    _ = ChargingPowerState.enablePowerAdapter()
                }
                return ChargingPowerState.disableCharging()
            }
        } else {
            _ = ChargingPowerState.enablePowerAdapter()
            
            if ChargingSettings.sailingMode {
                let sailingThreshold = limit >= ChargingSettings.sailingModeLimit ? limit - ChargingSettings.sailingModeLimit : 0
                if percent >= sailingThreshold && ChargingPowerState.isChargingDisabled() {
                    // Stay disabled in sailing mode range
                    ChargingPowerState.syncMagSafeState(percent: percent)
                    return true
                }
            }
            return ChargingPowerState.enableCharging()
        }
    }
}

@MainActor
enum PowerEvents {
    private static func err_system(_ x: UInt32) -> UInt32 { return (x & 0x3f) << 26 }
    private static func err_sub(_ x: UInt32) -> UInt32 { return (x & 0xfff) << 14 }
    private static let sys_iokit = err_system(0x38)
    private static let sub_iokit_common = err_sub(0)
    private static func iokit_common_msg(_ message: UInt32) -> UInt32 {
        return (sys_iokit|sub_iokit_common|message)
    }
    
    static let kIOMessageCanSystemSleep = iokit_common_msg(0x270)
    static let kIOMessageSystemWillSleep = iokit_common_msg(0x280)
    static let kIOMessageSystemHasPoweredOn = iokit_common_msg(0x300)
    
    private static var notifyPortRef: IONotificationPortRef? = nil
    private static var notifierObject: io_object_t = IO_OBJECT_NULL
    private(set) static var root_port: io_connect_t = IO_OBJECT_NULL
    
    static func register(callback: @escaping IOServiceInterestCallback) -> Bool {
        assert(self.root_port == IO_OBJECT_NULL)
        assert(self.notifyPortRef == nil)
        assert(self.notifierObject == IO_OBJECT_NULL)

        self.root_port = IORegisterForSystemPower(
            nil,
            &self.notifyPortRef,
            callback,
            &self.notifierObject
        )
        guard self.root_port != IO_OBJECT_NULL else {
            return false
        }

        assert(self.notifyPortRef != nil)
        assert(self.notifierObject != IO_OBJECT_NULL)

        IONotificationPortSetDispatchQueue(
            self.notifyPortRef!,
            DispatchQueue.main
        )
        
        return true
    }

    static func deregister() {
        assert(self.root_port != IO_OBJECT_NULL)
        assert(self.notifyPortRef != nil)
        assert(self.notifierObject != IO_OBJECT_NULL)

        IODeregisterForSystemPower(&self.notifierObject)
        IOServiceClose(self.root_port)
        IONotificationPortDestroy(self.notifyPortRef!)

        self.root_port = IO_OBJECT_NULL
        self.notifyPortRef = nil
        self.notifierObject = IO_OBJECT_NULL
    }
}
