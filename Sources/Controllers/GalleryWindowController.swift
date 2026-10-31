import AppKit
import SwiftUI

public final class GalleryWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = GalleryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wallpaper Gallery & Workshop Hub"
        window.center()
        window.setFrameAutosaveName("BackdropPlayer.GalleryWindow")
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: GalleryView())
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        print("[GalleryWindowController] Showing gallery window...")
        NSApp.setActivationPolicy(.regular)
        guard let window = self.window else { return }

        // Re-create root view to refresh catalog if needed
        window.contentView = NSHostingView(rootView: GalleryView())
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        print("[GalleryWindowController] Gallery window closed, reverting to accessory mode.")
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
