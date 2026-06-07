import Defaults
import ServiceManagement
import SwiftUI
import os.log
import smc_power

struct ChargingSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.chargeLimit) var chargeLimit
    @Default(.sailingMode) var sailingMode
    @Default(.sailingModeLimit) var sailingModeLimit
    @Default(.automaticDischarge) var automaticDischarge
    @Default(.disableSleepUntilChargeLimit) var disableSleepUntilChargeLimit
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Default(.heatProtectionLimit) var heatProtectionLimit
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState
    @Default(.chargingOnHoldMagSafeLEDState) var chargingOnHoldMagSafeLEDState
    @State private var helperManager = ChargingHelperManager.shared

    private let capabilities: DeviceCapabilities

    private let logger = Logger(
        subsystem: "com.dinanathdash.stasis",
        category: "ChargingSettingsView"
    )

    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
    }

    private var hasChargingControl: Bool {
        capabilities.chargingControl
    }

    private var hasAdapterControl: Bool {
        capabilities.adapterControl
    }

    private var hasMagSafe: Bool {
        capabilities.hasMagSafe
    }

    private var hasAnyControl: Bool {
        hasChargingControl || hasAdapterControl
    }

    private var sailingResumePercentage: Int {
        chargeLimit - sailingModeLimit
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Manage charging",
                    isOn: Binding(
                        get: { manageCharging },
                        set: { newValue in
                            toggleManageCharging(newValue)
                        }
                    )
                )
                .disabled(!hasAnyControl)

                if helperManager.helperStatus == .requiresApproval {
                    LabeledContent {
                        HStack {
                            Button("Open Settings") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            Button("Check Again") {
                                checkApprovalStatus()
                            }
                        }
                    } label: {
                        Text(
                            "Approve Stasis in System Settings \u{2192} Login Items to continue."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                if manageCharging && helperManager.helperStatus == .installed {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(chargeLimit) },
                                    set: { chargeLimit = Int($0) }
                                ),
                                in: 50...100,
                                step: 5
                            )
                            Text("\(chargeLimit)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    } label: {
                        Text("Charge limit")
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge Management")
                    Text(
                        "Limit the maximum charge level to extend battery lifespan."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } footer: {
                if !hasAnyControl {
                    Text("Charge management is not supported on this device.")
                } else if manageCharging
                    && helperManager.helperStatus == .installed
                {
                    Text(
                        "For reliable charge management, ensure that \"Optimize Battery Charging\" is disabled and Apple's native Charge Limit is exactly at **100%** in **System Settings → Battery**."
                    )
                }
            }

            if manageCharging && helperManager.helperStatus == .installed {
                Section {
                    Toggle("Automatic discharge", isOn: $automaticDischarge)
                        .disabled(!hasAdapterControl)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discharge")
                        Text(
                            "Discharge the battery to your charge limit when plugged in above the target level."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                } footer: {
                    if !hasAdapterControl {
                        Text("Adapter control is not supported on this device.")
                    }
                }

                Section {
                    Toggle(
                        "Disable sleep until charge limit",
                        isOn: $disableSleepUntilChargeLimit
                    )
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Prevention")
                        Text(
                            "Prevent your Mac from sleeping while charging towards the charge limit. Sleep is re-enabled once the limit is reached or the adapter is disconnected."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Enable sailing mode", isOn: $sailingMode)
                        .disabled(!hasChargingControl)

                    if sailingMode {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(sailingModeLimit) },
                                        set: { sailingModeLimit = Int($0) }
                                    ),
                                    in: 1...20,
                                    step: 1
                                )
                                Text("\(sailingModeLimit)%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Threshold below limit")
                        }

                        LabeledContent("Charging resumes at") {
                            Text("\(sailingResumePercentage)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sailing Mode")
                        Text(
                            "Automatically resume charging when the battery drops below the threshold relative to your charge limit."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                } footer: {
                    if !hasChargingControl {
                        Text(
                            "Charging control is not supported on this device."
                        )
                    }
                }

                Section {
                    Toggle(
                        "Enable heat protection",
                        isOn: $enableHeatProtectionMode
                    )
                    .disabled(!hasChargingControl)

                    if enableHeatProtectionMode {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(heatProtectionLimit) },
                                        set: { heatProtectionLimit = Int($0) }
                                    ),
                                    in: 30...50,
                                    step: 1
                                )
                                Text("\(heatProtectionLimit)°C")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } label: {
                            Text("Temperature limit")
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Heat Protection")
                        Text(
                            "Pause charging when the battery temperature exceeds the threshold."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                } footer: {
                    if !hasChargingControl {
                        Text(
                            "Charging control is not supported on this device."
                        )
                    }
                }

                if hasMagSafe {
                    Section {
                        Toggle("Manage MagSafe LED", isOn: $manageMagSafeLED)
                            .disabled(!capabilities.magsafeLEDControl)

                        if manageMagSafeLED {
                            if enableHeatProtectionMode {
                                Picker(
                                    "LED during heat protection",
                                    selection: $heatProtectionMagSafeLEDState
                                ) {
                                    Text("Off").tag(MagSafeLEDState.off)
                                    Text("Green").tag(MagSafeLEDState.green)
                                    Text("Orange").tag(MagSafeLEDState.orange)
                                    Text("Blinking Orange Slow").tag(
                                        MagSafeLEDState.blinkOrangeSlow
                                    )
                                    Text("Blinking Orange Fast").tag(
                                        MagSafeLEDState.blinkOrangeFast
                                    )
                                }
                            }
                        }
                    } header: {
                        Text("MagSafe LED Control")
                    } footer: {
                        if !capabilities.magsafeLEDControl {
                            Text(
                                "MagSafe LED control is not supported on this device."
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollEdgeEffectStyleSoftIfAvailable()
        .animation(.default, value: manageCharging)
        .animation(.default, value: sailingMode)
        .animation(.default, value: enableHeatProtectionMode)
        .animation(.default, value: manageMagSafeLED)
        .animation(.default, value: helperManager.helperStatus)
    }

    private func toggleManageCharging(_ enabled: Bool) {
        do {
            if enabled {
                try helperManager.install()
                if helperManager.helperStatus == .installed {
                    manageCharging = true
                    Defaults[.launchAtLogin] = true
                    LaunchAtLoginService.shared.setLaunchAtLogin(true)
                } else if helperManager.helperStatus == .requiresApproval {
                    // Store the user's intent to enable charging management so the toggle
                    // reflects a natural ON state (with handle) while waiting for approval.
                    manageCharging = true
                }
            } else {
                try helperManager.uninstall()
                manageCharging = false
            }
        } catch {
            logger.error(
                "Failed to \(enabled ? "install" : "uninstall") charging helper: \(error)"
            )
            let title = "Failed to \(enabled ? "install" : "uninstall") charging helper"
            let msg = error.localizedDescription + "\n\nTip: Check System Settings -> General -> Login Items. Ensure Stasis is allowed to run in the background. If it is already on, try toggling it off and on again."
            NSAlert.show(title: title, message: msg, style: .warning)
        }
    }

    private func checkApprovalStatus() {
        helperManager.refreshStatus()
        if helperManager.helperStatus == .installed {
            do {
                try helperManager.install()
            } catch {
                logger.error(
                    "Failed to install helper after approval: \(error)"
                )
            }
            manageCharging = true
            Defaults[.launchAtLogin] = true
            LaunchAtLoginService.shared.setLaunchAtLogin(true)

            NSAlert.show(
                title: "Success",
                message: "Stasis background helper has been successfully approved and background charging is now active!"
            )
        } else {
            NSAlert.show(
                title: "Approval Required",
                message: "Stasis has not been approved yet.\n\nPlease enable the toggle for Stasis under 'App Background Activity' in the Login Items settings. You may also want to ensure Stasis is added to 'Open at Login'.",
                style: .informational
            )
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

#Preview {
    ChargingSettingsView(
        capabilities: DeviceCapabilities(
            chargingControl: true,
            adapterControl: true,
            hasMagSafe: true,
            magsafeLEDControl: true
        )
    )
}
