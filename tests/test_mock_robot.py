"""Acceptance of SBX-020: the safety rules of the mock robot."""

from __future__ import annotations

import math
from pathlib import Path

import pytest
from openmind_protocol import Command, CommandName, Event, Status, decode_topic, encode, topic_of

from openmind_sandbox.config import RobotConfig
from openmind_sandbox.mock_robot import MockRobot, Obstacle, Pose, RobotState, World, format_line

CONFIG = RobotConfig.load(Path(__file__).parents[1] / "config" / "robot.yaml")
EMPTY = World(width=10.0, height=10.0, obstacles=())
DT = 0.02


class Clock:
    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


class Harness:
    """A robot with a fake clock, a fake decoder and a running status."""

    def __init__(self, world: World = EMPTY, pose: Pose | None = None) -> None:
        self.clock = Clock()
        self.robot = MockRobot(CONFIG, world=world, pose=pose or Pose(5, 5, 0.0), clock=self.clock)
        self.seq = 0
        self.robot.step()

    def status(self, state: str = "running") -> None:
        self.robot.on_status(Status(state=state, model="test", user="P00"))  # type: ignore[arg-type]

    def command(self, name: CommandName, confidence: float = 0.95) -> None:
        self.robot.on_command(
            Command(command=name, confidence=confidence, user="P00", seq=self.seq)
        )
        self.seq += 1

    def run(
        self, seconds: float, heartbeat: bool = True, repeat: CommandName | None = None
    ) -> None:
        steps = round(seconds / DT)
        for i in range(steps):
            self.clock.now += DT
            if heartbeat and i % 12 == 0:  # about 4 Hz
                self.status()
            if repeat is not None and i % 12 == 0:
                self.command(repeat)
            self.robot.step()


# --- Heartbeat ---------------------------------------------------------------


def test_robot_does_not_move_before_the_first_status() -> None:
    h = Harness()
    h.command("forward")
    h.run(1.0, heartbeat=False)
    assert h.robot.state is RobotState.SAFETY_STOP
    assert h.robot.reason == "no_status"
    assert h.robot.pose.x == 5


def test_robot_stops_when_the_status_stops() -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(1.0)
    assert h.robot.state is RobotState.MOVING
    h.run(CONFIG.safety.status_timeout_s - 0.3, heartbeat=False)
    assert h.robot.state is RobotState.MOVING  # still within the timeout
    h.run(0.5, heartbeat=False)
    assert h.robot.state is RobotState.SAFETY_STOP
    assert h.robot.reason == "no_status"
    assert h.robot.speed == 0
    x = h.robot.pose.x
    h.run(1.0, heartbeat=False)
    assert h.robot.pose.x == x


def test_robot_needs_a_new_command_after_the_decoder_returns() -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(0.5)
    h.run(2.5, heartbeat=False)
    h.status()
    h.run(0.5)
    assert h.robot.state is RobotState.STOPPED
    assert h.robot.command == "rest"


def test_restarted_decoder_seq_is_accepted_after_a_silence() -> None:
    h = Harness()
    h.status()
    h.seq = 50
    h.command("left")
    h.run(2.5, heartbeat=False)
    h.status()
    h.seq = 0  # the decoder restarted
    h.command("forward")
    h.run(0.2)
    assert h.robot.state is RobotState.MOVING


@pytest.mark.parametrize("state", ["idle", "calibrating", "degraded"])
def test_non_running_status_stops_immediately(state: str) -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(0.5)
    h.status(state)
    h.robot.step()
    assert h.robot.state is RobotState.SAFETY_STOP
    assert h.robot.reason == f"decoder_{state}"
    h.command("forward")
    h.run(0.3, heartbeat=False)
    assert h.robot.speed == 0


# --- Confidence and order ----------------------------------------------------


def test_low_confidence_command_stops_the_robot() -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(1.0)
    assert h.robot.speed > 0
    h.command("forward", confidence=CONFIG.safety.min_confidence - 0.01)
    h.run(DT)
    assert h.robot.state is RobotState.STOPPED
    assert h.robot.reason == "low_confidence"
    assert h.robot.speed == 0


def test_valid_command_after_a_low_confidence_stop_is_reported() -> None:
    h = Harness()
    h.status()
    h.command("forward", confidence=0.1)
    h.run(0.1)
    h.robot.pop_transitions()
    h.command("rest")
    h.run(0.1)
    assert h.robot.pop_transitions() == [(RobotState.STOPPED, None)]


def test_command_at_the_threshold_is_applied() -> None:
    h = Harness()
    h.status()
    h.command("left", confidence=CONFIG.safety.min_confidence)
    h.run(0.1)
    assert h.robot.state is RobotState.PIVOTING


def test_stale_commands_are_ignored() -> None:
    h = Harness()
    h.status()
    h.seq = 10
    h.command("forward")
    h.seq = 5
    h.command("rest")  # out of order
    h.run(0.2)
    assert h.robot.state is RobotState.MOVING


# --- Fail safe ---------------------------------------------------------------


@pytest.mark.parametrize("reason", ["invalid_message", "disconnected"])
def test_faults_stop_until_the_next_running_status(reason: str) -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(0.5)
    h.robot.on_fault(reason)
    h.command("forward")
    h.robot.step()
    assert h.robot.state is RobotState.SAFETY_STOP
    assert h.robot.reason == reason
    h.status()
    h.command("forward")
    h.run(0.2)
    assert h.robot.state is RobotState.MOVING


# --- Obstacle ----------------------------------------------------------------


def test_robot_stops_before_an_obstacle() -> None:
    world = World(width=10, height=10, obstacles=[Obstacle(6.0, 5.0, 0.1)])
    h = Harness(world=world)
    h.status()
    h.command("forward")
    h.run(20.0, repeat="forward")
    assert h.robot.state is RobotState.SAFETY_STOP
    assert h.robot.reason == "obstacle"
    assert h.robot.speed == 0
    assert h.robot.obstacle is not None
    assert h.robot.obstacle == pytest.approx(CONFIG.safety.obstacle_stop_m, abs=0.01)
    assert h.robot.obstacle >= CONFIG.safety.obstacle_stop_m - 1e-9


def test_robot_can_pivot_away_from_an_obstacle_then_drive() -> None:
    world = World(width=10, height=10, obstacles=[Obstacle(6.0, 5.0, 0.1)])
    h = Harness(world=world)
    h.status()
    h.command("forward")
    h.run(20.0)
    h.command("left")
    h.run(1.0)  # 90° at 90°/s
    assert h.robot.state is RobotState.PIVOTING
    h.command("forward")
    h.run(1.0)
    assert h.robot.state is RobotState.MOVING


def test_robot_stops_before_a_wall() -> None:
    h = Harness(world=World(width=2, height=2, obstacles=()), pose=Pose(1, 1, 0.0))
    h.status()
    h.command("forward")
    h.run(20.0)
    assert h.robot.reason == "obstacle"
    front = h.robot.pose.x + CONFIG.geometry.length_m / 2
    assert 2 - front == pytest.approx(CONFIG.safety.obstacle_stop_m, abs=0.01)


def test_distance_ahead() -> None:
    world = World(width=4, height=4, obstacles=[Obstacle(3, 2, 0.5)])
    assert world.distance_ahead(1, 2, 0.0) == pytest.approx(1.5)
    assert world.distance_ahead(1, 2, math.pi) == pytest.approx(1.0)
    assert world.distance_ahead(1, 2, math.pi / 2) == pytest.approx(2.0)


def test_far_obstacles_are_out_of_sensor_range() -> None:
    h = Harness(world=World(width=20, height=20, obstacles=()), pose=Pose(1, 10, 0.0))
    assert h.robot.obstacle is None


# --- Kinematics --------------------------------------------------------------


def test_forward_accelerates_up_to_the_max_speed() -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(1.0)
    assert h.robot.speed == pytest.approx(CONFIG.motion.acceleration_mps2 * 1.0, rel=0.05)
    h.run(10.0)
    assert h.robot.speed == CONFIG.motion.max_speed_mps


def test_pivot_turns_in_place_at_the_configured_rate() -> None:
    h = Harness()
    h.status()
    h.command("left")
    h.run(1.0)
    assert math.degrees(h.robot.pose.heading) == pytest.approx(CONFIG.motion.pivot_speed_dps, 0.05)
    assert (h.robot.pose.x, h.robot.pose.y) == (5, 5)
    h.command("right")
    h.run(1.0)
    assert h.robot.pose.heading == pytest.approx(0.0, abs=0.05)


def test_rest_stops() -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(1.0)
    h.command("rest")
    h.run(DT)
    assert h.robot.state is RobotState.STOPPED
    assert h.robot.speed == 0


def test_action_makes_a_u_turn_that_rest_does_not_cut() -> None:
    h = Harness()
    h.status()
    h.command("action")
    h.run(0.1)
    h.command("rest")  # what a decoder sends right after the gesture
    h.run(3.0)
    assert h.robot.state is RobotState.STOPPED
    assert abs(h.robot.pose.heading) == pytest.approx(math.pi, abs=1e-6)


def test_movement_command_interrupts_a_u_turn() -> None:
    h = Harness()
    h.status()
    h.command("action")
    h.run(0.5)
    h.command("forward")
    h.run(0.2)
    assert h.robot.state is RobotState.MOVING


# --- Telemetry ---------------------------------------------------------------


def test_telemetry_and_state_events_conform_to_the_protocol() -> None:
    h = Harness()
    h.status()
    h.command("forward")
    h.run(0.5)
    events: list[Event] = [h.robot.telemetry_event()]
    events += [h.robot.state_event(s, r) for s, r in h.robot.pop_transitions()]
    assert any(e.kind == "state" and e.data["state"] == "MOVING" for e in events)
    for event in events:
        assert decode_topic(topic_of(event), encode(event)) == event
    data = events[0].data
    assert set(data) == {
        "x_m", "y_m", "heading_deg", "speed_mps", "turn_dps", "obstacle_m", "state", "reason",
        "command",
    }  # fmt: skip
    assert "MOVING" in format_line(data)
