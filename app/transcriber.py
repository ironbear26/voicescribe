"""
Lokale Sprachtranskription – unterstützt faster-whisper und NVIDIA Parakeet (via NeMo).
Das gewählte Modell wird beim ersten Aufruf automatisch heruntergeladen.

Backends:
  "whisper"   – faster-whisper (Standard, läuft auf CPU/MPS)
  "parakeet"  – NVIDIA Parakeet via nemo_toolkit (benötigt: pip install nemo_toolkit[asr])
               Standard-Modell: nvidia/parakeet-tdt-0.6b-v2
"""

import logging
import os
import time
from typing import Callable, Optional

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Whisper-Backend
# ---------------------------------------------------------------------------

class WhisperTranscriber:
    """Transkription mit faster-whisper (lokal, kein Internet nach erstem Download)."""

    def __init__(self, model_size: str = "base", language: str = "de"):
        self.model_size = model_size
        self.language = language
        self._model = None
        self._loading = False

    def _load_model(self, cb: Optional[Callable[[str], None]] = None):
        if self._model is not None:
            return
        while self._loading:
            time.sleep(0.2)
        if self._model is not None:
            return

        self._loading = True
        try:
            from faster_whisper import WhisperModel
            if cb:
                cb(f"Lade Whisper '{self.model_size}'…")
            logger.info("Lade Whisper-Modell: %s", self.model_size)
            self._model = WhisperModel(self.model_size, device="cpu", compute_type="int8")
            logger.info("Whisper-Modell '%s' bereit.", self.model_size)
            if cb:
                cb("Modell geladen.")
        except Exception as e:
            logger.error("Whisper-Ladefehler: %s", e)
            raise RuntimeError(f"Whisper-Modell konnte nicht geladen werden: {e}") from e
        finally:
            self._loading = False

    def transcribe(self, audio_path: str, cb: Optional[Callable[[str], None]] = None) -> str:
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio-Datei nicht gefunden: {audio_path}")
        self._load_model(cb)
        if cb:
            cb("Transkribiere (Whisper)…")
        try:
            segments, info = self._model.transcribe(
                audio_path,
                language=self.language or None,
                beam_size=5,
                vad_filter=True,
                vad_parameters=dict(min_silence_duration_ms=500),
            )
            text = " ".join(s.text.strip() for s in segments).strip()
            logger.info("Whisper fertig (lang=%s, %.2fs): %s…", info.language, info.duration, text[:60])
            return text
        except Exception as e:
            logger.error("Whisper-Transkriptionsfehler: %s", e)
            raise RuntimeError(f"Transkription fehlgeschlagen: {e}") from e

    def update_model(self, model_size: str):
        if model_size != self.model_size:
            logger.info("Whisper-Modell wechselt: %s → %s", self.model_size, model_size)
            self.model_size = model_size
            self._model = None


# ---------------------------------------------------------------------------
# Parakeet-Backend (NVIDIA NeMo)
# ---------------------------------------------------------------------------

class ParakeetTranscriber:
    """
    Transkription mit NVIDIA Parakeet über das NeMo-Framework.
    Läuft auf CPU (Apple Silicon kompatibel, kein CUDA nötig).

    Voraussetzung:
        pip install nemo_toolkit[asr]

    Standard-Modell: nvidia/parakeet-tdt-0.6b-v2
    Weitere Modelle:  nvidia/parakeet-ctc-1.1b
                      nvidia/parakeet-rnnt-1.1b
    """

    DEFAULT_MODEL = "nvidia/parakeet-tdt-0.6b-v2"

    def __init__(self, model_name: str = DEFAULT_MODEL, language: str = "de"):
        self.model_name = model_name
        self.language = language      # Parakeet ist primär Englisch – Hinweis in README
        self._model = None
        self._loading = False

    def _load_model(self, cb: Optional[Callable[[str], None]] = None):
        if self._model is not None:
            return
        while self._loading:
            time.sleep(0.2)
        if self._model is not None:
            return

        self._loading = True
        try:
            if cb:
                cb(f"Lade Parakeet '{self.model_name}'… (Erstdownload dauert einige Minuten)")
            logger.info("Lade Parakeet-Modell: %s", self.model_name)

            # Logging von NeMo/PyTorch auf Minimum reduzieren
            import logging as _logging
            for noisy in ("nemo_logger", "pytorch_lightning", "nemo"):
                _logging.getLogger(noisy).setLevel(_logging.ERROR)

            import nemo.collections.asr as nemo_asr  # noqa: F401 (lazy import)
            self._model = nemo_asr.models.ASRModel.from_pretrained(self.model_name)
            self._model.eval()

            logger.info("Parakeet-Modell '%s' bereit.", self.model_name)
            if cb:
                cb("Parakeet-Modell geladen.")
        except ImportError:
            raise RuntimeError(
                "nemo_toolkit ist nicht installiert.\n"
                "Installiere es mit:  pip install nemo_toolkit[asr]"
            )
        except Exception as e:
            logger.error("Parakeet-Ladefehler: %s", e)
            raise RuntimeError(f"Parakeet-Modell konnte nicht geladen werden: {e}") from e
        finally:
            self._loading = False

    def transcribe(self, audio_path: str, cb: Optional[Callable[[str], None]] = None) -> str:
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio-Datei nicht gefunden: {audio_path}")
        self._load_model(cb)
        if cb:
            cb("Transkribiere (Parakeet)…")
        try:
            # NeMo erwartet eine Liste von Dateipfaden
            results = self._model.transcribe([audio_path])
            # Rückgabe ist je nach Modelltyp eine Liste von Strings oder Hypothesen
            text = results[0] if isinstance(results[0], str) else results[0].text
            text = text.strip()
            logger.info("Parakeet fertig: %s…", text[:60])
            return text
        except Exception as e:
            logger.error("Parakeet-Transkriptionsfehler: %s", e)
            raise RuntimeError(f"Parakeet-Transkription fehlgeschlagen: {e}") from e

    def update_model(self, model_name: str):
        if model_name != self.model_name:
            logger.info("Parakeet-Modell wechselt: %s → %s", self.model_name, model_name)
            self.model_name = model_name
            self._model = None


# ---------------------------------------------------------------------------
# Öffentliche Factory  –  wird von menu_bar.py und main.py verwendet
# ---------------------------------------------------------------------------

class Transcriber:
    """
    Einheitliches Interface für alle Transkriptions-Backends.
    Das Backend wird über config["transcription_backend"] gewählt:
      "whisper"   (Standard)
      "parakeet"
    """

    def __init__(self, config: dict):
        backend = config.get("transcription_backend", "whisper").lower()
        language = config.get("language", "de")

        if backend == "parakeet":
            model_name = config.get("parakeet_model", ParakeetTranscriber.DEFAULT_MODEL)
            self._backend = ParakeetTranscriber(model_name=model_name, language=language)
            self.backend_name = "Parakeet"
        else:
            model_size = config.get("whisper_model", "base")
            self._backend = WhisperTranscriber(model_size=model_size, language=language)
            self.backend_name = "Whisper"

        logger.info("Transkriptions-Backend: %s", self.backend_name)

    def transcribe(
        self,
        audio_path: str,
        progress_callback: Optional[Callable[[str], None]] = None,
    ) -> str:
        return self._backend.transcribe(audio_path, cb=progress_callback)

    def update_config(self, config: dict):
        """Aktualisiert Modell-Parameter ohne Neustart (sofern Backend gleich bleibt)."""
        backend = config.get("transcription_backend", "whisper").lower()
        if backend == "parakeet" and isinstance(self._backend, ParakeetTranscriber):
            model_name = config.get("parakeet_model", ParakeetTranscriber.DEFAULT_MODEL)
            self._backend.update_model(model_name)
        elif backend == "whisper" and isinstance(self._backend, WhisperTranscriber):
            model_size = config.get("whisper_model", "base")
            self._backend.update_model(model_size)
