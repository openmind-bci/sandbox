"""A fake lamp with a tiny local HTTP API, to try :class:`LampAdapter` offline.

``GET /light`` returns ``{"on": bool, "brightness": 0-100}``; ``PUT`` or ``POST``
on ``/light`` merges the fields of a JSON body into that state. Standard library
only; it binds to localhost.
"""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

DEFAULT_LAMP_PORT = 8781


class FakeLampServer(ThreadingHTTPServer):
    """HTTP server holding the state of a fake lamp."""

    daemon_threads = True

    def __init__(self, port: int = DEFAULT_LAMP_PORT, host: str = "127.0.0.1") -> None:
        super().__init__((host, port), _Handler)
        self.light: dict[str, Any] = {"on": False, "brightness": 50}
        self.lock = threading.Lock()
        self.quiet = False

    @property
    def port(self) -> int:
        """Actual TCP port (useful with port 0)."""
        return int(self.server_address[1])


class _Handler(BaseHTTPRequestHandler):
    server: FakeLampServer

    def do_GET(self) -> None:
        if self.path != "/light":
            self._send(404, {"error": "not found"})
            return
        with self.server.lock:
            self._send(200, dict(self.server.light))

    def do_PUT(self) -> None:
        if self.path != "/light":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(body, dict):
                raise ValueError("body must be a JSON object")
            update: dict[str, Any] = {}
            if "on" in body:
                update["on"] = bool(body["on"])
            if "brightness" in body:
                update["brightness"] = max(0, min(100, int(body["brightness"])))
        except (ValueError, TypeError) as error:
            self._send(400, {"error": str(error)})
            return
        with self.server.lock:
            self.server.light.update(update)
            state = dict(self.server.light)
        if not self.server.quiet:
            print(f"lamp: {'on' if state['on'] else 'off'}, brightness {state['brightness']}")
        self._send(200, state)

    do_POST = do_PUT  # noqa: N815

    def _send(self, status: int, body: dict[str, Any]) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: Any) -> None:
        """Silence the default access log."""
