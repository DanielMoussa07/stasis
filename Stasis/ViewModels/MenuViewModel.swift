import AppKit
import Defaults
import Foundation
import Observation

@MainActor
@Observable
class MenuViewModel {
    private let batteryService: BatteryService
    private let chargeManager: ChargeManager
    private let bootTimestamp: Date?

    var batteryPercentageText: String = "0%"
    var powerSourceText: String = "Battery"
    var timeRemainingText: String = "Calculating..."
    var uptimeText: String = "00:00"
    var batteryModeText: String = "Unknown"
    var batteryTemperatureText: String = "0°C"
    var externalInputText: String = "0V @ 0A"
    var internalInputText: String = "0V @ 0A"
    var cycleCountText: String = "0"
    var batteryHealthText: String = "100%"

    var displayPercentage: Int = 0
    var chargingMode: ChargingMode = .discharging
    var batteryPower: Double = 0
    var adapterPower: Double = 0
    var systemPower: Double = 0
    var powerSource: PowerSource = .battery
    var isCharging: Bool = false
    var isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    var chargeLimitOverrideActive: Bool { chargeManager.chargeLimitOverrideActive }
    var forceDischargeActive: Bool { chargeManager.forceDischargeActive }
    var manageChargingEnabled: Bool { Defaults[.manageCharging] }
    var adapterConnected: Bool = false

    private var metricsObservation: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?
    private var uptimeTask: Task<Void, Never>?
    private var powerModeObservation: Task<Void, Never>?
    private var trendSample: (date: Date, percentage: Int, isCharging: Bool)?

    init(batteryService: BatteryService, chargeManager: ChargeManager) {
        self.batteryService = batteryService
        self.chargeManager = chargeManager
        self.bootTimestamp = SystemService.bootTimestamp()
        startObservingMetrics()
        startObservingSettings()
        startObservingPowerMode()
    }

    private func startObservingMetrics() {
        metricsObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.updateFormattedValues(
                    from: self.batteryService.metrics,
                    adapter: self.batteryService.adapterMetrics
                )
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryService.metrics
                        _ = self.batteryService.adapterMetrics
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func startObservingSettings() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates([.useHardwarePercentage], initial: false) {
                guard let self else { return }
                self.updateFormattedValues(
                    from: self.batteryService.metrics,
                    adapter: self.batteryService.adapterMetrics
                )
            }
        }
    }

    private func startObservingPowerMode() {
        powerModeObservation = Task { [weak self] in
            guard let self else { return }
            for await _ in NotificationCenter.default.notifications(
                named: .NSProcessInfoPowerStateDidChange
            ) {
                self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func toggleChargeLimitOverride() {
        chargeManager.toggleChargeLimitOverride()
    }

    func toggleForceDischarge() {
        chargeManager.toggleForceDischarge()
    }

    private func updateFormattedValues(from metrics: BatteryMetrics, adapter: AdapterMetrics) {
        let useHardware = Defaults[.useHardwarePercentage]
        let percentage =
            useHardware
            ? metrics.hardwareBatteryPercentage : metrics.batteryPercentage
        displayPercentage = percentage
        batteryPercentageText = "\(percentage)%"

        let derivedPowerSource = derivePowerSource(battery: metrics, adapter: adapter)

        powerSourceText = formatPowerSourceText(
            source: derivedPowerSource,
            adapterCapacityWatts: adapter.adapterCapacityWatts
        )

        timeRemainingText = formatTimeRemaining(
            reportedMinutes: metrics.timeRemaining,
            powerSource: derivedPowerSource,
            isCharging: metrics.isCharging,
            adapterConnected: adapter.adapterConnected,
            batteryPercentage: percentage
        )

        updateUptimeText()

        if adapter.adapterConnected {
            if metrics.isCharging {
                chargingMode = .charging
                batteryModeText = "Charging"
            } else {
                chargingMode = .pluggedIn
                batteryModeText = "Plugged In (Not Charging)"
            }
        } else {
            chargingMode = .discharging
            batteryModeText = "Discharging"
        }

        batteryTemperatureText =
            "\(metrics.batteryTemperature.formatted(.number.precision(.fractionLength(1))))°C"

        let voltageFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        let currentFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

        externalInputText =
            "\(adapter.adapterVoltage.formatted(voltageFormat))V @ \(adapter.adapterCurrent.formatted(currentFormat))A"

        internalInputText =
            "\(metrics.batteryVoltage.formatted(voltageFormat))V @ \(metrics.batteryCurrent.formatted(currentFormat))A"

        batteryPower = metrics.batteryPower
        adapterPower = adapter.adapterPower
        systemPower = adapter.adapterPower - metrics.batteryPower
        powerSource = derivedPowerSource
        isCharging = metrics.isCharging
        adapterConnected = adapter.adapterConnected

        cycleCountText = "\(metrics.cycleCount)"
        batteryHealthText = "\(metrics.batteryHealth)%"
    }

    private func derivePowerSource(battery: BatteryMetrics, adapter: AdapterMetrics) -> PowerSource {
        guard adapter.adapterConnected else { return .battery }

        if battery.batteryPower >= 0 {
            return .acAdapter
        } else {
            return .both
        }
    }

    private func updateUptimeText() {
        guard let bootTimestamp else {
            uptimeText = "Unknown"
            return
        }

        let uptime = max(0, Int(Date().timeIntervalSince(bootTimestamp)))
        let days = uptime / 86_400
        let hours = (uptime % 86_400) / 3_600
        let minutes = (uptime % 3_600) / 60

        if days > 0 {
            uptimeText = "\(days)D \(hours)H \(minutes)M"
        } else if hours > 0 {
            uptimeText = "\(hours)H \(minutes)M"
        } else {
            uptimeText = "\(minutes)M"
        }
    }

    private func startUptimeTimer() {
        guard uptimeTask == nil else { return }

        uptimeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.updateUptimeText()
            }
        }
    }

    private func stopUptimeTimer() {
        uptimeTask?.cancel()
        uptimeTask = nil
    }

    func menuWillOpen() {
        updateUptimeText()
        startUptimeTimer()
        batteryService.enableFastPolling()
    }

    func menuDidClose() {
        stopUptimeTimer()
        batteryService.disableFastPolling()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func formatTimeRemaining(minutes: Int, powerSource: PowerSource, isCharging: Bool) -> String {
        formatTimeRemaining(
            reportedMinutes: minutes,
            powerSource: powerSource,
            isCharging: isCharging,
            adapterConnected: powerSource != .battery,
            batteryPercentage: displayPercentage
        )
    }

    private func formatTimeRemaining(
        reportedMinutes: Int,
        powerSource: PowerSource,
        isCharging: Bool,
        adapterConnected: Bool,
        batteryPercentage: Int
    ) -> String {
        if adapterConnected && !isCharging {
            return "N/A"
        }

        let adjustedReportedMinutes = adjustedReportedMinutesToTarget(
            reportedMinutes: reportedMinutes,
            isCharging: isCharging,
            batteryPercentage: batteryPercentage
        )

        let fallbackMinutes = estimateMinutesFromTrend(
            batteryPercentage: batteryPercentage,
            isCharging: isCharging,
            adapterConnected: adapterConnected
        )

        let effectiveMinutes = adjustedReportedMinutes >= 0 ? adjustedReportedMinutes : fallbackMinutes
        guard let effectiveMinutes, effectiveMinutes >= 0 else {
            return "Calculating..."
        }

        let hours = effectiveMinutes / 60
        let mins = effectiveMinutes % 60
        return String(format: "%02d:%02d", hours, mins)
    }

    private func adjustedReportedMinutesToTarget(
        reportedMinutes: Int,
        isCharging: Bool,
        batteryPercentage: Int
    ) -> Int {
        guard reportedMinutes >= 0 else { return -1 }
        guard isCharging else { return reportedMinutes }

        let targetPercentage = chargingTargetPercentage
        if batteryPercentage >= targetPercentage {
            return 0
        }

        if targetPercentage >= 100 || batteryPercentage >= 100 {
            return reportedMinutes
        }

        let remainingToTarget = max(0, targetPercentage - batteryPercentage)
        let remainingToFull = max(1, 100 - batteryPercentage)
        let scaled = Double(reportedMinutes) * Double(remainingToTarget) / Double(remainingToFull)
        return Int(ceil(scaled))
    }

    private var chargingTargetPercentage: Int {
        if Defaults[.manageCharging] && !chargeLimitOverrideActive {
            return Defaults[.chargeLimit]
        }
        return 100
    }

    private func estimateMinutesFromTrend(
        batteryPercentage: Int,
        isCharging: Bool,
        adapterConnected: Bool
    ) -> Int? {
        let now = Date()
        defer {
            trendSample = (date: now, percentage: batteryPercentage, isCharging: isCharging)
        }

        guard !(adapterConnected && !isCharging) else { return nil }
        guard let previous = trendSample else { return nil }
        guard previous.isCharging == isCharging else { return nil }

        let elapsedMinutes = now.timeIntervalSince(previous.date) / 60
        guard elapsedMinutes >= 0.5 else { return nil }

        let deltaPercent = batteryPercentage - previous.percentage
        guard deltaPercent != 0 else { return nil }

        let percentPerMinute = abs(Double(deltaPercent) / elapsedMinutes)
        guard percentPerMinute > 0 else { return nil }

        let remainingPercent: Int = {
            if isCharging {
                return max(0, chargingTargetPercentage - batteryPercentage)
            }
            return max(0, batteryPercentage)
        }()

        if remainingPercent == 0 {
            return 0
        }

        let minutes = Double(remainingPercent) / percentPerMinute
        return Int(ceil(minutes))
    }

    private func formatPowerSourceText(source: PowerSource, adapterCapacityWatts: Int) -> String {
        let hasCapacity = adapterCapacityWatts > 0
        switch source {
        case .battery:
            return "Battery"
        case .acAdapter:
            return hasCapacity
                ? "Power Adapter (\(adapterCapacityWatts) W)"
                : "Power Adapter"
        case .both:
            return hasCapacity
                ? "Battery & Power Adapter (\(adapterCapacityWatts) W)"
                : "Battery & Power Adapter"
        }
    }

    deinit {
        MainActor.assumeIsolated {
            metricsObservation?.cancel()
            settingsObservation?.cancel()
            uptimeTask?.cancel()
            powerModeObservation?.cancel()
        }
    }
}
