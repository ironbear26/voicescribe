#!/usr/bin/env python3
"""
VoiceScribe – macOS Sprachtranskriptions-App
============================================
Einstiegspunkt der Anwendung.

Starte mit:
    python main.py

Benötigte macOS-Berechtigungen:
- Mikrofon (wird beim ersten Start angefragt)
- Bedienungshilfen / Accessibility (für globale Hotkeys mit pynput)
"""

import logging
import sys
import threading

# Logging konfigurieren
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)


def main():
    """Initialisiert alle Komponenten und startet die App."""
    logger.info("VoiceScribe wird gestartet...")

    # Konfiguration laden
    try:
        from app.config import Config
        config = Config()
        logger.info("Konfiguration geladen.")
    except Exception as e:
        logger.critical("Konfiguration konnte nicht geladen werden: %s", e)
        sys.exit(1)

    # Menu-Bar-App erstellen
    try:
        from app.menu_bar import VoiceScribeApp
        app = VoiceScribeApp(config)
        logger.info("Menu-Bar-App initialisiert.")
    except Exception as e:
        logger.critical("App konnte nicht initialisiert werden: %s", e)
        sys.exit(1)

    # Hotkey-Manager starten (läuft in Hintergrund-Thread)
    try:
        from app.hotkeys import HotkeyManager
        hotkey_manager = HotkeyManager(
            hotkey_config=config.hotkeys,
            on_transcript=app.trigger_transcript,
            on_assistant=app.trigger_assistant,
            on_dictation=app.trigger_dictation,
            on_stop=app.trigger_stop,
        )
        hotkey_manager.start()
        logger.info("Hotkey-Manager gestartet.")
    except Exception as e:
        logger.warning(
            "Hotkey-Manager konnte nicht gestartet werden (Bedienungshilfen-Berechtigung?): %s", e
        )
        # App läuft auch ohne Hotkeys (nur über Menü bedienbar)

    # rumps-App starten (blockiert den Main-Thread)
    logger.info("Starte rumps-Event-Loop...")
    try:
        app.run()
    except KeyboardInterrupt:
        logger.info("Beenden per Tastatur.")
    finally:
        try:
            hotkey_manager.stop()
        except Exception:
            pass
        logger.info("VoiceScribe beendet.")


if __name__ == "__main__":
    main()
