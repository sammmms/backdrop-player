import SwiftUI
import AppKit

public struct WallpaperConfigSheet: View {
    let item: CatalogItem
    let onDismiss: () -> Void

    @State private var playbackRate: Double
    @State private var volume: Float
    @State private var scalingMode: WallpaperScalingMode
    @State private var showSavedNotification: Bool = false

    private let ratePresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init(item: CatalogItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss

        let initialRate = WallpaperEngine.shared.getPlaybackRate(for: item.id)
        let initialVol = WallpaperEngine.shared.getVolume(for: item.id)
        let initialMode = WallpaperEngine.shared.scalingMode

        _playbackRate = State(initialValue: initialRate)
        _volume = State(initialValue: initialVol)
        _scalingMode = State(initialValue: initialMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ThumbnailImageView(item: item)
                    .frame(width: 80, height: 50)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(item.sourceDescription)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(3)

                        Text(item.category)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 1. Playback Speed (Time Scale)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Playback Speed (Time Scale)", systemImage: "speedometer")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text(String(format: "%.2fx", playbackRate))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(5)
                        }

                        Text("Control the animation speed of this video wallpaper (slow motion for relaxing ambient, or fast forward).")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Text("0.25x")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)

                            Slider(value: $playbackRate, in: 0.25...2.5, step: 0.05) { editing in
                                if !editing {
                                    applyRateChange(playbackRate)
                                }
                            }
                            .onChange(of: playbackRate) { newVal in
                                applyRateChange(newVal)
                            }

                            Text("2.50x")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        // Presets
                        HStack(spacing: 6) {
                            ForEach(ratePresets, id: \.self) { preset in
                                Button(action: {
                                    playbackRate = preset
                                    applyRateChange(preset)
                                }) {
                                    Text(String(format: "%.2fx", preset))
                                        .font(.system(size: 11, weight: playbackRate == preset ? .bold : .regular))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(playbackRate == preset ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                        .foregroundColor(playbackRate == preset ? .white : .primary)
                                        .cornerRadius(5)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)

                    // 2. Audio Volume
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Wallpaper Volume", systemImage: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text(volume == 0 ? "Muted" : "\(Int(volume * 100))%")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .cornerRadius(5)
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                volume = (volume > 0) ? 0.0 : 1.0
                                applyVolumeChange(volume)
                            }) {
                                Image(systemName: volume == 0 ? "speaker.slash" : "speaker.wave.2")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Slider(value: $volume, in: 0.0...1.0, step: 0.05) { editing in
                                if !editing {
                                    applyVolumeChange(volume)
                                }
                            }
                            .onChange(of: volume) { newVal in
                                applyVolumeChange(newVal)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)

                    // 3. Scaling Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Display Scaling Mode", systemImage: "aspectratio.fill")
                            .font(.system(size: 13, weight: .bold))

                        Picker("", selection: $scalingMode) {
                            ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: scalingMode) { newMode in
                            WallpaperEngine.shared.scalingMode = newMode
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)

                    // 4. Apply Actions
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Apply Wallpaper", systemImage: "arrow.up.and.line.horizontal.and.arrow.down")
                            .font(.system(size: 13, weight: .bold))

                        HStack(spacing: 8) {
                            Button(action: {
                                saveConfig()
                                WallpaperDownloader.shared.downloadAndApply(item: item, target: .desktop) { _ in
                                    onDismiss()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "display")
                                    Text("Apply Desktop")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                saveConfig()
                                WallpaperDownloader.shared.downloadAndApply(item: item, target: .lockScreen) { _ in
                                    onDismiss()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                    Text("Apply Lock")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                saveConfig()
                                WallpaperDownloader.shared.downloadAndApply(item: item, target: .both) { _ in
                                    onDismiss()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("Apply Both")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                if showSavedNotification {
                    Text("✓ Settings saved")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }

                Spacer()

                Button("Save & Close") {
                    saveConfig()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 480, height: 530)
    }

    private func applyRateChange(_ rate: Double) {
        WallpaperEngine.shared.setPlaybackRate(rate, for: item.id)
    }

    private func applyVolumeChange(_ vol: Float) {
        WallpaperEngine.shared.setVolume(vol, for: item.id)
    }

    private func saveConfig() {
        WallpaperEngine.shared.setPlaybackRate(playbackRate, for: item.id)
        WallpaperEngine.shared.setVolume(volume, for: item.id)
        WallpaperEngine.shared.scalingMode = scalingMode
        showSavedNotification = true
    }
}
