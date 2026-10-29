import AppKit
import SwiftUI

public final class GalleryWindowController: NSWindowController {
    public static let shared = GalleryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wallpaper Gallery & Hub"
        window.center()
        window.setFrameAutosaveName("BackdropPlayer.GalleryWindow")
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: GalleryView())
        window.contentView = hostingView

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        guard let window = self.window else { return }

        // Re-create root view to refresh catalog if needed
        window.contentView = NSHostingView(rootView: GalleryView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
