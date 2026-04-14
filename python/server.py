#!/usr/bin/env python3
"""
Parakeet Transkriptions-Daemon
Lädt das Modell einmal und bleibt im Hintergrund aktiv.
Hört auf localhost:9393

Stabil auch wenn nemo noch nicht installiert ist:
  → /status gibt {"ready": false, "error": "..."} zurück
  → Server startet sofort, Modell lädt im Hintergrund
"""

import json
import logging
import os
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

MODEL_NAME = "nvidia/parakeet-tdt-0.6b-v2"
HOST = "127.0.0.1"
PORT = 9393

model = None
model_ready = False
model_error: str = ""


# ── Modell laden ──────────────────────────────────────────────────────────────

def load_model():
    global model, model_ready, model_error

    # NeMo-Logging ruhig stellen
    for name in ["nemo_logger", "pytorch_lightning", "nemo", "root"]:
        logging.getLogger(name).setLevel(logging.ERROR)

    try:
        logger.info("Importiere nemo.collections.asr ...")
        import nemo.collections.asr as nemo_asr
    except ImportError as e:
        model_error = (
            f"nemo_toolkit nicht installiert: {e}\n"
            "Bitte './install.sh' ausfuehren."
        )
        logger.error(model_error)
        return
    except Exception as e:
        model_error = f"nemo Import-Fehler: {e}"
        logger.error(model_error)
        return

    try:
        logger.info("Lade Modell %s ...", MODEL_NAME)
        model = nemo_asr.models.ASRModel.from_pretrained(MODEL_NAME)
        model.eval()
        model_ready = True
        model_error = ""
        logger.info("Modell geladen und bereit.")
    except Exception as e:
        model_error = f"Modell konnte nicht geladen werden: {e}"
        logger.error(model_error)


# ── HTTP Handler ──────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Access-Logs unterdrücken

    def do_GET(self):
        if self.path == "/status":
            self._json({
                "ready": model_ready,
                "model": MODEL_NAME,
                "error": model_error,
            })
        else:
            self._json({"error": "Not found"}, 404)

    def do_POST(self):
        if self.path == "/transcribe":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            audio_path = body.get("file", "")

            if not model_ready:
                self._json({
                    "error": model_error or "Modell laedt noch ...",
                    "ready": False,
                }, 503)
                return

            if not os.path.isfile(audio_path):
                self._json({"error": f"Datei nicht gefunden: {audio_path}"}, 400)
                return

            try:
                results = model.transcribe([audio_path])
                text = results[0] if isinstance(results[0], str) else results[0].text
                self._json({"text": text.strip()})
            except Exception as e:
                logger.error("Transkriptionsfehler: %s", e)
                self._json({"error": str(e)}, 500)
        else:
            self._json({"error": "Not found"}, 404)

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


# ── Port freimachen ───────────────────────────────────────────────────────────

def free_port(host, port):
    """Beendet alten Daemon auf dem gleichen Port."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect((host, port))
        # Port belegt – alten Prozess beenden
        import subprocess
        result = subprocess.run(
            ["lsof", "-ti", ":%d" % port],
            capture_output=True, text=True
        )
        for pid_str in result.stdout.strip().splitlines():
            try:
                os.kill(int(pid_str), signal.SIGTERM)
                logger.info("Alter Daemon (PID %s) beendet.", pid_str)
            except Exception:
                pass
        time.sleep(0.5)
    except (ConnectionRefusedError, OSError):
        pass  # Port ist frei


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    free_port(HOST, PORT)

    # Modell im Hintergrund laden – Server startet sofort
    threading.Thread(target=load_model, daemon=True, name="model-loader").start()

    try:
        server = HTTPServer((HOST, PORT), Handler)
        logger.info("Parakeet-Daemon läuft auf http://%s:%d", HOST, PORT)
        server.serve_forever()
    except OSError as e:
        logger.error("Konnte Server nicht starten: %s", e)
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Daemon beendet.")
