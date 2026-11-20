"""Integration with a live broker (``pytest -m broker``)."""

from __future__ import annotations

import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest
from openmind_protocol import BandPower, Command, Message, Status, decode_topic, topics

from openmind_sandbox.mqtt import MqttLink

from .conftest import BROKER_HOST, BROKER_PORT

pytestmark = pytest.mark.broker


class Collector:
    def __init__(self) -> None:
        self.messages: list[Message] = []
        self.invalid: list[str] = []
        self._lock = threading.Lock()

    def __call__(self, topic: str, payload: bytes) -> None:
        try:
            message = decode_topic(topic, payload)
        except ValueError as error:
            with self._lock:
                self.invalid.append(str(error))
            return
        with self._lock:
            self.messages.append(message)


def subscribed_link(collector: Collector) -> MqttLink:
    link = MqttLink(BROKER_HOST, BROKER_PORT, name="test-sub", on_message=collector)
    link.subscribe([f"{topics.PREFIX}/#"])
    link.connect()
    time.sleep(0.2)  # let the subscription settle
    return link


def test_link_publishes_validated_messages() -> None:
    collector = Collector()
    sub = subscribed_link(collector)
    try:
        with MqttLink(BROKER_HOST, BROKER_PORT, name="test-pub") as pub:
            pub.publish(Command(command="left", confidence=0.8, user="P01", seq=1))
            time.sleep(0.3)
    finally:
        sub.close()
    assert any(isinstance(m, Command) and m.command == "left" for m in collector.messages)
    assert collector.invalid == []


def test_keys_script_publishes_a_live_decoder(tmp_path: Path) -> None:
    script = tmp_path / "script.yaml"
    script.write_text(
        "steps:\n"
        "  - {command: left, duration: 0.6}\n"
        "  - {command: action, duration: 0.3}\n"
        "  - {command: forward, duration: 0.6}\n"
    )
    collector = Collector()
    sub = subscribed_link(collector)
    try:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "openmind_sandbox.cli",
                "keys",
                "--host",
                BROKER_HOST,
                "--port",
                str(BROKER_PORT),
                "--script",
                str(script),
                "--bandpower",
                "--seed",
                "1",
            ],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        time.sleep(0.3)
    finally:
        sub.close()
    assert result.returncode == 0, result.stderr
    assert collector.invalid == []
    commands = [m for m in collector.messages if isinstance(m, Command)]
    assert {"left", "action", "forward", "rest"} <= {c.command for c in commands}
    assert [c.seq for c in commands] == sorted(c.seq for c in commands)
    assert sum(isinstance(m, Status) for m in collector.messages) >= 3
    assert sum(isinstance(m, BandPower) for m in collector.messages) >= 8
