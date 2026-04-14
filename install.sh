#!/usr/bin/env bash
# install.sh – Richtet die Python-Umgebung für den Parakeet-Daemon ein
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${HOME}/Library/Application Support/VoiceScribe/venv"
REQUIREMENTS="${SCRIPT_DIR}/python/requirements.txt"

echo "=== VoiceScribe Installation ==="
echo ""

# ── 1. Prüfe Python-Version ──────────────────────────────────────────────────
echo "→ Prüfe Python-Version..."
if ! command -v python3 &>/dev/null; then
    echo "FEHLER: python3 nicht gefunden. Bitte Python 3.10+ installieren."
    echo "       https://www.python.org/downloads/"
    exit 1
fi

PY_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)")
PY_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")

if [[ "${PY_MAJOR}" -lt 3 ]] || { [[ "${PY_MAJOR}" -eq 3 ]] && [[ "${PY_MINOR}" -lt 10 ]]; }; then
    echo "FEHLER: Python 3.10+ erforderlich, gefunden: ${PY_VERSION}"
    exit 1
fi
echo "   ✓ Python ${PY_VERSION}"

# ── 2. Prüfe Xcode Command Line Tools (für swiftc) ───────────────────────────
echo "→ Prüfe Xcode Command Line Tools..."
if ! command -v swiftc &>/dev/null; then
    echo "FEHLER: swiftc nicht gefunden."
    echo "       Xcode Command Line Tools installieren:"
    echo "       xcode-select --install"
    exit 1
fi
SWIFT_VERSION=$(swiftc --version 2>&1 | head -1)
echo "   ✓ ${SWIFT_VERSION}"

# ── 3. Erstelle venv ─────────────────────────────────────────────────────────
echo "→ Erstelle Python-Umgebung in:"
echo "   ${VENV_DIR}"
mkdir -p "$(dirname "${VENV_DIR}")"
python3 -m venv "${VENV_DIR}"
echo "   ✓ venv erstellt"

# ── 4. Aktualisiere pip ───────────────────────────────────────────────────────
echo "→ Aktualisiere pip..."
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet
echo "   ✓ pip aktualisiert"

# ── 5. Installiere Abhängigkeiten ─────────────────────────────────────────────
echo "→ Installiere nemo_toolkit[asr]..."
echo "   (Das kann mehrere Minuten dauern – PyTorch + NeMo werden heruntergeladen)"
echo ""
"${VENV_DIR}/bin/pip" install -r "${REQUIREMENTS}"
echo ""
echo "   ✓ Abhängigkeiten installiert"

# ── 6. Baue die App ───────────────────────────────────────────────────────────
echo ""
echo "→ Baue VoiceScribe.app..."
bash "${SCRIPT_DIR}/build.sh"

echo ""
echo "=== Installation abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. open '${SCRIPT_DIR}/VoiceScribe.app'"
echo "  2. Beim ersten Start: Mikrofon-Zugriff erlauben"
echo "  3. Für Auto-Einfügen: Bedienungshilfen-Zugriff erlauben"
echo "     Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → VoiceScribe"
echo "  4. Anthropic API-Key in Einstellungen eintragen (Menüleiste → Einstellungen)"
echo ""
echo "Hinweis: Beim ersten Start von VoiceScribe wird das Parakeet-Modell heruntergeladen"
echo "         (~1,2 GB). Das dauert je nach Internetverbindung einige Minuten."
