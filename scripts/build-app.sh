#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
APP="$PWD/dist/DeskGPT.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/DeskGPT" "$APP/Contents/MacOS/DeskGPT"
if [[ ! -f "$APP/Contents/Resources/DeskGPT.icns" || scripts/make-icon.swift -nt "$APP/Contents/Resources/DeskGPT.icns" ]]; then
    swift scripts/make-icon.swift "$PWD/.build/DeskGPT.iconset"
    iconutil -c icns "$PWD/.build/DeskGPT.iconset" -o "$APP/Contents/Resources/DeskGPT.icns"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DeskGPT</string>
<key>CFBundleDisplayName</key><string>DeskGPT</string>
<key>CFBundleIdentifier</key><string>app.deskgpt.desktop</string>
<key>CFBundleIconFile</key><string>DeskGPT</string>
<key>CFBundleExecutable</key><string>DeskGPT</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
