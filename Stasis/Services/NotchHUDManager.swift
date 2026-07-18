import AppKit
import Defaults
import Foundation
import Observation
import SwiftUI

@MainActor
class NotchHUDManager {
    private let window: NotchWindow
    private let viewModel: MenuViewModel
    private var observationTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private let state = NotchHUDState() // Persistent state for smooth animations

    // Track previous states to detect changes
    private var previousChargingMode: ChargingMode?
    private var previousLowPowerMode: Bool?
    private var previousForceDischarge: Bool?
    private var previousAdapterConnected: Bool?

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        self.window = NotchWindow()
        // Override default shadow padding/height for our custom view
        self.window.contentHeight = 36
        self.window.shadowPadding = 0 // Tighter padding for a cleaner look
        self.window.hasShadow = false // Fix grayish color blending

        startObserving()
    }

    private func startObserving() {
        observationTask = Task {
            // Wait for initial values to settle
            try? await Task.sleep(for: .seconds(2))
            
            // Set initial state without triggering HUD
            previousChargingMode = viewModel.chargingMode
            previousLowPowerMode = viewModel.isLowPowerModeEnabled
            previousForceDischarge = viewModel.forceDischargeActive
            previousAdapterConnected = viewModel.adapterConnected

            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                // To allow Low Power Mode observation without polling
                Task { @MainActor in
                    self.checkStateAndShowHUD()
                }
            }
        }
        
        Task {
            // Give time for initial properties to settle
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = viewModel.chargingMode
                        _ = viewModel.isLowPowerModeEnabled
                        _ = viewModel.forceDischargeActive
                        _ = viewModel.adapterConnected
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
                checkStateAndShowHUD()
            }
        }
    }

    private func checkStateAndShowHUD() {
        guard Defaults[.enableNotchHUD] else { return }
        
        if !Defaults[.showNotchHUDOnLockScreen] {
            if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
               let isLocked = session["CGSSessionScreenIsLocked"] as? Bool,
               isLocked {
                return
            }
        }

        let currentChargingMode = viewModel.chargingMode
        let currentLowPowerMode = viewModel.isLowPowerModeEnabled
        let currentForceDischarge = viewModel.forceDischargeActive
        let currentAdapterConnected = viewModel.adapterConnected

        // Determine what changed
        let modeChanged = currentChargingMode != previousChargingMode
        let lpmChanged = currentLowPowerMode != previousLowPowerMode
        let fdChanged = currentForceDischarge != previousForceDischarge
        let adapterChanged = currentAdapterConnected != previousAdapterConnected

        // If something relevant changed, show HUD
        if modeChanged || lpmChanged || fdChanged || adapterChanged {
            let text = determineStatusText(
                chargingMode: currentChargingMode,
                lowPowerMode: currentLowPowerMode,
                forceDischarge: currentForceDischarge,
                adapterConnected: currentAdapterConnected,
                lpmChanged: lpmChanged
            )
            showHUD(with: text)
        }

        // Update tracking
        previousChargingMode = currentChargingMode
        previousLowPowerMode = currentLowPowerMode
        previousForceDischarge = currentForceDischarge
        previousAdapterConnected = currentAdapterConnected
    }

    private func determineStatusText(
        chargingMode: ChargingMode,
        lowPowerMode: Bool,
        forceDischarge: Bool,
        adapterConnected: Bool,
        lpmChanged: Bool
    ) -> String {
        if lowPowerMode && lpmChanged {
            return "Low Power Mode"
        }
        if forceDischarge {
            return "Force Discharging"
        }
        if !adapterConnected {
            return "On Battery"
        }
        if chargingMode == .charging {
            return "Charging"
        }
        if chargingMode == .pluggedIn {
            if Defaults[.manageCharging] {
                // If manage charging is on and we are plugged in but not charging
                let level = viewModel.displayPercentage
                if level >= Defaults[.chargeLimit] {
                    return "Limit Reached"
                } else if Defaults[.sailingMode] {
                    return "Sailing Mode"
                } else {
                    return "On Hold"
                }
            }
            if viewModel.displayPercentage == 100 {
                return "Fully Charged"
            }
            return "Plugged In"
        }
        return "Unknown"
    }

    private func showHUD(with text: String) {
        let displayMode = Defaults[.notchHUDDisplayMode]
        var targetScreens: [NSScreen] = []
        
        if displayMode == .macDisplayOnly {
            // Find the screen with a physical notch
            if let notchScreen = NSScreen.screens.first(where: { NotchWindow.hasNotch(screen: $0) }) {
                targetScreens.append(notchScreen)
            } else if let mainScreen = NSScreen.main {
                // Fallback to main if no notch is found, maybe it's an older Mac display
                targetScreens.append(mainScreen)
            }
        } else {
            // Show on main screen or all screens. For simplicity, just use main screen if all displays
            if let mainScreen = NSScreen.main {
                targetScreens.append(mainScreen)
            }
        }

        guard let targetScreen = targetScreens.first else { return }
        let isPill = !NotchWindow.hasNotch(screen: targetScreen)

        let wasVisible = window.isVisible
        
        // Ensure state starts collapsed if window is not visible
        if !wasVisible {
            state.isVisible = false
        }

        // Update state content
        state.statusText = text
        state.batteryLevel = viewModel.displayPercentage
        state.chargingMode = viewModel.chargingMode
        state.isLowPowerModeEnabled = viewModel.isLowPowerModeEnabled
        
        // Ensure the window is shown with the view bound to our state
        if window.contentView == nil || !wasVisible {
            let contentView = ChargingNotchView(state: state)
            if !isPill {
                window.contentHeight = targetScreen.safeAreaInsets.top
                window.showNotch(on: targetScreen, content: contentView)
            } else {
                window.contentHeight = 36
                window.showPill(on: targetScreen, content: contentView)
            }
            
            // Trigger animation on next runloop tick so view is in hierarchy
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                self.state.isVisible = true
            }
        } else {
            state.isVisible = true
        }

        // Cancel existing hide task
        hideTask?.cancel()

        // Create new hide task
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            
            // Trigger SwiftUI collapse animation
            state.isVisible = false
            
            // Wait for spring animation to finish then close window
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            window.orderOut(nil)
        }
    }
}
