#!/usr/bin/env python3
"""
VoiceScribe Transkriptions-Daemon
Unterstützt zwei Backends:
  - whisper  : faster-whisper, mehrsprachig (Standard für Deutsch)
  - parakeet : nvidia/parakeet-tdt-0.6b-v2, nur Englisch

Backend und Sprache werden per POST /configure oder config.json gesetzt.
Server startet sofort; Modell lädt im Hintergrund.
"""

import json
import logging
import os
import pathlib
import signal
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

HOST = "127.0.0.1"
PORT = 9393

# ── Konfiguration laden ───────────────────────────────────────────────────────
# Sucht config.json neben server.py oder in ~/Library/Application Support/VoiceScribe/
def _find_config() -> dict:
    candidates = [
        pathlib.Path(__file__).parent.parent / "config.json",           # Bundle Resources
        pathlib.Path.home() / "Library/Application Support/VoiceScribe/config.json",
        pathlib.Path(__file__).parent.parent.parent.parent.parent / "config.json",  # Dev
    ]
    for p in candidates:
        if p.exists():
            try:
                return json.loads(p.read_text())
            except Exception:
                pass
    return {}

_cfg = _find_config()
BACKEND  = _cfg.get("transcriptionBackend", "whisper").lower()
LANGUAGE = _cfg.get("language", "de")
WHISPER_MODEL = _cfg.get("whisperModel", "large-v3")

model        = None
model_ready  = False
model_error  = ""
model_name   = ""


# ── Modell laden ──────────────────────────────────────────────────────────────

def _silence_loggers():
    for name in ["nemo_logger", "pytorch_lightning", "nemo", "root",
                 "faster_whisper", "ctranslate2"]:
        logging.getLogger(name).setLevel(logging.ERROR)

def load_whisper():
    global model, model_ready, model_error, model_name
    _silence_loggers()
    try:
        from faster_whisper import WhisperModel
        name = WHISPER_MODEL
        model_name = f"faster-whisper/{name}"
        logger.info("Lade Whisper-Modell '%s' (Sprache: %s) ...", name, LANGUAGE)
        model = WhisperModel(name, device="cpu", compute_type="int8")
        model_ready = True
        model_error = ""
        logger.info("Whisper-Modell geladen und bereit.")
    except ImportError as e:
        model_error = f"faster-whisper nicht installiert: {e} – './install.sh' ausführen."
        logger.error(model_error)
    except Exception as e:
        model_error = f"Whisper-Ladefehler: {e}"
        logger.error(model_error)

def load_parakeet():
    global model, model_ready, model_error, model_name
    _silence_loggers()
    name = "nvidia/parakeet-tdt-0.6b-v2"
    model_name = name
    try:
        import nemo.collections.asr as nemo_asr
        logger.info("Lade Parakeet-Modell '%s' ...", name)
        model = nemo_asr.models.ASRModel.from_pretrained(name)
        model.eval()
        model_ready = True
        model_error = ""
        logger.info("Parakeet-Modell geladen und bereit.")
    except ImportError as e:
        model_error = f"nemo_toolkit nicht installiert: {e} – './install.sh' ausführen."
        logger.error(model_error)
    except Exception as e:
        model_error = f"Parakeet-Ladefehler: {e}"
        logger.error(model_error)

def load_model():
    if BACKEND == "parakeet":
        load_parakeet()
    else:
        load_whisper()


# ── Transkription ─────────────────────────────────────────────────────────────

def transcribe_file(audio_path: str) -> str:
    if BACKEND == "parakeet":
        results = model.transcribe([audio_path])
        text = results[0] if isinstance(results[0], str) else results[0].text
        return text.strip()
    else:
        # faster-whisper
        segments, _ = model.transcribe(
            audio_path,
            language=LANGUAGE if LANGUAGE else None,
            beam_size=5,
            vad_filter=True,
            vad_parameters={"min_silence_duration_ms": 500},
        )
        return " ".join(s.text.strip() for s in segments).strip()


# ── HTTP Handler ──────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/status":
            self._json({
                "ready":   model_ready,
                "backend": BACKEND,
                "model":   model_name or (
                    "nvidia/parakeet-tdt-0.6b-v2" if BACKEND == "parakeet"
                    else f"faster-whisper/{WHISPER_MODEL}"
                ),
                "language": LANGUAGE,
                "error":   model_error,
            })
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body   = json.loads(self.rfile.read(length) or b"{}")

        if self.path == "/transcribe":
            if not model_ready:
                self._json({"error": model_error or "Modell lädt noch …", "ready": False}, 503)
                return
            audio_path = body.get("file", "")
            if not os.path.isfile(audio_path):
                self._json({"error": f"Datei nicht gefunden: {audio_path}"}, 400)
                return
            try:
                text = transcribe_file(audio_path)
                self._json({"text": text})
            except Exception as e:
                logger.error("Transkriptionsfehler: %s", e)
                self._json({"error": str(e)}, 500)
        else:
            self._json({"error": "not found"}, 404)

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


# ── Port freimachen ───────────────────────────────────────────────────────────

def free_port(host, port):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            s.connect((host, port))
        import subprocess
        pids = subprocess.run(["lsof", "-ti", f":{port}"],
                              capture_output=True, text=True).stdout.strip().splitlines()
        for pid in pids:
            try:
                os.kill(int(pid), signal.SIGTERM)
                logger.info("Alter Daemon (PID %s) beendet.", pid)
            except Exception:
                pass
        time.sleep(0.5)
    except (ConnectionRefusedError, OSError):
        pass


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    logger.info("Backend: %s | Sprache: %s", BACKEND, LANGUAGE)
    free_port(HOST, PORT)
    threading.Thread(target=load_model, daemon=True, name="model-loader").start()
    try:
        server = HTTPServer((HOST, PORT), Handler)
        logger.info("Daemon läuft auf http://%s:%d", HOST, PORT)
        server.serve_forever()
    except OSError as e:
        logger.error("Server-Start fehlgeschlagen: %s", e)
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Daemon beendet.")
