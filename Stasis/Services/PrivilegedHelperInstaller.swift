import Foundation
import os.log
import Security

/// Installs the charging helper as a root launch daemon behind a single administrator prompt
/// (Touch ID or password), instead of asking the user to approve it in Login Items.
///
/// The helper links `smc_power.framework` through `@loader_path/../../Frameworks`, so the
/// payload is copied as a small root-owned bundle rather than as a lone binary. Everything the
/// root script trusts is passed inside the script text itself; nothing is read back from
/// user-writable files after the prompt.
enum PrivilegedHelperInstaller {
    static let label = "com.dinanathdash.stasis.charging-helper"
    static let installDirectory = "/Library/PrivilegedHelperTools/\(label).d"
    static let requirementPath = "\(installDirectory)/requirement"
    static let launchDaemonPath = "/Library/LaunchDaemons/\(label).plist"

    private nonisolated static let userCancelledErrorNumber = -128

    private static let logger = Logger(
        subsystem: "com.dinanathdash.stasis",
        category: "PrivilegedHelperInstaller"
    )

    enum InstallerError: LocalizedError {
        case payloadMissing
        case signingInformationUnavailable
        case bundleModified
        case cancelled
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .payloadMissing:
                String(localized: "The helper files are missing from the app bundle.")
            case .signingInformationUnavailable:
                String(localized: "Could not read the app's code signature.")
            case .bundleModified:
                String(localized: "The app has changed since it was launched. Reinstall Stasis and try again.")
            case .cancelled:
                String(localized: "Installation was cancelled.")
            case let .scriptFailed(message):
                message
            }
        }
    }

    private static var bundledHelperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(label)")
    }

    private static var bundledFrameworkURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/smc_power.framework")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: launchDaemonPath)
            && FileManager.default.fileExists(atPath: requirementPath)
    }

    /// The installed helper only accepts the exact app build recorded at install time, so a
    /// different build of the app needs a reinstall.
    static func isCurrent() -> Bool {
        guard isInstalled,
              let installed = try? String(contentsOfFile: requirementPath, encoding: .utf8),
              let current = try? currentRequirement()
        else { return false }
        return installed == current
    }

    static func install() async throws {
        let script = try installScript()
        try await runPrivileged(script)
    }

    static func uninstall() async throws {
        let script = """
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        /bin/rm -f '\(launchDaemonPath)'
        /bin/rm -rf '\(installDirectory)'
        """
        try await runPrivileged(script)
    }

    private static func currentRequirement() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var requirementString: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &requirementString) == errSecSuccess, let requirementString
        else { throw InstallerError.signingInformationUnavailable }
        return requirementString as String
    }

    /// The requirement is the running process's own cdhash pin, so the bundle on disk (including the
    /// nested helper and framework) must be byte-for-byte the code that launched. Without this, a
    /// helper swapped into the bundle after launch would be installed as root.
    private static func verifyBundleMatchesRunningApp(requirement: String) throws {
        var pinned: SecRequirement?
        var staticCode: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecRequirementCreateWithString(requirement as CFString, [], &pinned) == errSecSuccess, let pinned,
              SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidityWithErrors(staticCode, flags, pinned, nil) == errSecSuccess
        else { throw InstallerError.bundleModified }
    }

    private static func codeDirectoryHash(of url: URL) throws -> String {
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let unique = dictionary[kSecCodeInfoUnique as String] as? Data
        else { throw InstallerError.signingInformationUnavailable }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func installScript() throws -> String {
        guard FileManager.default.fileExists(atPath: bundledHelperURL.path),
              FileManager.default.fileExists(atPath: bundledFrameworkURL.path)
        else { throw InstallerError.payloadMissing }

        let requirement = try currentRequirement()
        try verifyBundleMatchesRunningApp(requirement: requirement)
        let helperHash = try codeDirectoryHash(of: bundledHelperURL)
        let frameworkHash = try codeDirectoryHash(of: bundledFrameworkURL)

        let toolPath = "\(installDirectory)/Contents/Library/LaunchServices/\(label)"
        let frameworkPath = "\(installDirectory)/Contents/Frameworks/smc_power.framework"

        return """
        set -e
        umask 077
        [ ! -L \(shellQuoted(bundledHelperURL.path)) ] && [ ! -L \(shellQuoted(bundledFrameworkURL.path)) ] || { echo 'Helper payload must not be a symbolic link.' >&2; exit 1; }
        /bin/launchctl bootout system/\(label) 2>/dev/null || true
        /bin/rm -rf \(shellQuoted(installDirectory))
        /usr/bin/install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
        /usr/bin/install -d -m 755 -o root -g wheel \(shellQuoted(installDirectory))
        /usr/bin/install -d -m 755 -o root -g wheel \(shellQuoted(installDirectory + "/Contents"))
        /usr/bin/install -d -m 755 -o root -g wheel \(shellQuoted(installDirectory + "/Contents/Library"))
        /usr/bin/install -d -m 755 -o root -g wheel \(shellQuoted(installDirectory + "/Contents/Library/LaunchServices"))
        /usr/bin/install -d -m 755 -o root -g wheel \(shellQuoted(installDirectory + "/Contents/Frameworks"))
        /usr/bin/install -m 700 -o root -g wheel \(shellQuoted(bundledHelperURL.path)) \(shellQuoted(toolPath))
        /usr/bin/ditto \(shellQuoted(bundledFrameworkURL.path)) \(shellQuoted(frameworkPath))
        /usr/sbin/chown -R root:wheel \(shellQuoted(installDirectory))
        /usr/bin/codesign --verify --strict --deep -R \(shellQuoted("=cdhash H\"" + helperHash + "\"")) \(shellQuoted(toolPath)) || { echo 'Helper signature does not match the app.' >&2; /bin/rm -rf \(shellQuoted(installDirectory)); exit 1; }
        /usr/bin/codesign --verify --strict --deep -R \(shellQuoted("=cdhash H\"" + frameworkHash + "\"")) \(shellQuoted(frameworkPath)) || { echo 'Framework signature does not match the app.' >&2; /bin/rm -rf \(shellQuoted(installDirectory)); exit 1; }
        /bin/chmod -R go+rX,go-w \(shellQuoted(installDirectory))
        /usr/bin/printf '%s' \(shellQuoted(requirement)) > \(shellQuoted(requirementPath))
        /usr/sbin/chown root:wheel \(shellQuoted(requirementPath))
        /bin/chmod 644 \(shellQuoted(requirementPath))
        /bin/cat > \(shellQuoted(launchDaemonPath)) <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(toolPath)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(label)</key>
                <true/>
            </dict>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        PLIST
        /usr/sbin/chown root:wheel \(shellQuoted(launchDaemonPath))
        /bin/chmod 644 \(shellQuoted(launchDaemonPath))
        /bin/launchctl bootstrap system \(shellQuoted(launchDaemonPath))
        """
    }

    private static func runPrivileged(_ script: String) async throws {
        let outcome: PrivilegedOutcome = await Task.detached {
            // sudo is first because, with pam_tid enabled, it is the only prompt that offers Touch ID
            // to a third-party app; Apple's authorization sheet shows a password field only.
            for attempt in [runWithSudo, runWithSystemAuthorization] {
                let outcome = attempt(script)
                if case .unavailable = outcome { continue }
                return outcome
            }
            return runWithAppleScript(script)
        }.value

        switch outcome {
        case .succeeded:
            return
        case .cancelled:
            throw InstallerError.cancelled
        case let .failed(message):
            logger.error("Privileged helper script failed: \(message, privacy: .public)")
            throw InstallerError.scriptFailed(message)
        case .unavailable:
            throw InstallerError.scriptFailed("No administrator prompt is available.")
        }
    }

    private enum PrivilegedOutcome: Sendable {
        case succeeded
        case cancelled
        case failed(String)
        case unavailable
    }

    private typealias ExecuteWithPrivileges = @convention(c) (
        AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private nonisolated static let exitMarker = "__STASIS_EXIT:"

    /// The system authorization sheet offers Touch ID as well as the password. Its execute call is
    /// deprecated and hidden from Swift, so it is looked up at runtime; if it is missing the
    /// AppleScript prompt (password only) is used instead.
    private nonisolated static func runWithSystemAuthorization(_ script: String) -> PrivilegedOutcome {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else {
            return .unavailable
        }
        let execute = unsafeBitCast(symbol, to: ExecuteWithPrivileges.self)

        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess, let authorization else {
            return .unavailable
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let toolPath = "/bin/sh"
        let rightName = strdup(kAuthorizationRightExecute)
        let rightValue = strdup(toolPath)
        let promptName = strdup(kAuthorizationEnvironmentPrompt)
        let promptText = "Stasis needs to install its background helper, which controls battery charging."
        let promptValue = strdup(promptText)
        defer {
            free(rightName); free(rightValue); free(promptName); free(promptValue)
        }
        guard let rightName, let rightValue, let promptName, let promptValue else { return .unavailable }

        var right = AuthorizationItem(name: UnsafePointer(rightName), valueLength: toolPath.utf8.count, value: rightValue, flags: 0)
        var promptItem = AuthorizationItem(name: UnsafePointer(promptName), valueLength: promptText.utf8.count, value: promptValue, flags: 0)

        let rightsStatus: OSStatus = withUnsafeMutablePointer(to: &right) { rightPointer in
            withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                var rights = AuthorizationRights(count: 1, items: rightPointer)
                var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                return AuthorizationCopyRights(
                    authorization, &rights, &environment,
                    [.interactionAllowed, .extendRights, .preAuthorize], nil
                )
            }
        }
        if rightsStatus == errAuthorizationCanceled { return .cancelled }
        guard rightsStatus == errAuthorizationSuccess else { return .unavailable }

        let wrapped = "( \(script)\n ); echo \(exitMarker)$?"
        guard let dashC = strdup("-c"), let body = strdup(wrapped) else { return .unavailable }
        defer { free(dashC); free(body) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [dashC, body, nil]
        var pipe: UnsafeMutablePointer<FILE>?
        let status = arguments.withUnsafeMutableBufferPointer { buffer in
            execute(authorization, toolPath, [], UnsafePointer(buffer.baseAddress!), &pipe)
        }
        guard status == errAuthorizationSuccess, let pipe else { return .unavailable }
        defer { fclose(pipe) }

        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = fread(&chunk, 1, chunk.count, pipe)
            if count == 0 { break }
            output.append(chunk, count: count)
        }
        let text = String(decoding: output, as: UTF8.self)
        guard let markerRange = text.range(of: exitMarker, options: .backwards) else {
            return .failed(text.isEmpty ? "The installer did not report a result." : text)
        }
        let exitCode = Int(text[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        if exitCode == 0 { return .succeeded }
        let message = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "The installer exited with status \(exitCode)." : message)
    }

    /// Runs the script through `sudo` with no terminal. Without Touch ID for sudo configured it
    /// fails before running anything, which reports as unavailable so the next prompt is tried.
    private nonisolated static func runWithSudo(_ script: String) -> PrivilegedOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-k", "/bin/sh", "-c", "( \(script)\n ); echo \(exitMarker)$?"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .unavailable
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(decoding: data, as: UTF8.self)
        guard let markerRange = text.range(of: exitMarker, options: .backwards) else {
            return .unavailable
        }
        let exitCode = Int(text[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        if exitCode == 0 { return .succeeded }
        let message = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "The installer exited with status \(exitCode)." : message)
    }

    private nonisolated static func runWithAppleScript(_ script: String) -> PrivilegedOutcome {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            return .failed("Could not prepare the installer.")
        }
        appleScript.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .succeeded }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        return number == userCancelledErrorNumber ? .cancelled : .failed(message)
    }
}
