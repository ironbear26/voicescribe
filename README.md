# VoiceScribe

**VoiceScribe** ist eine native macOS Menu-Bar-App für lokale Sprachtranskription.  
Sprich – drücke die Stopptaste – und der Text erscheint direkt in der Zwischenablage oder wird automatisch eingefügt.

Transkription erfolgt **vollständig lokal** mit [Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) von NVIDIA (via NeMo).  
Optionale KI-Nachbearbeitung läuft über die **Claude-API** von Anthropic.

---

## Architektur

```
┌────────────────────────────────────────────┐
│  VoiceScribe.app  (Swift / AppKit)         │
│                                            │
│  NSStatusItem   →  Menu Bar Icon           │
│  AVAudioEngine  →  Mikrofon-Aufnahme       │
│  Carbon Hotkeys →  Globale Tastenkürzel    │
│  URLSession     →  HTTP an Daemon + API    │
└──────────────────────┬─────────────────────┘
                       │ HTTP 127.0.0.1:9393
┌──────────────────────▼─────────────────────┐
│  Parakeet-Daemon  (Python / NeMo)          │
│                                            │
│  POST /transcribe  →  WAV → Text           │
│  GET  /status      →  {"ready": true}      │
└────────────────────────────────────────────┘
```

Die Swift-App startet den Python-Daemon beim Launch automatisch und kommuniziert per HTTP mit ihm. Das Parakeet-Modell bleibt im RAM – keine Ladezeit nach dem ersten Start.

---

## Modi

| Modus | Hotkey | Beschreibung |
|---|---|---|
| **Transkript-Modus** | `Ctrl+Shift+T` | Rohtranskription direkt von Parakeet |
| **Assistent-Modus** | `Ctrl+Shift+A` | Claude bereinigt Korrekturen und Füllwörter |
| **Diktat-Modus** | `Ctrl+Shift+D` | Claude wandelt Gesprochenes in natürlichen Text um |
| **Stopp** | `Ctrl+Shift+S` | Aufnahme manuell stoppen |

Denselben Hotkey erneut drücken stoppt ebenfalls die Aufnahme.

**Beispiel Assistent-Modus:**  
Gesprochen: *„Ja nein, also das Meeting ist um nein halt um halb zehn"*  
Ergebnis: *„Das Meeting ist um halb zehn"*

**Beispiel Diktat-Modus:**  
Gesprochen: *„Hey kannst du morgen mal schauen ob der Bericht fertig ist danke"*  
Ergebnis: *„Hey, könntest du morgen bitte prüfen, ob der Bericht fertig ist? Danke."*

---

## Voraussetzungen

- **macOS 13** (Ventura) oder neuer
- **Python 3.10** oder neuer
- **Xcode Command Line Tools** (für `swiftc`)

```bash
xcode-select --install
```

---

## Installation

```bash
# 1. Repository klonen
cd /pfad/zu/sprachsteuerung

# 2. Python-Umgebung einrichten + App bauen
./install.sh
```

`install.sh` erledigt automatisch:
- Python-venv erstellen unter `~/Library/Application Support/VoiceScribe/venv/`
- `nemo_toolkit[asr]` installieren (PyTorch + NeMo, ca. 3–5 GB)
- Swift-Quellen kompilieren
- `VoiceScribe.app` bauen

Nur die App neu bauen (nach Code-Änderungen):

```bash
./build.sh
```

Dann starten:

```bash
open VoiceScribe.app
```

---

## macOS-Berechtigungen

### Mikrofon
Wird beim ersten Start automatisch angefragt.  
Manuell: *Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon → VoiceScribe aktivieren*

### Bedienungshilfen (für Auto-Einfügen)
Nur nötig, wenn "Auto-Einfügen" aktiviert ist (simuliertes Cmd+V).

1. *Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen*
2. **VoiceScribe** hinzufügen und aktivieren

### Globale Hotkeys
Carbon-Hotkeys (`RegisterEventHotKey`) benötigen **keine** Bedienungshilfen-Berechtigung.  
Sie funktionieren direkt nach dem Start.

---

## Einstellungen

Der API-Key und weitere Optionen sind über das Menü erreichbar:  
**Menüleiste → Einstellungen...**

Alternativ direkt in `~/Library/Application Support/VoiceScribe/config.json` bearbeiten:

```json
{
  "anthropicApiKey": "sk-ant-...",
  "autoPaste": false,
  "autoCopy": true,
  "language": "de",
  "assistantPrompt": "Du bist ein Assistent...",
  "dictationPrompt": "Wandle den folgenden..."
}
```

### Anthropic API-Key
Für Assistent-Modus und Diktat-Modus wird ein [Anthropic API-Key](https://console.anthropic.com) benötigt.  
Ohne API-Key funktioniert der **Transkript-Modus** vollständig offline.

---

## Parakeet-Modell

VoiceScribe verwendet **nvidia/parakeet-tdt-0.6b-v2**, ein 0.6B-Parameter-Modell von NVIDIA.

**Wichtige Hinweise:**
- Das Modell wurde primär auf **Englisch** trainiert und erzielt auf Englisch die beste Qualität.
- Für Deutsch und andere Sprachen funktioniert es, aber die Genauigkeit ist geringer als bei sprachspezifischen Modellen.
- **Erster Start:** Das Modell (~1,2 GB) wird beim ersten Daemon-Start heruntergeladen und unter `~/.cache/huggingface/` gespeichert. Das dauert je nach Verbindung 2–10 Minuten.
- Nach dem ersten Download bleibt das Modell lokal und lädt in Sekunden.

Den Lade-Status sieht man unter **Menüleiste → Modell-Status**.

---

## Verzeichnisstruktur

```
sprachsteuerung/
├── Sources/                    Swift-Quellen
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   ├── AudioRecorder.swift
│   ├── HotkeyManager.swift
│   ├── TranscriptionClient.swift
│   ├── AssistantClient.swift
│   ├── ClipboardManager.swift
│   ├── SettingsManager.swift
│   └── SettingsWindowController.swift
├── Resources/
│   ├── Info.plist
│   └── VoiceScribe.entitlements
├── python/
│   ├── server.py               Parakeet HTTP-Daemon
│   └── requirements.txt
├── build.sh                    App kompilieren und bündeln
├── install.sh                  Alles einrichten
├── config.json                 Standard-Konfiguration
└── README.md
```

---

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| `swiftc` nicht gefunden | `xcode-select --install` |
| Hotkeys ohne Funktion | App neu starten; beim ersten Start einmal auf das Icon klicken |
| Mikrofon-Fehler | Berechtigung in Systemeinstellungen prüfen |
| Daemon startet nicht | Log prüfen: `~/Library/Logs/VoiceScribe/daemon.log` |
| Modell-Download schlägt fehl | Internetverbindung prüfen; Proxy-Einstellungen beachten |
| „App beschädigt" Meldung | `xattr -cr VoiceScribe.app` ausführen |
| API-Fehler bei Claude | API-Key in Einstellungen prüfen |
| Auto-Einfügen funktioniert nicht | Bedienungshilfen-Berechtigung für VoiceScribe vergeben |

---

## Lizenz

MIT License – frei verwendbar und anpassbar.
