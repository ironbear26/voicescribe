# VoiceScribe 🎙

**VoiceScribe** ist eine macOS Menu-Bar-App für lokale Sprachtranskription.  
Sprich – drücke die Stopptaste – und der Text erscheint direkt in der Zwischenablage oder wird automatisch eingefügt.

Transkription erfolgt **vollständig lokal** mit [faster-whisper](https://github.com/SYSTRAN/faster-whisper).  
Optionale KI-Verarbeitung läuft über die **Claude-API** von Anthropic.

---

## Funktionsweise

1. Du drückst einen Hotkey oder klickst im Menü auf einen Modus
2. Die App nimmt deine Stimme auf (rotes Icon im Menü)
3. Du drückst erneut den Hotkey oder Stopp → Whisper transkribiert lokal
4. Je nach Modus wird der Text ggf. mit Claude bereinigt
5. Der Text wird in die Zwischenablage kopiert (und optional automatisch eingefügt)
6. Du erhältst eine macOS-Benachrichtigung mit der Vorschau

---

## Modi

| Modus | Hotkey | Beschreibung |
|---|---|---|
| **Transkript-Modus** | `Ctrl+Shift+T` | Rohtranskription direkt von Whisper |
| **Assistent-Modus** | `Ctrl+Shift+A` | KI bereinigt Korrekturen und Füllwörter |
| **Diktat-Modus** | `Ctrl+Shift+D` | KI wandelt Gesprochenes in natürlichen Text um |
| **Stopp** | `Ctrl+Shift+S` | Aufnahme manuell stoppen |

**Beispiel Assistent-Modus:**  
Gesprochen: *„Ja nein, also das Meeting ist um nein halt um halb zehn"*  
Ergebnis: *„Das Meeting ist um halb zehn"*

**Beispiel Diktat-Modus:**  
Gesprochen: *„Hey kannst du morgen mal schauen ob der Bericht fertig ist danke"*  
Ergebnis: *„Hey, könntest du morgen bitte prüfen, ob der Bericht fertig ist? Danke."*

---

## Installation

### Voraussetzungen

- macOS 12 (Monterey) oder neuer
- Python 3.10 oder neuer
- [Homebrew](https://brew.sh) empfohlen

### Schritte

```bash
# 1. Repository klonen oder Dateien herunterladen
cd /pfad/zu/sprachsteuerung

# 2. Virtuelle Umgebung erstellen (empfohlen)
python3 -m venv venv
source venv/bin/activate

# 3. Abhängigkeiten installieren
pip install -r requirements.txt

# 4. App starten
python main.py
```

Das Whisper-Modell (`base`, ca. 145 MB) wird beim **ersten Start** automatisch heruntergeladen.  
Beim ersten Hotkey-Druck lädt das Modell in den Speicher (kann 5–15 Sekunden dauern).

---

## Benötigte macOS-Berechtigungen

Die App benötigt **zwei** Berechtigungen:

### 1. Mikrofon
Wird beim ersten Start automatisch angefragt.  
Manuell: *Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon → Terminal / Python aktivieren*

### 2. Bedienungshilfen (für globale Hotkeys)
Ohne diese Berechtigung funktionieren die Tastenkombinationen **nicht**.

**Einrichten:**
1. *Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen*
2. **Terminal** (oder dein Python-Interpreter) hinzufügen und aktivieren
3. App neu starten

> **Hinweis:** Wenn die Hotkeys nicht funktionieren, erscheint eine Warnung im Terminal. Die App ist dann nur über das Menü in der Menüleiste bedienbar.

---

## Konfiguration

Die Konfigurationsdatei `config.json` liegt im App-Verzeichnis und kann direkt bearbeitet werden.  
Im Menü: *Einstellungen öffnen* öffnet die Datei automatisch im Standard-Editor.

### Alle Einstellungen

```json
{
  "anthropic_api_key": "",        // Claude API-Schlüssel (für Modi 2 & 3)
  "whisper_model": "base",        // Whisper-Modell (tiny/base/small/medium/large)
  "language": "de",               // Sprache für Whisper (de, en, fr, ...)
  "hotkeys": {
    "transcript": "<ctrl>+<shift>+t",
    "assistant":  "<ctrl>+<shift>+a",
    "dictation":  "<ctrl>+<shift>+d",
    "stop":       "<ctrl>+<shift>+s"
  },
  "auto_paste": false,            // Text automatisch einfügen (Cmd+V)
  "auto_copy": true,              // Text immer in Zwischenablage kopieren
  "assistant_prompt": "...",      // System-Prompt für Assistent-Modus
  "dictation_prompt": "..."       // System-Prompt für Diktat-Modus
}
```

### Whisper-Modelle im Vergleich

| Modell | Größe | Geschwindigkeit | Genauigkeit |
|---|---|---|---|
| `tiny` | ~75 MB | Sehr schnell | Gering |
| `base` | ~145 MB | Schnell | Gut (**Standard**) |
| `small` | ~470 MB | Mittel | Sehr gut |
| `medium` | ~1.5 GB | Langsam | Exzellent |
| `large-v3` | ~3 GB | Sehr langsam | Höchste |

Für die meisten Anwendungsfälle ist `base` oder `small` empfohlen.

---

## Claude API-Schlüssel konfigurieren

Der Assistent-Modus und Diktat-Modus benötigen einen Anthropic API-Schlüssel.

1. API-Schlüssel unter [console.anthropic.com](https://console.anthropic.com) erstellen
2. Schlüssel in `config.json` eintragen:
   ```json
   {
     "anthropic_api_key": "sk-ant-..."
   }
   ```
3. App neu starten (oder Einstellungen neu laden)

**Ohne API-Schlüssel** funktioniert nur der **Transkript-Modus** (reine Whisper-Transkription).

---

## Tipps

- **Aufnahme stoppen:** Denselben Hotkey erneut drücken **oder** `Ctrl+Shift+S`
- **Auto-Einfügen:** Im Menü unter „Auto-Einfügen: Aus/Ein" umschalten – praktisch für Direkteingabe in Textfelder
- **Sprache ändern:** `"language": "en"` für Englisch, `"language": null` für automatische Erkennung
- **Lange Texte:** Das Whisper-Modell verarbeitet Aufnahmen beliebiger Länge
- **Datenschutz:** Alle Aufnahmen werden lokal verarbeitet; die Audiodaten verlassen das Gerät nicht (außer bei aktivierter Claude-Verarbeitung wird der *Text* an die API gesendet)

---

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| Hotkeys funktionieren nicht | Bedienungshilfen-Berechtigung prüfen (siehe oben) |
| Kein Mikrofon-Zugriff | Mikrofon-Berechtigung in Systemeinstellungen prüfen |
| Modell-Download schlägt fehl | Internetverbindung prüfen; Modell wird unter `~/.cache/huggingface/` gespeichert |
| Assistent gibt Fehler | API-Schlüssel in config.json prüfen |
| App startet nicht | `pip install -r requirements.txt` erneut ausführen |

---

## Technische Details

- **Transkription:** [faster-whisper](https://github.com/SYSTRAN/faster-whisper) mit CTranslate2 (CPU, int8-Quantisierung)
- **KI-Verarbeitung:** Claude 3.5 Haiku via Anthropic API mit Prompt-Caching
- **Audio:** sounddevice, 16 kHz Mono WAV
- **Hotkeys:** pynput keyboard listener
- **Zwischenablage:** pyperclip + pyautogui
- **UI:** rumps (Cocoa menu bar wrapper)

---

## Lizenz

MIT License – frei verwendbar und anpassbar.
