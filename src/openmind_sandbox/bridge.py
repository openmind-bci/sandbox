"""Gateway between MQTT, WebSocket clients (the Godot cockpit) and LSL.

Godot has no MQTT client: it talks to this bridge over a plain WebSocket.

- **MQTT → WebSocket.** Every message on ``openmind/v1/#`` is validated with
  ``openmind-protocol`` and sent to all clients as
  ``{"topic": ..., "kind": ..., "message": {...}}``. Invalid messages are logged
  and dropped, so a client never sees them.
- **WebSocket → MQTT and LSL.** Clients send ``marker`` and ``event`` messages as
  ``{"kind": "marker", "message": {...}}`` (``v`` and ``ts`` are filled in when
  missing). They are validated, published on MQTT and, for markers, pushed on an
  LSL markers stream so that EEG and cues share the LSL clock in OpenMind Core.
  A rejected message is answered with ``{"kind": "error", ...}``.
- **Bridge state.** Clients receive ``{"kind": "hello", ...}`` on connection and
  ``{"kind": "bridge", "mqtt_connected": ...}`` when the broker link changes, so
  that a scene can stop its objects when the broker is lost.

- **EEG (optional).** With ``eeg=True``, the LSL EEG stream is relayed read-only
  to the clients for the signal panel (see :mod:`openmind_sandbox.eeg_relay`).

The WebSocket listens on ``127.0.0.1:8765`` by default: local clients only.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any, Final

import openmind_protocol
from openmind_protocol import Event, Marker, Message, ProtocolError, decode, decode_topic, topics
from websockets.asyncio.server import Server, ServerConnection, broadcast, serve
from websockets.exceptions import ConnectionClosed

import openmind_sandbox
from openmind_sandbox.mqtt import DEFAULT_HOST, DEFAULT_PORT, MqttLink

log = logging.getLogger(__name__)

DEFAULT_WS_HOST: Final = "127.0.0.1"
DEFAULT_WS_PORT: Final = 8765

#: Message kinds a client may send through the bridge.
CLIENT_KINDS: Final = ("marker", "event")

#: Name, type and source id of the LSL markers stream (OpenMind Plug stream spec).
LSL_NAME: Final = "openmind-markers"
LSL_TYPE: Final = "Markers"
LSL_SOURCE_ID: Final = "openmind-sandbox:bridge:markers"
#: Version of the OpenMind Plug LSL stream specification followed by the stream.
LSL_SPEC_VERSION: Final = "1.1.0"
#: Largest transit delay (s) trusted when back-dating a marker to its ``ts``.
MAX_MARKER_DELAY: Final = 1.0


# --- Pure helpers ----------------------------------------------------------------


def envelope(topic: str, message: Message) -> str:
    """JSON text frame carrying ``message`` to the WebSocket clients."""
    return json.dumps(
        {"topic": topic, "kind": message.KIND, "message": message.model_dump(mode="json")},
        separators=(",", ":"),
        ensure_ascii=False,
    )


def parse_client_message(text: str | bytes, now: Callable[[], float] = time.time) -> Message:
    """Validate a frame sent by a client: a ``marker`` or an ``event``.

    ``v`` and ``ts`` are added when missing, so that clients may leave them out.

    Raises:
        ProtocolError: If the frame is not JSON, has another kind, or the message
            breaks the schema.
    """
    try:
        frame = json.loads(text)
    except (ValueError, UnicodeDecodeError) as error:
        raise ProtocolError("client", [f"(root): not valid JSON ({error})"]) from error
    if not isinstance(frame, dict) or not isinstance(frame.get("message"), dict):
        raise ProtocolError("client", ['(root): expected {"kind": ..., "message": {...}}'])
    kind = frame.get("kind")
    if kind == "marker":
        model: type[Message] = Marker
    elif kind == "event":
        model = Event
    else:
        problem = f"kind: {kind!r} is not accepted, use one of {CLIENT_KINDS}"
        raise ProtocolError("client", [problem])
    message: dict[str, Any] = {"v": openmind_protocol.VERSION, **frame["message"]}
    message.setdefault("ts", now())
    return decode(json.dumps(message), model)


def lsl_marker_sample(marker: Marker) -> str:
    """JSON content of the LSL sample for ``marker`` (OpenMind Plug stream spec 2.2).

    ``cue`` markers follow the specification (``label``, ``trial``);
    ``trial_start``, ``trial_end`` and ``event`` keep their protocol type, which
    consumers of the specification ignore if they do not know it.
    """
    sample: dict[str, Any] = {"type": marker.type, "label": marker.label, "source": "sandbox"}
    if marker.trial is not None:
        sample["trial"] = marker.trial
    if marker.scene is not None:
        sample["scene"] = marker.scene
    return json.dumps(sample, separators=(",", ":"), ensure_ascii=False)


def lsl_timestamp(marker_ts: float, wall_now: float, lsl_now: float) -> float:
    """LSL time of a marker created at Unix time ``marker_ts``.

    The marker is back-dated by its transit delay (client → bridge), measured on
    the wall clock of this machine. A delay outside ``[0, MAX_MARKER_DELAY]``
    (clocks of different machines, stale message) is not trusted: the marker then
    gets the reception time.
    """
    delay = wall_now - marker_ts
    if 0.0 <= delay <= MAX_MARKER_DELAY:
        return lsl_now - delay
    return lsl_now


# --- LSL outlet ------------------------------------------------------------------


class MarkerOutlet:
    """LSL markers stream ``openmind-markers`` published by the bridge."""

    def __init__(self) -> None:
        import pylsl

        self._pylsl = pylsl
        info = pylsl.StreamInfo(
            LSL_NAME, LSL_TYPE, 1, pylsl.IRREGULAR_RATE, pylsl.cf_string, LSL_SOURCE_ID
        )
        desc = info.desc()
        desc.append_child_value("spec_version", LSL_SPEC_VERSION)
        acquisition = desc.append_child("acquisition")
        acquisition.append_child_value("manufacturer", "OpenMind BCI")
        acquisition.append_child_value("model", "sandbox bridge")
        acquisition.append_child_value("driver", "bridge")
        self._outlet = pylsl.StreamOutlet(info)

    def push(self, marker: Marker) -> float:
        """Push ``marker`` and return its LSL timestamp."""
        stamp = lsl_timestamp(marker.ts, time.time(), self._pylsl.local_clock())
        self._outlet.push_sample([lsl_marker_sample(marker)], stamp)
        return stamp


# --- Bridge ----------------------------------------------------------------------


@dataclass
class BridgeStats:
    """Counters, for logs and tests."""

    relayed: int = 0
    rejected_mqtt: int = 0
    from_clients: int = 0
    rejected_clients: int = 0
    lsl_markers: int = 0


@dataclass
class Bridge:
    """MQTT ↔ WebSocket ↔ LSL gateway; run it with :meth:`run`.

    Args:
        mqtt_host: Broker host.
        mqtt_port: Broker port.
        ws_host: WebSocket listening address (``127.0.0.1``: this machine only).
        ws_port: WebSocket port; ``0`` picks a free one (see :attr:`ws_port`).
        lsl: Publish received markers on the LSL markers stream.
        eeg: Relay the LSL EEG stream ``openmind-eeg`` to the clients (read only).
    """

    mqtt_host: str = DEFAULT_HOST
    mqtt_port: int = DEFAULT_PORT
    ws_host: str = DEFAULT_WS_HOST
    ws_port: int = DEFAULT_WS_PORT
    lsl: bool = True
    eeg: bool = False
    stats: BridgeStats = field(default_factory=BridgeStats)
    _clients: set[ServerConnection] = field(default_factory=set, init=False, repr=False)
    _loop: asyncio.AbstractEventLoop | None = field(default=None, init=False, repr=False)
    _stop: asyncio.Event | None = field(default=None, init=False, repr=False)
    _link: MqttLink | None = field(default=None, init=False, repr=False)
    _outlet: MarkerOutlet | None = field(default=None, init=False, repr=False)

    async def run(self, on_ready: Callable[[], None] | None = None) -> None:
        """Connect to the broker, serve WebSocket clients until :meth:`stop`.

        Raises:
            BrokerUnavailableError: If the broker cannot be reached at start.
        """
        self._loop = asyncio.get_running_loop()
        self._stop = asyncio.Event()
        if self.lsl:
            self._outlet = MarkerOutlet()
        self._link = MqttLink(
            self.mqtt_host,
            self.mqtt_port,
            name="openmind-bridge",
            on_message=self._on_mqtt_message,
            on_connection_change=self._on_mqtt_connection,
        )
        self._link.subscribe([f"{topics.PREFIX}/#"])
        await asyncio.to_thread(self._link.connect)
        relay = None
        if self.eeg:
            from openmind_sandbox.eeg_relay import EegRelay

            relay = EegRelay(self._broadcast_threadsafe)
            relay.start()
        try:
            async with serve(self._handle_client, self.ws_host, self.ws_port) as server:
                self.ws_port = _bound_port(server, self.ws_port)
                log.info("WebSocket on ws://%s:%d", self.ws_host, self.ws_port)
                if on_ready is not None:
                    on_ready()
                await self._stop.wait()
        finally:
            if relay is not None:
                relay.stop()
            self._link.close()

    def stop(self) -> None:
        """Ask :meth:`run` to return; safe to call from any thread."""
        if self._loop is not None and self._stop is not None:
            self._loop.call_soon_threadsafe(self._stop.set)

    # -- MQTT side (network thread) ------------------------------------------------

    def _on_mqtt_message(self, topic: str, payload: bytes) -> None:
        try:
            message = decode_topic(topic, payload)
        except (KeyError, ProtocolError) as error:
            self.stats.rejected_mqtt += 1
            log.warning("Dropped MQTT message on %s: %s", topic, error)
            return
        self.stats.relayed += 1
        self._broadcast_threadsafe(envelope(topic, message))

    def _on_mqtt_connection(self, connected: bool) -> None:
        if not connected:
            log.warning("Lost the MQTT broker; reconnecting")
        self._broadcast_threadsafe(_frame(kind="bridge", mqtt_connected=connected))

    def _broadcast_threadsafe(self, frame: str) -> None:
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._broadcast, frame)

    def _broadcast(self, frame: str) -> None:
        broadcast(self._clients, frame)

    # -- WebSocket side ---------------------------------------------------------

    async def _handle_client(self, connection: ServerConnection) -> None:
        self._clients.add(connection)
        log.info("Client connected: %s", connection.remote_address)
        try:
            await connection.send(
                _frame(
                    kind="hello",
                    bridge=openmind_sandbox.__version__,
                    protocol=openmind_protocol.PROTOCOL_VERSION,
                    mqtt_connected=self._link is not None and self._link.connected,
                )
            )
            async for text in connection:
                reply = self._on_client_frame(text)
                if reply is not None:
                    await connection.send(reply)
        except ConnectionClosed:
            pass
        finally:
            self._clients.discard(connection)
            log.info("Client disconnected: %s", connection.remote_address)

    def _on_client_frame(self, text: str | bytes) -> str | None:
        try:
            message = parse_client_message(text)
        except ProtocolError as error:
            self.stats.rejected_clients += 1
            log.warning("Rejected client message: %s", error)
            return _frame(kind="error", error=str(error), problems=error.problems)
        assert self._link is not None
        if not self._link.connected:
            self.stats.rejected_clients += 1
            return _frame(kind="error", error="MQTT broker not connected", problems=[])
        self.stats.from_clients += 1
        self._link.publish(message)
        if isinstance(message, Marker) and self._outlet is not None:
            self._outlet.push(message)
            self.stats.lsl_markers += 1
        elif not isinstance(message, (Marker, Event)):  # pragma: no cover - guarded above
            raise AssertionError(message)
        return None


def _frame(**fields: Any) -> str:
    return json.dumps(fields, separators=(",", ":"), ensure_ascii=False)


def _bound_port(server: Server, requested: int) -> int:
    for sock in server.sockets:
        port: int = sock.getsockname()[1]
        return port
    return requested
