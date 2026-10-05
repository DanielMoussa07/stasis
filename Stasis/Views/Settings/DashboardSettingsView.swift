import Defaults
import SwiftUI

struct DashboardSettingsView: View {
    @Default(.showPowerSource) var showPowerSource
    @Default(.showTimeTillDischarge) var showTimeTillDischarge
    @Default(.showUptime) var showUptime
    @Default(.showBatteryMode) var showBatteryMode
    @Default(.showBatteryTemperature) var showBatteryTemperature
    @Default(.showBatteryCycleCount) var showBatteryCycleCount
    @Default(.showBatteryHealth) var showBatteryHealth
    @Default(.showInternalPower) var showInternalPower
    @Default(.showExternalPower) var showExternalPower
    @Default(.showSessionEnergy) var showSessionEnergy
    @Default(.showPowerDistribution) var showPowerDistribution
    @Default(.showTwoDecimalPowerValues) var showTwoDecimalPowerValues
    @Default(.showOutputPortsText) var showOutputPortsText
    @Default(.outputVisualizationMode) var outputVisualizationMode
    @Default(.showSignificantEnergyApps) var showSignificantEnergyApps
    @Default(.showChargeLimitControl) var showChargeLimitControl
    @Default(.showLowPowerModeToggle) var showLowPowerModeToggle

    var body: some View {
        Form {
            Section {
                Toggle("Power source", isOn: $showPowerSource)
                Toggle("Time until discharge", isOn: $showTimeTillDischarge)
                Toggle("Uptime", isOn: $showUptime)
                Toggle("Battery mode", isOn: $showBatteryMode)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status")
                    Text(
                        "General system and battery status information shown in the menu dropdown."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Battery Health") {
                Toggle("Cycle count", isOn: $showBatteryCycleCount)
                Toggle("Health", isOn: $showBatteryHealth)
                Toggle("Temperature", isOn: $showBatteryTemperature)
            }

            Section("Power") {
                Toggle("Battery Power Metrics", isOn: $showInternalPower)
                Toggle("Adapter Power Metrics", isOn: $showExternalPower)
                Toggle("Session Energy", isOn: $showSessionEnergy)
            }

            Section("Controls") {
                Toggle("Charge limit slider", isOn: $showChargeLimitControl)
                Toggle("Low Power Mode toggle", isOn: $showLowPowerModeToggle)
            }

            Section("Energy Impact") {
                Toggle("Apps using significant energy", isOn: $showSignificantEnergyApps)
            }

            Section("Visuals") {
                Toggle("Power distribution diagram", isOn: $showPowerDistribution)
                Toggle(
                    "Two decimal places for power values",
                    isOn: $showTwoDecimalPowerValues
                )
                .disabled(!showPowerDistribution)
                Picker("Show outgoing output", selection: $outputVisualizationMode) {
                    Text("Off").tag(OutputVisualizationMode.off)
                    Text("Power Only").tag(OutputVisualizationMode.powerOnly)
                    Text("Battery Only").tag(OutputVisualizationMode.batteryOnly)
                    Text("Always").tag(OutputVisualizationMode.always)
                }
                .disabled(!showPowerDistribution)
                Toggle("Output ports text row", isOn: $showOutputPortsText)
                    .disabled(!showPowerDistribution || outputVisualizationMode == .off)
            }

            MenuOrderSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollEdgeEffectStyleSoftIfAvailable()
    }
}

private struct MenuOrderSection: View {
    // Observing the stored order is what re-renders this section after a move.
    @Default(.dashboardModuleOrder) private var moduleOrder
    @Default(.dashboardItemOrder) private var itemOrder

    var body: some View {
        let modules = DashboardLayoutStore.orderedModules
        Section {
            ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                DisclosureGroup {
                    let items = DashboardLayoutStore.orderedItems(in: module)
                    ForEach(Array(items.enumerated()), id: \.element) { itemIndex, item in
                        ReorderRow(
                            title: item.title,
                            canMoveUp: itemIndex > 0,
                            canMoveDown: itemIndex < items.count - 1
                        ) { delta in
                            var reordered = items
                            reordered.swapAt(itemIndex, itemIndex + delta)
                            DashboardLayoutStore.saveItems(reordered, in: module)
                        }
                    }
                } label: {
                    ReorderRow(
                        title: module.title,
                        canMoveUp: index > 0,
                        canMoveDown: index < modules.count - 1
                    ) { delta in
                        var reordered = modules
                        reordered.swapAt(index, index + delta)
                        DashboardLayoutStore.saveModules(reordered)
                    }
                }
            }

            Button("Restore Default Order") {
                DashboardLayoutStore.restoreDefaults()
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Menu Order")
                Text("Use the arrows to reorder sections, or the rows inside a section, in the menu dropdown.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReorderRow: View {
    let title: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (_ delta: Int) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .accessibilityLabel(Text("Move Up"))
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .accessibilityLabel(Text("Move Down"))
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    DashboardSettingsView()
}
