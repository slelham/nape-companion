#!/bin/bash
# Build a local, ad-hoc signed Nape Companion.app. Does not install or launch it.
# Requires the Xcode Command Line Tools on macOS. No paid developer account.

set -euo pipefail

cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build.sh produces the macOS app and must be run on a Mac." >&2
  echo "On this machine, run: swift test" >&2
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="${APP:-$PWD/build/Nape Companion.app}"
MACOS="$APP/Contents/MacOS"
HOST="$(uname -m)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$HOST" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported architecture: $HOST" >&2
    exit 1
    ;;
esac

if [[ "$HOST" == "arm64" ]]; then
  OTHER="x86_64"
else
  OTHER="arm64"
fi

SOURCES=(
  Sources/NapeProtocol/Commands.swift
  Sources/NapeProtocol/Reports.swift
  Sources/NapeProtocol/Identity.swift
  Sources/NapeProtocol/Names.swift
  Sources/NapeProtocol/HIDMessages.swift
  Sources/NapeProtocol/Engine.swift
  Sources/NapeProtocol/Presentation.swift
  App/RegistryCensus.swift
  App/HIDMonitor.swift
  App/RenamePanel.swift
  App/NapeApp.swift
)

compile_arch() {
  local arch="$1"
  local output="$2"
  swiftc -O -swift-version 5 -parse-as-library \
    -target "${arch}-apple-macosx12.0" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework IOKit \
    -framework Foundation \
    -o "$output" \
    "${SOURCES[@]}"
}

mkdir -p "$MACOS"
rm -f "$MACOS/NapeCompanion"

if ! compile_arch "$HOST" "$WORK/NapeCompanion-$HOST"; then
  echo "swiftc failed for $HOST" >&2
  exit 1
fi

if compile_arch "$OTHER" "$WORK/NapeCompanion-$OTHER"; then
  lipo -create -output "$MACOS/NapeCompanion" \
    "$WORK/NapeCompanion-$HOST" \
    "$WORK/NapeCompanion-$OTHER"
else
  echo "Could not compile $OTHER. The app will run on $HOST only." >&2
  cp "$WORK/NapeCompanion-$HOST" "$MACOS/NapeCompanion"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Nape Companion</string>
  <key>CFBundleDisplayName</key>
  <string>Nape Companion</string>
  <key>CFBundleIdentifier</key>
  <string>local.slelham.nape-companion</string>
  <key>CFBundleExecutable</key>
  <string>NapeCompanion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. --timestamp=none keeps the command from contacting Apple.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
echo "Run: open \"$APP\""
