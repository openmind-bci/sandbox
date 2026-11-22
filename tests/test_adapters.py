"""Acceptance of SBX-085: adapter base class, lamp example and template."""

from __future__ import annotations

import importlib.util
import threading
from collections.abc import Iterator
from pathlib import Path

import pytest
from openmind_protocol import Command, CommandName, Event, Message, Status, encode, topic_of, topics

from openmind_sandbox.adapters import Adapter
from openmind_sandbox.adapters.examples.fake_lamp import FakeLampServer
from openmind_sandbox.adapters.examples.lamp import LampAdapter


class Clock:
    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


class Recorder(Adapter):
    def __init__(self, clock: Clock, allow_action: bool = False) -> None:
        self.sent: list[Message] = []
        super().__init__("recorder", clock=clock, publish=self.sent.append)
        self.commands: list[tuple[str, float]] = []
        self.stops = 0
        self.allow_action = allow_action

    def on_command(self, command: str, confidence: float) -> None:
        self.commands.append((command, confidence))

    def stop(self) -> None:
        self.stops += 1

    def context_allows_action(self) -> bool:
        return self.allow_action


class Feeder:
    """Feeds an adapter like the broker would."""

    def __init__(self, adapter: Adapter, clock: Clock) -> None:
        self.adapter, self.clock, self.seq = adapter, clock, 0

    def status(self, state: str = "running") -> None:
        message = Status(state=state, model="test", user="P00")  # type: ignore[arg-type]
        self.adapter.handle_message(topic_of(message), encode(message))

    def command(self, name: CommandName, confidence: float = 0.95, seq: int | None = None) -> None:
        if seq is None:
            self.seq += 1
            seq = self.seq
        message = Command(command=name, confidence=confidence, user="P00", seq=seq)
        self.adapter.handle_message(topic_of(message), encode(message))


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def adapter(clock: Clock) -> Recorder:
    return Recorder(clock)


@pytest.fixture
def feed(adapter: Recorder, clock: Clock) -> Feeder:
    return Feeder(adapter, clock)


def test_no_command_before_first_status(adapter: Recorder, feed: Feeder) -> None:
    feed.command("forward")
    assert adapter.commands == []
    feed.status()
    feed.command("forward")
    assert adapter.commands == [("forward", 0.95)]


def test_stop_at_start_once(adapter: Recorder) -> None:
    adapter.tick()
    adapter.tick()
    assert adapter.stops == 1
    assert adapter.stopped


def test_stop_on_heartbeat_loss_once(adapter: Recorder, feed: Feeder, clock: Clock) -> None:
    feed.status()
    feed.command("forward")
    adapter.tick()
    assert adapter.stops == 0
    clock.now += 1.9
    adapter.tick()
    assert adapter.stops == 0
    clock.now += 0.2
    for _ in range(5):
        adapter.tick()
    assert adapter.stops == 1
    feed.command("left")  # silent decoder: refused
    assert len(adapter.commands) == 1
    feed.status()
    feed.command("left", seq=10)
    assert len(adapter.commands) == 2
    clock.now += 3
    adapter.tick()
    assert adapter.stops == 2


def test_stop_when_decoder_not_running(adapter: Recorder, feed: Feeder) -> None:
    feed.status()
    feed.command("forward")
    feed.status("calibrating")
    feed.status("calibrating")
    assert adapter.stops == 1
    feed.command("forward")
    assert len(adapter.commands) == 1


def test_low_confidence_refused_but_rest_accepted(adapter: Recorder, feed: Feeder) -> None:
    feed.status()
    feed.command("forward", 0.5)
    assert adapter.commands == []
    feed.command("rest", 0.1)
    assert adapter.commands == [("rest", 0.1)]


def test_old_seq_refused(adapter: Recorder, feed: Feeder) -> None:
    feed.status()
    feed.command("forward", seq=5)
    feed.command("left", seq=5)
    feed.command("left", seq=4)
    feed.command("right", seq=6)
    assert [c for c, _ in adapter.commands] == ["forward", "right"]


def test_action_needs_context(adapter: Recorder, feed: Feeder) -> None:
    feed.status()
    feed.command("action")
    assert adapter.commands == []
    adapter.allow_action = True
    feed.command("action")
    assert adapter.commands == [("action", 0.95)]


def test_invalid_payload_ignored(adapter: Recorder, feed: Feeder) -> None:
    feed.status()
    adapter.handle_message(topics.COMMANDS, b"not json")
    adapter.handle_message(topics.COMMANDS, b'{"v":1,"command":"fly"}')
    adapter.handle_message("other/topic", b"{}")
    assert adapter.commands == []
    feed.command("forward")
    assert len(adapter.commands) == 1


def test_failing_hook_stops_object(clock: Clock) -> None:
    class Broken(Recorder):
        def on_command(self, command: str, confidence: float) -> None:
            raise RuntimeError("boom")

    broken = Broken(clock)
    feeder = Feeder(broken, clock)
    feeder.status()
    feeder.command("forward")
    assert broken.stops == 1


def test_events_published(adapter: Recorder) -> None:
    adapter.emit_event("state", {"on": True})
    (event,) = adapter.sent
    assert isinstance(event, Event)
    assert (event.object, event.kind, event.data) == ("recorder", "state", {"on": True})


# --- lamp ---------------------------------------------------------------------------


@pytest.fixture
def lamp_server() -> Iterator[FakeLampServer]:
    server = FakeLampServer(port=0)
    server.quiet = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield server
    server.shutdown()
    server.server_close()


def test_lamp_toggle_and_dim(lamp_server: FakeLampServer, clock: Clock) -> None:
    sent: list[Message] = []
    lamp = LampAdapter(f"http://127.0.0.1:{lamp_server.port}", clock=clock, publish=sent.append)
    feeder = Feeder(lamp, clock)
    feeder.status()
    feeder.command("action")
    assert lamp_server.light["on"] is True
    feeder.command("left")
    assert lamp_server.light["brightness"] == 40
    feeder.command("right")
    feeder.command("right")
    assert lamp_server.light["brightness"] == 60
    feeder.command("rest")
    feeder.command("forward")
    assert lamp_server.light == {"on": True, "brightness": 60}
    feeder.command("action")
    assert lamp_server.light["on"] is False
    assert len(sent) == 5
    lamp.stop()
    assert lamp_server.light == {"on": False, "brightness": 60}


def test_lamp_unreachable_is_not_fatal(clock: Clock) -> None:
    lamp = LampAdapter("http://127.0.0.1:9", clock=clock)  # nothing listens on port 9
    feeder = Feeder(lamp, clock)
    feeder.status()
    feeder.command("action")  # logged, not raised


# --- template -----------------------------------------------------------------------


def test_template_adapter_works_unchanged(clock: Clock, capsys: pytest.CaptureFixture[str]) -> None:
    path = Path(__file__).parents[1] / "template" / "adapter" / "my_object.py"
    spec = importlib.util.spec_from_file_location("my_object_template", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    obj = module.MyObject()
    assert isinstance(obj, Adapter)
    obj._clock = clock
    obj._watchdog._clock = clock
    feeder = Feeder(obj, clock)
    feeder.command("forward")  # no status yet
    feeder.status()
    feeder.command("forward", 0.9)
    feeder.command("left", 0.3)  # below the template threshold
    clock.now += 3
    obj.tick()
    out = capsys.readouterr().out
    assert "forward (0.90)" in out
    assert "left" not in out
    assert out.strip().endswith("stop")
