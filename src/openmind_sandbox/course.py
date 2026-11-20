"""Courses: arena, obstacles and waypoints shared by the robot twin and the mock robot.

Courses are YAML files in ``scenarios/courses/``. Godot has no YAML parser, so
:func:`export_godot_data` writes JSON copies of the courses and of ``robot.yaml``
into ``godot/data/`` (``openmind-sandbox export-godot``); a test checks that the
committed copies are up to date.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Annotated

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

from openmind_sandbox.config import RobotConfig
from openmind_sandbox.mock_robot import Obstacle, Pose, World

Positive = Annotated[float, Field(gt=0)]
_STRICT = ConfigDict(extra="forbid", frozen=True)


class Arena(BaseModel):
    model_config = _STRICT
    width: Positive
    height: Positive


class Start(BaseModel):
    model_config = _STRICT
    x: float
    y: float
    heading_deg: float = 90.0


class Circle(BaseModel):
    model_config = _STRICT
    x: float
    y: float
    radius: Positive


class Course(BaseModel):
    """A course: the robot starts at ``start`` and visits ``waypoints`` in order."""

    model_config = _STRICT

    name: Annotated[str, Field(pattern=r"^[a-z0-9_]+$")]
    title: str
    arena: Arena
    start: Start
    obstacles: list[Circle] = []
    waypoints: Annotated[list[Circle], Field(min_length=1)]

    @model_validator(mode="after")
    def _inside_arena(self) -> Course:
        points = [("start", self.start.x, self.start.y)]
        points += [(f"waypoints.{i}", w.x, w.y) for i, w in enumerate(self.waypoints)]
        points += [(f"obstacles.{i}", o.x, o.y) for i, o in enumerate(self.obstacles)]
        for where, x, y in points:
            if not (0 <= x <= self.arena.width and 0 <= y <= self.arena.height):
                raise ValueError(f"{where} ({x}, {y}) is outside the arena")
        return self

    @classmethod
    def load(cls, path: Path) -> Course:
        """Read and validate a course file.

        Raises:
            ValueError: If the file is not valid YAML or not a valid course.
        """
        try:
            return cls.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))
        except yaml.YAMLError as error:
            raise ValueError(f"{path}: not valid YAML ({error})") from error
        except ValidationError as error:
            problems = "; ".join(
                f"{'.'.join(str(p) for p in e['loc']) or '(root)'}: {e['msg']}"
                for e in error.errors()
            )
            raise ValueError(f"{path}: invalid course: {problems}") from error

    def world(self) -> World:
        """Arena and obstacles for the mock robot."""
        return World(
            width=self.arena.width,
            height=self.arena.height,
            obstacles=tuple(Obstacle(o.x, o.y, o.radius) for o in self.obstacles),
        )

    def start_pose(self) -> Pose:
        """Starting pose for the mock robot."""
        return Pose(self.start.x, self.start.y, math.radians(self.start.heading_deg))


def export_godot_data(root: Path) -> list[Path]:
    """Write ``godot/data/robot.json`` and ``godot/data/courses/*.json`` under ``root``.

    Returns the written files.
    """
    written: list[Path] = []
    for relative, content in godot_data(root).items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        written.append(path)
    return written


def godot_data(root: Path) -> dict[str, str]:
    """Expected content of the generated files, by path relative to ``root``."""
    expected = {
        "godot/data/robot.json": _dumps(
            RobotConfig.load(root / "config" / "robot.yaml").model_dump(mode="json")
        )
    }
    for source in sorted((root / "scenarios" / "courses").glob("*.yaml")):
        course = Course.load(source)
        expected[f"godot/data/courses/{course.name}.json"] = _dumps(course.model_dump(mode="json"))
    return expected


def _dumps(document: object) -> str:
    header = {"_generated": "by `openmind-sandbox export-godot`; do not edit"}
    if isinstance(document, dict):
        document = {**header, **document}
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"
