import Defaults
import os.log
import ServiceManagement
import smc_power
import SwiftUI

struct ChargingSettingsView: View {
    @Default(.manageCharging) var manageCharging
    @Default(.chargeLimit) var chargeLimit
    @Default(.sailingMode) var sailingMode
    @Default(.sailingModeLimit) var sailingModeLimit
    @Default(.automaticDischarge) var automaticDischarge
    @Default(.disableSleepUntilChargeLimit) var disableSleepUntilChargeLimit
    @Default(.disableSleepWhileDischarging) var disableSleepWhileDischarging
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Default(.heatProtectionLimit) var heatProtectionLimit
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState
    @Default(.chargingMagSafeLEDState) var chargingMagSafeLEDState
    @Default(.pausedMagSafeLEDState) var pausedMagSafeLEDState
    @Default(.dischargingMagSafeLEDState) var dischargingMagSafeLEDState

    // Calibration settings
    @Default(.enableAutomaticCalibration) var enableAutomaticCalibration
    @Default(.calibrationIntervalDays) var calibrationIntervalDays
    @Default(.calibrationTimeOfDay) var calibrationTimeOfDay
    @Default(.calibrationStatus) var calibrationStatus
    @Default(.lastCalibrationDate) var lastCalibrationDate

    @Environment(ChargeManager.self) private var chargeManager
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

    /// PowerUI (macOS 26/27) only supports discrete charge-limit steps (80, 85, 90, 95, 100),
    /// so the sailing threshold must land on one of those steps below `limit` — i.e. a multiple
    /// of 5, between 5 and `limit - 80`. Clamps (and snaps to 5s) whatever value is currently set.
    private func clampedSailingModeLimit(for limit: Int) -> Int {
        guard capabilities.nativeMode else {
            return min(max(sailingModeLimit, 1), 20)
        }
        let lower = 5
        let upper = max(lower, limit - 80)
        let snapped = (sailingModeLimit / 5) * 5
        return min(max(snapped, lower), upper)
    }

    /// Re-persists `sailingModeLimit` if it's no longer valid for the current charge limit —
    /// e.g. it was set at a higher limit and the limit was since lowered, or the device is in
    /// PowerUI native mode where only 5%-step thresholds are valid.
    private func reclampSailingModeLimitIfNeeded() {
        guard sailingMode else { return }
        let clamped = clampedSailingModeLimit(for: chargeLimit)
        if clamped != sailingModeLimit {
            sailingModeLimit = clamped
        }
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

                if helperManager.helperStatus != .installed {
                    LabeledContent {
                        Button("Enable Helper") {
                            Task { await installHelper() }
                        }
                        .disabled(helperManager.isInstalling)
                    } label: {
                        Text(
                            "Approve with Touch ID or your password to install the background helper."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                if manageCharging {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(chargeLimit) },
                                    set: { chargeLimit = Int($0) }
                                ),
                                in: (capabilities.nativeMode ? 80.0 : 50.0) ... 100.0,
                                step: 5
                            )
                            Text(chargeLimit.formattedPercentage)
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
                } else if manageCharging {
                    Text(
                        "For reliable charge management, ensure that \"Optimize Battery Charging\" is disabled and Apple's native Charge Limit is exactly at **\(100.formattedPercentage)** in **System Settings → Battery**."
                    )
                }
            }

            if manageCharging {
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
                    } else if capabilities.dischargeOnlyFallback && !automaticDischarge {
                        Text("Your Mac's firmware can't pause charging directly on this macOS version. Turn on Automatic Discharge, or your charge limit won't be enforced.")
                    }
                }

                Section {
                    Toggle(
                        "Disable sleep until charge limit",
                        isOn: $disableSleepUntilChargeLimit
                    )
                    Toggle(
                        "Disable sleep while discharging",
                        isOn: $disableSleepWhileDischarging
                    )
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep Prevention")
                        Text(
                            "Prevent your Mac from sleeping while charging or discharging. This enables Clamshell Mode while discharging."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                if capabilities.nativeMode && chargeLimit <= 80 {
                    Section {
                        Text("Sailing mode requires a charge limit above 80% on this device.")
                            .foregroundStyle(.secondary)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sailing Mode")
                            Text("Automatically resume charging when the battery drops below the threshold relative to your charge limit.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Toggle("Enable sailing mode", isOn: $sailingMode)
                            .disabled(!hasChargingControl)

                        if sailingMode {
                            LabeledContent {
                                HStack(spacing: 8) {
                                    if capabilities.nativeMode && chargeLimit <= 85 {
                                        Text("5%")
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .trailing)
                                    } else {
                                        Slider(
                                            value: Binding(
                                                get: { Double(clampedSailingModeLimit(for: chargeLimit)) },
                                                set: { sailingModeLimit = Int($0) }
                                            ),
                                            in: (capabilities.nativeMode ? 5.0 : 1.0) ... (capabilities.nativeMode ? Double(chargeLimit - 80) : 20.0),
                                            step: capabilities.nativeMode ? 5.0 : 1.0
                                        )
                                        Text(sailingModeLimit.formattedPercentage)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                }
                            } label: {
                                Text("Threshold below limit")
                            }

                            LabeledContent("Charging resumes at") {
                                Text(sailingResumePercentage.formattedPercentage)
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
                                    in: 30 ... 50,
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
                            Picker(String(localized: "LED while charging"), selection: $chargingMagSafeLEDState) {
                                Text(String(localized: "Reset to System")).tag(MagSafeLEDState.reset)
                                Text(String(localized: "Off")).tag(MagSafeLEDState.off)
                                Text(String(localized: "Green")).tag(MagSafeLEDState.green)
                                Text(String(localized: "Orange")).tag(MagSafeLEDState.orange)
                                Text(String(localized: "Blinking Orange Slow")).tag(MagSafeLEDState.blinkOrangeSlow)
                                Text(String(localized: "Blinking Orange Fast")).tag(MagSafeLEDState.blinkOrangeFast)
                            }

                            Picker(String(localized: "LED when paused or limit reached"), selection: $pausedMagSafeLEDState) {
                                Text(String(localized: "Reset to System")).tag(MagSafeLEDState.reset)
                                Text(String(localized: "Off")).tag(MagSafeLEDState.off)
                                Text(String(localized: "Green")).tag(MagSafeLEDState.green)
                                Text(String(localized: "Orange")).tag(MagSafeLEDState.orange)
                                Text(String(localized: "Blinking Orange Slow")).tag(MagSafeLEDState.blinkOrangeSlow)
                                Text(String(localized: "Blinking Orange Fast")).tag(MagSafeLEDState.blinkOrangeFast)
                            }

                            Picker(String(localized: "LED while discharging"), selection: $dischargingMagSafeLEDState) {
                                Text(String(localized: "Reset to System")).tag(MagSafeLEDState.reset)
                                Text(String(localized: "Off")).tag(MagSafeLEDState.off)
                                Text(String(localized: "Green")).tag(MagSafeLEDState.green)
                                Text(String(localized: "Orange")).tag(MagSafeLEDState.orange)
                                Text(String(localized: "Blinking Orange Slow")).tag(MagSafeLEDState.blinkOrangeSlow)
                                Text(String(localized: "Blinking Orange Fast")).tag(MagSafeLEDState.blinkOrangeFast)
                            }

                            if enableHeatProtectionMode {
                                Picker(
                                    String(localized: "LED during heat protection"),
                                    selection: $heatProtectionMagSafeLEDState
                                ) {
                                    Text(String(localized: "Reset to System")).tag(MagSafeLEDState.reset)
                                    Text(String(localized: "Off")).tag(MagSafeLEDState.off)
                                    Text(String(localized: "Green")).tag(MagSafeLEDState.green)
                                    Text(String(localized: "Orange")).tag(MagSafeLEDState.orange)
                                    Text(String(localized: "Blinking Orange Slow")).tag(
                                        MagSafeLEDState.blinkOrangeSlow
                                    )
                                    Text(String(localized: "Blinking Orange Fast")).tag(
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
                        } else if manageMagSafeLED {
                            Text(
                                String(localized: "Note: The slow and fast blinking speeds may appear identical on modern Macs due to hardware limitations.")
                            )
                        }
                    }
                }

                if !capabilities.nativeMode {
                    Section {
                        Toggle("Enable automatic calibration", isOn: $enableAutomaticCalibration)
                            .disabled(!hasAnyControl)

                        if enableAutomaticCalibration {
                            Picker("Interval", selection: Binding(
                                get: { self.calibrationIntervalDays },
                                set: { self.calibrationIntervalDays = $0 }
                            )) {
                                Text("Every 7 days").tag(7)
                                Text("Every 14 days").tag(14)
                                Text("Every 30 days").tag(30)
                                Text("Every 60 days").tag(60)
                            }

                            DatePicker("Time of Day", selection: Binding(
                                get: { self.calibrationTimeOfDay },
                                set: { self.calibrationTimeOfDay = $0 }
                            ), displayedComponents: .hourAndMinute)
                        }

                        LabeledContent("Status") {
                            switch calibrationStatus {
                            case .idle:
                                if let last = lastCalibrationDate {
                                    Text("Last calibrated on \(last.formatted(date: .abbreviated, time: .shortened))")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Never calibrated")
                                        .foregroundStyle(.secondary)
                                }
                            case .discharging:
                                Text("Discharging to \(15.formattedPercentage)...")
                                    .foregroundStyle(.orange)
                            case .charging:
                                Text("Charging to \(100.formattedPercentage)...")
                                    .foregroundStyle(.blue)
                            case .resting:
                                Text("Resting at \(100.formattedPercentage)...")
                                    .foregroundStyle(.green)
                            }
                        }

                        if calibrationStatus == .idle {
                            Button("Start Calibration Now") {
                                Defaults[.calibrationStatus] = .discharging
                            }
                            .disabled(!hasAnyControl)
                        } else {
                            Button("Cancel Calibration") {
                                Defaults[.calibrationStatus] = .idle
                            }
                            .foregroundStyle(.red)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery Calibration")
                            Text(
                                "Periodically run a full discharge and recharge cycle to maintain accurate battery capacity readings."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    } footer: {
                        if !hasAnyControl {
                            Text(
                                "Battery calibration is not supported on this device."
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
        .onChange(of: chargeLimit) { _, _ in reclampSailingModeLimitIfNeeded() }
        .onChange(of: sailingMode) { _, _ in reclampSailingModeLimitIfNeeded() }
        .onAppear { reclampSailingModeLimitIfNeeded() }
    }

    private func toggleManageCharging(_ enabled: Bool) {
        guard enabled else {
            // Turning charge management off only updates the setting; ChargeManager syncs it to the
            // daemon, which resets the firmware to defaults. The daemon stays installed so the XPC
            // connection is not torn down.
            manageCharging = false
            return
        }
        guard helperManager.isInstalled else {
            Task { await installHelper() }
            return
        }
        enableChargeManagement()
    }

    private func installHelper() async {
        NSApp.activate(ignoringOtherApps: true)
        do {
            try await helperManager.install()
            chargeManager.forceSyncSettings()
            enableChargeManagement()
        } catch PrivilegedHelperInstaller.InstallerError.cancelled {
            logger.info("Helper install cancelled by the user")
        } catch {
            logger.error("Failed to install charging helper: \(error)")
            NSAlert.show(
                title: String(localized: "Failed to install charging helper"),
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func enableChargeManagement() {
        manageCharging = true
        Defaults[.launchAtLogin] = true
        LaunchAtLoginService.shared.setLaunchAtLogin(true)
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
