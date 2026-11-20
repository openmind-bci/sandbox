"""Apartments of the wheelchair scene (``scenarios/apartments/*.yaml``).

Validated here and exported as JSON for Godot with the courses
(``openmind-sandbox export-godot``).
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

Positive = Annotated[float, Field(gt=0)]
_STRICT = ConfigDict(extra="forbid", frozen=True)


class Size(BaseModel):
    model_config = _STRICT
    width: Positive
    height: Positive


class Start(BaseModel):
    model_config = _STRICT
    x: float
    y: float
    heading_deg: float = 0.0


class Chair(BaseModel):
    """Wheelchair parameters (virtual: this scene drives no real chair)."""

    model_config = _STRICT
    radius_m: Positive
    max_speed_mps: Positive
    acceleration_mps2: Positive
    turn_speed_dps: Positive
    stop_margin_m: Positive
    door_reach_m: Positive
    door_angle_deg: Annotated[float, Field(gt=0, le=90)]
    min_confidence: Annotated[float, Field(ge=0, le=1)]


class Segment(BaseModel):
    model_config = _STRICT
    x1: float
    y1: float
    x2: float
    y2: float

    @model_validator(mode="after")
    def _not_a_point(self) -> Segment:
        if (self.x1, self.y1) == (self.x2, self.y2):
            raise ValueError("a segment needs two distinct ends")
        return self


class Door(Segment):
    id: Annotated[str, Field(pattern=r"^[a-z0-9_]+$")]


class Waypoint(BaseModel):
    model_config = _STRICT
    name: str
    x: float
    y: float
    radius: Positive


class Apartment(BaseModel):
    """An apartment: walls, doors and rooms to reach in order."""

    model_config = _STRICT

    name: Annotated[str, Field(pattern=r"^[a-z0-9_]+$")]
    title: str
    size: Size
    start: Start
    chair: Chair
    walls: list[Segment] = []
    doors: list[Door] = []
    waypoints: Annotated[list[Waypoint], Field(min_length=1)]

    @model_validator(mode="after")
    def _inside(self) -> Apartment:
        points = [("start", self.start.x, self.start.y)]
        points += [(f"waypoints.{i}", w.x, w.y) for i, w in enumerate(self.waypoints)]
        for where, x, y in points:
            if not (0 <= x <= self.size.width and 0 <= y <= self.size.height):
                raise ValueError(f"{where} ({x}, {y}) is outside the apartment")
        ids = [door.id for door in self.doors]
        if len(set(ids)) != len(ids):
            raise ValueError("door ids must be distinct")
        return self

    @classmethod
    def load(cls, path: Path) -> Apartment:
        """Read and validate an apartment file.

        Raises:
            ValueError: If the file is not valid YAML or not a valid apartment.
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
            raise ValueError(f"{path}: invalid apartment: {problems}") from error
