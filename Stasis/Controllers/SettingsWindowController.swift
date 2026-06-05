import AppKit
import SwiftUI
import smc_power

@MainActor
enum AppActivationPolicy {
    private static var count = 0

    static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let capabilities: DeviceCapabilities
    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
    }

    func showSettings() {
        if let existingWindow = window {
            let wasVisible = existingWindow.isVisible
            existingWindow.makeKeyAndOrderFront(nil)
            if !wasVisible {
                AppActivationPolicy.enter()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        let settingsView = SettingsView(
            capabilities: capabilities
        )
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = String(localized: "Stasis Settings")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titlebarSeparatorStyle = .none
        newWindow.toolbarStyle = .automatic
        newWindow.toolbar = NSToolbar() // Required for the liquid glass effect
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        AppActivationPolicy.enter()

        self.window = newWindow
    }
    
    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
    }
}
