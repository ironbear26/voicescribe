"""
Claude-KI-Integration für Assistent-Modus und Diktat-Modus.
Verwendet das anthropic SDK mit Prompt-Caching für System-Prompts.
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)


class Assistant:
    """Verarbeitet transkribierten Text mit Claude AI."""

    def __init__(self, api_key: str, assistant_prompt: str, dictation_prompt: str):
        self.api_key = api_key
        self.assistant_prompt = assistant_prompt
        self.dictation_prompt = dictation_prompt
        self._client = None

    def _get_client(self):
        """Erstellt den Anthropic-Client (lazy initialization)."""
        if self._client is None:
            if not self.api_key:
                raise ValueError(
                    "Kein Anthropic API-Schlüssel konfiguriert. "
                    "Bitte den API-Schlüssel in config.json eintragen."
                )
            try:
                import anthropic
                self._client = anthropic.Anthropic(api_key=self.api_key)
                logger.info("Anthropic-Client initialisiert.")
            except ImportError as e:
                raise RuntimeError(
                    "Das 'anthropic' Paket ist nicht installiert. "
                    "Bitte 'pip install anthropic' ausführen."
                ) from e
        return self._client

    def _call_claude(self, system_prompt: str, user_text: str) -> str:
        """
        Sendet eine Anfrage an Claude und gibt die Antwort zurück.
        Nutzt Prompt-Caching für den System-Prompt.
        """
        client = self._get_client()

        try:
            import anthropic

            response = client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=2048,
                system=[
                    {
                        "type": "text",
                        "text": system_prompt,
                        "cache_control": {"type": "ephemeral"},
                    }
                ],
                messages=[
                    {
                        "role": "user",
                        "content": user_text,
                    }
                ],
            )

            result = response.content[0].text.strip()
            logger.info(
                "Claude-Antwort erhalten (%d → %d Tokens). Ergebnis: '%s...'",
                response.usage.input_tokens,
                response.usage.output_tokens,
                result[:60],
            )
            return result

        except anthropic.AuthenticationError as e:
            raise RuntimeError(
                "API-Authentifizierung fehlgeschlagen. Bitte API-Schlüssel prüfen."
            ) from e
        except anthropic.RateLimitError as e:
            raise RuntimeError(
                "API-Ratenlimit erreicht. Bitte kurz warten und erneut versuchen."
            ) from e
        except anthropic.APIConnectionError as e:
            raise RuntimeError(
                "Keine Verbindung zur Anthropic API. Bitte Internetverbindung prüfen."
            ) from e
        except Exception as e:
            logger.error("Unbekannter API-Fehler: %s", e)
            raise RuntimeError(f"Claude-API-Fehler: {e}") from e

    def clean_transcript(self, text: str) -> str:
        """
        Assistent-Modus: Bereinigt Sprachaufnahme-Artefakte.
        Entfernt Korrekturen, Füllwörter und Wiederholungen.
        """
        if not text.strip():
            return text

        logger.info("Assistent-Modus: Bereinige Text...")
        return self._call_claude(self.assistant_prompt, text)

    def dictation_mode(self, text: str) -> str:
        """
        Diktat-Modus: Wandelt gesprochene Sprache in geschriebenen Stil um.
        """
        if not text.strip():
            return text

        logger.info("Diktat-Modus: Konvertiere Text...")
        return self._call_claude(self.dictation_prompt, text)

    def update_api_key(self, api_key: str):
        """Aktualisiert den API-Schlüssel und setzt den Client zurück."""
        self.api_key = api_key
        self._client = None

    def update_prompts(self, assistant_prompt: str = None, dictation_prompt: str = None):
        """Aktualisiert die System-Prompts."""
        if assistant_prompt is not None:
            self.assistant_prompt = assistant_prompt
        if dictation_prompt is not None:
            self.dictation_prompt = dictation_prompt
