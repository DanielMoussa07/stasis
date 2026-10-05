import Foundation
import os.log
import ServiceManagement

enum ChargingHelperStatus {
    case notInstalled
    case requiresApproval
    case installed
}

/// Resumes a `CheckedContinuation` at most once, guarding against the XPC reply and a
/// fallback timeout both firing (a double-resume is a runtime crash).
private nonisolated final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var isResumed = false
    private let continuation: CheckedContinuation<Value, Never>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation.resume(returning: value)
    }
}

private extension ResumeOnce where Value == Void {
    nonisolated func resume() {
        resume(returning: ())
    }
}

@MainActor
@Observable
class ChargingHelperManager {
    static let shared = ChargingHelperManager()

    private static let machServiceName = "com.dinanathdash.stasis.charging-helper"
    private static let plistName = "com.dinanathdash.stasis.charging-helper.plist"

    private static let upgradeAttemptLimit = 3
    private static let responsivenessChecks = 4
    private static let livenessTimeout: Duration = .seconds(3)

    private var service: SMAppService
    private var connection: NSXPCConnection?
    private let logger = Logger(
        subsystem: "com.dinanathdash.stasis",
        category: "ChargingHelperManager"
    )

    private(set) var helperStatus: ChargingHelperStatus

    var isInstalled: Bool {
        helperStatus == .installed
    }

    private init() {
        service = SMAppService.daemon(plistName: Self.plistName)
        switch SMAppService.daemon(plistName: Self.plistName).status {
        case .enabled: helperStatus = .installed
        case .requiresApproval: helperStatus = .requiresApproval
        default: helperStatus = .notInstalled
        }
    }

    func install() throws {
        logger.info("Registering charging helper daemon")

        do {
            try service.register()
        } catch {
            // register() commonly throws "Operation not permitted" while macOS
            // processes the background item notification, even though the
            // registration advanced to requiresApproval or enabled.
            let currentStatus = SMAppService.daemon(plistName: Self.plistName).status
            if currentStatus != .enabled, currentStatus != .requiresApproval {
                throw error
            }
        }

        refreshStatus()
    }

    func forceUpgrade() {
        logger.info("Force upgrading charging helper daemon")
        Task { await upgradeUntilResponsive() }
    }

    /// After a rebuild the helper's code signature changes, and backgroundtaskmanagementd
    /// sometimes registers the new daemon with a stale launch constraint, so launchd refuses to
    /// spawn it (EX_CONFIG) even though register() succeeded. A fresh unregister/register cycle
    /// fixes it, so verify the helper actually answers and retry with a longer pause if not.
    private func upgradeUntilResponsive() async {
        for attempt in 1 ... Self.upgradeAttemptLimit {
            disconnect()
            do {
                try await service.unregister()
            } catch {
                logger.warning("Unregister before upgrade failed (attempt \(attempt)): \(String(describing: error), privacy: .public)")
            }

            // register() straight after unregister() races BTM's cached signature of the previous
            // daemon and fails with errSecCSReqFailed (-67028).
            try? await Task.sleep(for: .seconds(1.5 * Double(attempt)))

            do {
                let newService = SMAppService.daemon(plistName: Self.plistName)
                try newService.register()
                service = newService
            } catch {
                logger.error("Force upgrade register failed (attempt \(attempt)): \(String(describing: error), privacy: .public)")
                continue
            }

            // Retrying cannot help here: the user has to re-enable Stasis under Login Items.
            if service.status == .requiresApproval {
                logger.error("Helper registered but macOS requires approval under Login Items (attempt \(attempt))")
                helperStatus = .requiresApproval
                return
            }

            if await waitUntilResponsive() {
                logger.info("Force upgrade successful (attempt \(attempt))")
                refreshStatus()
                return
            }
            logger.warning("Helper unresponsive after register (attempt \(attempt)), retrying")
        }

        logger.error("Force upgrade gave up: helper never became responsive")
        refreshStatus()
    }

    private func waitUntilResponsive() async -> Bool {
        for _ in 0 ..< Self.responsivenessChecks {
            if await checkLiveness() { return true }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return false
    }

    func uninstall() async throws {
        logger.info("Unregistering charging helper daemon")
        // Reset the SMC to its default state before uninstalling so the Mac isn't stuck at 80%
        if let helper = getHelper(errorHandler: { _ in }) {
            // Wait briefly for the reset to complete before we destroy the daemon, without
            // blocking the main thread the way a DispatchSemaphore wait would.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let once = ResumeOnce<Void>(continuation)
                helper.resetToDefaults { _, _ in once.resume() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    once.resume()
                }
            }
        }

        disconnect()
        try await service.unregister()
        helperStatus = .notInstalled

        // Force the UI toggle off since the helper is gone
        UserDefaults.standard.set(false, forKey: "manageCharging")
        UserDefaults.standard.synchronize()
    }

    func refreshStatus() {
        let currentStatus = SMAppService.daemon(plistName: Self.plistName).status
        switch currentStatus {
        case .enabled:
            Task {
                if await checkLiveness() {
                    await MainActor.run { self.helperStatus = .installed }
                } else {
                    await MainActor.run { self.helperStatus = .notInstalled }
                }
            }
        case .requiresApproval: helperStatus = .requiresApproval
        default: helperStatus = .notInstalled
        }
    }

    private func checkLiveness() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce<Bool>(continuation)
            guard let helper = getHelper(errorHandler: { _ in
                once.resume(returning: false)
            }) else {
                once.resume(returning: false)
                return
            }

            helper.ping { success in
                once.resume(returning: success)
            }

            // A daemon launchd refuses to spawn can leave the call with neither a reply nor an error.
            Task {
                try? await Task.sleep(for: Self.livenessTimeout)
                once.resume(returning: false)
            }
        }
    }

    func getHelper(errorHandler: @escaping @Sendable (Error) -> Void) -> ChargingHelperProtocol? {
        if connection == nil {
            connect()
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? ChargingHelperProtocol
    }

    private func connect() {
        logger.info("Setting up XPC connection to charging helper daemon")
        let newConnection = NSXPCConnection(
            machServiceName: Self.machServiceName
        )
        newConnection.remoteObjectInterface = NSXPCInterface(
            with: ChargingHelperProtocol.self
        )

        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.warning("Charging helper XPC connection invalidated")
                self.connection = nil
            }
        }

        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.warning("Charging helper XPC connection interrupted")
                self.connection = nil
            }
        }

        newConnection.resume()
        connection = newConnection
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    func setLowPowerMode(_ enabled: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let helper = getHelper(errorHandler: { error in
                continuation.resume(throwing: error)
            }) else {
                continuation.resume(throwing: NSError(domain: "ChargingHelperManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Helper not available"]))
                return
            }

            helper.setLowPowerMode(enabled: enabled) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "ChargingHelperManager", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage ?? "Unknown error"]))
                }
            }
        }
    }
}
