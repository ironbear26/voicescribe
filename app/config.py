"""
Konfigurationsverwaltung für VoiceScribe.
Lädt und speichert Einstellungen aus config.json.
"""

import json
import os
import logging

logger = logging.getLogger(__name__)

DEFAULT_CONFIG = {
    "anthropic_api_key": "",
    "transcription_backend": "whisper",
    "whisper_model": "base",
    "parakeet_model": "nvidia/parakeet-tdt-0.6b-v2",
    "language": "de",
    "hotkeys": {
        "transcript": "<ctrl>+<shift>+t",
        "assistant": "<ctrl>+<shift>+a",
        "dictation": "<ctrl>+<shift>+d",
        "stop": "<ctrl>+<shift>+s"
    },
    "auto_paste": False,
    "auto_copy": True,
    "assistant_prompt": (
        "Du bist ein Assistent der gesprochene Texte bereinigt. "
        "Entferne Korrekturen (z.B. 'nein, 9:30 Uhr' → nur '9:30 Uhr'), "
        "Füllwörter und Wiederholungen. Behalte den Inhalt aber gib nur den finalen sauberen Text zurück."
    ),
    "dictation_prompt": (
        "Wandle den folgenden gesprochenen Text in eine natürliche, gut geschriebene Nachricht um. "
        "Passe Stil, Grammatik und Formulierungen an, damit es wie ein professionell geschriebener Text klingt. "
        "Gib nur den finalen Text zurück ohne Erklärungen."
    )
}

# Pfad zur config.json relativ zu diesem Skript
_CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config.json")


class Config:
    """Verwaltet die App-Konfiguration."""

    def __init__(self, config_path: str = None):
        self.config_path = config_path or _CONFIG_PATH
        self._data = {}
        self.load()

    def load(self):
        """Lädt die Konfiguration aus config.json. Fehlende Schlüssel werden mit Defaults ergänzt."""
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    loaded = json.load(f)
                # Tiefes Merge: Defaults werden durch geladene Werte überschrieben
                self._data = self._deep_merge(DEFAULT_CONFIG.copy(), loaded)
                logger.info("Konfiguration geladen: %s", self.config_path)
            except (json.JSONDecodeError, OSError) as e:
                logger.error("Fehler beim Laden der Konfiguration: %s", e)
                self._data = DEFAULT_CONFIG.copy()
        else:
            logger.info("Keine config.json gefunden – verwende Standardwerte und erstelle Datei.")
            self._data = DEFAULT_CONFIG.copy()
            self.save()

    def save(self):
        """Speichert die aktuelle Konfiguration in config.json."""
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(self._data, f, indent=2, ensure_ascii=False)
            logger.info("Konfiguration gespeichert: %s", self.config_path)
        except OSError as e:
            logger.error("Fehler beim Speichern der Konfiguration: %s", e)

    def get(self, key: str, default=None):
        """Gibt einen Konfigurationswert zurück."""
        return self._data.get(key, default)

    def set(self, key: str, value):
        """Setzt einen Konfigurationswert und speichert."""
        self._data[key] = value
        self.save()

    def __getitem__(self, key):
        return self._data[key]

    def __setitem__(self, key, value):
        self._data[key] = value
        self.save()

    @property
    def anthropic_api_key(self) -> str:
        return self._data.get("anthropic_api_key", "")

    @property
    def transcription_backend(self) -> str:
        return self._data.get("transcription_backend", "whisper")

    @property
    def whisper_model(self) -> str:
        return self._data.get("whisper_model", "base")

    @property
    def parakeet_model(self) -> str:
        return self._data.get("parakeet_model", "nvidia/parakeet-tdt-0.6b-v2")

    @property
    def language(self) -> str:
        return self._data.get("language", "de")

    @property
    def hotkeys(self) -> dict:
        return self._data.get("hotkeys", DEFAULT_CONFIG["hotkeys"])

    @property
    def auto_paste(self) -> bool:
        return self._data.get("auto_paste", False)

    @auto_paste.setter
    def auto_paste(self, value: bool):
        self._data["auto_paste"] = value
        self.save()

    @property
    def auto_copy(self) -> bool:
        return self._data.get("auto_copy", True)

    @property
    def assistant_prompt(self) -> str:
        return self._data.get("assistant_prompt", DEFAULT_CONFIG["assistant_prompt"])

    @property
    def dictation_prompt(self) -> str:
        return self._data.get("dictation_prompt", DEFAULT_CONFIG["dictation_prompt"])

    @property
    def config_path_str(self) -> str:
        return self.config_path

    @staticmethod
    def _deep_merge(base: dict, override: dict) -> dict:
        """Führt zwei Dicts rekursiv zusammen. override-Werte haben Priorität."""
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = Config._deep_merge(result[key], value)
            else:
                result[key] = value
        return result
