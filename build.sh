#!/usr/bin/env bash
# build.sh – Baut VoiceScribe via Swift Package Manager und erstellt das .app-Bundle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="VoiceScribe"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RES_DIR="${APP_BUNDLE}/Contents/Resources"
RES_SRC_DIR="${SCRIPT_DIR}/Resources"

echo "=== VoiceScribe Build ==="
echo "Ziel: ${APP_BUNDLE}"
echo ""

# ── 1. Swift Package Manager Build ───────────────────────────────────────────
echo "→ Kompiliere mit swift build (Release)..."
cd "${SCRIPT_DIR}"
swift build -c release 2>&1

# Ermittle den Pfad des kompilierten Binaries
ARCH="$(uname -m)"
if [[ "${ARCH}" == "arm64" ]]; then
    BINARY="${SCRIPT_DIR}/.build/arm64-apple-macosx/release/${APP_NAME}"
else
    BINARY="${SCRIPT_DIR}/.build/x86_64-apple-macosx/release/${APP_NAME}"
fi

if [[ ! -f "${BINARY}" ]]; then
    echo "FEHLER: Binary nicht gefunden unter ${BINARY}" >&2
    exit 1
fi
echo "   ✓ Kompilierung erfolgreich"
echo ""

# ── 2. App-Bundle-Verzeichnisstruktur ─────────────────────────────────────────
echo "→ Erstelle App-Bundle-Verzeichnisstruktur..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RES_DIR}"

# ── 3. Copy binary into bundle ───────────────────────────────────────────────
echo "→ Kopiere Binary ins Bundle..."
cp "${BINARY}" "${MACOS_DIR}/${APP_NAME}"

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
