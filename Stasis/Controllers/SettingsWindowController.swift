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
        let activeScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        
        let positionWindow: (NSWindow) -> Void = { win in
            if let screen = activeScreen {
                let screenRect = screen.visibleFrame
                let windowRect = win.frame
                let newX = screenRect.origin.x + (screenRect.width - windowRect.width) / 2
                let newY = screenRect.origin.y + (screenRect.height - windowRect.height) / 2
                win.setFrameOrigin(NSPoint(x: newX, y: newY))
            } else {
                win.center()
            }
        }

        if let existingWindow = window {
            let wasVisible = existingWindow.isVisible
            if !wasVisible {
                AppActivationPolicy.enter()
            }
            positionWindow(existingWindow)
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
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        newWindow.delegate = self
        
        positionWindow(newWindow)
        
        AppActivationPolicy.enter()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
    
    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
    }
}
