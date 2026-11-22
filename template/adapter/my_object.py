"""Template: connect your own object to OpenMind BCI.

Copy this file, rename the class, fill in the two methods marked TODO.

The safety rules are NOT in this file, on purpose: the base class applies them
before calling you and you cannot switch them off. You never receive a command
that is stale, too uncertain, or sent while the decoder is silent.

Try it without a headset and without your object:

    docker compose -f dev/docker-compose.yml up -d     # local broker
    python my_object.py                                # this adapter
    openmind-sandbox keys                              # arrows + space
"""

from __future__ import annotations

from openmind_sandbox.adapters import Adapter
from openmind_sandbox.mqtt import MqttLink


class MyObject(Adapter):
    """A minimal object that only prints what it would do."""

    def __init__(self) -> None:
        # The name appears in the events published for dashboards.
        # min_confidence: commands below it are dropped by the base class.
        super().__init__("my-object", min_confidence=0.8)

    def on_command(self, command: str, confidence: float) -> None:
        """React to "left", "right", "forward", "rest" or "action".

        TODO: replace print() with a call to your hardware or API. Keep it short:
        this runs on the network thread, do not block for seconds.
        "rest" always arrives, whatever its confidence: make it stop the object.
        """
        print(f"{command} ({confidence:.2f})")
        self.emit_event("command_applied", {"command": command})

    def stop(self) -> None:
        """Bring the object to a SAFE state (motors off, valve closed...).

        Called when the decoder is silent for 2 s, reports a problem, has not
        started yet, or when you quit. It must work even if the object is
        already stopped, and it must never raise because of a lost connection.
        """
        print("stop")

    def context_allows_action(self) -> bool:
        """Say when the "action" gesture makes sense (default: never).

        "action" is a deliberate one-shot gesture (a double jaw clench). For an
        object where it has an effect in the real world (open a door, toggle
        mains power), return True only when it is clearly safe, e.g. when a
        sensor sees the door. Return False and "action" is simply ignored.
        """
        return True


if __name__ == "__main__":
    MyObject().run(MqttLink())  # localhost:1883; Ctrl+C calls stop() and exits
