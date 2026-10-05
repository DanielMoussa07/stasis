import AppKit
import Defaults
import SwiftUI

@MainActor
class MenuBuilder {
    private let viewModel: MenuViewModel
    private let settingsWindowController: SettingsWindowController

    init(
        viewModel: MenuViewModel,
        settingsWindowController: SettingsWindowController
    ) {
        self.viewModel = viewModel
        self.settingsWindowController = settingsWindowController
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Stasis")
        populateMenu(menu)
        return menu
    }

    func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let mainInfoItem = createMenuItem(
            view: BatteryMainInfoView(viewModel: viewModel)
        )
        menu.addItem(mainInfoItem)

        for module in DashboardLayoutStore.orderedModules {
            let items = DashboardLayoutStore.orderedItems(in: module).flatMap(makeItems)
            guard !items.isEmpty else { continue }
            menu.addItem(NSMenuItem.separator())
            items.forEach(menu.addItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings"),
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeItems(for itemID: DashboardItemID) -> [NSMenuItem] {
        switch itemID {
        case .powerSource:
            return infoItems(itemID, shown: Defaults[.showPowerSource], keyPath: \.powerSourceText)
        case .timeRemaining:
            return infoItems(itemID, shown: Defaults[.showTimeTillDischarge], keyPath: \.timeRemainingText)
        case .uptime:
            return infoItems(itemID, shown: Defaults[.showUptime], keyPath: \.uptimeText)
        case .batteryMode:
            return infoItems(itemID, shown: Defaults[.showBatteryMode], keyPath: \.batteryModeText)
        case .batteryTemperature:
            return infoItems(itemID, shown: Defaults[.showBatteryTemperature], keyPath: \.batteryTemperatureText)
        case .internalPower:
            return infoItems(itemID, shown: Defaults[.showInternalPower], keyPath: \.internalInputText)
        case .externalPower:
            return infoItems(itemID, shown: Defaults[.showExternalPower], keyPath: \.externalInputText)
        case .sessionEnergy:
            return infoItems(
                itemID,
                shown: Defaults[.showSessionEnergy] && viewModel.shouldShowSessionEnergy,
                keyPath: \.sessionEnergyText
            )
        case .powerDistribution:
            guard Defaults[.showPowerDistribution] else { return [] }
            return [createMenuItem(view: PowerSankeyViewWrapper(viewModel: viewModel))]
        case .outputPorts:
            return infoItems(
                itemID,
                shown: Defaults[.showPowerDistribution] && shouldShowOutputPortsTextRow,
                keyPath: \.outputPortDetailsText
            )
        case .cycleCount:
            return infoItems(itemID, shown: Defaults[.showBatteryCycleCount], keyPath: \.cycleCountText)
        case .batteryHealth:
            return infoItems(itemID, shown: Defaults[.showBatteryHealth], keyPath: \.batteryHealthText)
        case .significantEnergyApps:
            guard Defaults[.showSignificantEnergyApps] else { return [] }
            return [
                createDynamicMenuItem(
                    view: SignificantEnergyMenuView(service: viewModel.significantEnergyService)
                ),
            ]
        case .chargeLimit:
            guard viewModel.manageChargingEnabled, Defaults[.showChargeLimitControl] else { return [] }
            return [createMenuItem(view: ChargeLimitSliderView(nativeMode: viewModel.nativeMode))]
        case .advancedControls:
            return makeAdvancedControlItems()
        }
    }

    private func infoItems(
        _ itemID: DashboardItemID,
        shown: Bool,
        keyPath: KeyPath<MenuViewModel, String>
    ) -> [NSMenuItem] {
        guard shown else { return [] }
        return [createInfoItem(label: itemID.title, keyPath: keyPath)]
    }

    private func makeAdvancedControlItems() -> [NSMenuItem] {
        guard viewModel.manageChargingEnabled, viewModel.adapterConnected,
              Defaults[.showAdvancedChargingControls]
        else { return [] }

        // Top Up works on every OS: SMC override on macOS 26, PowerUI temporary lift on 27.
        var items: [NSMenuItem] = []
        if !viewModel.nativeMode {
            items.append(createMenuItem(view: ChargeToLimitToggleView(viewModel: viewModel)))
        }
        items.append(createMenuItem(view: ChargeLimitOverrideToggleView(viewModel: viewModel)))
        if !viewModel.nativeMode {
            items.append(createMenuItem(view: ForceDischargeToggleView(viewModel: viewModel)))
            items.append(createMenuItem(view: BatteryCalibrationToggleView(viewModel: viewModel)))
        }
        return items
    }

    private var shouldShowOutputPortsTextRow: Bool {
        guard Defaults[.showOutputPortsText] else {
            return false
        }
        switch Defaults[.outputVisualizationMode] {
        case .off:
            return false
        case .powerOnly:
            return viewModel.adapterConnected
        case .batteryOnly:
            return !viewModel.adapterConnected
        case .always:
            return true
        }
    }

    private func createInfoItem(
        label: String,
        keyPath: KeyPath<MenuViewModel, String>
    ) -> NSMenuItem {
        createMenuItem(
            view: BatteryAdditionalInfoObserverView(
                label: label,
                viewModel: viewModel,
                keyPath: keyPath
            )
        )
    }

    private static let menuWidth: CGFloat = 300

    private func createMenuItem<V: View>(view: V) -> NSMenuItem {
        let hostingView = NSHostingView(rootView: view)
        let height = hostingView.fittingSize.height
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Self.menuWidth,
            height: height
        )

        let menuItem = NSMenuItem()
        menuItem.view = hostingView

        return menuItem
    }

    private func createDynamicMenuItem<V: View>(view: V) -> NSMenuItem {
        let hostingView = DynamicallyResizingHostingView(rootView: view)
        let height = hostingView.fittingSize.height
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Self.menuWidth,
            height: height
        )

        let menuItem = NSMenuItem()
        menuItem.view = hostingView
        hostingView.menuItem = menuItem

        return menuItem
    }

    @objc private func handleSettings() {
        settingsWindowController.showSettings()
    }

    @objc private func handleQuit() {
        viewModel.quit()
    }
}

struct BatteryMainInfoView: View {
    let viewModel: MenuViewModel
    @Default(.manageCharging) private var manageCharging
    @Default(.chargeLimit) private var chargeLimit

    private var barColor: Color {
        if viewModel.isCharging { return .green }
        return viewModel.displayPercentage <= 10 ? .red : .secondary
    }

    var body: some View {
        BatteryMainInfo(
            label: String(localized: "Battery"),
            value: viewModel.batteryPercentageText,
            percentage: viewModel.displayPercentage,
            chargeLimit: manageCharging ? (viewModel.chargeLimitOverrideActive ? 100 : chargeLimit) : nil,
            barColor: barColor
        )
    }
}

struct BatteryAdditionalInfoObserverView: View {
    let label: String
    let viewModel: MenuViewModel
    let keyPath: KeyPath<MenuViewModel, String>

    var body: some View {
        BatteryAdditionalInfo(label: label, value: viewModel[keyPath: keyPath])
    }
}

struct PowerSankeyViewWrapper: View {
    let viewModel: MenuViewModel

    private var shouldShowOutput: Bool {
        switch Defaults[.outputVisualizationMode] {
        case .off:
            return false
        case .powerOnly:
            return viewModel.adapterConnected
        case .batteryOnly:
            return !viewModel.adapterConnected
        case .always:
            return true
        }
    }

    var body: some View {
        PowerSankeyView(
            powerSource: viewModel.powerSource,
            isCharging: viewModel.isCharging,
            batteryPower: viewModel.batteryPower,
            adapterPower: viewModel.adapterPower,
            systemPower: viewModel.systemPower,
            outputPower: shouldShowOutput ? viewModel.outputPower : 0,
            outputPortPowers: shouldShowOutput
                ? viewModel.outputPortPowers.map(\.powerWatts)
                : [],
            outputIcons: shouldShowOutput ? viewModel.outputIcons : [],
            hasMultiPort: viewModel.hasMultiPort,
            connectedAccessories: viewModel.connectedAccessories
        )
    }
}

struct ChargeLimitSliderView: View {
    let nativeMode: Bool
    @Default(.chargeLimit) private var chargeLimit

    var body: some View {
        HStack(spacing: 8) {
            Text("Charge limit")
            Slider(
                value: Binding(
                    get: { Double(chargeLimit) },
                    set: { chargeLimit = Int($0) }
                ),
                in: (nativeMode ? 80.0 : 50.0) ... 100.0,
                step: 5
            )
            Text(chargeLimit.formattedPercentage)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

struct ChargeLimitOverrideToggleView: View {
    let viewModel: MenuViewModel

    var body: some View {
        HStack {
            Text("Charge Limit Override")
            Spacer(minLength: 20)
            Toggle(
                "Charge Limit Override",
                isOn: Binding(
                    get: { viewModel.chargeLimitOverrideActive },
                    set: { _ in viewModel.toggleChargeLimitOverride() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

struct ForceDischargeToggleView: View {
    let viewModel: MenuViewModel

    var body: some View {
        HStack {
            Text("Force Discharge")
            Spacer(minLength: 20)
            Toggle(
                "Force Discharge",
                isOn: Binding(
                    get: { viewModel.forceDischargeActive },
                    set: { _ in viewModel.toggleForceDischarge() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

struct ChargeToLimitToggleView: View {
    let viewModel: MenuViewModel

    var body: some View {
        HStack {
            Text("Top-up to Limit")
            Spacer(minLength: 20)
            Toggle(
                "Top-up to Limit",
                isOn: Binding(
                    get: { viewModel.chargeToLimitActive },
                    set: { _ in viewModel.toggleChargeToLimit() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

struct BatteryCalibrationToggleView: View {
    let viewModel: MenuViewModel

    var body: some View {
        HStack {
            Text("Battery Calibration")
            Spacer(minLength: 20)
            Toggle(
                "Battery Calibration",
                isOn: Binding(
                    get: { viewModel.isCalibrating },
                    set: { _ in viewModel.toggleCalibration() }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
