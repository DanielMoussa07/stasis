import AppKit
import Foundation

struct SignificantEnergyApp: Identifiable, Equatable, Sendable {
    let id: pid_t
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let powerScore: Double
    let icon: NSImage?

    static func == (lhs: SignificantEnergyApp, rhs: SignificantEnergyApp) -> Bool {
        lhs.id == rhs.id && lhs.powerScore == rhs.powerScore
    }

    @MainActor
    func activate() {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }
}
