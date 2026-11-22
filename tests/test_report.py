"""Course report from a synthetic events log, and the bridge log file."""

from __future__ import annotations

import json
from pathlib import Path

from openmind_protocol import Command, Event, Marker
from typer.testing import CliRunner

from openmind_sandbox.bridge import Bridge, JsonlLog
from openmind_sandbox.cli import app
from openmind_sandbox.report import build_report, format_report

runner = CliRunner()


def _event(ts: float, obj: str, kind: str, data: dict[str, object]) -> str:
    message = {"v": 1, "ts": ts, "object": obj, "kind": kind, "data": data}
    return json.dumps({"topic": "openmind/v1/events", "kind": "event", "message": message})


def _command(ts: float, name: str) -> str:
    message = {"v": 1, "ts": ts, "command": name, "confidence": 0.9, "user": "P00", "seq": 1}
    return json.dumps({"topic": "openmind/v1/commands", "kind": "command", "message": message})


def _telemetry(ts: float, obj: str, state: str, reason: str | None, speed: float) -> str:
    return _event(ts, obj, "telemetry", {"state": state, "reason": reason, "speed_mps": speed})


def _state(ts: float, obj: str, state: str, reason: str | None) -> str:
    return _event(ts, obj, "state", {"state": state, "reason": reason})


def twin_log() -> list[str]:
    twin = "robot-twin"
    return [
        _state(0.0, twin, "SAFETY_STOP", "no_status"),
        _command(0.5, "forward"),  # before the run: not counted
        _event(1.0, twin, "start", {"course": "twin_default"}),
        _state(1.0, twin, "MOVING", None),
        _command(1.2, "forward"),
        _telemetry(1.4, twin, "MOVING", None, 0.2),
        _state(2.0, twin, "SAFETY_STOP", "obstacle"),
        _telemetry(2.2, twin, "SAFETY_STOP", "obstacle", 0.0),
        _command(2.5, "left"),
        _command(2.6, "left"),
        _event(3.0, twin, "waypoint", {"course": "twin_default", "index": 0, "time_s": 2.0}),
        _state(3.5, twin, "SAFETY_STOP", "no_status"),
        _state(4.0, twin, "MOVING", None),
        _telemetry(4.2, twin, "MOVING", None, 0.1),
        _event(5.0, twin, "waypoint", {"course": "twin_default", "index": 1, "time_s": 4.0}),
        _event(
            5.5,
            twin,
            "finish",
            {"course": "twin_default", "time_s": 4.5, "errors": 2, "collisions_avoided": 1},
        ),
        _command(6.0, "rest"),  # after the run: not counted
    ]


def test_twin_run_is_summarised() -> None:
    report = build_report(twin_log())
    assert report.skipped_lines == 0
    [run] = report.runs
    assert (run.object, run.course, run.finished) == ("robot-twin", "twin_default", True)
    assert run.duration_s == 4.5
    assert run.waypoints_reached == 2
    assert (run.errors, run.collisions_avoided) == (2, 1)
    assert run.obstacle_stops == 1
    assert run.safety_stops == {"no_status": 1}
    assert run.commands == {"forward": 1, "left": 2}
    assert run.average_speed_mps == 0.1
    assert run.average_moving_speed_mps == 0.15
    assert "finished" in format_report(report)


def test_new_start_closes_the_previous_run_as_unfinished() -> None:
    lines = [
        _event(1.0, "robot-twin", "start", {"course": "c"}),
        _event(2.0, "robot-twin", "waypoint", {"course": "c", "index": 0, "time_s": 1.0}),
        _event(5.0, "robot-twin", "start", {"course": "c"}),
        _event(6.0, "robot-twin", "waypoint", {"course": "c", "index": 0, "time_s": 1.0}),
    ]
    first, second = build_report(lines).runs
    assert (first.finished, first.duration_s, first.waypoints_reached) == (False, 1.0, 1)
    assert (second.finished, second.duration_s, second.start_ts) == (False, 1.0, 5.0)
    assert first.errors is None


def test_real_robot_telemetry_only_gives_one_session() -> None:
    robot = "robot"
    lines = [
        _telemetry(0.0, robot, "SAFETY_STOP", "no_status", 0.0),
        _command(0.5, "forward"),
        _telemetry(1.0, robot, "MOVING", None, 0.1),
        _telemetry(2.0, robot, "MOVING", None, 0.2),
        _telemetry(3.0, robot, "SAFETY_STOP", "obstacle", 0.0),
        _telemetry(4.0, robot, "SAFETY_STOP", "decoder_stopped", 0.0),
        _telemetry(5.0, robot, "SAFETY_STOP", "decoder_stopped", 0.0),
        _command(4.5, "rest"),
    ]
    [run] = build_report(lines).runs
    assert (run.object, run.course, run.finished) == ("robot", None, False)
    assert run.duration_s == 4.0  # first movement to last event
    assert run.obstacle_stops == 1
    assert run.safety_stops == {"decoder_stopped": 1}
    assert run.commands == {"rest": 1}
    assert run.waypoints_reached == 0
    assert run.errors is None
    assert run.average_speed_mps == 0.06


def test_bad_lines_are_skipped_and_empty_log_is_reported() -> None:
    report = build_report(["not json", "[1]", '{"message": {"ts": "x"}}', ""])
    assert report.runs == [] and report.skipped_lines == 3
    assert "No run found" in format_report(report)


def test_bare_messages_are_accepted() -> None:
    event = {"v": 1, "ts": 1.0, "object": "boat", "kind": "start", "data": {"course": "sea"}}
    [run] = build_report([json.dumps(event)]).runs
    assert (run.object, run.course) == ("boat", "sea")


def test_cli_report_text_and_json(tmp_path: Path) -> None:
    path = tmp_path / "events.jsonl"
    path.write_text("\n".join(twin_log()) + "\n", encoding="utf-8")
    text = runner.invoke(app, ["report", str(path)])
    assert text.exit_code == 0
    assert "Run 1: robot-twin, course twin_default (finished)" in text.output
    as_json = runner.invoke(app, ["report", str(path), "--json"])
    data = json.loads(as_json.output)
    assert data["runs"][0]["waypoints_reached"] == 2


def test_cli_report_missing_file(tmp_path: Path) -> None:
    result = runner.invoke(app, ["report", str(tmp_path / "missing.jsonl")])
    assert result.exit_code != 0


def test_jsonl_log_skips_band_power_and_appends(tmp_path: Path) -> None:
    path = tmp_path / "log.jsonl"
    log = JsonlLog(path)
    log.append("openmind/v1/events", Event(object="robot", kind="telemetry", data={"x": 1}, ts=1.0))
    log.append("openmind/v1/bandpower", Event(object="x", kind="y", data={}))
    log.close()
    JsonlLog(path).close()
    lines = path.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0])["message"]["object"] == "robot"
    assert json.loads(lines[0])["received"] > 1e9


def test_received_time_is_preferred_to_message_ts() -> None:
    def line(received: float, state: str) -> str:
        data = {"state": state, "reason": None, "speed_mps": 0.1 if state == "MOVING" else 0.0}
        message = {"v": 1, "ts": 0.0, "object": "robot", "kind": "telemetry", "data": data}
        frame = {"topic": "openmind/v1/events", "message": message, "received": received}
        return json.dumps(frame)

    [run] = build_report([line(100.0, "MOVING"), line(103.0, "STOPPED")]).runs
    assert run.duration_s == 3.0


def test_bridge_logs_what_it_receives(tmp_path: Path) -> None:
    path = tmp_path / "bridge.jsonl"
    bridge = Bridge(log_path=path)
    bridge._log = JsonlLog(path)
    command = Command(command="left", confidence=0.9, user="P01", seq=1, ts=2.0)
    marker = Marker(type="cue", label="left", trial=1, scene="bird", ts=3.0)
    bridge._on_mqtt_message("openmind/v1/commands", command.model_dump_json().encode())
    bridge._on_mqtt_message("openmind/v1/markers", marker.model_dump_json().encode())
    bridge._on_mqtt_message("openmind/v1/commands", b"not json")  # rejected: not logged
    bridge._log.close()
    topics_logged = [json.loads(x)["topic"] for x in path.read_text().splitlines()]
    assert topics_logged == ["openmind/v1/commands", "openmind/v1/markers"]
    [run_lines] = [path.read_text().splitlines()]
    assert build_report(run_lines).runs == []
