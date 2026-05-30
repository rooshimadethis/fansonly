import SwiftUI
import AppKit

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    let manager = HelperManager()
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        popover.contentViewController = NSHostingController(rootView: MenuView(manager: manager))
        popover.behavior = .transient
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "Fan Control")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusItemText()
        }
        updateStatusItemText()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        manager.stopWatchdog()
        manager.setAutoMode()
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    private func updateStatusItemText() {
        guard let button = statusItem?.button else { return }
        
        if let status = manager.status {
            let maxSpeed = status.fans.map { $0.actual }.max() ?? 0
            let label = String(format: " %.0f°C (%.0f RPM)", status.cpu_temp, maxSpeed)
            
            let font = NSFont.systemFont(ofSize: 10.0, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
            button.attributedTitle = NSAttributedString(string: label, attributes: attributes)
            
            if maxSpeed > 1500 {
                button.image = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "Fan Control")
            } else {
                button.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "Fan Control")
            }
        }
    }
}
