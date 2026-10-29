#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="BackdropPlayer"
BUNDLE_NAME="${APP_NAME}.app"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${BUNDLE_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Building release binary with Swift..."
swift build -c release

echo "📦 Packaging ${BUNDLE_NAME}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

BIN_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Generate Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.sam.BackdropPlayer</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Backdrop Player</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ App bundle created at: ${APP_DIR}"
echo "👉 You can run it with: open \"${APP_DIR}\""
