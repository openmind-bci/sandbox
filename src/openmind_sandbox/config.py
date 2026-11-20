"""Robot configuration (``config/robot.yaml``), the contract shared by every robot.

The firmware, the Godot twin and the mock robot read the same parameters. The
file carries a SemVer ``version``; this package reads major version 1.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Final

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

#: Major version of ``robot.yaml`` read by this package.
SUPPORTED_MAJOR: Final = 1

Positive = Annotated[float, Field(gt=0)]

_STRICT = ConfigDict(extra="forbid", frozen=True)


class Geometry(BaseModel):
    """Physical size of the robot, in metres."""

    model_config = _STRICT

    wheel_base_m: Positive
    wheel_diameter_m: Positive
    length_m: Positive
    width_m: Positive


class Motion(BaseModel):
    """Speeds and accelerations."""

    model_config = _STRICT

    max_speed_mps: Positive
    acceleration_mps2: Positive
    pivot_speed_dps: Positive
    uturn_deg: Positive


class Safety(BaseModel):
    """Safety thresholds; every robot must apply them."""

    model_config = _STRICT

    obstacle_stop_m: Positive
    sensor_range_m: Positive
    status_timeout_s: Annotated[float, Field(gt=0, le=2.0)]
    min_confidence: Annotated[float, Field(ge=0, le=1)]


class Telemetry(BaseModel):
    """Telemetry publication."""

    model_config = _STRICT

    rate_hz: Annotated[float, Field(gt=0, le=50)]


class RobotConfig(BaseModel):
    """Content of ``robot.yaml``."""

    model_config = _STRICT

    version: str
    geometry: Geometry
    motion: Motion
    safety: Safety
    telemetry: Telemetry

    @field_validator("version")
    @classmethod
    def _supported_version(cls, value: str) -> str:
        parts = value.split(".")
        if len(parts) != 3 or not all(part.isdigit() for part in parts):
            raise ValueError(f"version {value!r} is not MAJOR.MINOR.PATCH")
        if int(parts[0]) != SUPPORTED_MAJOR:
            raise ValueError(f"version {value} is not supported, expected {SUPPORTED_MAJOR}.x.y")
        return value

    @classmethod
    def load(cls, path: Path | None = None) -> RobotConfig:
        """Read and validate ``path`` (default: :func:`default_robot_config`).

        Raises:
            FileNotFoundError: If the file does not exist.
            ValueError: If it is not valid YAML or breaks the schema; the message
                names each faulty key.
        """
        path = path or default_robot_config()
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
            raise ValueError(f"{path}: invalid robot configuration: {problems}") from error


def default_robot_config() -> Path:
    """Path of the ``robot.yaml`` used when none is given.

    ``config/robot.yaml`` in the current directory first (a checkout of the
    repository), then the copy installed with the package.
    """
    local = Path("config") / "robot.yaml"
    if local.is_file():
        return local
    packaged = Path(__file__).parent / "data" / "robot.yaml"
    if packaged.is_file():
        return packaged
    return Path(__file__).parents[2] / "config" / "robot.yaml"
