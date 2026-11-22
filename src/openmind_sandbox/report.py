"""Course report built from a log of protocol messages (JSON lines).

The log is written by ``openmind-sandbox bridge --log FILE`` (see
:class:`openmind_sandbox.bridge.JsonlLog`) and holds the
messages seen on ``openmind/v1/``, one JSON object per line::

    {"topic":"openmind/v1/events","kind":"event","message":{"v":1,"ts":...,"object":"robot-twin",...}}

The bridge adds ``received`` (its own wall-clock time), preferred to the ``ts`` of the
message because the real robot may have no clock (``ts`` 0) before NTP sync.
A bare protocol message per line (a command or an event without the
``topic``/``kind`` wrapper) is accepted too. The twin (Godot), the mock robot and
the real robot publish the same events, so one report serves them all:

- an object that sends ``start`` / ``waypoint`` / ``finish`` events (the twin, the
  wheelchair, the boat) gets one run per ``start``; a run ends at ``finish``, at
  the next ``start`` or at the last event of the log (``finished`` is then false);
- an object without such events (the mock robot, the real robot) gets a single
  ``session`` run, from its first movement to its last event, without waypoints.

States and safety stops are read from ``state`` events and from the ``state`` /
``reason`` fields of ``telemetry`` events, so a robot that only sends telemetry
is counted too.
"""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Final

_MOVING_STATES: Final = frozenset({"MOVING", "PIVOTING"})


@dataclass
class RunReport:
    """Figures of one run of one object."""

    object: str
    course: str | None
    start_ts: float
    end_ts: float
    finished: bool
    duration_s: float
    waypoints_reached: int = 0
    errors: int | None = None
    collisions_avoided: int | None = None
    obstacle_stops: int = 0
    safety_stops: dict[str, int] = field(default_factory=dict)
    commands: dict[str, int] = field(default_factory=dict)
    average_speed_mps: float | None = None
    average_moving_speed_mps: float | None = None
    telemetry_samples: int = 0


@dataclass
class Report:
    """All runs of a log, in order of start."""

    runs: list[RunReport]
    skipped_lines: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {"runs": [asdict(run) for run in self.runs], "skipped_lines": self.skipped_lines}


@dataclass
class _Entry:
    ts: float
    topic: str  # "event" or "command"
    object: str = ""
    kind: str = ""
    data: dict[str, Any] = field(default_factory=dict)


@dataclass
class _Run:
    report: RunReport
    speeds: list[float] = field(default_factory=list)


def parse_log(lines: list[str]) -> tuple[list[_Entry], int]:
    """Events and commands of ``lines``, sorted by time, and the count of skipped lines."""
    entries: list[_Entry] = []
    skipped = 0
    for line in lines:
        if not line.strip():
            continue
        entry = _parse_line(line)
        if entry is None:
            skipped += 1
        else:
            entries.append(entry)
    entries.sort(key=lambda entry: entry.ts)  # stable: ties keep the log order
    return entries, skipped


def _parse_line(line: str) -> _Entry | None:
    try:
        raw = json.loads(line)
    except ValueError:
        return None
    if not isinstance(raw, dict):
        return None
    inner = raw.get("message")
    message: dict[str, Any] = inner if isinstance(inner, dict) else raw
    ts = raw.get("received") if "received" in raw else message.get("ts")
    if not isinstance(ts, (int, float)) or isinstance(ts, bool):
        return None
    if isinstance(message.get("command"), str):
        return _Entry(float(ts), "command", kind=message["command"])
    data = message.get("data")
    if isinstance(message.get("object"), str) and isinstance(message.get("kind"), str):
        return _Entry(
            float(ts),
            "event",
            object=message["object"],
            kind=message["kind"],
            data=data if isinstance(data, dict) else {},
        )
    return None  # status, markers, scores...


def build_report(lines: list[str]) -> Report:
    """Compute the runs of a log given as JSON lines."""
    entries, skipped = parse_log(lines)
    explicit = {e.object for e in entries if e.topic == "event" and e.kind == "start"}
    runs: list[_Run] = []
    current: dict[str, _Run | None] = {}
    last_state: dict[str, tuple[Any, Any]] = {}

    for entry in entries:
        if entry.topic != "event":
            continue
        obj = entry.object
        transition = _transition(entry, last_state)
        run = current.get(obj)
        if entry.kind == "start":
            if run is not None:
                _close(run, run.report.end_ts, finished=False)
            run = _Run(
                RunReport(obj, _str(entry.data.get("course")), entry.ts, entry.ts, False, 0.0)
            )
            runs.append(run)
            current[obj] = run
        elif run is None and obj not in explicit and _is_moving(entry, transition):
            run = _Run(RunReport(obj, None, entry.ts, entry.ts, False, 0.0))
            runs.append(run)
            current[obj] = run
        if run is None:
            continue
        report = run.report
        report.end_ts = entry.ts
        if transition is not None:
            _count_stop(report, transition)
        if entry.kind == "waypoint":
            report.waypoints_reached += 1
        elif entry.kind == "telemetry":
            speed = entry.data.get("speed_mps")
            if isinstance(speed, (int, float)):
                run.speeds.append(float(speed))
        elif entry.kind == "finish":
            report.errors = _int(entry.data.get("errors"))
            report.collisions_avoided = _int(entry.data.get("collisions_avoided"))
            _close(run, entry.ts, finished=True, time_s=entry.data.get("time_s"))
            current[obj] = None

    for run in runs:
        _finish(run)
        report = run.report
        counter = Counter(
            e.kind
            for e in entries
            if e.topic == "command" and report.start_ts <= e.ts <= report.end_ts
        )
        report.commands = dict(sorted(counter.items()))
    runs.sort(key=lambda run: run.report.start_ts)
    return Report([run.report for run in runs], skipped)


def load_report(path: Path) -> Report:
    """Read ``path`` (JSON lines) and build its report."""
    return build_report(path.read_text(encoding="utf-8").splitlines())


def _transition(entry: _Entry, last: dict[str, tuple[Any, Any]]) -> tuple[Any, Any] | None:
    """New ``(state, reason)`` of the object when this entry changes it."""
    if entry.kind not in ("state", "telemetry") or "state" not in entry.data:
        return None
    current = (entry.data["state"], entry.data.get("reason"))
    if last.get(entry.object) == current:
        return None
    last[entry.object] = current
    return current


def _is_moving(entry: _Entry, transition: tuple[Any, Any] | None) -> bool:
    if transition is not None and transition[0] in _MOVING_STATES:
        return True
    speed = entry.data.get("speed_mps")
    return entry.kind == "telemetry" and isinstance(speed, (int, float)) and speed > 0


def _count_stop(report: RunReport, transition: tuple[Any, Any]) -> None:
    state, reason = transition
    if state != "SAFETY_STOP" or not isinstance(reason, str):
        return
    if reason == "obstacle":
        report.obstacle_stops += 1
    else:
        report.safety_stops[reason] = report.safety_stops.get(reason, 0) + 1


def _close(run: _Run, end_ts: float, finished: bool, time_s: object = None) -> None:
    report = run.report
    report.end_ts = end_ts
    report.finished = finished
    if isinstance(time_s, (int, float)) and not isinstance(time_s, bool):
        report.duration_s = float(time_s)


def _finish(run: _Run) -> None:
    report = run.report
    if not (report.finished and report.duration_s > 0):
        report.duration_s = report.end_ts - report.start_ts
    report.duration_s = round(report.duration_s, 3)
    report.telemetry_samples = len(run.speeds)
    if run.speeds:
        report.average_speed_mps = round(sum(run.speeds) / len(run.speeds), 4)
        moving = [s for s in run.speeds if s > 0]
        if moving:
            report.average_moving_speed_mps = round(sum(moving) / len(moving), 4)
    report.safety_stops = dict(sorted(report.safety_stops.items()))


def _int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _str(value: object) -> str | None:
    return value if isinstance(value, str) else None


def format_report(report: Report) -> str:
    """Human-readable text of ``report``."""
    if not report.runs:
        text = "No run found in the log (no movement, no start event)."
    else:
        blocks = [_format_run(i, run) for i, run in enumerate(report.runs, start=1)]
        text = "\n\n".join(blocks)
    if report.skipped_lines:
        text += f"\n\n{report.skipped_lines} line(s) skipped (not JSON or not a message)."
    return text


def _format_run(number: int, run: RunReport) -> str:
    status = "finished" if run.finished else "not finished"
    title = f"Run {number}: {run.object}" + (f", course {run.course}" if run.course else "")
    stops = ", ".join(f"{reason} {n}" for reason, n in run.safety_stops.items()) or "none"
    commands = ", ".join(f"{name} {n}" for name, n in run.commands.items()) or "none"
    lines = [
        f"{title} ({status})",
        f"  duration            {run.duration_s:.1f} s",
        f"  waypoints reached   {run.waypoints_reached}",
        f"  errors              {_show(run.errors)}",
        f"  collisions avoided  {_show(run.collisions_avoided)}",
        f"  obstacle stops      {run.obstacle_stops}",
        f"  safety stops        {stops}",
        f"  commands            {commands}",
        f"  average speed       {_speed(run.average_speed_mps)}"
        f" (while moving {_speed(run.average_moving_speed_mps)})",
    ]
    return "\n".join(lines)


def _show(value: int | None) -> str:
    return "n/a" if value is None else str(value)


def _speed(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.3f} m/s"
