"""Firmware parameters generated from ``config/robot.yaml``.

``openmind-sandbox export-firmware`` writes
``firmware/esp32-robot/include/robot_config.h``; a test checks that the committed
header matches ``robot.yaml``, so that the firmware, the Godot twin and the mock
robot always share the same parameters.
"""

from __future__ import annotations

from pathlib import Path
from typing import Final

from openmind_sandbox.config import RobotConfig

HEADER_PATH: Final = Path("firmware/esp32-robot/include/robot_config.h")


def robot_config_header(config: RobotConfig) -> str:
    """C++ header with the parameters of ``config``."""
    geometry, motion, safety = config.geometry, config.motion, config.safety
    constants = [
        ("kWheelBaseM", geometry.wheel_base_m, "distance between the wheels, m"),
        ("kWheelDiameterM", geometry.wheel_diameter_m, "wheel diameter, m"),
        ("kLengthM", geometry.length_m, "body length, m"),
        ("kWidthM", geometry.width_m, "body width, m"),
        ("kMaxSpeedMps", motion.max_speed_mps, "hard bound on forward speed, m/s"),
        ("kAccelerationMps2", motion.acceleration_mps2, "forward acceleration, m/s^2"),
        ("kPivotSpeedDps", motion.pivot_speed_dps, "turning rate of left / right, deg/s"),
        ("kUturnDeg", motion.uturn_deg, "turn made by action, deg"),
        ("kObstacleStopM", safety.obstacle_stop_m, "no forward motion closer than this, m"),
        ("kSensorRangeM", safety.sensor_range_m, "distance sensor range, m"),
        ("kStatusTimeoutS", safety.status_timeout_s, "stop after this long without status, s"),
        ("kMinConfidence", safety.min_confidence, "commands below this stop the robot"),
        ("kTelemetryRateHz", config.telemetry.rate_hz, "telemetry events per second"),
    ]
    lines = [
        "// Generated from config/robot.yaml by `openmind-sandbox export-firmware`.",
        "// Do not edit: change robot.yaml (a contract) and regenerate.",
        "#pragma once",
        "",
        "namespace openmind {",
        "",
        f'constexpr const char* kRobotConfigVersion = "{config.version}";',
    ]
    for name, value, comment in constants:
        lines.append(f"constexpr float {name} = {float(value)!r}f;  // {comment}")
    lines += ["", "}  // namespace openmind", ""]
    return "\n".join(lines)


def export_firmware_header(root: Path) -> Path:
    """Write the header under ``root``; returns its path."""
    path = root / HEADER_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    config = RobotConfig.load(root / "config" / "robot.yaml")
    path.write_text(robot_config_header(config), encoding="utf-8")
    return path
