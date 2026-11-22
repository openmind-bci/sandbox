"""Example adapter: a lamp controlled through a LOCAL HTTP API (no cloud).

======== ====================================================================
action   toggle on/off (always allowed: switching a lamp is harmless)
left     dim down by one step
right    dim up by one step
rest     keep the current state
forward  ignored
======== ====================================================================

The API is the one of :mod:`openmind_sandbox.adapters.examples.fake_lamp`:
``GET`` and ``PUT`` on ``<url>/light`` with ``{"on": bool, "brightness": 0-100}``.
Adapt :meth:`LampAdapter._get` and :meth:`LampAdapter._put` to your own lamp.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import Any

from openmind_protocol import Message

from openmind_sandbox.adapters.base import Adapter

log = logging.getLogger(__name__)

DEFAULT_URL = "http://127.0.0.1:8781"
#: Seconds before giving up on the lamp; short, so the loop never hangs.
TIMEOUT_S = 1.0


class LampAdapter(Adapter):
    """A lamp that toggles on ``action`` and dims with ``left`` / ``right``.

    Args:
        url: Base URL of the lamp API (local network only).
        step: Brightness change (0-100 scale) of one ``left`` / ``right``.
        min_confidence: Commands below this confidence are ignored.
        publish: Where events go (see :class:`Adapter`).
        clock: Monotonic time source, for tests.
    """

    def __init__(
        self,
        url: str = DEFAULT_URL,
        step: int = 10,
        min_confidence: float = 0.7,
        publish: Callable[[Message], None] | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        super().__init__("lamp", min_confidence=min_confidence, publish=publish, clock=clock)
        self.url = url.rstrip("/")
        self.step = step

    def context_allows_action(self) -> bool:
        """Toggling a lamp is harmless: ``action`` is always allowed."""
        return True

    def on_command(self, command: str, confidence: float) -> None:
        if command == "action":
            state = self._get()
            if state is not None:
                self._set({"on": not state["on"]}, "toggle")
        elif command in ("left", "right"):
            state = self._get()
            if state is not None:
                delta = -self.step if command == "left" else self.step
                brightness = max(0, min(100, int(state["brightness"]) + delta))
                self._set({"brightness": brightness}, "dim")
        # "rest" keeps the state; "forward" has no meaning for a lamp.

    def stop(self) -> None:
        """Keep the light as it is.

        A lamp has no motion, so its safe state is "no change": nothing is sent.
        Commands are no longer applied, so no dimming can continue by itself.
        """
        log.info("lamp: safe state, no further change")

    # -- local HTTP API ------------------------------------------------------------

    def _get(self) -> dict[str, Any] | None:
        return self._request("GET", None)

    def _set(self, fields: dict[str, Any], reason: str) -> None:
        state = self._request("PUT", fields)
        if state is not None:
            self.emit_event("state", {**state, "reason": reason})

    def _request(self, method: str, body: dict[str, Any] | None) -> dict[str, Any] | None:
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(
            f"{self.url}/light",
            data=data,
            method=method,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
                state = json.loads(response.read())
            if isinstance(state, dict) and "on" in state and "brightness" in state:
                return state
            log.warning("unexpected answer from the lamp: %r", state)
        except (urllib.error.URLError, OSError, ValueError) as error:
            log.warning("lamp request failed: %s", error)
        return None
