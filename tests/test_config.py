from pathlib import Path

import pytest
import yaml

from openmind_sandbox.config import RobotConfig, default_robot_config

ROBOT_YAML = Path(__file__).parents[1] / "config" / "robot.yaml"


def test_repository_robot_yaml_is_valid() -> None:
    config = RobotConfig.load(ROBOT_YAML)
    assert config.safety.obstacle_stop_m == 0.20
    assert config.safety.status_timeout_s == 2.0
    assert 0 < config.safety.min_confidence <= 1


def test_default_path_finds_the_repository_copy() -> None:
    assert default_robot_config().resolve() == ROBOT_YAML.resolve()


def edited(tmp_path: Path, section: str, key: str, value: object) -> Path:
    document = yaml.safe_load(ROBOT_YAML.read_text())
    if section:
        document[section][key] = value
    else:
        document[key] = value
    path = tmp_path / "robot.yaml"
    path.write_text(yaml.safe_dump(document))
    return path


@pytest.mark.parametrize(
    ("section", "key", "value", "match"),
    [
        ("", "version", "2.0.0", "not supported"),
        ("", "version", "1.0", "MAJOR.MINOR.PATCH"),
        ("motion", "max_speed_mps", 0, "max_speed_mps"),
        ("safety", "status_timeout_s", 3.0, "status_timeout_s"),
        ("safety", "min_confidence", 1.5, "min_confidence"),
        ("safety", "unknown_key", 1, "unknown_key"),
    ],
)
def test_invalid_configurations_are_rejected(
    tmp_path: Path, section: str, key: str, value: object, match: str
) -> None:
    with pytest.raises(ValueError, match=match):
        RobotConfig.load(edited(tmp_path, section, key, value))
