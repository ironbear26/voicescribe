"""
Audio-Aufnahme mit sounddevice.
Nimmt vom Standard-Mikrofon auf und gibt den Pfad zu einer temporären WAV-Datei zurück.
"""

import logging
import os
import tempfile
import threading
import wave

import numpy as np
import sounddevice as sd

logger = logging.getLogger(__name__)

SAMPLE_RATE = 16000   # 16 kHz – optimal für Whisper
CHANNELS = 1          # Mono
DTYPE = "float32"
CHUNK_SIZE = 1024     # Frames pro Block


class Recorder:
    """Verwaltet die Mikrofon-Aufnahme."""

    def __init__(self):
        self._chunks: list[np.ndarray] = []
        self._is_recording = False
        self._stream: sd.InputStream | None = None
        self._lock = threading.Lock()

    @property
    def is_recording(self) -> bool:
        return self._is_recording

    def start_recording(self):
        """Startet die Aufnahme vom Standard-Mikrofon."""
        if self._is_recording:
            logger.warning("Aufnahme läuft bereits.")
            return

        with self._lock:
            self._chunks = []
            self._is_recording = True

        try:
            self._stream = sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=CHANNELS,
                dtype=DTYPE,
                blocksize=CHUNK_SIZE,
                callback=self._audio_callback,
            )
            self._stream.start()
            logger.info("Aufnahme gestartet (Abtastrate: %d Hz)", SAMPLE_RATE)
        except Exception as e:
            self._is_recording = False
            logger.error("Fehler beim Starten der Aufnahme: %s", e)
            raise RuntimeError(f"Mikrofon konnte nicht geöffnet werden: {e}") from e

    def stop_recording(self) -> str:
        """
        Stoppt die Aufnahme und speichert die Audiodaten als temporäre WAV-Datei.

        Returns:
            Pfad zur temporären WAV-Datei.

        Raises:
            RuntimeError: Wenn keine Aufnahme läuft oder keine Audiodaten vorhanden sind.
        """
        if not self._is_recording:
            raise RuntimeError("Keine laufende Aufnahme.")

        # Stream stoppen
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception as e:
                logger.error("Fehler beim Stoppen des Streams: %s", e)
            finally:
                self._stream = None

        self._is_recording = False

        with self._lock:
            chunks = list(self._chunks)
            self._chunks = []

        if not chunks:
            raise RuntimeError("Keine Audiodaten aufgenommen.")

        # Chunks zusammenführen
        audio_data = np.concatenate(chunks, axis=0)
        logger.info(
            "Aufnahme gestoppt. Länge: %.2f Sekunden (%d Samples)",
            len(audio_data) / SAMPLE_RATE,
            len(audio_data),
        )

        # Als WAV-Datei speichern
        wav_path = self._save_wav(audio_data)
        return wav_path

    def _audio_callback(self, indata: np.ndarray, frames: int, time_info, status):
        """Callback der sounddevice InputStream – wird in einem separaten Thread aufgerufen."""
        if status:
            logger.warning("sounddevice Status: %s", status)
        if self._is_recording:
            with self._lock:
                self._chunks.append(indata.copy())

    def _save_wav(self, audio_data: np.ndarray) -> str:
        """Speichert numpy-Array als 16-bit WAV-Datei in eine temporäre Datei."""
        # Float32 [-1.0, 1.0] → Int16 [-32768, 32767]
        audio_int16 = (audio_data * 32767).astype(np.int16)

        tmp = tempfile.NamedTemporaryFile(
            suffix=".wav", prefix="voicescribe_", delete=False
        )
        tmp_path = tmp.name
        tmp.close()

        try:
            with wave.open(tmp_path, "wb") as wf:
                wf.setnchannels(CHANNELS)
                wf.setsampwidth(2)  # 16-bit = 2 Bytes
                wf.setframerate(SAMPLE_RATE)
                wf.writeframes(audio_int16.tobytes())
            logger.info("WAV gespeichert: %s", tmp_path)
        except Exception as e:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
            raise RuntimeError(f"WAV konnte nicht gespeichert werden: {e}") from e

        return tmp_path
