// Generated from config/robot.yaml by `openmind-sandbox export-firmware`.
// Do not edit: change robot.yaml (a contract) and regenerate.
#pragma once

namespace openmind {

constexpr const char* kRobotConfigVersion = "1.0.0";
constexpr float kWheelBaseM = 0.13f;  // distance between the wheels, m
constexpr float kWheelDiameterM = 0.065f;  // wheel diameter, m
constexpr float kLengthM = 0.18f;  // body length, m
constexpr float kWidthM = 0.15f;  // body width, m
constexpr float kMaxSpeedMps = 0.25f;  // hard bound on forward speed, m/s
constexpr float kAccelerationMps2 = 0.1f;  // forward acceleration, m/s^2
constexpr float kPivotSpeedDps = 90.0f;  // turning rate of left / right, deg/s
constexpr float kUturnDeg = 180.0f;  // turn made by action, deg
constexpr float kObstacleStopM = 0.2f;  // no forward motion closer than this, m
constexpr float kSensorRangeM = 4.0f;  // distance sensor range, m
constexpr float kStatusTimeoutS = 2.0f;  // stop after this long without status, s
constexpr float kMinConfidence = 0.8f;  // commands below this stop the robot
constexpr float kTelemetryRateHz = 5.0f;  // telemetry events per second

}  // namespace openmind
