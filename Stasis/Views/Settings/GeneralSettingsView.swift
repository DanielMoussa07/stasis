import Defaults
import SwiftUI

struct GeneralSettingsView: View {
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.batteryPercentageVisibility) var batteryPercentageVisibility
    @Default(.showBatteryStateInStatusIcon) var showBatteryStateInStatusIcon
    @Default(.disableNotifications) var disableNotifications
    @Default(.showChargingStatusChangedNotification) var showChargingStatusChangedNotification
    @Default(.enableNotchHUD) var enableNotchHUD
    @Default(.showNotchHUDOnLockScreen) var showNotchHUDOnLockScreen
    @Default(.notchHUDDisplayMode) var notchHUDDisplayMode

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Section {
                Picker("Battery percentage", selection: $batteryPercentageVisibility) {
                    ForEach(BatteryPercentageVisibility.allCases) { visibility in
                        Text(LocalizedStringKey(visibility.rawValue)).tag(visibility)
                    }
                }
                Toggle("Show battery state", isOn: $showBatteryStateInStatusIcon)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu Bar Icon")
                    Text(
                        "Display battery percentage next to or inside the menu bar icon."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Disable all notifications", isOn: $disableNotifications)
                Toggle("Charging status changed", isOn: $showChargingStatusChangedNotification)
                    .disabled(disableNotifications)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications")
                    Text("Control when Stasis sends you notifications.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show charging state in Notch HUD", isOn: $enableNotchHUD)
                if enableNotchHUD {
                    Toggle("Show on lock screen", isOn: $showNotchHUDOnLockScreen)
                    Picker("Display mode", selection: $notchHUDDisplayMode) {
                        ForEach(NotchHUDDisplayMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notch HUD")
                    Text("Display a floating Dynamic Island-style HUD when the charging state changes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollEdgeEffectStyleSoftIfAvailable()
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginService.shared.setLaunchAtLogin(newValue)
        }
    }
}

#Preview {
    GeneralSettingsView()
}
