import Foundation
import os.log
import ServiceManagement

enum ChargingHelperStatus {
    case notInstalled
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

    private static let responsivenessChecks = 4
    private static let livenessTimeout: Duration = .seconds(3)

    private var service: SMAppService
    private var connection: NSXPCConnection?
    private let logger = Logger(
        subsystem: "com.dinanathdash.stasis",
        category: "ChargingHelperManager"
    )

    private(set) var helperStatus: ChargingHelperStatus
    private(set) var isInstalling = false

    var isInstalled: Bool {
        helperStatus == .installed
    }

    private init() {
        service = SMAppService.daemon(plistName: Self.plistName)
        helperStatus = PrivilegedHelperInstaller.isInstalled ? .installed : .notInstalled
    }

    /// Installs (or reinstalls) the helper behind one administrator prompt, then waits until it answers.
    func install() async throws {
        logger.info("Installing charging helper daemon")
        isInstalling = true
        defer { isInstalling = false }
        disconnect()
        // An earlier build registered the same label through Login Items; it must go first.
        try? await service.unregister()
        try await PrivilegedHelperInstaller.install()

        if await waitUntilResponsive() {
            logger.info("Charging helper installed and responding")
            helperStatus = .installed
        } else {
            logger.error("Charging helper installed but not responding")
            helperStatus = .notInstalled
            throw PrivilegedHelperInstaller.InstallerError.scriptFailed(
                String(localized: "The helper was installed but did not start.")
            )
        }
    }

    /// Called at launch. Prompts only when the helper is missing after an earlier install, or
    /// was installed for a different build of the app (the helper pins the app's exact signature).
    func ensureHelperCurrent(isFirstRun: Bool) async {
        let hadLoginItemsHelper = service.status == .enabled || service.status == .requiresApproval
        let needsInstall: Bool
        if PrivilegedHelperInstaller.isInstalled {
            needsInstall = !PrivilegedHelperInstaller.isCurrent()
        } else {
            needsInstall = isFirstRun || hadLoginItemsHelper
        }

        guard needsInstall else {
            refreshStatus()
            return
        }

        do {
            try await install()
        } catch {
            logger.error("Helper install at launch failed: \(String(describing: error), privacy: .public)")
            refreshStatus()
        }
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
        try? await service.unregister()
        try await PrivilegedHelperInstaller.uninstall()
        helperStatus = .notInstalled

        // Force the UI toggle off since the helper is gone
        UserDefaults.standard.set(false, forKey: "manageCharging")
        UserDefaults.standard.synchronize()
    }

    func refreshStatus() {
        guard PrivilegedHelperInstaller.isInstalled else {
            helperStatus = .notInstalled
            return
        }
        Task {
            helperStatus = await checkLiveness() ? .installed : .notInstalled
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
