"""
macOS Menu Bar App mit rumps.
Steuert die Benutzeroberfläche und koordiniert alle App-Komponenten.
"""

import logging
import os
import subprocess
import tempfile
import threading

import rumps

from app.config import Config
from app.recorder import Recorder
from app.transcriber import Transcriber
from app.assistant import Assistant
from app import clipboard_manager

logger = logging.getLogger(__name__)

# Icons für verschiedene Zustände
ICON_IDLE = "🎙"
ICON_RECORDING = "🔴"
ICON_PROCESSING = "⚙️"
ICON_DONE = "✓"
ICON_ERROR = "⚠️"

# Modi
MODE_TRANSCRIPT = "transcript"
MODE_ASSISTANT = "assistant"
MODE_DICTATION = "dictation"


class VoiceScribeApp(rumps.App):
    """Haupt-App-Klasse für VoiceScribe."""

    def __init__(self, config: Config):
        super().__init__(
            name="VoiceScribe",
            title=ICON_IDLE,
            quit_button=None,  # Eigener Beenden-Eintrag unten
        )

        self.config = config
        self._current_mode: str | None = None
        self._state_lock = threading.Lock()
        self._last_transcript: str = ""

        # Komponenten initialisieren
        self.recorder = Recorder()
        self.transcriber = Transcriber(config=config._data)
        self.assistant = Assistant(
            api_key=config.anthropic_api_key,
            assistant_prompt=config.assistant_prompt,
            dictation_prompt=config.dictation_prompt,
        )

        # Menü aufbauen
        self._build_menu()

    def _build_menu(self):
        """Erstellt das Menü."""
        # Status-Anzeige (nicht klickbar)
        self.status_item = rumps.MenuItem("● Bereit")
        self.status_item.set_callback(None)

        # Modi
        self.transcript_item = rumps.MenuItem(
            "Transkript-Modus (⌃⇧T)",
            callback=self._on_transcript_menu,
        )
        self.assistant_item = rumps.MenuItem(
            "Assistent-Modus (⌃⇧A)",
            callback=self._on_assistant_menu,
        )
        self.dictation_item = rumps.MenuItem(
            "Diktat-Modus (⌃⇧D)",
            callback=self._on_dictation_menu,
        )

        # Stop
        self.stop_item = rumps.MenuItem(
            "Aufnahme stoppen (⌃⇧S)",
            callback=self._on_stop_menu,
        )

        # Auto-Einfügen Toggle
        auto_paste_label = self._auto_paste_label()
        self.auto_paste_item = rumps.MenuItem(
            auto_paste_label,
            callback=self._on_toggle_auto_paste,
        )

        # Sonstiges
        self.settings_item = rumps.MenuItem(
            "Einstellungen öffnen",
            callback=self._on_open_settings,
        )
        self.last_transcript_item = rumps.MenuItem(
            "Letztes Transkript anzeigen",
            callback=self._on_show_last_transcript,
        )
        self.quit_item = rumps.MenuItem(
            "Beenden",
            callback=self._on_quit,
        )

        self.menu = [
            self.status_item,
            rumps.separator,
            self.transcript_item,
            self.assistant_item,
            self.dictation_item,
            self.stop_item,
            rumps.separator,
            self.auto_paste_item,
            rumps.separator,
            self.settings_item,
            self.last_transcript_item,
            rumps.separator,
            self.quit_item,
        ]

    # -------------------------------------------------------------------------
    # Menü-Callbacks
    # -------------------------------------------------------------------------

    def _on_transcript_menu(self, sender):
        self._handle_mode_trigger(MODE_TRANSCRIPT)

    def _on_assistant_menu(self, sender):
        self._handle_mode_trigger(MODE_ASSISTANT)

    def _on_dictation_menu(self, sender):
        self._handle_mode_trigger(MODE_DICTATION)

    def _on_stop_menu(self, sender):
        self.trigger_stop()

    def _on_toggle_auto_paste(self, sender):
        self.config.auto_paste = not self.config.auto_paste
        self.auto_paste_item.title = self._auto_paste_label()
        state = "aktiviert" if self.config.auto_paste else "deaktiviert"
        rumps.notification(
            "VoiceScribe",
            "Auto-Einfügen",
            f"Auto-Einfügen wurde {state}.",
            sound=False,
        )

    def _on_open_settings(self, sender):
        try:
            subprocess.Popen(["open", self.config.config_path_str])
        except Exception as e:
            rumps.alert(
                title="Fehler",
                message=f"Einstellungen konnten nicht geöffnet werden:\n{e}",
            )

    def _on_show_last_transcript(self, sender):
        if self._last_transcript:
            rumps.alert(
                title="Letztes Transkript",
                message=self._last_transcript,
            )
        else:
            rumps.alert(
                title="Letztes Transkript",
                message="Noch kein Transkript vorhanden.",
            )

    def _on_quit(self, sender):
        if self.recorder.is_recording:
            try:
                self.recorder.stop_recording()
            except Exception:
                pass
        rumps.quit_application()

    # -------------------------------------------------------------------------
    # Hotkey-Callbacks (werden aus HotkeyManager aufgerufen)
    # -------------------------------------------------------------------------

    def trigger_transcript(self):
        """Wird vom HotkeyManager für Transkript-Modus aufgerufen."""
        self._handle_mode_trigger(MODE_TRANSCRIPT)

    def trigger_assistant(self):
        """Wird vom HotkeyManager für Assistent-Modus aufgerufen."""
        self._handle_mode_trigger(MODE_ASSISTANT)

    def trigger_dictation(self):
        """Wird vom HotkeyManager für Diktat-Modus aufgerufen."""
        self._handle_mode_trigger(MODE_DICTATION)

    def trigger_stop(self):
        """Wird vom HotkeyManager für Stop aufgerufen."""
        if self.recorder.is_recording:
            threading.Thread(
                target=self._stop_and_process,
                daemon=True,
                name="stop-process",
            ).start()
        else:
            logger.info("Stop-Hotkey gedrückt, aber keine Aufnahme läuft.")

    # -------------------------------------------------------------------------
    # Aufnahme-Workflow
    # -------------------------------------------------------------------------

    def _handle_mode_trigger(self, mode: str):
        """
        Hauptlogik: Wenn Aufnahme läuft → stoppen und verarbeiten.
        Wenn idle → starten.
        """
        with self._state_lock:
            is_recording = self.recorder.is_recording

        if is_recording:
            # Bereits eine Aufnahme – stoppen und den aktuellen Modus verwenden
            threading.Thread(
                target=self._stop_and_process,
                daemon=True,
                name="stop-process",
            ).start()
        else:
            # Neue Aufnahme starten
            self._current_mode = mode
            threading.Thread(
                target=self._start_recording,
                daemon=True,
                name="start-recording",
            ).start()

    def _start_recording(self):
        """Startet die Aufnahme (läuft in Hintergrund-Thread)."""
        try:
            self.recorder.start_recording()
            self._set_state_recording()
            logger.info("Aufnahme gestartet im Modus: %s", self._current_mode)
        except RuntimeError as e:
            logger.error("Aufnahme konnte nicht gestartet werden: %s", e)
            self._set_state_error()
            rumps.alert(
                title="Aufnahmefehler",
                message=str(e),
            )

    def _stop_and_process(self):
        """Stoppt die Aufnahme und führt den kompletten Verarbeitungs-Workflow durch."""
        wav_path = None
        try:
            # 1. Aufnahme stoppen
            self._set_state_processing("Aufnahme wird gespeichert...")
            wav_path = self.recorder.stop_recording()

            # 2. Whisper-Transkription
            self._set_state_processing("Transkribiere...")
            text = self.transcriber.transcribe(
                wav_path,
                progress_callback=self._set_state_processing,
            )

            if not text.strip():
                rumps.notification(
                    "VoiceScribe",
                    "Keine Sprache erkannt",
                    "Es wurde kein Text transkribiert.",
                    sound=False,
                )
                self._set_state_idle()
                return

            # 3. Optionale KI-Verarbeitung
            mode = self._current_mode
            if mode == MODE_ASSISTANT:
                self._set_state_processing("Assistent bereinigt Text...")
                text = self.assistant.clean_transcript(text)
            elif mode == MODE_DICTATION:
                self._set_state_processing("Diktat wird formatiert...")
                text = self.assistant.dictation_mode(text)

            # 4. Ergebnis speichern
            self._last_transcript = text

            # 5. In Zwischenablage kopieren
            if self.config.auto_copy:
                clipboard_manager.copy_to_clipboard(text)

            # 6. Auto-Einfügen
            if self.config.auto_paste:
                clipboard_manager.auto_paste()

            # 7. Benachrichtigung
            preview = text[:80] + ("…" if len(text) > 80 else "")
            mode_label = {
                MODE_TRANSCRIPT: "Transkript",
                MODE_ASSISTANT: "Assistent",
                MODE_DICTATION: "Diktat",
            }.get(mode, "Transkript")

            rumps.notification(
                "VoiceScribe",
                f"{mode_label} bereit",
                preview,
                sound=False,
            )
            logger.info("Workflow abgeschlossen. Text: '%s...'", text[:60])

            # 8. Icon kurz auf "erledigt" setzen
            self._set_state_done()

        except RuntimeError as e:
            logger.error("Verarbeitungsfehler: %s", e)
            self._set_state_error()
            rumps.notification(
                "VoiceScribe",
                "Fehler",
                str(e),
                sound=False,
            )

        except Exception as e:
            logger.exception("Unerwarteter Fehler im Workflow: %s", e)
            self._set_state_error()
            rumps.alert(
                title="Unerwarteter Fehler",
                message=str(e),
            )

        finally:
            # Temporäre WAV-Datei löschen
            if wav_path and os.path.exists(wav_path):
                try:
                    os.unlink(wav_path)
                    logger.info("Temporäre WAV-Datei gelöscht: %s", wav_path)
                except OSError as e:
                    logger.warning("WAV-Datei konnte nicht gelöscht werden: %s", e)

    # -------------------------------------------------------------------------
    # UI-Zustandsverwaltung (thread-safe via rumps.App.title)
    # -------------------------------------------------------------------------

    def _set_state_idle(self):
        """Setzt die App in den Bereit-Zustand."""
        self.title = ICON_IDLE
        self.status_item.title = "● Bereit"

    def _set_state_recording(self):
        """Setzt die App in den Aufnahme-Zustand."""
        self.title = ICON_RECORDING
        mode_label = {
            MODE_TRANSCRIPT: "Transkript",
            MODE_ASSISTANT: "Assistent",
            MODE_DICTATION: "Diktat",
        }.get(self._current_mode, "")
        self.status_item.title = f"⏺ Aufnahme läuft... ({mode_label})"

    def _set_state_processing(self, message: str = "Verarbeite..."):
        """Setzt die App in den Verarbeitungs-Zustand."""
        self.title = ICON_PROCESSING
        self.status_item.title = f"⚙ {message}"

    def _set_state_done(self):
        """Setzt die App kurz in den Erledigt-Zustand, dann zurück zu idle."""
        self.title = ICON_DONE
        self.status_item.title = "✓ Fertig"
        threading.Timer(2.0, self._set_state_idle).start()

    def _set_state_error(self):
        """Setzt die App in den Fehler-Zustand, dann zurück zu idle."""
        self.title = ICON_ERROR
        self.status_item.title = "⚠ Fehler"
        threading.Timer(3.0, self._set_state_idle).start()

    # -------------------------------------------------------------------------
    # Hilfsmethoden
    # -------------------------------------------------------------------------

    def _auto_paste_label(self) -> str:
        state = "Ein" if self.config.auto_paste else "Aus"
        return f"Auto-Einfügen: {state}"
