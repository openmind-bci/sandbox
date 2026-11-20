"""Thin MQTT link for protocol messages (paho-mqtt), validated in both directions.

Outgoing messages are encoded with :func:`openmind_protocol.encode`, which checks
them against the JSON Schema. Incoming payloads are handed over raw, with their
topic, so that each object decides how to react to an invalid message (objects
that move must stop).
"""

from __future__ import annotations

import threading
import uuid
from collections.abc import Callable, Iterable
from typing import Any

import paho.mqtt.client as mqtt
from openmind_protocol import Message, encode, topic_of
from paho.mqtt.enums import CallbackAPIVersion

#: QoS per message kind, as suggested by the protocol (markers and scores matter).
QOS: dict[str, int] = {"marker": 1, "score": 1}

DEFAULT_HOST = "localhost"
DEFAULT_PORT = 1883

MessageHandler = Callable[[str, bytes], None]


class BrokerUnavailableError(ConnectionError):
    """Raised when the MQTT broker cannot be reached."""


class MqttLink:
    """Connection to an MQTT broker that publishes and receives protocol messages.

    Args:
        host: Broker host name.
        port: Broker TCP port.
        name: Prefix of the client id (a random suffix keeps it unique).
        on_message: Called with ``(topic, payload)`` for every received message,
            from the network thread.
        on_connection_change: Called with ``True`` on connection and ``False`` on
            disconnection, from the network thread.
    """

    def __init__(
        self,
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
        name: str = "openmind-sandbox",
        on_message: MessageHandler | None = None,
        on_connection_change: Callable[[bool], None] | None = None,
    ) -> None:
        self.host = host
        self.port = port
        self._on_message = on_message
        self._on_connection_change = on_connection_change
        self._subscriptions: list[str] = []
        self._connected = threading.Event()
        self._client = mqtt.Client(
            callback_api_version=CallbackAPIVersion.VERSION2,
            client_id=f"{name}-{uuid.uuid4().hex[:8]}",
        )
        self._client.on_connect = self._handle_connect
        self._client.on_disconnect = self._handle_disconnect
        self._client.on_message = self._handle_message

    @property
    def connected(self) -> bool:
        """Whether the link is currently connected to the broker."""
        return self._connected.is_set()

    def connect(self, timeout: float = 5.0) -> None:
        """Connect and start the network thread; reconnects automatically afterwards.

        Raises:
            BrokerUnavailableError: If the broker does not accept the connection
                within ``timeout`` seconds.
        """
        try:
            self._client.connect(self.host, self.port, keepalive=10)
        except OSError as error:
            raise BrokerUnavailableError(self._unreachable(str(error))) from error
        self._client.loop_start()
        if not self._connected.wait(timeout):
            self.close()
            raise BrokerUnavailableError(self._unreachable("no answer"))

    def subscribe(self, topics: Iterable[str]) -> None:
        """Subscribe to ``topics``, now and after every reconnection."""
        for topic in topics:
            if topic not in self._subscriptions:
                self._subscriptions.append(topic)
                if self.connected:
                    self._client.subscribe(topic, qos=1)

    def publish(self, message: Message) -> None:
        """Publish a protocol message on its topic (validated against its schema)."""
        self._client.publish(topic_of(message), encode(message), qos=QOS.get(message.KIND, 0))

    def close(self) -> None:
        """Disconnect and stop the network thread."""
        self._client.disconnect()
        self._client.loop_stop()
        self._connected.clear()

    def __enter__(self) -> MqttLink:
        self.connect()
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _unreachable(self, reason: str) -> str:
        return (
            f"cannot reach the MQTT broker at {self.host}:{self.port} ({reason}). "
            "Start the development broker with "
            "`docker compose -f dev/docker-compose.yml up -d`."
        )

    def _handle_connect(
        self, client: mqtt.Client, userdata: Any, flags: Any, reason: Any, properties: Any
    ) -> None:
        if reason.is_failure:
            return
        for topic in self._subscriptions:
            client.subscribe(topic, qos=1)
        self._connected.set()
        if self._on_connection_change is not None:
            self._on_connection_change(True)

    def _handle_disconnect(
        self, client: mqtt.Client, userdata: Any, flags: Any, reason: Any, properties: Any
    ) -> None:
        self._connected.clear()
        if self._on_connection_change is not None:
            self._on_connection_change(False)

    def _handle_message(self, client: mqtt.Client, userdata: Any, msg: mqtt.MQTTMessage) -> None:
        if self._on_message is not None:
            self._on_message(msg.topic, bytes(msg.payload))
