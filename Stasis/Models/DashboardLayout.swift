import Defaults
import Foundation

enum DashboardItemID: String, CaseIterable, Identifiable, Sendable {
    case powerSource
    case timeRemaining
    case uptime
    case batteryMode
    case batteryTemperature
    case internalPower
    case externalPower
    case sessionEnergy
    case powerDistribution
    case outputPorts
    case cycleCount
    case batteryHealth
    case significantEnergyApps
    case chargeLimit
    case lowPowerMode
    case advancedControls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerSource: String(localized: "Power Source")
        case .timeRemaining: String(localized: "Time Remaining")
        case .uptime: String(localized: "Uptime")
        case .batteryMode: String(localized: "Battery Mode")
        case .batteryTemperature: String(localized: "Battery Temperature")
        case .internalPower: String(localized: "Battery")
        case .externalPower: String(localized: "Adapter")
        case .sessionEnergy: String(localized: "Session Energy")
        case .powerDistribution: String(localized: "Power distribution diagram")
        case .outputPorts: String(localized: "Output Ports")
        case .cycleCount: String(localized: "Cycle Count")
        case .batteryHealth: String(localized: "Battery Health")
        case .significantEnergyApps: String(localized: "Apps using significant energy")
        case .chargeLimit: String(localized: "Charge limit")
        case .lowPowerMode: String(localized: "Low Power Mode")
        case .advancedControls: String(localized: "Advanced charging controls")
        }
    }
}

/// Each module is one separator-delimited block of the menu. Items only move within their module.
enum DashboardModuleID: String, CaseIterable, Identifiable, Sendable {
    case batteryStatus
    case powerMetrics
    case powerFlow
    case batteryHealth
    case energyApps
    case chargingControls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batteryStatus: String(localized: "Status")
        case .powerMetrics: String(localized: "Power")
        case .powerFlow: String(localized: "Visuals")
        case .batteryHealth: String(localized: "Battery Health")
        case .energyApps: String(localized: "Energy Impact")
        case .chargingControls: String(localized: "Charging Controls")
        }
    }

    var defaultItems: [DashboardItemID] {
        switch self {
        case .batteryStatus:
            [.powerSource, .timeRemaining, .uptime, .batteryMode, .batteryTemperature]
        case .powerMetrics:
            [.internalPower, .externalPower, .sessionEnergy]
        case .powerFlow:
            [.powerDistribution, .outputPorts]
        case .batteryHealth:
            [.cycleCount, .batteryHealth]
        case .energyApps:
            [.significantEnergyApps]
        case .chargingControls:
            [.chargeLimit, .lowPowerMode, .advancedControls]
        }
    }
}

enum DashboardLayoutStore {
    static var orderedModules: [DashboardModuleID] {
        resolved(Defaults[.dashboardModuleOrder])
    }

    static func orderedItems(in module: DashboardModuleID) -> [DashboardItemID] {
        let stored: [DashboardItemID] = resolved(Defaults[.dashboardItemOrder])
        return stored.filter(module.defaultItems.contains)
    }

    static func saveModules(_ modules: [DashboardModuleID]) {
        Defaults[.dashboardModuleOrder] = modules.map(\.rawValue)
    }

    static func saveItems(_ items: [DashboardItemID], in module: DashboardModuleID) {
        let reordered = Dictionary(
            uniqueKeysWithValues: DashboardModuleID.allCases.map { current in
                (current, current == module ? items : orderedItems(in: current))
            }
        )
        Defaults[.dashboardItemOrder] = DashboardModuleID.allCases
            .flatMap { reordered[$0] ?? [] }
            .map(\.rawValue)
    }

    static func restoreDefaults() {
        Defaults.reset(.dashboardModuleOrder, .dashboardItemOrder)
    }

    /// Stored order first, then anything missing (for example items added in a later version).
    private static func resolved<ID: CaseIterable & RawRepresentable & Hashable>(
        _ stored: [String]
    ) -> [ID] where ID.RawValue == String, ID.AllCases == [ID] {
        var seen = Set<ID>()
        let known = stored.compactMap(ID.init(rawValue:)).filter { seen.insert($0).inserted }
        return known + ID.allCases.filter { !seen.contains($0) }
    }
}
