import Foundation
import ObjectiveC
import os.log

// MARK: - Errors

public enum NativeChargeError: LocalizedError {
    case unavailable
    case unsupportedLimit
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Native charge control is unavailable on this Mac."
        case .unsupportedLimit:
            return "This charge limit is not supported by macOS (supported: 80, 85, 90, 95, 100)."
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Backend Protocol

public protocol NativeChargeBackend: AnyObject {
    var limits: [Int] { get }
    func readLimit() throws -> Int
    func writeLimit(_ value: Int) throws
    /// Lifts the Maximum Charge Limit until `rearmLimit()` (or the OS) re-arms it. Keeps the
    /// user's stored limit, unlike `writeLimit(100)`.
    func temporarilyDisableLimit() throws
    /// Re-arms the Maximum Charge Limit with the stored limit.
    func rearmLimit() throws
}

// MARK: - Session

/// Wraps a NativeChargeBackend with journaling so the original system limit
/// can always be recovered — even across crashes — on the next launch.
public final class NativeChargeSession {
    private let backend: NativeChargeBackend
    private let defaults: UserDefaults
    private let recoveryKey = "nativeChargeOriginalLimit"
    private let logger = Logger(subsystem: "com.dinanathdash.stasis", category: "NativeChargeSession")

    public init(backend: NativeChargeBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    public var supportedLimits: [Int] { backend.limits }

    /// Nearest supported PowerUI limit step at or below `value`. Nil if value < minimum (80).
    public func nearestLimit(atOrBelow value: Int) -> Int? {
        backend.limits.filter { $0 <= value }.max()
    }

    /// Nearest supported PowerUI limit step at or above `value`. Nil if value > maximum (100).
    public func nearestLimit(atOrAbove value: Int) -> Int? {
        backend.limits.filter { $0 >= value }.min()
    }

    /// Writes `value` and verifies the readback, retrying the whole write+readback round trip
    /// a few times before giving up. Right after the PowerUI client first connects (e.g. the
    /// daemon just launched), its very first WRITE can fail outright — not just a stale
    /// readback — because the private client needs a brief moment after construction before
    /// it's ready to accept writes, even though reads during init already succeeded fine.
    private func writeAndVerify(_ value: Int, attempts: Int = 4) throws -> Int {
        var lastError: Error?
        for attempt in 1 ... attempts {
            do {
                try backend.writeLimit(value)
                let readback = try backend.readLimit()
                guard readback == value else {
                    throw NativeChargeError.failed(
                        "macOS did not retain the requested limit (read back \(readback)%, expected \(value)%)."
                    )
                }
                return readback
            } catch {
                lastError = error
                if attempt < attempts {
                    logger.warning("PowerUI write attempt \(attempt) failed, retrying: \(error.localizedDescription)")
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
        }
        throw lastError ?? NativeChargeError.failed("Unknown failure applying limit \(value)%.")
    }

    public func apply(_ limit: Int) throws {

        guard backend.limits.contains(limit) else { throw NativeChargeError.unsupportedLimit }
        let current = try backend.readLimit()
        if defaults.object(forKey: recoveryKey) == nil {
            defaults.set(current, forKey: recoveryKey)
            defaults.synchronize()
            logger.info("Journaled original native charge limit: \(current)%")
        }
        guard current != limit else { return }
        logger.info("Setting native charge limit: \(current)% → \(limit)%")
        _ = try writeAndVerify(limit)
    }

    // MARK: Top Up

    /// Maximum time a Top Up may stay active before the limit is forcibly re-armed.
    public static let topUpMaxDuration: TimeInterval = 12 * 60 * 60

    private var topUpStartedAt: Date?

    public var isTopUpActive: Bool { topUpStartedAt != nil }

    /// Lifts the charge limit so the battery can charge to 100% without touching the stored limit.
    /// Idempotent. Expires on its own after `topUpMaxDuration` via `endTopUpIfExpired()`.
    public func beginTopUp() throws {
        guard topUpStartedAt == nil else { return }
        try backend.temporarilyDisableLimit()
        topUpStartedAt = Date()
        logger.info("Top Up started: native charge limit temporarily lifted")
    }

    /// Re-arms the stored limit. Pass `force` after a crash/restart, when the in-memory flag is
    /// gone but the OS may still hold the temporary override.
    public func endTopUp(force: Bool = false) throws {
        guard topUpStartedAt != nil || force else { return }
        try backend.rearmLimit()
        topUpStartedAt = nil
        logger.info("Top Up ended: native charge limit re-armed")
    }

    public func endTopUpIfExpired(now: Date = Date()) throws {
        guard let started = topUpStartedAt,
              now.timeIntervalSince(started) >= Self.topUpMaxDuration else { return }
        try endTopUp()
    }

    public func restore() throws {
        guard defaults.object(forKey: recoveryKey) != nil else { return }
        let original = defaults.integer(forKey: recoveryKey)
        logger.info("Restoring native charge limit to \(original)%")
        _ = try writeAndVerify(original)
        defaults.removeObject(forKey: recoveryKey)
        defaults.synchronize()
        logger.info("Native charge limit restored and journal cleared.")
    }
}

// MARK: - PowerUI Private Framework Backend

/// Loads Apple's private PowerUI framework at runtime and calls PowerUISmartChargeClient
/// via ObjC runtime selectors. Same service client used by System Settings → Battery.
/// Fails closed: any missing selector or unavailable hardware → throws .unavailable.
public final class PowerUIChargeBackend: NativeChargeBackend {
    private let client: NSObject
    public let limits: [Int]
    private typealias ErrorPointer = AutoreleasingUnsafeMutablePointer<NSError?>?
    private let logger = Logger(subsystem: "com.dinanathdash.stasis", category: "PowerUIChargeBackend")

    public init() throws {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type
        else { throw NativeChargeError.unavailable }

        let allocSel = NSSelectorFromString("alloc")
        typealias Alloc = @convention(c) (AnyObject, Selector) -> AnyObject
        guard let allocMethod = class_getClassMethod(cls, allocSel) else { throw NativeChargeError.unavailable }
        let allocated = unsafeBitCast(method_getImplementation(allocMethod), to: Alloc.self)(cls, allocSel)

        let initSel = NSSelectorFromString("initWithClientName:")
        typealias Init = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
        guard let initMethod = class_getInstanceMethod(cls, initSel) else { throw NativeChargeError.unavailable }
        guard let initialized = unsafeBitCast(method_getImplementation(initMethod), to: Init.self)(
            allocated, initSel, "Stasis"
        ) as? NSObject else { throw NativeChargeError.unavailable }
        client = initialized

        for name in ["isMCLSupported", "isMCLCurrentlyEnabled:", "getMCLLimitWithError:",
                     "availableChargeLimitsWithError:", "setMCLLimit:error:"] {
            guard client.responds(to: NSSelectorFromString(name)) else { throw NativeChargeError.unavailable }
        }

        let supportedSel = NSSelectorFromString("isMCLSupported")
        typealias Supported = @convention(c) (AnyObject, Selector) -> Bool
        guard unsafeBitCast(client.method(for: supportedSel), to: Supported.self)(client, supportedSel) else {
            throw NativeChargeError.unavailable
        }

        var error: NSError?
        let enabledSel = NSSelectorFromString("isMCLCurrentlyEnabled:")
        typealias Enabled = @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt
        let isEnabled = unsafeBitCast(client.method(for: enabledSel), to: Enabled.self)(client, enabledSel, &error)
        guard error == nil else { throw NativeChargeError.unavailable }
        
        if isEnabled == 0 {
            let enableSel = NSSelectorFromString("enableMCL:")
            typealias Enable = @convention(c) (AnyObject, Selector, ErrorPointer) -> Bool
            if client.responds(to: enableSel) {
                let success = unsafeBitCast(client.method(for: enableSel), to: Enable.self)(client, enableSel, &error)
                if !success || error != nil {
                    Logger(subsystem: "com.dinanathdash.stasis", category: "PowerUIChargeBackend")
                        .error("Failed to enable MCL. OS native limit might not be respected.")
                } else {
                    Logger(subsystem: "com.dinanathdash.stasis", category: "PowerUIChargeBackend")
                        .info("MCL was disabled in system settings; successfully enabled it.")
                }
            }
        }

        let availSel = NSSelectorFromString("availableChargeLimitsWithError:")
        typealias Available = @convention(c) (AnyObject, Selector, ErrorPointer) -> Unmanaged<AnyObject>?
        let values = unsafeBitCast(client.method(for: availSel), to: Available.self)(
            client, availSel, &error
        )?.takeUnretainedValue() as? [NSNumber]
        guard error == nil, let values else { throw NativeChargeError.unavailable }

        limits = values.map(\.intValue).filter { (80...100).contains($0) }.sorted()
        guard limits.contains(80), limits.contains(100) else { throw NativeChargeError.unavailable }
        Logger(subsystem: "com.dinanathdash.stasis", category: "PowerUIChargeBackend")
            .info("PowerUI backend ready. Limits: \(self.limits)")
    }

    public func readLimit() throws -> Int {
        let sel = NSSelectorFromString("getMCLLimitWithError:")
        typealias Read = @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt8
        var error: NSError?
        let result = unsafeBitCast(client.method(for: sel), to: Read.self)(client, sel, &error)
        if let error { throw error }
        // macOS returns 0 when limit is disabled (= 100%)
        let value = result == 0 ? 100 : Int(result)
        guard limits.contains(value) else { throw NativeChargeError.unsupportedLimit }
        return value
    }

    public func temporarilyDisableLimit() throws {
        try callBoolWithError("temporarilyDisableMCL:", failure: "macOS rejected the temporary charge-limit lift.")
        logger.info("PowerUI temporarily disabled MCL")
    }

    public func rearmLimit() throws {
        try callBoolWithError("enableMCL:", failure: "macOS rejected re-arming the charge limit.")
        logger.info("PowerUI re-armed MCL")
    }

    private func callBoolWithError(_ name: String, failure: String) throws {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel) else { throw NativeChargeError.unavailable }
        typealias Call = @convention(c) (AnyObject, Selector, ErrorPointer) -> Bool
        var error: NSError?
        let success = unsafeBitCast(client.method(for: sel), to: Call.self)(client, sel, &error)
        if let error { throw error }
        guard success else { throw NativeChargeError.failed(failure) }
    }

    public func writeLimit(_ value: Int) throws {
        guard limits.contains(value) else { throw NativeChargeError.unsupportedLimit }
        let sel = NSSelectorFromString("setMCLLimit:error:")
        typealias Write = @convention(c) (AnyObject, Selector, UInt8, ErrorPointer) -> Bool
        var error: NSError?
        let raw = UInt8(value == 100 ? 0 : value)  // macOS uses 0 for "no limit"
        let success = unsafeBitCast(client.method(for: sel), to: Write.self)(client, sel, raw, &error)
        if let error { throw error }
        guard success else {
            throw NativeChargeError.failed("macOS rejected the charge-limit update to \(value)%.")
        }
        logger.info("PowerUI wrote \(value)% (raw=\(raw))")
    }
}
