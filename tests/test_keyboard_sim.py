"""Acceptance of SBX-010: every simulated message conforms to the protocol."""

from pathlib import Path

import pytest
from openmind_protocol import BandPower, Command, Message, Status, decode_topic, encode, topic_of

from openmind_sandbox.keyboard_sim import (
    DEFAULT_CHANNELS,
    CommandSimulator,
    FakeBandPower,
    HoldTracker,
    Script,
    ScriptPlayer,
    motor_weight,
)

EXAMPLE_SCRIPT = Path(__file__).parents[1] / "examples" / "keys-demo.yaml"


def roundtrip(message: Message) -> Message:
    """Encode (schema-checked) and decode as a subscriber would."""
    return decode_topic(topic_of(message), encode(message))


def run(simulator: CommandSimulator, until: float, step: float = 0.02) -> list[Message]:
    messages: list[Message] = []
    t = 0.0
    while t <= until:
        messages.extend(simulator.poll(t))
        t += step
    return messages


# --- HoldTracker ---------------------------------------------------------------


def test_hold_tracker_falls_back_to_rest_after_the_hold_window() -> None:
    tracker = HoldTracker(hold=0.5)
    assert tracker.command(0.0) == "rest"
    tracker.press("left", 1.0)
    assert tracker.command(1.4) == "left"
    tracker.press("left", 1.4)  # auto-repeat keeps it held
    assert tracker.command(1.8) == "left"
    assert tracker.command(1.95) == "rest"


def test_latched_tracker_keeps_the_command() -> None:
    tracker = HoldTracker(latch=True)
    tracker.press("forward", 0.0)
    assert tracker.command(100.0) == "forward"
    tracker.press("rest", 100.0)
    assert tracker.command(100.1) == "rest"


# --- CommandSimulator ----------------------------------------------------------


def test_status_is_published_at_least_at_2_hz() -> None:
    messages = run(CommandSimulator(), until=10.0)
    status_count = sum(isinstance(m, Status) for m in messages)
    assert status_count >= 2 * 10
    assert all(m.state == "running" for m in messages if isinstance(m, Status))


def test_commands_follow_the_intent_with_increasing_seq() -> None:
    simulator = CommandSimulator(repeat_period=10.0)
    first = simulator.poll(0.0)
    simulator.intent = "left"
    second = simulator.poll(0.05)
    commands = [m for m in first + second if isinstance(m, Command)]
    assert [c.command for c in commands] == ["rest", "left"]
    assert [c.seq for c in commands] == [0, 1]


def test_unchanged_command_is_repeated_at_the_repeat_period() -> None:
    simulator = CommandSimulator(repeat_period=0.25)
    simulator.intent = "forward"
    commands = [m for m in run(simulator, until=1.0) if isinstance(m, Command)]
    assert 4 <= len(commands) <= 6
    assert {c.command for c in commands} == {"forward"}


def test_action_is_sent_once_with_a_refractory_time() -> None:
    simulator = CommandSimulator(action_refractory=0.6)
    simulator.poll(0.0)
    assert simulator.trigger_action(1.0)
    assert not simulator.trigger_action(1.3)  # space bar auto-repeat
    commands = [m for m in simulator.poll(1.3) if isinstance(m, Command)]
    assert [c.command for c in commands] == ["action"]
    assert [m.command for m in simulator.poll(1.31) if isinstance(m, Command)] == ["rest"]


def test_confidence_is_clamped() -> None:
    simulator = CommandSimulator(confidence=0.98)
    simulator.confidence += 0.05
    assert simulator.confidence == 1.0
    simulator.confidence = -0.2
    assert simulator.confidence == 0.0


def test_status_period_must_honour_the_2_hz_heartbeat() -> None:
    with pytest.raises(ValueError, match="2 Hz"):
        CommandSimulator(status_period=0.6)


def test_every_simulated_message_conforms_to_the_protocol() -> None:
    simulator = CommandSimulator(user="P07", confidence=0.83)
    messages: list[Message] = []
    for t, intent in [(0.0, "rest"), (0.3, "left"), (0.6, "right"), (0.9, "forward")]:
        simulator.intent = intent  # type: ignore[assignment]
        messages.extend(simulator.poll(t))
    simulator.trigger_action(1.2)
    messages.extend(simulator.poll(1.2))
    assert {m.command for m in messages if isinstance(m, Command)} == {
        "rest",
        "left",
        "right",
        "forward",
        "action",
    }
    for message in messages:
        assert roundtrip(message) == message


# --- Scripts -------------------------------------------------------------------


def test_example_script_is_valid() -> None:
    script = Script.load(EXAMPLE_SCRIPT)
    assert script.duration > 0
    assert script.user == "P00"


def test_script_steps_and_loop() -> None:
    script = Script.model_validate(
        {
            "loop": True,
            "steps": [{"command": "left", "duration": 1}, {"command": "right", "duration": 2}],
        }
    )
    assert script.step_at(0.5)[1].command == "left"  # type: ignore[index]
    assert script.step_at(2.0)[1].command == "right"  # type: ignore[index]
    assert script.step_at(3.5)[1].command == "left"  # type: ignore[index]


def test_script_player_replays_commands_then_stops() -> None:
    script = Script.model_validate(
        {
            "steps": [
                {"command": "forward", "duration": 1, "confidence": 0.7},
                {"command": "action", "duration": 1},
            ]
        }
    )
    simulator = CommandSimulator(confidence=0.9)
    player = ScriptPlayer(script, simulator, start=0.0)
    sent: list[Command] = []
    t = 0.0
    while player.update(t):
        sent.extend(m for m in simulator.poll(t) if isinstance(m, Command))
        t += 0.02
    assert sent[0].command == "forward"
    assert sent[0].confidence == 0.7
    assert [c.command for c in sent].count("action") == 1
    assert sent[-1].command == "rest"
    assert simulator.intent == "rest"


@pytest.mark.parametrize(
    ("text", "match"),
    [
        ("steps: []", "steps"),
        ("steps: [{command: jump, duration: 1}]", "command"),
        ("steps: [{command: left, duration: 0}]", "duration"),
        ("user: Alice\nsteps: [{command: left, duration: 1}]", "user"),
        ("steps: [", "YAML"),
    ],
)
def test_invalid_scripts_are_rejected(tmp_path: Path, text: str, match: str) -> None:
    path = tmp_path / "bad.yaml"
    path.write_text(text)
    with pytest.raises(ValueError, match=match):
        Script.load(path)


# --- Fake band power -----------------------------------------------------------


@pytest.mark.parametrize(
    ("command", "strongest"),
    [("left", "C4"), ("right", "C3"), ("forward", "Cz")],
)
def test_desynchronization_is_strongest_over_the_expected_electrode(
    command: str, strongest: str
) -> None:
    fake = FakeBandPower(seed=1, noise=0.0)
    message = fake.step("rest", 0.0)
    for i in range(1, 40):
        message = fake.step(command, i * 0.1)  # type: ignore[arg-type]
    rel_mu = {c.label: c.rel_mu for c in message.channels}
    assert min(rel_mu, key=lambda label: rel_mu[label] or 0.0) in {strongest}
    assert rel_mu[strongest] == pytest.approx(-0.45, abs=0.02)


def test_motor_weights() -> None:
    assert motor_weight("C4", "left") == 1.0
    assert motor_weight("C3", "left") == 0.0
    assert motor_weight("FC3", "right") == 0.6
    assert motor_weight("CPz", "forward") == 0.6
    assert motor_weight("Cz", "left") == 0.0
    assert motor_weight("O1", "right") == 0.0
    assert motor_weight("C4", "rest") == 0.0


def test_jaw_clench_raises_beta_everywhere() -> None:
    fake = FakeBandPower(seed=1, noise=0.0)
    fake.step("rest", 0.0)
    message = fake.step("action", 5.0)
    assert all((c.rel_beta or 0) > 1.0 for c in message.channels)


def test_rest_stays_near_baseline_and_transitions_are_smooth() -> None:
    fake = FakeBandPower(seed=3)
    fake.step("rest", 0.0)
    first = fake.step("left", 0.1).channel("C4").rel_mu
    assert first is not None
    assert -0.2 < first < 0.1  # one step of 0.1 s with tau 0.4 s: partial change


def test_bad_channels_are_reported_as_not_ok() -> None:
    fake = FakeBandPower(bad_channels=["CPz"], seed=0)
    entry = fake.step("forward", 0.0).channel("CPz")
    assert not entry.ok
    assert entry.mu is None
    with pytest.raises(ValueError, match="not in the montage"):
        FakeBandPower(bad_channels=["Fp1"])


def test_seeded_band_power_is_reproducible() -> None:
    a = [FakeBandPower(seed=5).step("left", t * 0.1) for t in range(3)]
    b = [FakeBandPower(seed=5).step("left", t * 0.1) for t in range(3)]
    assert [m.channels for m in a] == [m.channels for m in b]


@pytest.mark.parametrize("command", ["rest", "left", "right", "forward", "action"])
def test_band_power_messages_conform_to_the_protocol(command: str) -> None:
    fake = FakeBandPower(user="P03", bad_channels=["FC4"], seed=2)
    for i in range(5):
        message = fake.step(command, i * 0.1)  # type: ignore[arg-type]
        decoded = roundtrip(message)
        assert isinstance(decoded, BandPower)
        assert [c.label for c in decoded.channels] == list(DEFAULT_CHANNELS)
