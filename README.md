# Backdrop Player (macOS)

A high-performance, ultra-lightweight macOS menu bar application built natively in **Swift**, **AppKit**, and **AVFoundation** to render video and static wallpapers seamlessly on your Mac desktop.

It directly discovers and plays downloaded wallpaper assets from the **Backdrop** app (`~/Library/Application Support/Backdrop/Library/Assets`), matching them to their human-friendly titles via Backdrop's SQLite database.

---

## ✨ Features

- **⚡ Hardware-Accelerated & Ultra Low Overhead**:
  - Uses Apple's VideoToolbox via `AVQueuePlayer` and `AVPlayerLooper` for seamless 60/120fps video playback with `< 1% CPU` and minimal battery consumption.
- **🖥️ True Desktop Layering**:
  - Positions the wallpaper window directly behind your desktop icons (`desktopIconWindow - 1`), allowing you to interact with desktop files, select, drag, and open Finder right-click context menus uninterrupted.
- **🌌 Mission Control / Spaces Support**:
  - Persistent across all macOS Spaces and virtual desktops without flashing or hiding during space transitions.
- **🔄 Auto-Discovery of Backdrop Assets**:
  - Queries `Backdrop.sqlite` to display wallpapers by their real names (*"Kirby Floating on Pond"*, *"Room in the forest"*, *"Dancing Petals"*, *"Abi Toads"*).
  - Watches the Backdrop assets directory for newly downloaded wallpapers and auto-refreshes in real-time.
- **📂 Custom Wallpapers**:
  - Choose and play any local `.mov`, `.mp4`, `.m4v`, or high-res `.heic` / `.png` / `.jpg` file via file picker.
- **🔋 Battery-Conscious Sleep Detection**:
  - Automatically pauses playback when displays go to sleep and resumes immediately upon waking.
- **🖥️ Multi-Display Support**:
  - Dynamically creates independent rendering sessions for every attached display and adapts automatically when displays are plugged/unplugged or resolutions change.
- **🎛️ Menu Bar Controls**:
  - Quick 1-click wallpaper switcher.
  - Play / Pause toggle (`⌘P`).
  - Mute / Unmute audio toggle (`⌘M`).
  - Scaling modes (Fill Screen / Crop vs. Fit Screen / Letterbox).
  - Desktop layer modes (Behind Desktop Icons vs. Base Desktop Layer).
  - Open Backdrop Assets folder directly in Finder.

---

## 🛠️ Build & Run

### Quick Run (Swift Package Manager)

```bash
cd ~/Documents/GitHub/backdrop-player
swift run
```

### Build Standalone `.app` Bundle

```bash
cd ~/Documents/GitHub/backdrop-player
./scripts/build-app.sh
```

The output will be created at:
`dist/BackdropPlayer.app`

To launch it:
```bash
open dist/BackdropPlayer.app
```

To install it into your system Applications folder:
```bash
cp -R dist/BackdropPlayer.app /Applications/
open /Applications/BackdropPlayer.app
```

---

## 📁 Project Architecture

```
backdrop-player/
├── Package.swift                    # Swift package specification (macOS 13+)
├── scripts/
│   └── build-app.sh                 # Releases and packages BackdropPlayer.app bundle
└── Sources/
    ├── main.swift                   # Application entry point
    ├── AppDelegate.swift            # NSApplicationDelegate (menu bar accessory mode)
    ├── Models/
    │   └── WallpaperItem.swift      # Wallpaper model (id, title, type, fileURL, size)
    ├── Services/
    │   └── BackdropLibraryService.swift # SQLite3 query & folder watcher
    ├── Views/
    │   └── WallpaperWindow.swift    # Borderless desktop-layer NSWindow
    └── Controllers/
        ├── WallpaperEngine.swift    # AVQueuePlayer + AVPlayerLooper multi-screen engine
        └── StatusBarController.swift # NSStatusItem & menu management
```
