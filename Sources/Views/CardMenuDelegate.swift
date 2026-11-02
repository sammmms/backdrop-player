import AppKit

public final class CardMenuDelegate: NSObject {
    public static let shared = CardMenuDelegate()

    public var onPreview: ((CatalogItem) -> Void)?
    public var onDesktop: ((CatalogItem) -> Void)?
    public var onLock: ((CatalogItem) -> Void)?
    public var onBoth: ((CatalogItem) -> Void)?
    public var onWeb: ((CatalogItem) -> Void)?
    public var onReveal: ((CatalogItem) -> Void)?
    public var onDelete: ((CatalogItem) -> Void)?

    private override init() {
        super.init()
    }

    public func showMenu(for item: CatalogItem, isDownloaded: Bool) {
        let menu = NSMenu()

        let miPreview = NSMenuItem(title: "Preview & Configure in Sidebar", action: #selector(handlePreview(_:)), keyEquivalent: "")
        miPreview.target = self
        miPreview.representedObject = item
        menu.addItem(miPreview)

        menu.addItem(NSMenuItem.separator())

        let miDesktop = NSMenuItem(title: "Set as Desktop Wallpaper", action: #selector(handleDesktop(_:)), keyEquivalent: "")
        miDesktop.target = self
        miDesktop.representedObject = item
        menu.addItem(miDesktop)

        let miLock = NSMenuItem(title: "Set as Lock Screen Wallpaper", action: #selector(handleLock(_:)), keyEquivalent: "")
        miLock.target = self
        miLock.representedObject = item
        menu.addItem(miLock)

        let miBoth = NSMenuItem(title: "Set as Both (Desktop + Lock Screen)", action: #selector(handleBoth(_:)), keyEquivalent: "")
        miBoth.target = self
        miBoth.representedObject = item
        menu.addItem(miBoth)

        if !item.isLocalCopy {
            menu.addItem(NSMenuItem.separator())
            let miWeb = NSMenuItem(title: "Open Source Webpage", action: #selector(handleWeb(_:)), keyEquivalent: "")
            miWeb.target = self
            miWeb.representedObject = item
            menu.addItem(miWeb)
        }

        if isDownloaded {
            menu.addItem(NSMenuItem.separator())
            let miReveal = NSMenuItem(title: "Reveal in Finder", action: #selector(handleReveal(_:)), keyEquivalent: "")
            miReveal.target = self
            miReveal.representedObject = item
            menu.addItem(miReveal)

            let miDelete = NSMenuItem(title: "Delete Wallpaper from Disk", action: #selector(handleDelete(_:)), keyEquivalent: "")
            miDelete.target = self
            miDelete.representedObject = item
            menu.addItem(miDelete)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func handlePreview(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onPreview?(item)
    }

    @objc private func handleDesktop(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onDesktop?(item)
    }

    @objc private func handleLock(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onLock?(item)
    }

    @objc private func handleBoth(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onBoth?(item)
    }

    @objc private func handleWeb(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onWeb?(item)
    }

    @objc private func handleReveal(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onReveal?(item)
    }

    @objc private func handleDelete(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? CatalogItem else { return }
        onDelete?(item)
    }
}
