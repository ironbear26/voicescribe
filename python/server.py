#!/usr/bin/env python3
"""
Parakeet Transkriptions-Daemon
Lädt das Modell einmal und bleibt im Hintergrund aktiv.
Hört auf localhost:9393
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import logging
import threading

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

model = None
model_ready = False
model_name = "nvidia/parakeet-tdt-0.6b-v2"


def load_model():
    global model, model_ready
    logger.info("Lade Parakeet-Modell: %s ...", model_name)

    # Reduce noisy framework loggers
    import logging as _l
    for noisy in ("nemo_logger", "pytorch_lightning", "nemo", "root", "lightning"):
        _l.getLogger(noisy).setLevel(_l.ERROR)

    try:
        import nemo.collections.asr as nemo_asr  # type: ignore
        model = nemo_asr.models.ASRModel.from_pretrained(model_name)
        model.eval()
        model_ready = True
        logger.info("Parakeet-Modell geladen und bereit.")
    except Exception as exc:
        logger.error("Modell konnte nicht geladen werden: %s", exc)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        pass  # Suppress per-request access logs

    # ------------------------------------------------------------------
    def do_GET(self):
        if self.path == "/status":
            self._json_response({"ready": model_ready, "model": model_name})
        else:
            self._json_response({"error": "Not found"}, status=404)

    # ------------------------------------------------------------------
    def do_POST(self):
        if self.path == "/transcribe":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            audio_path = body.get("file", "")

            if not model_ready:
                self._json_response(
                    {"error": "Modell noch nicht geladen – bitte kurz warten."}, status=503
                )
                return

            if not audio_path:
                self._json_response({"error": "Kein Dateipfad angegeben."}, status=400)
                return

            try:
                results = model.transcribe([audio_path])
                # NeMo returns either str or objects with a .text attribute
                result = results[0]
                text = result if isinstance(result, str) else result.text
                self._json_response({"text": text.strip()})
            except Exception as exc:
                logger.error("Transkriptionsfehler: %s", exc)
                self._json_response({"error": str(exc)}, status=500)
        else:
            self._json_response({"error": "Not found"}, status=404)

    # ------------------------------------------------------------------
    def _json_response(self, data: dict, status: int = 200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    # Load model in a background thread so the HTTP server starts immediately.
    # /status will return {"ready": false} until loading finishes.
    loader = threading.Thread(target=load_model, daemon=True)
    loader.start()

    server = HTTPServer(("127.0.0.1", 9393), Handler)
    logger.info("Parakeet-Server läuft auf http://127.0.0.1:9393")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Server beendet.")
