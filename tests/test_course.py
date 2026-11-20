import math
from pathlib import Path

import pytest

from openmind_sandbox.config import RobotConfig
from openmind_sandbox.course import Course, godot_data
from openmind_sandbox.mock_robot import MockRobot

ROOT = Path(__file__).parents[1]
COURSES = sorted((ROOT / "scenarios" / "courses").glob("*.yaml"))


@pytest.mark.parametrize("path", COURSES, ids=lambda p: p.stem)
def test_courses_are_valid(path: Path) -> None:
    course = Course.load(path)
    assert course.name == path.stem


def test_godot_copies_are_up_to_date() -> None:
    for relative, expected in godot_data(ROOT).items():
        path = ROOT / relative
        assert path.is_file(), f"{relative} missing: run `openmind-sandbox export-godot`"
        assert path.read_text(encoding="utf-8") == expected, (
            f"{relative} is stale: run `openmind-sandbox export-godot`"
        )


def test_course_builds_the_mock_robot_world() -> None:
    course = Course.load(ROOT / "scenarios" / "courses" / "twin_default.yaml")
    robot = MockRobot(
        RobotConfig.load(ROOT / "config" / "robot.yaml"),
        world=course.world(),
        pose=course.start_pose(),
    )
    assert robot.pose.heading == pytest.approx(math.radians(course.start.heading_deg))
    assert len(robot.world.obstacles) == len(course.obstacles)


def test_points_outside_the_arena_are_rejected(tmp_path: Path) -> None:
    path = tmp_path / "bad.yaml"
    path.write_text(
        "name: bad\ntitle: t\narena: {width: 1, height: 1}\nstart: {x: 0.5, y: 0.5}\n"
        "waypoints: [{x: 2, y: 0.5, radius: 0.1}]\n"
    )
    with pytest.raises(ValueError, match="outside the arena"):
        Course.load(path)


def test_example_keys_script_completes_the_default_course_with_the_mock_robot() -> None:
    from openmind_protocol import Command, Status

    from openmind_sandbox.keyboard_sim import Script

    course = Course.load(ROOT / "scenarios" / "courses" / "twin_default.yaml")
    script = Script.load(ROOT / "examples" / "keys-twin-course.yaml")
    now = [0.0]
    robot = MockRobot(
        RobotConfig.load(ROOT / "config" / "robot.yaml"),
        world=course.world(),
        pose=course.start_pose(),
        clock=lambda: now[0],
    )
    seq, reached, dt = 0, 0, 0.02
    for step in script.steps:
        for i in range(round(step.duration / dt)):
            if i % 12 == 0:  # status and repeated command at about 4 Hz, like `keys`
                robot.on_status(Status(state="running", model="test", user="P00"))
                robot.on_command(Command(command=step.command, confidence=0.9, user="P00", seq=seq))
                seq += 1
            now[0] += dt
            robot.step()
            if reached < len(course.waypoints):
                target = course.waypoints[reached]
                if math.hypot(robot.pose.x - target.x, robot.pose.y - target.y) <= target.radius:
                    reached += 1
    assert reached == len(course.waypoints)


@pytest.mark.parametrize(
    "path", sorted((ROOT / "scenarios" / "apartments").glob("*.yaml")), ids=lambda p: p.stem
)
def test_apartments_are_valid(path: Path) -> None:
    from openmind_sandbox.apartment import Apartment

    apartment = Apartment.load(path)
    assert apartment.name == path.stem
    assert apartment.doors
