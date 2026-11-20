"""Guided calibration protocol (``scenarios/calibration_*.yaml``), played by the bird scene.

The protocol is validated here and exported as JSON for Godot with the courses
(``openmind-sandbox export-godot``).
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Final

import yaml
from openmind_protocol import CommandName
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

#: A calibration block must last between these durations (seconds).
BLOCK_RANGE_S: Final = (5 * 60.0, 7 * 60.0)

Positive = Annotated[float, Field(gt=0)]
_STRICT = ConfigDict(extra="forbid", frozen=True)


class Timing(BaseModel):
    """Durations of one trial, in seconds."""

    model_config = _STRICT

    fixation_s: Positive
    cue_s: Positive
    imagery_s: Positive
    rest_min_s: Positive
    rest_max_s: Positive
    break_s: Annotated[float, Field(ge=0)]

    @model_validator(mode="after")
    def _rest_range(self) -> Timing:
        if self.rest_max_s < self.rest_min_s:
            raise ValueError("rest_max_s must be >= rest_min_s")
        return self

    @property
    def mean_trial_s(self) -> float:
        """Mean duration of a trial."""
        rest = (self.rest_min_s + self.rest_max_s) / 2
        return self.fixation_s + self.cue_s + self.imagery_s + rest


class Stage(BaseModel):
    """Learning stage: the instruction shown while assistance is at most ``max_assistance``."""

    model_config = _STRICT

    id: Annotated[str, Field(pattern=r"^[a-z_]+$")]
    title: str
    max_assistance: Annotated[float, Field(ge=0, le=1)]
    instruction: str


class Calibration(BaseModel):
    """A guided calibration protocol."""

    model_config = _STRICT

    name: Annotated[str, Field(pattern=r"^[a-z0-9_]+$")]
    title: str
    classes: Annotated[list[CommandName], Field(min_length=2)]
    trials_per_class: Annotated[int, Field(ge=1)]
    blocks: Annotated[int, Field(ge=1)]
    seed: int | None = None
    timing: Timing
    stages: Annotated[list[Stage], Field(min_length=1)]
    cue_text: dict[CommandName, str]

    @model_validator(mode="after")
    def _consistent(self) -> Calibration:
        if len(set(self.classes)) != len(self.classes):
            raise ValueError("classes must be distinct")
        if "action" in self.classes:
            raise ValueError("action is a jaw clench, not a motor imagery class")
        missing = set(self.classes) - set(self.cue_text)
        if missing:
            raise ValueError(f"cue_text misses {sorted(missing)}")
        levels = [stage.max_assistance for stage in self.stages]
        if levels != sorted(levels, reverse=True):
            raise ValueError("stages must go from most to least assisted")
        return self

    @property
    def block_s(self) -> float:
        """Mean duration of a block, in seconds."""
        return len(self.classes) * self.trials_per_class * self.timing.mean_trial_s

    def check_block_duration(self) -> list[str]:
        """Warnings when a block is outside 5-7 minutes (empty when it is fine)."""
        low, high = BLOCK_RANGE_S
        if low <= self.block_s <= high:
            return []
        return [
            f"{self.name}: blocks last about {self.block_s / 60:.1f} min, "
            f"outside the recommended {low / 60:.0f}-{high / 60:.0f} min"
        ]

    @classmethod
    def load(cls, path: Path) -> Calibration:
        """Read and validate a protocol file.

        Raises:
            ValueError: If the file is not valid YAML or not a valid protocol.
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
            raise ValueError(f"{path}: invalid calibration protocol: {problems}") from error
