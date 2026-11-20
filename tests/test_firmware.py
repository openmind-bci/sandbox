from pathlib import Path

from openmind_sandbox.config import RobotConfig
from openmind_sandbox.firmware import HEADER_PATH, robot_config_header

ROOT = Path(__file__).parents[1]


def test_firmware_header_is_up_to_date() -> None:
    expected = robot_config_header(RobotConfig.load(ROOT / "config" / "robot.yaml"))
    path = ROOT / HEADER_PATH
    assert path.is_file(), "run `openmind-sandbox export-firmware`"
    assert path.read_text(encoding="utf-8") == expected, (
        "robot_config.h is stale: run `openmind-sandbox export-firmware`"
    )


def test_header_carries_the_safety_values() -> None:
    header = robot_config_header(RobotConfig.load(ROOT / "config" / "robot.yaml"))
    assert "constexpr float kObstacleStopM = 0.2f;" in header
    assert "constexpr float kStatusTimeoutS = 2.0f;" in header
    assert "constexpr float kMinConfidenceAction = 0.85f;" in header
    assert 'kRobotConfigVersion = "1.1.0"' in header
