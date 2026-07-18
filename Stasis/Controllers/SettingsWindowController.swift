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
        // Window positioning is now handled by .center()
        if let existingWindow = window {
            let wasVisible = existingWindow.isVisible
            if !wasVisible {
                AppActivationPolicy.enter()
            }
            existingWindow.center()
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            capabilities: capabilities
        )

        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = String(localized: "Stasis Settings")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.titleVisibility = .visible
        newWindow.titlebarAppearsTransparent = false
        newWindow.toolbarStyle = .automatic
        newWindow.isMovableByWindowBackground = true
        newWindow.minSize = NSSize(width: 750, height: 540)
        newWindow.setContentSize(NSSize(width: 750, height: 540))
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        
        newWindow.center() // Center it on first launch after reset

        newWindow.delegate = self
        window = newWindow
        newWindow.setFrameAutosaveName("SettingsWindow")
        
        AppActivationPolicy.enter()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
    
    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
    }
}
