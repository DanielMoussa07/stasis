import Foundation
import os.log
import smc_power

let logger = Logger(
    subsystem: "com.dinanathdash.stasis.charging-helper",
    category: "ServiceDelegate"
)

let battery: SMCBattery
let adapter: SMCAdapter
do {
    battery = try SMCBattery.probe()
    adapter = try SMCAdapter.probe()
} catch {
    logger.fault("Failed to probe SMC capabilities: \(error.localizedDescription)")
    exit(1)
}

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    let helper: ChargingHelper

    init(helper: ChargingHelper) {
        self.helper = helper
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: (any ChargingHelperProtocol).self
        )
        newConnection.exportedObject = helper

        logger.info("XPC connection accepted")

        newConnection.invalidationHandler = {
            logger.info("XPC connection invalidated, but daemon stays alive")
        }

        newConnection.resume()
        return true
    }
}

let helper = ChargingHelper(battery: battery, adapter: adapter)
let delegate = ServiceDelegate(helper: helper)
let listener = NSXPCListener(
    machServiceName: "com.dinanathdash.stasis.charging-helper"
)
listener.delegate = delegate
listener.resume()

// Initialize the SMC Power state controller
ChargingPowerState.initialize(battery: battery, adapter: adapter)

// Start monitoring power events in the background
ChargingPowerEvents.start()

// Setup graceful teardown
let termSource = DispatchSource.makeSignalSource(
    signal: SIGTERM,
    queue: DispatchQueue.main
)
termSource.setEventHandler {
    ChargingPowerState.restoreDefaults()
    ChargingPowerEvents.stop()
    exit(0)
}
termSource.resume()
signal(SIGTERM, SIG_IGN)

dispatchMain()
