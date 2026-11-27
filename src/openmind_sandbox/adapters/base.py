"""Base class of every controllable object, with the protocol safety rules built in.

A subclass only says what the commands do (:meth:`Adapter.on_command`) and how to
bring the object to a safe state (:meth:`Adapter.stop`). Everything else is done
here and cannot be overridden (see ``docs/protocol.md`` of OpenMind Core, section 4):

1. nothing is executed before a ``running`` status was received; :meth:`stop` is
   called until then, again when no status arrived for 2 s, and when the decoder
   reports any other state than ``running``;
2. commands below ``min_confidence`` are ignored; ``rest`` has no threshold,
   since stopping is never risky;
3. commands whose ``seq`` is not newer than the last accepted one are ignored;
4. ``action`` is contextual: it is forwarded only when
   :meth:`Adapter.context_allows_action` says so;
5. an invalid message on an OpenMind topic stops the object, and commands are
   refused until the next valid ``running`` status (the same rule as the mock
   robot); a message on another topic is not addressed to the object and is
   ignored;
6. optionally (``confirm_action=True``), ``action`` needs two accepted commands
   within ``confirm_window_s``: the first only arms it (event ``action_armed``,
   hook :meth:`Adapter.on_action_armed`), the second executes it (event
   ``action_confirmed``). A movement command, a timeout or a stop cancels it
   (event ``action_cancelled``); ``rest`` does not, since the decoder repeats
   ``rest`` between the two gestures.

The adapter takes its time from an injectable clock and publishes through an
injectable callable, so it is tested without a broker.
"""

from __future__ import annotations

import logging
import threading
import time
from abc import ABC, abstractmethod
from collections.abc import Callable
from typing import Any, Final, final

from openmind_protocol import (
    Command,
    Event,
    Message,
    ProtocolError,
    Status,
    Watchdog,
    decode_topic,
    topics,
)

from openmind_sandbox.mqtt import MqttLink

log = logging.getLogger(__name__)

#: Seconds without ``running`` status after which the object is stopped.
HEARTBEAT_TIMEOUT_S: Final = 2.0
#: Seconds between two :meth:`Adapter.tick` calls in :meth:`Adapter.run` (10 Hz).
TICK_PERIOD_S: Final = 0.1


class Adapter(ABC):
    """Base class of a controllable object.

    Args:
        name: Identifier of the object, used as ``object`` in the events.
        min_confidence: Commands below this confidence are ignored (``rest`` is not).
        publish: Called with every message to publish (``MqttLink.publish`` in
            :meth:`run`). Without it, events are dropped.
        clock: Monotonic time source, for tests.
        confirm_action: Require a second ``action`` within ``confirm_window_s``
            before :meth:`on_action` runs. Off by default; recommended for objects
            acting in the real world when the action cannot be undone.
        confirm_window_s: Seconds during which the second ``action`` confirms.
    """

    def __init__(
        self,
        name: str,
        min_confidence: float = 0.7,
        publish: Callable[[Message], None] | None = None,
        clock: Callable[[], float] = time.monotonic,
        confirm_action: bool = False,
        confirm_window_s: float = 3.0,
    ) -> None:
        if confirm_window_s <= 0:
            raise ValueError("confirm_window_s must be positive")
        self.name = name
        self.confirm_action = confirm_action
        self.confirm_window_s = confirm_window_s
        self._armed_until: float | None = None
        self._publish = publish
        self._clock = clock
        # Thresholds are applied here (rest is exempt), so the watchdog only
        # checks the heartbeat and the order of the commands.
        self._watchdog = Watchdog(min_confidence=0.0, timeout=HEARTBEAT_TIMEOUT_S, clock=clock)
        self.min_confidence = min_confidence
        self._stopped = False
        self._fault = False  # invalid message seen; cleared by a running status
        self._lock = threading.RLock()

    # -- hooks for subclasses ------------------------------------------------------

    @abstractmethod
    def on_command(self, command: str, confidence: float) -> None:
        """Apply ``left``, ``right``, ``forward``, ``rest`` or ``action``.

        Only called for commands that passed the safety rules (and, for
        ``action``, :meth:`context_allows_action`).
        """

    @abstractmethod
    def stop(self) -> None:
        """Bring the object to a safe state.

        Called at start until the first status, when the heartbeat is lost, when
        the decoder is not ``running`` and on shutdown. It may be called again
        after the object was restarted by new commands; keep it quick and safe to
        repeat.
        """

    def on_action(self, confidence: float) -> None:
        """Apply ``action`` (only called when the context allows it)."""
        self.on_command("action", confidence)

    def on_action_armed(self) -> None:  # noqa: B027 - optional hook, no-op default
        """Called when a first ``action`` armed the confirmation (default: nothing).

        Use it for a cue (light, beep) telling the user to repeat ``action`` within
        ``confirm_window_s`` seconds. Only used when ``confirm_action`` is true.
        """

    def context_allows_action(self) -> bool:
        """Whether ``action`` makes sense now (e.g. in front of a door).

        ``action`` is a one-shot, contextual gesture: it is ignored unless the
        object says so. Default: never.
        """
        return False

    # -- safety, not overridable ---------------------------------------------------

    @final
    @property
    def action_armed(self) -> bool:
        """Whether a first ``action`` is waiting for its confirmation."""
        return self._armed_until is not None

    @final
    @property
    def stopped(self) -> bool:
        """Whether the object is in its safe state (until a command is applied)."""
        return self._stopped

    @final
    def handle_message(self, topic: str, payload: bytes) -> None:
        """Process a raw message received from the broker."""
        try:
            message = decode_topic(topic, payload)
        except KeyError as error:  # not an OpenMind topic: not addressed to us
            log.warning("ignored message on %s: %s", topic, error)
            return
        except ProtocolError as error:
            log.warning("invalid message on %s, stopping: %s", topic, error)
            with self._lock:
                self._fault = True
                self._cancel_armed("invalid_message")
                self._enter_safe_state()
            return
        with self._lock:
            if isinstance(message, Status):
                self._on_status(message)
            elif isinstance(message, Command):
                self._on_command(message)

    @final
    def tick(self, now: float | None = None) -> None:
        """Check the heartbeat; call it about every 100 ms.

        Stops the object once when no ``running`` status arrived for 2 s. The
        ``now`` argument is accepted for symmetry with other components; the
        injected clock is what the watchdog uses.
        """
        del now
        with self._lock:
            if not self._watchdog.alive:
                self._cancel_armed("heartbeat_lost")
                self._enter_safe_state()
            elif self._armed_until is not None and self._clock() >= self._armed_until:
                self._cancel_armed("timeout")

    @final
    def emit_event(self, kind: str, data: dict[str, Any] | None = None) -> None:
        """Publish an ``event`` of this object on ``openmind/v1/events``."""
        if self._publish is None:
            return
        try:
            self._publish(Event(object=self.name, kind=kind, data=data or {}))
        except Exception:
            log.exception("could not publish event %r", kind)

    @final
    def run(self, link: MqttLink) -> None:
        """Serve the object until Ctrl+C: connect, subscribe, tick, stop on exit."""
        link.set_handlers(on_message=self.handle_message)
        link.subscribe([topics.COMMANDS, topics.STATUS])
        self._publish = link.publish
        link.connect()
        try:
            while True:
                self.tick()
                time.sleep(TICK_PERIOD_S)
        except KeyboardInterrupt:
            pass
        finally:
            with self._lock:
                self._enter_safe_state(force=True)
            link.close()

    # -- internals -----------------------------------------------------------------

    def _on_status(self, status: Status) -> None:
        if not self._watchdog.alive:
            # The decoder was silent (or restarted): its seq starts over.
            self._watchdog.reset_sequence()
        self._watchdog.on_status(status)
        if status.state == "running":
            self._fault = False
        else:
            self._cancel_armed("decoder_not_running")
            self._enter_safe_state()

    def _on_command(self, command: Command) -> None:
        name = command.command
        if not self._watchdog.alive:
            self._cancel_armed("heartbeat_lost")
            return
        if self._fault:
            return  # stopped on an invalid message: wait for a running status
        if name != "rest" and command.confidence < self.min_confidence:
            return
        if not self._watchdog.accept(command):
            return  # stale or duplicate seq
        if self._armed_until is not None and self._clock() >= self._armed_until:
            self._cancel_armed("timeout")
        if name == "action":
            if not self.context_allows_action():
                self._cancel_armed("context_lost")
                return
            if self.confirm_action and self._armed_until is None:
                self._arm_action()
                return
        elif name != "rest":
            # rest keeps the confirmation armed: the decoder repeats it between
            # the two gestures, so only a movement cancels.
            self._cancel_armed("other_command")
        confirmed = name == "action" and self._armed_until is not None
        if name == "action":
            self._armed_until = None
        try:
            if name == "action":
                self.on_action(command.confidence)
            else:
                self.on_command(name, command.confidence)
        except Exception:
            log.exception("command %r failed, stopping the object", name)
            self._enter_safe_state(force=True)
            return
        if confirmed:
            self.emit_event("action_confirmed")
        self._stopped = False  # stop() will run again on heartbeat loss

    def _arm_action(self) -> None:
        self._armed_until = self._clock() + self.confirm_window_s
        self.emit_event("action_armed", {"window_s": self.confirm_window_s})
        try:
            self.on_action_armed()
        except Exception:
            log.exception("on_action_armed() failed")

    def _cancel_armed(self, reason: str) -> None:
        if self._armed_until is None:
            return
        self._armed_until = None
        self.emit_event("action_cancelled", {"reason": reason})

    def _enter_safe_state(self, force: bool = False) -> None:
        self._cancel_armed("stopped")
        if self._stopped and not force:
            return
        self._stopped = True
        try:
            self.stop()
        except Exception:
            log.exception("stop() failed")
