from pathlib import Path

import pytest
import yaml

from openmind_sandbox.calibration import Calibration

ROOT = Path(__file__).parents[1]
DEFAULT = ROOT / "scenarios" / "calibration_default.yaml"


def test_default_protocol_follows_the_specification() -> None:
    protocol = Calibration.load(DEFAULT)
    timing = protocol.timing
    assert (timing.fixation_s, timing.cue_s, timing.imagery_s) == (2.0, 1.0, 4.0)
    assert (timing.rest_min_s, timing.rest_max_s) == (1.5, 3.0)
    assert protocol.check_block_duration() == []  # 5 to 7 minutes
    assert [s.id for s in protocol.stages] == ["discovery", "transition", "thought"]


def edited(tmp_path: Path, **changes: object) -> Path:
    document = yaml.safe_load(DEFAULT.read_text())
    document.update(changes)
    path = tmp_path / "protocol.yaml"
    path.write_text(yaml.safe_dump(document))
    return path


@pytest.mark.parametrize(
    ("changes", "match"),
    [
        ({"classes": ["left", "left"]}, "distinct"),
        ({"classes": ["left", "action"]}, "jaw clench"),
        ({"classes": ["left", "jump"]}, "classes"),
        ({"cue_text": {"left": "L"}}, "cue_text"),
        ({"trials_per_class": 0}, "trials_per_class"),
    ],
)
def test_invalid_protocols_are_rejected(
    tmp_path: Path, changes: dict[str, object], match: str
) -> None:
    with pytest.raises(ValueError, match=match):
        Calibration.load(edited(tmp_path, **changes))


def test_short_blocks_are_reported(tmp_path: Path) -> None:
    protocol = Calibration.load(edited(tmp_path, trials_per_class=2))
    assert "outside the recommended" in protocol.check_block_duration()[0]
