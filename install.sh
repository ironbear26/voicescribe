#!/usr/bin/env bash
# install.sh – Richtet die Python-Umgebung für den Parakeet-Daemon ein
# nemo_toolkit unterstützt Python 3.10–3.12. Python 3.13+ wird NICHT unterstützt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${HOME}/Library/Application Support/VoiceScribe/venv"
REQUIREMENTS="${SCRIPT_DIR}/python/requirements.txt"

echo "=== VoiceScribe Installation ==="
echo ""

# ── 1. Kompatibles Python finden (3.10–3.12) ─────────────────────────────────
echo "→ Suche kompatibles Python (3.10–3.12 erforderlich für nemo_toolkit)..."

PYTHON=""
for candidate in \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /opt/homebrew/bin/python3.10 \
    /usr/local/bin/python3.12 \
    /usr/local/bin/python3.11 \
    /usr/local/bin/python3.10; do
    if [[ -x "$candidate" ]]; then
        PYTHON="$candidate"
        break
    fi
done

if [[ -z "$PYTHON" ]]; then
    echo ""
    echo "  Kein kompatibles Python (3.10–3.12) gefunden."
    echo "  Python 3.12 wird jetzt via Homebrew installiert..."
    echo ""

    if ! command -v brew &>/dev/null; then
        echo "FEHLER: Homebrew nicht gefunden."
        echo "  Homebrew installieren: https://brew.sh"
        exit 1
    fi

    brew install python@3.12
    PYTHON="/opt/homebrew/bin/python3.12"

    if [[ ! -x "$PYTHON" ]]; then
        echo "FEHLER: Installation von python@3.12 fehlgeschlagen."
        exit 1
    fi
fi

PY_VERSION=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "   ✓ Verwende Python $PY_VERSION unter $PYTHON"

# ── 2. Prüfe Xcode Command Line Tools ────────────────────────────────────────
echo "→ Prüfe Xcode Command Line Tools..."
if ! command -v swiftc &>/dev/null; then
    echo "FEHLER: swiftc nicht gefunden."
    echo "  Installieren mit: xcode-select --install"
    exit 1
fi
echo "   ✓ $(swiftc --version 2>&1 | head -1)"

# ── 3. Erstelle venv ──────────────────────────────────────────────────────────
echo "→ Erstelle Python-Umgebung in:"
echo "   ${VENV_DIR}"
mkdir -p "$(dirname "${VENV_DIR}")"
"$PYTHON" -m venv "${VENV_DIR}"
echo "   ✓ venv erstellt"

# ── 4. pip aktualisieren ──────────────────────────────────────────────────────
echo "→ Aktualisiere pip..."
"${VENV_DIR}/bin/pip" install --upgrade pip --quiet
echo "   ✓ pip aktualisiert"

# ── 5. nemo_toolkit installieren ──────────────────────────────────────────────
echo "→ Installiere nemo_toolkit[asr]..."
echo "  (Erstinstallation: PyTorch + NeMo werden heruntergeladen, ~3–5 GB)"
echo ""
"${VENV_DIR}/bin/pip" install nemo_toolkit[asr]
echo ""
echo "   ✓ nemo_toolkit installiert"

# ── 6. Verifikation ───────────────────────────────────────────────────────────
echo "→ Teste nemo-Import..."
"${VENV_DIR}/bin/python3" -c "import nemo; print('   ✓ nemo', nemo.__version__)"

# ── 7. App bauen ──────────────────────────────────────────────────────────────
echo ""
echo "→ Baue VoiceScribe.app..."
bash "${SCRIPT_DIR}/build.sh"

echo ""
echo "=== Installation abgeschlossen ==="
echo ""
echo "Nächste Schritte:"
echo "  1. open '${SCRIPT_DIR}/VoiceScribe.app'"
echo "  2. Beim ersten Start: Mikrofon-Zugriff erlauben"
echo "  3. Für Hotkeys: Bedienungshilfen-Zugriff erlauben"
echo "     Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → VoiceScribe"
echo "  4. Anthropic API-Key in Einstellungen eintragen (für Assistent/Diktat-Modus)"
echo ""
echo "Hinweis: Beim ersten App-Start wird das Parakeet-Modell heruntergeladen (~1,2 GB)."
