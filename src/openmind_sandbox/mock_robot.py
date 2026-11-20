"""Mock robot: 2D kinematics and the same safety rules as the ESP32 firmware.

The robot is a differential-drive vehicle with a forward distance sensor, in a
rectangular arena with round obstacles. Commands map to motion as follows:

========== ==================================================================
``left``   pivot in place, counter-clockwise, at ``pivot_speed_dps``
``right``  pivot in place, clockwise
``forward`` move forward, speeding up by ``acceleration_mps2`` up to ``max_speed_mps``
``rest``   stop
``action`` U-turn (``uturn_deg``), then stop
========== ==================================================================

A command stays in force until the next accepted one. A U-turn is a short
maneuver: the ``rest`` that follows ``action`` does not cut it, but a movement
command or any safety stop does. Safety, applied before any
motion (see ``docs/protocol.md`` of OpenMind Core, section 4):

1. no ``running`` status for ``status_timeout_s`` (or none yet): stop
   (``SAFETY_STOP``, reason ``no_status``); a non-running status stops at once;
2. command below ``min_confidence``: stop (``STOPPED``, ``low_confidence``);
3. stale ``seq``: ignored;
4. invalid message or broker disconnection: stop (``SAFETY_STOP``) until the next
   valid ``running`` status;
5. obstacle closer than ``obstacle_stop_m`` ahead: no forward motion
   (``SAFETY_STOP``, ``obstacle``); pivoting away stays possible;
6. speed bounded by ``max_speed_mps``.

The simulation takes time from an injectable clock, so the tests run instantly.
"""

from __future__ import annotations

import math
import threading
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Final

from openmind_protocol import Command, CommandName, Event, Status, Watchdog

from openmind_sandbox.config import RobotConfig

#: ``object`` field of the events published by the mock robot.
OBJECT_NAME: Final = "mock-robot"


class RobotState(StrEnum):
    """States of the robot, identical to the firmware state machine."""

    STOPPED = "STOPPED"
    MOVING = "MOVING"
    PIVOTING = "PIVOTING"
    SAFETY_STOP = "SAFETY_STOP"


# --- World ---------------------------------------------------------------------


@dataclass(frozen=True)
class Obstacle:
    """Round obstacle (a post, a box seen from above), in metres."""

    x: float
    y: float
    radius: float


@dataclass(frozen=True)
class World:
    """Rectangular arena ``[0, width] x [0, height]`` with obstacles, in metres."""

    width: float = 3.0
    height: float = 3.0
    obstacles: Sequence[Obstacle] = (Obstacle(1.5, 2.2, 0.15),)

    def distance_ahead(self, x: float, y: float, heading: float) -> float:
        """Distance from ``(x, y)`` to the first wall or obstacle along ``heading``."""
        dx, dy = math.cos(heading), math.sin(heading)
        hits: list[float] = []
        if dx > 1e-12:
            hits.append((self.width - x) / dx)
        elif dx < -1e-12:
            hits.append(-x / dx)
        if dy > 1e-12:
            hits.append((self.height - y) / dy)
        elif dy < -1e-12:
            hits.append(-y / dy)
        for obstacle in self.obstacles:
            # Ray-circle intersection: |p + t d - c| = r, smallest t >= 0.
            ox, oy = x - obstacle.x, y - obstacle.y
            b = ox * dx + oy * dy
            c = ox * ox + oy * oy - obstacle.radius**2
            disc = b * b - c
            if disc < 0:
                continue
            root = math.sqrt(disc)
            for t in (-b - root, -b + root):
                if t >= 0:
                    hits.append(t)
                    break
        return max(0.0, min(hits)) if hits else math.inf


# --- Robot ---------------------------------------------------------------------


@dataclass
class Pose:
    """Position (m) and heading (rad, 0 = +x, counter-clockwise positive)."""

    x: float = 1.5
    y: float = 0.5
    heading: float = math.pi / 2


@dataclass
class MockRobot:
    """Simulated robot driven by protocol messages.

    Thread-safe: messages may arrive from the MQTT thread while :meth:`step` runs
    in the main loop.

    Args:
        config: Content of ``robot.yaml``.
        world: Arena and obstacles.
        pose: Starting pose.
        clock: Monotonic time source, shared with the watchdog.
    """

    config: RobotConfig
    world: World = field(default_factory=World)
    pose: Pose = field(default_factory=Pose)
    clock: Callable[[], float] = time.monotonic
    state: RobotState = field(init=False, default=RobotState.SAFETY_STOP)
    reason: str | None = field(init=False, default="no_status")
    command: CommandName = field(init=False, default="rest")
    speed: float = field(init=False, default=0.0)
    turn_rate: float = field(init=False, default=0.0)
    obstacle: float | None = field(init=False, default=None)
    _watchdog: Watchdog = field(init=False, repr=False)
    _fault: str | None = field(init=False, default=None, repr=False)
    _command_reason: str | None = field(init=False, default=None, repr=False)
    _uturn_left: float = field(init=False, default=0.0, repr=False)
    _was_alive: bool = field(init=False, default=False, repr=False)
    _last_state: str | None = field(init=False, default=None, repr=False)
    _last_step: float | None = field(init=False, default=None, repr=False)
    _lock: threading.Lock = field(init=False, default_factory=threading.Lock, repr=False)
    _transitions: list[tuple[RobotState, str | None]] = field(
        init=False, default_factory=list, repr=False
    )

    def __post_init__(self) -> None:
        safety = self.config.safety
        self._watchdog = Watchdog(
            min_confidence=safety.min_confidence,
            timeout=safety.status_timeout_s,
            clock=self.clock,
        )
        self.obstacle = self._measure()

    # -- inputs ------------------------------------------------------------------

    def on_status(self, status: Status) -> None:
        """Record a decoder heartbeat."""
        with self._lock:
            if not self._watchdog.alive:
                # The decoder was silent (or restarted): its seq starts over.
                self._watchdog.reset_sequence()
            self._watchdog.on_status(status)
            self._last_state = status.state
            if status.state == "running":
                self._fault = None
            else:
                self._stop_command()

    def on_command(self, command: Command) -> None:
        """Apply a decoded command if the safety rules allow it."""
        with self._lock:
            if not self._watchdog.alive or self._fault is not None:
                return
            if command.confidence < self.config.safety.min_confidence:
                self._stop_command()
                self._command_reason = "low_confidence"
                return
            if not self._watchdog.accept(command):
                return  # stale or duplicate seq
            if command.command == "action":
                if self.command != "action":
                    self._uturn_left = math.radians(self.config.motion.uturn_deg)
            elif command.command == "rest" and self.command == "action":
                return  # a U-turn completes; only a movement command or safety ends it
            self.command = command.command
            self._command_reason = None

    def on_fault(self, reason: str) -> None:
        """Fail safe: stop on an invalid message or a lost broker connection."""
        with self._lock:
            self._fault = reason
            self._stop_command()

    # -- simulation --------------------------------------------------------------

    def step(self) -> None:
        """Advance the simulation to the current time of the clock."""
        with self._lock:
            now = self.clock()
            dt = 0.0 if self._last_step is None else max(0.0, now - self._last_step)
            self._last_step = now
            self._update(dt)

    def _update(self, dt: float) -> None:
        motion = self.config.motion
        self.obstacle = self._measure()
        blocked = self.obstacle is not None and self.obstacle < self.config.safety.obstacle_stop_m

        safety_reason = self._safety_reason()
        if safety_reason is not None:
            self._stop_command()
            self._set(RobotState.SAFETY_STOP, safety_reason)
            return

        pivot = math.radians(motion.pivot_speed_dps)
        if self.command == "forward":
            self.turn_rate = 0.0
            if blocked:
                self.speed = 0.0
                self._set(RobotState.SAFETY_STOP, "obstacle")
                return
            self.speed = min(motion.max_speed_mps, self.speed + motion.acceleration_mps2 * dt)
            self._set(RobotState.MOVING, None)
        elif self.command in ("left", "right"):
            self.speed = 0.0
            self.turn_rate = pivot if self.command == "left" else -pivot
            self._set(RobotState.PIVOTING, None)
        elif self.command == "action":
            self.speed = 0.0
            turn = min(self._uturn_left, pivot * dt)
            self._uturn_left -= turn
            self.turn_rate = pivot
            self.pose.heading = _wrap(self.pose.heading + turn)
            if self._uturn_left <= 1e-9:
                self._stop_command()
                self._set(RobotState.STOPPED, None)
            else:
                self._set(RobotState.PIVOTING, None)
            self.obstacle = self._measure()
            return
        else:
            self.speed = 0.0
            self.turn_rate = 0.0
            self._set(RobotState.STOPPED, self._command_reason)

        self.pose.heading = _wrap(self.pose.heading + self.turn_rate * dt)
        distance = self.speed * dt
        if distance > 0:
            # Never move past the stop distance within one step.
            ahead = math.inf if self.obstacle is None else self.obstacle
            room = ahead - self.config.safety.obstacle_stop_m
            distance = max(0.0, min(distance, room))
            self.pose.x += distance * math.cos(self.pose.heading)
            self.pose.y += distance * math.sin(self.pose.heading)
        self.obstacle = self._measure()

    def _safety_reason(self) -> str | None:
        if self._fault is not None:
            return self._fault
        if self._last_state is not None and self._last_state != "running":
            return f"decoder_{self._last_state}"
        if not self._watchdog.alive:
            return "no_status"
        return None

    def _stop_command(self) -> None:
        self.command = "rest"
        self.speed = 0.0
        self.turn_rate = 0.0
        self._uturn_left = 0.0

    def _set(self, state: RobotState, reason: str | None) -> None:
        if (state, reason) != (self.state, self.reason):
            self._transitions.append((state, reason))
        self.state = state
        self.reason = reason

    def _measure(self) -> float | None:
        """Simulated HC-SR04: distance from the front of the body, ``None`` out of range."""
        front = self.config.geometry.length_m / 2
        x = self.pose.x + front * math.cos(self.pose.heading)
        y = self.pose.y + front * math.sin(self.pose.heading)
        distance = self.world.distance_ahead(x, y, self.pose.heading)
        return None if distance > self.config.safety.sensor_range_m else distance

    # -- outputs -----------------------------------------------------------------

    def pop_transitions(self) -> list[tuple[RobotState, str | None]]:
        """State changes since the last call, oldest first."""
        with self._lock:
            transitions, self._transitions = self._transitions, []
            return transitions

    def telemetry(self) -> dict[str, Any]:
        """Current telemetry, as published in ``event.data``."""
        with self._lock:
            return {
                "x_m": round(self.pose.x, 4),
                "y_m": round(self.pose.y, 4),
                "heading_deg": round(math.degrees(self.pose.heading) % 360.0, 2),
                "speed_mps": round(self.speed, 4),
                "turn_dps": round(math.degrees(self.turn_rate), 2),
                "obstacle_m": None if self.obstacle is None else round(self.obstacle, 4),
                "state": self.state.value,
                "reason": self.reason,
                "command": self.command,
            }

    def telemetry_event(self) -> Event:
        """``telemetry`` event for ``openmind/v1/events``."""
        return Event(object=OBJECT_NAME, kind="telemetry", data=self.telemetry())

    def state_event(self, state: RobotState, reason: str | None) -> Event:
        """``state`` event for ``openmind/v1/events``, published on every change."""
        return Event(
            object=OBJECT_NAME, kind="state", data={"state": state.value, "reason": reason}
        )


def _wrap(angle: float) -> float:
    """Angle wrapped to ``[-pi, pi)``."""
    return (angle + math.pi) % (2 * math.pi) - math.pi


def format_line(data: dict[str, Any]) -> str:
    """One-line text view of a telemetry dictionary."""
    obstacle = "  -  " if data["obstacle_m"] is None else f"{data['obstacle_m']:.2f}"
    reason = f" ({data['reason']})" if data["reason"] else ""
    return (
        f"{data['state']:<11} cmd {data['command']:<7} "
        f"x {data['x_m']:5.2f} y {data['y_m']:5.2f} m  heading {data['heading_deg']:5.1f}°  "
        f"speed {data['speed_mps']:.2f} m/s  obstacle {obstacle} m{reason}"
    )
