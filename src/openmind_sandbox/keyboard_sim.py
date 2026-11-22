"""Keyboard command simulator: a stand-in for the decoder of OpenMind Core.

It publishes what a live decoder publishes, so that objects can be developed
without a headset:

- ``command`` messages: arrows give ``left`` / ``right`` / ``forward``, space gives
  one ``action``, no key gives ``rest``; repeated at a bounded rate with a new
  ``seq`` each time;
- ``status`` heartbeats (``running``) at 4 Hz by default (the protocol asks ≥ 2 Hz);
- optionally the calibration feedback of the decoder: an ``assistance`` level in
  ``status`` (fixed, or ramping down from 1 to 0) and periodic ``score`` messages;
- optionally fake ``bandpower`` messages at 10 Hz, with a simulated
  desynchronization over the motor area of the commanded movement.

Commands can also be replayed from a YAML script (:class:`Script`). All the timing
logic takes the time as an argument, so it is tested without waiting.
"""

from __future__ import annotations

import math
import random
import re
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Annotated, Final

import yaml
from openmind_protocol import (
    COMMANDS,
    BandPower,
    ChannelPower,
    Command,
    CommandName,
    Message,
    Score,
    Status,
)
from pydantic import BaseModel, ConfigDict, Field, ValidationError

#: Keys that select a held command (arrows, and WASD-style letters as a fallback).
KEY_COMMANDS: Final[dict[str, CommandName]] = {
    "left": "left",
    "right": "right",
    "up": "forward",
    "down": "rest",
    "a": "left",
    "d": "right",
    "w": "forward",
    "s": "rest",
}
#: Keys that trigger one ``action`` (the double jaw clench of the real decoder).
ACTION_KEYS: Final = frozenset({"space"})

#: Montage ``C`` of OpenMind Plug: the eight motor electrodes of the IronBCI-8.
DEFAULT_CHANNELS: Final = ("FC3", "FC4", "C3", "Cz", "C4", "CP3", "CP4", "CPz")
#: Frequency bands of the fake band power messages, in Hz.
BANDS: Final = {"alpha": (8.0, 12.0), "mu": (8.0, 13.0), "beta": (13.0, 30.0)}

UserId = Annotated[str, Field(pattern=r"^P[0-9]{2,}$")]


# --- Held keys -----------------------------------------------------------------


class HoldTracker:
    """Turn key presses into a held command.

    Terminals report presses, never releases: a key counts as held while its
    auto-repeat keeps arriving. After ``hold`` seconds without a repeat the
    command falls back to ``rest``. ``hold`` must exceed the auto-repeat delay of
    the system (about 0.4 s by default on macOS, Windows and most Linux desktops).

    With ``latch=True`` a command stays until another key is pressed (down arrow
    or ``s`` for ``rest``), which works on any terminal.
    """

    def __init__(self, hold: float = 0.5, latch: bool = False) -> None:
        if hold <= 0:
            raise ValueError("hold must be positive")
        self.hold = hold
        self.latch = latch
        self._command: CommandName = "rest"
        self._pressed_at = -math.inf

    def press(self, command: CommandName, now: float) -> None:
        """Record a press (or an auto-repeat) of a key mapped to ``command``."""
        self._command = command
        self._pressed_at = now

    def command(self, now: float) -> CommandName:
        """Command held at time ``now``."""
        if self.latch or now - self._pressed_at < self.hold:
            return self._command
        return "rest"


# --- Calibration feedback ------------------------------------------------------


class AssistanceSchedule:
    """Assistance level announced in ``status``: fixed, or ramping from 1 to 0.

    With ``ramp_s`` the level decreases linearly from 1 to 0 over ``ramp_s`` seconds,
    counted from the first call of :meth:`value`, then stays at 0; otherwise it
    is the constant ``fixed``.
    """

    def __init__(self, fixed: float = 1.0, ramp_s: float | None = None) -> None:
        if not 0.0 <= fixed <= 1.0:
            raise ValueError("assistance must be between 0 and 1")
        if ramp_s is not None and ramp_s <= 0:
            raise ValueError("the assistance ramp must last a positive number of seconds")
        self.fixed = fixed
        self.ramp_s = ramp_s
        self._start: float | None = None

    def value(self, now: float) -> float:
        """Assistance (0-1) at time ``now``."""
        if self.ramp_s is None:
            return self.fixed
        if self._start is None:
            self._start = now
        return round(min(1.0, max(0.0, 1.0 - (now - self._start) / self.ramp_s)), 3)


#: Per-command offsets so that the simulated accuracies differ a little.
_ACCURACY_OFFSET: Final[dict[CommandName, float]] = {
    "left": 0.03,
    "right": -0.03,
    "forward": -0.05,
    "rest": 0.05,
}


class ScoreSimulator:
    """Plausible ``score`` messages for a user who learns over ``duration_s`` seconds.

    Per-command accuracy rises linearly from 0.35 to 0.88 (false starts fall from
    0.30 to 0.04). ``ready`` follows the thresholds of the protocol documentation:
    every command at least ``min_accuracy`` (0.70), false starts at most
    ``max_false_starts`` (0.10) and ``stable_blocks_needed`` (2) consecutive blocks
    of ``block_s`` seconds in that state. Not a model of a user, only a known answer
    for the cockpit's progress panel.
    """

    def __init__(
        self,
        user: str = "P00",
        duration_s: float = 90.0,
        block_s: float = 10.0,
        min_accuracy: float = 0.70,
        max_false_starts: float = 0.10,
        stable_blocks_needed: int = 2,
    ) -> None:
        if duration_s <= 0 or block_s <= 0:
            raise ValueError("duration_s and block_s must be positive")
        self.user = user
        self.duration_s = duration_s
        self.block_s = block_s
        self.min_accuracy = min_accuracy
        self.max_false_starts = max_false_starts
        self.stable_blocks_needed = stable_blocks_needed
        self._start: float | None = None
        self._ok_since: float | None = None

    def score(self, now: float) -> Score:
        """Score at time ``now`` (call with non-decreasing times)."""
        if self._start is None:
            self._start = now
        progress = min(1.0, max(0.0, (now - self._start) / self.duration_s))
        per_command = {
            name: round(min(1.0, max(0.0, 0.35 + 0.53 * progress + offset)), 3)
            for name, offset in _ACCURACY_OFFSET.items()
        }
        false_starts = round(0.30 - 0.26 * progress, 3)
        met = (
            min(per_command.values()) >= self.min_accuracy and false_starts <= self.max_false_starts
        )
        if not met:
            self._ok_since = None
            stable = 0
        else:
            if self._ok_since is None:
                self._ok_since = now
            stable = int((now - self._ok_since) // self.block_s)
        return Score(
            user=self.user,
            overall=round(sum(per_command.values()) / len(per_command), 3),
            ready=met and stable >= self.stable_blocks_needed,
            per_command=per_command,
            false_start_rate=false_starts,
            stable_blocks=stable,
        )


# --- Decoder simulator ---------------------------------------------------------


class CommandSimulator:
    """Produce the ``command`` and ``status`` messages of a live decoder.

    Call :meth:`poll` often (every 10-50 ms) with the current time; it returns the
    messages due at that time.

    Args:
        user: Pseudonym of the simulated user.
        confidence: Confidence of the commands, between 0 and 1.
        model: Model name announced in ``status``.
        status_period: Seconds between two ``status`` messages (≤ 0.5 s).
        repeat_period: Seconds after which an unchanged command is sent again.
        action_refractory: Seconds during which further ``action`` triggers are
            ignored (auto-repeat of the space bar).
        assistance: Assistance announced in ``status`` (``None``: none announced).
        scores: Source of ``score`` messages, published every ``score_period``
            seconds (``None``: no score).
        score_period: Seconds between two ``score`` messages.
    """

    def __init__(
        self,
        user: str = "P00",
        confidence: float = 0.9,
        model: str = "keyboard-sim",
        status_period: float = 0.25,
        repeat_period: float = 0.25,
        action_refractory: float = 0.6,
        assistance: AssistanceSchedule | None = None,
        scores: ScoreSimulator | None = None,
        score_period: float = 2.0,
    ) -> None:
        if not 0 < status_period <= 0.5:
            raise ValueError("status_period must be in (0, 0.5] s (status at >= 2 Hz)")
        if repeat_period <= 0:
            raise ValueError("repeat_period must be positive")
        self.user = user
        self.confidence = confidence
        self.model = model
        self.status_period = status_period
        self.repeat_period = repeat_period
        self.action_refractory = action_refractory
        if score_period <= 0:
            raise ValueError("score_period must be positive")
        self.assistance = assistance
        self.scores = scores
        self.score_period = score_period
        self._next_score = -math.inf
        self.intent: CommandName = "rest"
        self.seq = 0
        self.last_sent: CommandName | None = None
        self._next_status = -math.inf
        self._last_command_at = -math.inf
        self._last_action_at = -math.inf
        self._action_pending = False

    @property
    def confidence(self) -> float:
        """Confidence attached to the next commands."""
        return self._confidence

    @confidence.setter
    def confidence(self, value: float) -> None:
        self._confidence = round(min(1.0, max(0.0, value)), 3)

    def trigger_action(self, now: float) -> bool:
        """Request one ``action`` command; returns ``False`` during the refractory time."""
        if now - self._last_action_at < self.action_refractory:
            return False
        self._last_action_at = now
        self._action_pending = True
        return True

    def recent_action(self, now: float, window: float = 0.5) -> bool:
        """Whether an ``action`` was triggered less than ``window`` seconds ago."""
        return now - self._last_action_at < window

    def poll(self, now: float) -> list[Message]:
        """Messages due at time ``now``: at most one status and one command."""
        messages: list[Message] = []
        if now >= self._next_status:
            level = self.assistance.value(now) if self.assistance is not None else None
            messages.append(
                Status(state="running", model=self.model, user=self.user, assistance=level)
            )
            self._next_status = max(self._next_status + self.status_period, now)
        if self.scores is not None and now >= self._next_score:
            self.scores.user = self.user
            messages.append(self.scores.score(now))
            self._next_score = max(self._next_score + self.score_period, now)
        if self._action_pending:
            self._action_pending = False
            messages.append(self._command("action", now))
        elif self.intent != self.last_sent or now - self._last_command_at >= self.repeat_period:
            messages.append(self._command(self.intent, now))
        return messages

    def _command(self, name: CommandName, now: float) -> Command:
        command = Command(command=name, confidence=self.confidence, user=self.user, seq=self.seq)
        self.seq += 1
        self.last_sent = name
        self._last_command_at = now
        return command


# --- Scripted commands ---------------------------------------------------------


class ScriptStep(BaseModel):
    """One step of a script: hold ``command`` for ``duration`` seconds."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    command: CommandName
    duration: Annotated[float, Field(gt=0)]
    confidence: Annotated[float, Field(ge=0, le=1)] | None = None


class Script(BaseModel):
    """A sequence of commands replayed by ``openmind-sandbox keys --script``.

    Example file::

        user: P00          # optional, overrides --user
        loop: false        # replay forever when true
        steps:
          - {command: rest, duration: 2}
          - {command: left, duration: 1.5, confidence: 0.92}
          - {command: action, duration: 0.5}

    An ``action`` step sends a single ``action`` command, then ``rest`` until the
    step ends.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    user: UserId | None = None
    loop: bool = False
    steps: Annotated[list[ScriptStep], Field(min_length=1)]

    @classmethod
    def load(cls, path: Path) -> Script:
        """Read and validate a script file.

        Raises:
            ValueError: If the file is not valid YAML or not a valid script; the
                message names the faulty fields.
        """
        try:
            document = yaml.safe_load(path.read_text(encoding="utf-8"))
            return cls.model_validate(document)
        except yaml.YAMLError as error:
            raise ValueError(f"{path}: not valid YAML ({error})") from error
        except ValidationError as error:
            problems = "; ".join(
                f"{'.'.join(str(p) for p in e['loc']) or '(root)'}: {e['msg']}"
                for e in error.errors()
            )
            raise ValueError(f"{path}: invalid script: {problems}") from error

    @property
    def duration(self) -> float:
        """Duration of one pass through the steps, in seconds."""
        return sum(step.duration for step in self.steps)

    def step_at(self, elapsed: float) -> tuple[int, ScriptStep] | None:
        """Index and step active ``elapsed`` seconds after the start; ``None`` when over."""
        if elapsed < 0:
            return None
        if self.loop:
            elapsed %= self.duration
        start = 0.0
        for index, step in enumerate(self.steps):
            if elapsed < start + step.duration:
                return index, step
            start += step.duration
        return None


class ScriptPlayer:
    """Drive a :class:`CommandSimulator` from a :class:`Script`."""

    def __init__(self, script: Script, simulator: CommandSimulator, start: float) -> None:
        self.script = script
        self.simulator = simulator
        self.start = start
        self._default_confidence = simulator.confidence
        self._last_step: tuple[int, int] | None = None  # (pass, index)

    def update(self, now: float) -> bool:
        """Apply the step active at ``now``; returns ``False`` once the script is over."""
        elapsed = now - self.start
        found = self.script.step_at(elapsed)
        if found is None:
            self.simulator.intent = "rest"
            return False
        index, step = found
        current = (int(elapsed // self.script.duration), index)
        entered = current != self._last_step
        self._last_step = current
        self.simulator.confidence = (
            step.confidence if step.confidence is not None else self._default_confidence
        )
        if step.command == "action":
            if entered:
                self.simulator.trigger_action(now)
            self.simulator.intent = "rest"
        else:
            self.simulator.intent = step.command
        return True


# --- Fake band power -----------------------------------------------------------


_LABEL = re.compile(r"^(?P<region>[A-Za-z]+?)(?P<side>z|\d+)$")
#: How strongly each region takes part in motor desynchronization.
_REGION_WEIGHT: Final = {"C": 1.0, "FC": 0.6, "CP": 0.6}


def motor_weight(label: str, command: CommandName) -> float:
    """Share (0-1) of the desynchronization of ``command`` seen on electrode ``label``.

    Imagining a left-hand movement desynchronizes the right motor cortex (even
    electrode numbers: C4...), a right-hand movement the left one (odd numbers:
    C3...), and feet (``forward``) the midline (Cz, CPz...). The central row
    (C) is weighted 1, the rows just in front and behind (FC, CP) 0.6, others 0.
    """
    match = _LABEL.match(label)
    if match is None or command not in ("left", "right", "forward"):
        return 0.0
    region = _REGION_WEIGHT.get(match["region"].upper(), 0.0)
    side = match["side"]
    if side == "z":
        return region if command == "forward" else 0.0
    is_right_hemisphere = int(side) % 2 == 0
    if command == "left" and is_right_hemisphere:
        return region
    if command == "right" and not is_right_hemisphere:
        return region
    return 0.0


@dataclass
class FakeBandPower:
    """Plausible ``bandpower`` messages driven by the simulated command.

    Not a model of EEG: it only gives the 3D brain panel something to show with a
    known answer. ``rel_mu`` drops by up to ``mu_drop`` (``rel_beta`` by half of
    it) over the motor area of the command, ``action`` (a jaw clench, a muscle
    signal) raises ``rel_beta`` on every electrode, and values move smoothly
    towards their target with time constant ``tau`` plus a little noise.

    Args:
        user: Pseudonym announced in the messages.
        channels: Electrode labels (10-10 names).
        bad_channels: Electrodes reported as ``ok: false`` with ``null`` values.
        seed: Seed of the noise, for reproducible sequences.
    """

    user: str = "P00"
    channels: Sequence[str] = DEFAULT_CHANNELS
    bad_channels: Sequence[str] = ()
    seed: int | None = None
    mu_drop: float = 0.45
    clench_beta_rise: float = 1.2
    noise: float = 0.03
    tau: float = 0.4
    srate_hz: float = 250.0
    _rng: random.Random = field(init=False, repr=False)
    _rel: dict[str, list[float]] = field(init=False, repr=False)
    _last: float | None = field(init=False, default=None, repr=False)

    def __post_init__(self) -> None:
        unknown = set(self.bad_channels) - set(self.channels)
        if unknown:
            raise ValueError(f"bad channels not in the montage: {sorted(unknown)}")
        self._rng = random.Random(self.seed)
        self._rel = {label: [0.0, 0.0] for label in self.channels}

    def targets(self, command: CommandName) -> dict[str, tuple[float, float]]:
        """Target ``(rel_mu, rel_beta)`` of each electrode for ``command``."""
        result: dict[str, tuple[float, float]] = {}
        for label in self.channels:
            weight = motor_weight(label, command)
            rel_mu = -self.mu_drop * weight
            rel_beta = -0.5 * self.mu_drop * weight
            if command == "action":
                rel_beta = self.clench_beta_rise
            result[label] = (rel_mu, rel_beta)
        return result

    def step(self, command: CommandName, now: float) -> BandPower:
        """Advance to time ``now`` with ``command`` held, and return the message."""
        dt = 0.0 if self._last is None else max(0.0, now - self._last)
        self._last = now
        alpha = 1.0 - math.exp(-dt / self.tau) if dt > 0 else 0.0
        entries: list[ChannelPower] = []
        for label, (target_mu, target_beta) in self.targets(command).items():
            state = self._rel[label]
            state[0] += alpha * (target_mu - state[0])
            state[1] += alpha * (target_beta - state[1])
            if label in self.bad_channels:
                entries.append(
                    ChannelPower(
                        label=label,
                        alpha=None,
                        mu=None,
                        beta=None,
                        rel_mu=None,
                        rel_beta=None,
                        ok=False,
                    )
                )
                continue
            rel_mu = max(-0.95, state[0] + self._rng.gauss(0.0, self.noise))
            rel_beta = max(-0.95, state[1] + self._rng.gauss(0.0, self.noise))
            entries.append(
                ChannelPower(
                    label=label,
                    alpha=round(8.0 * (1 + rel_mu), 3),
                    mu=round(10.0 * (1 + rel_mu), 3),
                    beta=round(3.5 * (1 + rel_beta), 3),
                    rel_mu=round(rel_mu, 3),
                    rel_beta=round(rel_beta, 3),
                    ok=True,
                )
            )
        return BandPower(user=self.user, srate_hz=self.srate_hz, bands=BANDS, channels=entries)


__all__ = [
    "ACTION_KEYS",
    "BANDS",
    "COMMANDS",
    "DEFAULT_CHANNELS",
    "KEY_COMMANDS",
    "AssistanceSchedule",
    "CommandSimulator",
    "FakeBandPower",
    "HoldTracker",
    "ScoreSimulator",
    "Script",
    "ScriptPlayer",
    "ScriptStep",
    "motor_weight",
]
