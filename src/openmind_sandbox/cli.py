"""Command-line interface: ``openmind-sandbox``."""

from __future__ import annotations

import sys
import time
from pathlib import Path
from typing import Annotated

import openmind_protocol
import typer
from openmind_protocol import Command, Message, ProtocolError, Status, decode_topic, topics

import openmind_sandbox
from openmind_sandbox import keyboard
from openmind_sandbox.adapters.examples.fake_lamp import DEFAULT_LAMP_PORT, FakeLampServer
from openmind_sandbox.adapters.examples.lamp import DEFAULT_URL, LampAdapter
from openmind_sandbox.bridge import DEFAULT_WS_PORT
from openmind_sandbox.calibration import Calibration
from openmind_sandbox.config import RobotConfig, with_thresholds
from openmind_sandbox.course import Course, export_godot_data
from openmind_sandbox.keyboard_sim import (
    ACTION_KEYS,
    DEFAULT_CHANNELS,
    KEY_COMMANDS,
    CommandSimulator,
    FakeBandPower,
    HoldTracker,
    Script,
    ScriptPlayer,
)
from openmind_sandbox.mock_robot import MockRobot, format_line
from openmind_sandbox.mqtt import DEFAULT_HOST, DEFAULT_PORT, BrokerUnavailableError, MqttLink

app = typer.Typer(
    name="openmind-sandbox",
    help="Virtual and real objects driven by OpenMind BCI commands.",
    no_args_is_help=True,
    add_completion=False,
)

adapter_app = typer.Typer(
    help="Run an adapter: connect a real or virtual object to the commands.",
    no_args_is_help=True,
)
app.add_typer(adapter_app, name="adapter")

Host = Annotated[str, typer.Option(help="MQTT broker host.")]
Port = Annotated[int, typer.Option(help="MQTT broker port.")]

#: Seconds between two iterations of the simulator loop.
_TICK = 0.02
#: Seconds between two band power messages (about 10 Hz).
_BANDPOWER_PERIOD = 0.1

_KEYS_HELP = (
    "arrows (or a/w/d) = left/forward/right while held, space = action, "
    "down (or s) = rest, +/- = confidence, q = quit"
)


@app.callback()
def main() -> None:
    """Virtual and real objects driven by OpenMind BCI commands."""


@app.command()
def version() -> None:
    """Print the sandbox and protocol versions."""
    typer.echo(f"openmind-sandbox {openmind_sandbox.__version__}")
    typer.echo(f"openmind-protocol {openmind_protocol.PROTOCOL_VERSION}")


@app.command()
def keys(
    host: Host = DEFAULT_HOST,
    port: Port = DEFAULT_PORT,
    user: Annotated[str, typer.Option(help="Pseudonym of the simulated user.")] = "P00",
    confidence: Annotated[
        float, typer.Option(min=0.0, max=1.0, help="Confidence of the commands.")
    ] = 0.9,
    hold: Annotated[
        float,
        typer.Option(
            min=0.05,
            help="Seconds a key stays held after its last auto-repeat; "
            "raise it if commands flicker to rest.",
        ),
    ] = 0.5,
    latch: Annotated[
        bool, typer.Option(help="Keep a command until another key is pressed.")
    ] = False,
    script: Annotated[
        Path | None,
        typer.Option(exists=True, dir_okay=False, help="Replay commands from a YAML script."),
    ] = None,
    bandpower: Annotated[
        bool, typer.Option(help="Also publish fake band power messages (10 Hz).")
    ] = False,
    channels: Annotated[
        str, typer.Option(help="Comma-separated electrodes of the fake band power.")
    ] = ",".join(DEFAULT_CHANNELS),
    bad_channel: Annotated[
        list[str] | None,
        typer.Option(help="Electrode reported as ok=false in band power (repeatable)."),
    ] = None,
    seed: Annotated[int | None, typer.Option(help="Seed of the band power noise.")] = None,
) -> None:
    """Simulate a live decoder from the keyboard or from a script.

    Publishes commands, a running status at 4 Hz and, with --bandpower, fake
    band power messages, all validated against the OpenMind protocol.
    """
    try:
        simulator = CommandSimulator(user=user, confidence=confidence)
        loaded = Script.load(script) if script is not None else None
        if loaded is not None and loaded.user is not None:
            simulator.user = loaded.user
        fake = (
            FakeBandPower(
                user=simulator.user,
                channels=[c.strip() for c in channels.split(",") if c.strip()],
                bad_channels=bad_channel or (),
                seed=seed,
            )
            if bandpower
            else None
        )
        # Fail early on an invalid pseudonym rather than at the first message.
        Status(state="running", model=simulator.model, user=simulator.user)
    except ValueError as error:
        raise typer.BadParameter(str(error)) from error

    if loaded is None and not keyboard.stdin_is_terminal():
        typer.echo("Keyboard mode needs an interactive terminal; use --script instead.", err=True)
        raise typer.Exit(2)

    link = MqttLink(host, port, name="openmind-keys")
    try:
        link.connect()
    except BrokerUnavailableError as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(1) from error

    loop = _Loop(simulator, fake, link)
    try:
        if loaded is not None:
            typer.echo(f"Replaying {script} ({loaded.duration:.1f} s per pass). Ctrl+C to stop.")
            loop.run_script(loaded)
        else:
            typer.echo(_KEYS_HELP)
            loop.run_keyboard(HoldTracker(hold=hold, latch=latch))
    except KeyboardInterrupt:
        pass
    finally:
        # Last word: rest. Objects then stop anyway when the status stops.
        simulator.intent = "rest"
        for message in simulator.poll(time.monotonic() + simulator.repeat_period):
            link.publish(message)
        link.close()
        typer.echo("\nStopped: no more status, objects will stop within 2 s.")


class _Loop:
    """Publishing loop shared by the keyboard and script modes."""

    def __init__(
        self, simulator: CommandSimulator, fake: FakeBandPower | None, link: MqttLink
    ) -> None:
        self.simulator = simulator
        self.fake = fake
        self.link = link
        self._next_bandpower = 0.0
        self._last_line = ""

    def tick(self, now: float) -> None:
        messages: list[Message] = self.simulator.poll(now)
        if self.fake is not None and now >= self._next_bandpower:
            held = "action" if self.simulator.recent_action(now) else self.simulator.intent
            messages.append(self.fake.step(held, now))
            self._next_bandpower = now + _BANDPOWER_PERIOD
        for message in messages:
            self.link.publish(message)
        self._render()

    def run_keyboard(self, tracker: HoldTracker) -> None:
        with keyboard.key_reader() as read:
            while True:
                now = time.monotonic()
                for key in read(_TICK):
                    if key in ("q", "Q"):
                        return
                    if key in KEY_COMMANDS:
                        tracker.press(KEY_COMMANDS[key], now)
                    elif key in ACTION_KEYS:
                        self.simulator.trigger_action(now)
                    elif key in ("+", "="):
                        self.simulator.confidence += 0.05
                    elif key in ("-", "_"):
                        self.simulator.confidence -= 0.05
                self.simulator.intent = tracker.command(time.monotonic())
                self.tick(time.monotonic())

    def run_script(self, script: Script) -> None:
        player = ScriptPlayer(script, self.simulator, start=time.monotonic())
        while player.update(time.monotonic()):
            self.tick(time.monotonic())
            time.sleep(_TICK)
        self.tick(time.monotonic())

    def _render(self) -> None:
        sim = self.simulator
        shown = "action" if sim.recent_action(time.monotonic()) else sim.intent
        line = f"\r  command {shown:<8} confidence {sim.confidence:.2f}  seq {sim.seq:<6}"
        if line != self._last_line:
            sys.stdout.write(line)
            sys.stdout.flush()
            self._last_line = line


@app.command("mock-robot")
def mock_robot(
    host: Host = DEFAULT_HOST,
    port: Port = DEFAULT_PORT,
    config: Annotated[
        Path | None,
        typer.Option(exists=True, dir_okay=False, help="robot.yaml (default: config/robot.yaml)."),
    ] = None,
    min_confidence: Annotated[
        float | None,
        typer.Option(min=0.0, max=1.0, help="Use this threshold for every command."),
    ] = None,
    threshold: Annotated[
        list[str] | None,
        typer.Option(
            help="Threshold of one command, as COMMAND=VALUE (repeatable), "
            "e.g. --threshold action=0.9."
        ),
    ] = None,
    course: Annotated[
        Path | None,
        typer.Option(
            exists=True, dir_okay=False, help="Course YAML (arena, obstacles, start pose)."
        ),
    ] = None,
    quiet: Annotated[bool, typer.Option(help="Do not print the live state line.")] = False,
) -> None:
    """Run the mock robot: 2D kinematics with the safety rules of the firmware.

    Listens to commands and status, publishes telemetry and state changes on
    openmind/v1/events, and prints its position and state.
    """
    try:
        robot_config = RobotConfig.load(config)
    except (OSError, ValueError) as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(2) from error
    try:
        robot_config = with_thresholds(robot_config, min_confidence, threshold or [])
    except ValueError as error:
        raise typer.BadParameter(str(error), param_hint="--threshold") from error
    if course is not None:
        try:
            loaded_course = Course.load(course)
        except ValueError as error:
            typer.echo(str(error), err=True)
            raise typer.Exit(2) from error
        robot = MockRobot(
            robot_config, world=loaded_course.world(), pose=loaded_course.start_pose()
        )
    else:
        robot = MockRobot(robot_config)

    def on_message(topic: str, payload: bytes) -> None:
        try:
            message = decode_topic(topic, payload)
        except ProtocolError as error:
            robot.on_fault("invalid_message")
            typer.echo(f"\nRejected message on {topic}: {error}", err=True)
            return
        if isinstance(message, Status):
            robot.on_status(message)
        elif isinstance(message, Command):
            robot.on_command(message)

    def on_connection(connected: bool) -> None:
        if not connected:
            robot.on_fault("disconnected")

    link = MqttLink(
        host,
        port,
        name="openmind-mock-robot",
        on_message=on_message,
        on_connection_change=on_connection,
    )
    link.subscribe([topics.COMMANDS, topics.STATUS])
    try:
        link.connect()
    except BrokerUnavailableError as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(1) from error

    safety = robot_config.safety
    thresholds = ", ".join(
        f"{name} {safety.threshold(name):.2f}" for name in ("left", "right", "forward", "action")
    )
    typer.echo(
        f"Mock robot (robot.yaml {robot_config.version}; thresholds {thresholds}; "
        "rest always stops). Waiting for a decoder status. Ctrl+C to stop."
    )
    telemetry_period = 1.0 / robot_config.telemetry.rate_hz
    next_telemetry = 0.0
    try:
        while True:
            robot.step()
            for state, reason in robot.pop_transitions():
                link.publish(robot.state_event(state, reason))
            now = time.monotonic()
            if now >= next_telemetry:
                event = robot.telemetry_event()
                link.publish(event)
                next_telemetry = now + telemetry_period
                if not quiet:
                    sys.stdout.write("\r" + format_line(event.data) + "\x1b[K")
                    sys.stdout.flush()
            time.sleep(_TICK)
    except KeyboardInterrupt:
        pass
    finally:
        link.close()
        typer.echo("\nMock robot stopped.")


@adapter_app.command("lamp")
def adapter_lamp(
    url: Annotated[str, typer.Option(help="Base URL of the lamp (local API only).")] = DEFAULT_URL,
    broker: Annotated[str, typer.Option(help="MQTT broker as HOST or HOST:PORT.")] = DEFAULT_HOST,
    min_confidence: Annotated[
        float, typer.Option(min=0.0, max=1.0, help="Commands below this are ignored.")
    ] = 0.7,
) -> None:
    """Example adapter: toggle and dim a lamp through its local HTTP API.

    action toggles, left/right dim, rest keeps the state. Try it with
    `openmind-sandbox fake-lamp` and `openmind-sandbox keys`.
    """
    host, _, port_text = broker.partition(":")
    try:
        port = int(port_text) if port_text else DEFAULT_PORT
    except ValueError as error:
        raise typer.BadParameter("expected HOST or HOST:PORT", param_hint="--broker") from error
    link = MqttLink(host or DEFAULT_HOST, port, name="openmind-lamp")
    lamp = LampAdapter(url=url, min_confidence=min_confidence)
    typer.echo(f"Lamp adapter on {url} (broker {host}:{port}). Ctrl+C to stop.")
    try:
        lamp.run(link)
    except BrokerUnavailableError as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(1) from error


@app.command("fake-lamp")
def fake_lamp(
    port: Annotated[int, typer.Option(help="TCP port to listen on.")] = DEFAULT_LAMP_PORT,
) -> None:
    """Run a fake lamp with a local HTTP API, to try the lamp adapter."""
    try:
        server = FakeLampServer(port)
    except OSError as error:
        typer.echo(f"cannot listen on port {port}: {error}", err=True)
        raise typer.Exit(1) from error
    typer.echo(f"Fake lamp on http://127.0.0.1:{port}/light. Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


@app.command("export-godot")
def export_godot(
    root: Annotated[
        Path, typer.Option(file_okay=False, help="Root of the sandbox repository.")
    ] = Path(),
) -> None:
    """Write robot.yaml and the courses as JSON for Godot (godot/data/)."""
    try:
        for path in export_godot_data(root):
            typer.echo(f"wrote {path}")
        for source in sorted((root / "scenarios").glob("calibration_*.yaml")):
            for warning in Calibration.load(source).check_block_duration():
                typer.echo(f"warning: {warning}", err=True)
    except (OSError, ValueError) as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(2) from error


@app.command("export-firmware")
def export_firmware(
    root: Annotated[
        Path, typer.Option(file_okay=False, help="Root of the sandbox repository.")
    ] = Path(),
) -> None:
    """Write robot.yaml as a C++ header for the ESP32 firmware."""
    from openmind_sandbox.firmware import export_firmware_header

    try:
        typer.echo(f"wrote {export_firmware_header(root)}")
    except (OSError, ValueError) as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(2) from error


@app.command()
def bridge(
    host: Host = DEFAULT_HOST,
    port: Port = DEFAULT_PORT,
    ws_host: Annotated[
        str, typer.Option(help="WebSocket address; 127.0.0.1 accepts this machine only.")
    ] = "127.0.0.1",
    ws_port: Annotated[int, typer.Option(help="WebSocket port.")] = DEFAULT_WS_PORT,
    lsl: Annotated[
        bool, typer.Option(help="Publish received markers on the LSL markers stream.")
    ] = True,
    eeg: Annotated[
        bool, typer.Option(help="Relay the LSL EEG stream to the cockpit signal panel.")
    ] = False,
    verbose: Annotated[bool, typer.Option("--verbose", "-v", help="Log every client.")] = False,
) -> None:
    """Relay protocol messages between MQTT and WebSocket clients (Godot), markers to LSL."""
    import asyncio
    import logging

    from openmind_sandbox.bridge import Bridge

    logging.basicConfig(
        level=logging.INFO if verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    gateway = Bridge(host, port, ws_host=ws_host, ws_port=ws_port, lsl=lsl, eeg=eeg)

    def ready() -> None:
        typer.echo(
            f"Bridge: MQTT {host}:{port} <-> ws://{ws_host}:{gateway.ws_port}"
            + (" -> LSL openmind-markers" if lsl else "")
            + (", relaying LSL openmind-eeg" if eeg else "")
            + ". Ctrl+C to stop."
        )

    try:
        asyncio.run(gateway.run(on_ready=ready))
    except BrokerUnavailableError as error:
        typer.echo(str(error), err=True)
        raise typer.Exit(1) from error
    except OSError as error:
        typer.echo(
            f"cannot listen on {ws_host}:{ws_port} ({error.strerror or error}); "
            "another program may use this port: try --ws-port 8781 and start the cockpit "
            "with `-- --bridge=ws://127.0.0.1:8781`.",
            err=True,
        )
        raise typer.Exit(1) from error
    except KeyboardInterrupt:
        typer.echo("Bridge stopped.")


if __name__ == "__main__":  # pragma: no cover
    app()
