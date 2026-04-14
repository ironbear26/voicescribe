#!/usr/bin/env bash
# build.sh – Compiles VoiceScribe Swift sources and creates VoiceScribe.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="VoiceScribe"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RES_DIR="${APP_BUNDLE}/Contents/Resources"
SRC_DIR="${SCRIPT_DIR}/Sources"
RES_SRC_DIR="${SCRIPT_DIR}/Resources"

echo "=== VoiceScribe Build ==="
echo "Ziel: ${APP_BUNDLE}"
echo ""

# ── 1. Create bundle structure ────────────────────────────────────────────────
echo "→ Erstelle App-Bundle-Verzeichnisstruktur..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RES_DIR}"

# ── 2. Detect architecture ───────────────────────────────────────────────────
ARCH="$(uname -m)"
if [[ "${ARCH}" == "arm64" ]]; then
    TARGET="arm64-apple-macosx13.0"
else
    TARGET="x86_64-apple-macosx13.0"
fi
echo "→ Architektur: ${ARCH}  (target: ${TARGET})"

# ── 3. Compile Swift sources ─────────────────────────────────────────────────
echo "→ Kompiliere Swift-Quellen..."
swiftc \
    "${SRC_DIR}/AppDelegate.swift" \
    "${SRC_DIR}/StatusBarController.swift" \
    "${SRC_DIR}/AudioRecorder.swift" \
    "${SRC_DIR}/HotkeyManager.swift" \
    "${SRC_DIR}/TranscriptionClient.swift" \
    "${SRC_DIR}/AssistantClient.swift" \
    "${SRC_DIR}/ClipboardManager.swift" \
    "${SRC_DIR}/SettingsManager.swift" \
    "${SRC_DIR}/SettingsWindowController.swift" \
    -o "${MACOS_DIR}/${APP_NAME}" \
    -framework AppKit \
    -framework Foundation \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreGraphics \
    -framework UserNotifications \
    -target "${TARGET}" \
    -swift-version 5

echo "   ✓ Kompilierung erfolgreich"

# ── 4. Copy Info.plist ────────────────────────────────────────────────────────
echo "→ Kopiere Info.plist..."
cp "${RES_SRC_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# ── 5. Copy AppIcon (optional) ────────────────────────────────────────────────
if [[ -f "${RES_SRC_DIR}/AppIcon.icns" ]]; then
    echo "→ Kopiere AppIcon.icns..."
    cp "${RES_SRC_DIR}/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
    # Add icon reference to Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true
fi

# ── 6. Copy Python daemon ────────────────────────────────────────────────────
echo "→ Kopiere Python-Daemon..."
mkdir -p "${RES_DIR}/python"
cp "${SCRIPT_DIR}/python/server.py" "${RES_DIR}/python/server.py"
cp "${SCRIPT_DIR}/python/requirements.txt" "${RES_DIR}/python/requirements.txt"

# ── 7. Copy config.json ───────────────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/config.json" ]]; then
    echo "→ Kopiere config.json..."
    cp "${SCRIPT_DIR}/config.json" "${RES_DIR}/config.json"
fi

# ── 8. Mark as executable ────────────────────────────────────────────────────
chmod +x "${MACOS_DIR}/${APP_NAME}"

# ── 9. Remove quarantine (if re-building) ────────────────────────────────────
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "=== Build abgeschlossen ==="
echo ""
echo "App-Bundle: ${APP_BUNDLE}"
echo ""
echo "Starten:"
echo "  open '${APP_BUNDLE}'"
echo ""
echo "Hinweis: Beim ersten Start macOS nach Mikrofon- und Bedienungshilfen-Zugriffsrechten fragen lassen."
echo "Falls 'nicht vertrauenswürdig' erscheint:"
echo "  Systemeinstellungen → Datenschutz & Sicherheit → App trotzdem öffnen"
