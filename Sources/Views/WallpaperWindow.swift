import AppKit

public final class WallpaperWindow: NSWindow {
    public var targetScreen: NSScreen?

    public init(screen: NSScreen, level: NSWindow.Level) {
        self.targetScreen = screen

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.setFrame(screen.frame, display: true)
        self.level = level
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        self.ignoresMouseEvents = true
        self.isOpaque = true
        self.backgroundColor = .black
        self.hasShadow = false
        self.canHide = false
    }

    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
