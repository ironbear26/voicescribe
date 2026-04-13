"""
Globale Hotkey-Verwaltung mit pynput.
Erkennt Tastenkombinationen systemweit und ruft Callbacks auf.

Benötigt macOS-Berechtigung "Bedienungshilfen" (Accessibility).
"""

import logging
import threading
from typing import Callable, Optional

from pynput import keyboard

logger = logging.getLogger(__name__)

# Mapping von Konfigurations-Strings zu pynput Key-Objekten
_SPECIAL_KEYS = {
    "<ctrl>": keyboard.Key.ctrl,
    "<shift>": keyboard.Key.shift,
    "<alt>": keyboard.Key.alt,
    "<cmd>": keyboard.Key.cmd,
    "<space>": keyboard.Key.space,
    "<enter>": keyboard.Key.enter,
    "<tab>": keyboard.Key.tab,
    "<esc>": keyboard.Key.esc,
}


def _parse_hotkey(hotkey_str: str) -> frozenset:
    """
    Parst einen Hotkey-String (z.B. '<ctrl>+<shift>+t') in ein frozenset
    von pynput Key-/KeyCode-Objekten.
    """
    parts = [p.strip() for p in hotkey_str.lower().split("+")]
    keys = set()
    for part in parts:
        if part in _SPECIAL_KEYS:
            keys.add(_SPECIAL_KEYS[part])
        elif len(part) == 1:
            keys.add(keyboard.KeyCode.from_char(part))
        else:
            logger.warning("Unbekannte Taste im Hotkey-String: '%s'", part)
    return frozenset(keys)


class HotkeyManager:
    """
    Überwacht globale Tasteneingaben und ruft Callbacks bei konfigurierten
    Tastenkombinationen auf.
    """

    def __init__(
        self,
        hotkey_config: dict,
        on_transcript: Callable,
        on_assistant: Callable,
        on_dictation: Callable,
        on_stop: Callable,
    ):
        self._callbacks = {
            "transcript": on_transcript,
            "assistant": on_assistant,
            "dictation": on_dictation,
            "stop": on_stop,
        }
        self._hotkeys: dict[str, frozenset] = {}
        self._pressed_keys: set = set()
        self._listener: Optional[keyboard.Listener] = None
        self._lock = threading.Lock()
        self._last_triggered: Optional[str] = None

        self._load_hotkeys(hotkey_config)

    def _load_hotkeys(self, hotkey_config: dict):
        """Parst alle Hotkeys aus der Konfiguration."""
        self._hotkeys = {}
        for action, hotkey_str in hotkey_config.items():
            try:
                parsed = _parse_hotkey(hotkey_str)
                self._hotkeys[action] = parsed
                logger.info("Hotkey registriert: %s → %s", action, hotkey_str)
            except Exception as e:
                logger.error("Fehler beim Parsen des Hotkeys '%s': %s", hotkey_str, e)

    def start(self):
        """Startet den Hotkey-Listener in einem Hintergrund-Thread."""
        if self._listener is not None:
            logger.warning("Hotkey-Listener läuft bereits.")
            return

        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release,
        )
        self._listener.daemon = True
        self._listener.start()
        logger.info("Hotkey-Listener gestartet.")

    def stop(self):
        """Stoppt den Hotkey-Listener."""
        if self._listener is not None:
            self._listener.stop()
            self._listener = None
            logger.info("Hotkey-Listener gestoppt.")

    def _normalize_key(self, key) -> object:
        """Normalisiert einen Taste-Event zu einem vergleichbaren Objekt."""
        # Modifier-Tasten: linke und rechte Variante auf gemeinsamen Key normalisieren
        modifier_map = {
            keyboard.Key.ctrl_l: keyboard.Key.ctrl,
            keyboard.Key.ctrl_r: keyboard.Key.ctrl,
            keyboard.Key.shift_l: keyboard.Key.shift,
            keyboard.Key.shift_r: keyboard.Key.shift,
            keyboard.Key.alt_l: keyboard.Key.alt,
            keyboard.Key.alt_r: keyboard.Key.alt,
            keyboard.Key.alt_gr: keyboard.Key.alt,
            keyboard.Key.cmd_l: keyboard.Key.cmd,
            keyboard.Key.cmd_r: keyboard.Key.cmd,
        }
        return modifier_map.get(key, key)

    def _on_press(self, key):
        """Callback beim Drücken einer Taste."""
        normalized = self._normalize_key(key)
        with self._lock:
            self._pressed_keys.add(normalized)
            current = frozenset(self._pressed_keys)

        # Prüfe, ob eine Kombination übereinstimmt
        for action, hotkey_set in self._hotkeys.items():
            if hotkey_set and hotkey_set == current:
                # Vermeide mehrfaches Auslösen beim Halten der Tasten
                if self._last_triggered != action:
                    self._last_triggered = action
                    logger.info("Hotkey ausgelöst: %s", action)
                    callback = self._callbacks.get(action)
                    if callback:
                        threading.Thread(
                            target=self._safe_call,
                            args=(callback,),
                            daemon=True,
                            name=f"hotkey-{action}",
                        ).start()
                break

    def _on_release(self, key):
        """Callback beim Loslassen einer Taste."""
        normalized = self._normalize_key(key)
        with self._lock:
            self._pressed_keys.discard(normalized)
            # Reset last_triggered wenn keine Hotkey-Modifier mehr gedrückt sind
            if not any(
                k in self._pressed_keys
                for k in [keyboard.Key.ctrl, keyboard.Key.shift, keyboard.Key.alt, keyboard.Key.cmd]
            ):
                self._last_triggered = None

    def _safe_call(self, callback: Callable):
        """Führt einen Callback sicher aus und fängt Exceptions."""
        try:
            callback()
        except Exception as e:
            logger.error("Fehler im Hotkey-Callback: %s", e)

    def update_hotkeys(self, hotkey_config: dict):
        """Aktualisiert die Hotkey-Konfiguration zur Laufzeit."""
        with self._lock:
            self._load_hotkeys(hotkey_config)
            self._pressed_keys.clear()
            self._last_triggered = None
