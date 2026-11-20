# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Gateway `openmind-sandbox bridge`: relays every valid protocol message from
  MQTT to WebSocket clients (`ws://127.0.0.1:8765`), drops and logs invalid
  ones, accepts markers and events from clients (validated, `v` and `ts`
  filled in), publishes them on MQTT and pushes markers on the LSL stream
  `openmind-markers` (back-dated by their transit delay). Clients are told
  when the broker link is lost. See `docs/bridge.md`.
- `config/robot.yaml` 1.0.0: kinematics and safety parameters shared by the
  firmware, the Godot twin and the mock robot, validated by `RobotConfig`
  (unknown keys and other major versions refused). See `docs/robot-config.md`.
- Mock robot `openmind-sandbox mock-robot`: 2D differential-drive kinematics,
  simulated distance sensor in an arena with obstacles, the firmware state
  machine (`STOPPED`, `MOVING`, `PIVOTING`, `SAFETY_STOP`) and its safety rules
  (stop without status, on low confidence, on invalid messages or lost broker,
  before obstacles), telemetry and state events on `openmind/v1/events`, live
  text view. See `docs/objects.md`.
- Keyboard command simulator `openmind-sandbox keys`: held arrows give
  `left` / `right` / `forward`, space one `action`, no key `rest`, adjustable
  confidence; `running` status at 4 Hz; script mode replaying commands from
  YAML (`examples/keys-demo.yaml`); fake `bandpower` messages at 10 Hz
  (`--bandpower`) with a desynchronization over C4, C3 or Cz. Every message is
  validated against `openmind-protocol`. See `docs/keys.md`.
- `MqttLink`: MQTT connection publishing validated protocol messages.
- Repository skeleton: `openmind-sandbox` package and command, dependency on
  `openmind-protocol` 1.0.1 (from the core repository), lint, typing and tests,
  CI, Git LFS rules for heavy assets.
- Local Mosquitto broker for development (`dev/docker-compose.yml`, MQTT on
  1883 and WebSocket on 9001, anonymous access, development only).
