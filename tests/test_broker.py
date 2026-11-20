"""Integration with a live broker (``pytest -m broker``)."""

from __future__ import annotations

import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest
from openmind_protocol import BandPower, Command, Event, Message, Status, decode_topic, topics

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


def test_mock_robot_moves_on_commands_and_stops_without_status() -> None:
    collector = Collector()
    sub = subscribed_link(collector)
    robot = subprocess.Popen(
        [sys.executable, "-m", "openmind_sandbox.cli", "mock-robot", "--quiet",
         "--host", BROKER_HOST, "--port", str(BROKER_PORT)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )  # fmt: skip
    try:
        time.sleep(1.5)
        with MqttLink(BROKER_HOST, BROKER_PORT, name="test-decoder") as decoder:
            for seq in range(6):
                decoder.publish(Status(state="running", model="test", user="P00"))
                decoder.publish(Command(command="forward", confidence=0.95, user="P00", seq=seq))
                time.sleep(0.25)
        time.sleep(2.6)  # decoder silent for longer than status_timeout_s
    finally:
        robot.terminate()
        robot.wait(timeout=5)
        sub.close()
    states = [
        (m.data["state"], m.data["reason"])
        for m in collector.messages
        if isinstance(m, Event) and m.object == "mock-robot" and m.kind == "state"
    ]
    assert ("MOVING", None) in states
    assert states[-1] == ("SAFETY_STOP", "no_status")
    telemetry = [m for m in collector.messages if isinstance(m, Event) and m.kind == "telemetry"]
    assert max(m.data["speed_mps"] for m in telemetry) > 0


def test_bridge_relays_mqtt_to_websocket_and_markers_to_mqtt_and_lsl() -> None:
    import asyncio
    import json

    import pylsl
    from websockets.sync.client import connect

    from openmind_sandbox.bridge import LSL_SOURCE_ID, Bridge

    gateway = Bridge(BROKER_HOST, BROKER_PORT, ws_port=0)
    ready = threading.Event()
    thread = threading.Thread(
        target=lambda: asyncio.run(gateway.run(on_ready=ready.set)), daemon=True
    )
    thread.start()
    assert ready.wait(10)
    collector = Collector()
    sub = subscribed_link(collector)
    inlet = None
    try:
        streams = pylsl.resolve_byprop("source_id", LSL_SOURCE_ID, 1, 5.0)
        assert streams, "LSL markers stream of the bridge not found"
        inlet = pylsl.StreamInlet(streams[0])
        inlet.open_stream(5.0)
        with connect(f"ws://127.0.0.1:{gateway.ws_port}") as ws:
            hello = json.loads(ws.recv(timeout=5))
            assert hello["kind"] == "hello"
            assert hello["mqtt_connected"] is True

            # MQTT -> WebSocket, with an invalid message dropped on the way.
            with MqttLink(BROKER_HOST, BROKER_PORT, name="test-decoder") as decoder:
                decoder._client.publish(topics.COMMANDS, b'{"v":1,"command":"jump"}')
                decoder.publish(Command(command="right", confidence=0.9, user="P02", seq=7))
                frame = json.loads(ws.recv(timeout=5))
            assert frame["topic"] == topics.COMMANDS
            assert frame["message"]["command"] == "right"

            # WebSocket -> MQTT + LSL.
            sent_at = pylsl.local_clock()
            ws.send(json.dumps({"kind": "marker", "message": {
                "type": "cue", "label": "left", "trial": 1, "scene": "test"}}))  # fmt: skip
            sample, stamp = inlet.pull_sample(timeout=5.0)
            assert sample is not None
            assert json.loads(sample[0])["label"] == "left"
            assert abs(stamp - sent_at) < 0.5

            # Rejected client message gets an error reply.
            ws.send(json.dumps({"kind": "command", "message": {}}))
            while True:
                reply = json.loads(ws.recv(timeout=5))
                if reply["kind"] == "error":
                    break
            assert "not accepted" in reply["error"]
        time.sleep(0.3)
    finally:
        if inlet is not None:
            inlet.close_stream()
        sub.close()
        gateway.stop()
        thread.join(5)
    markers = [m for m in collector.messages if m.KIND == "marker"]
    assert [m.label for m in markers] == ["left"]  # type: ignore[attr-defined]
    assert gateway.stats.rejected_mqtt >= 1
    assert gateway.stats.lsl_markers == 1
