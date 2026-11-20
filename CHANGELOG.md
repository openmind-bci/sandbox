# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `tools/check_topomap.py`: MNE topographic map of the band power messages,
  live or saved once to an image, with the colours of the 3D panel and the
  lowest electrode printed, to cross-check the 3D brain.
- Signal panel: scrolling EEG channels (5 or 10 s window, adjustable scale,
  flat and saturated channels flagged), fed by `bridge --eeg`, which relays the
  LSL `openmind-eeg` stream read-only in compact frames of at most 1 s.
- Live 3D brain panel: band power messages coloured at the sensors on a
  procedural brain surface (Gaussian distance weighting, diverging blue /
  orange scale for `rel_mu` or `rel_beta`, grey for electrodes not OK, smooth
  transitions), mouse rotation, top / left / right views, electrode names,
  explicit "not a source localisation" legend. 10-10 positions in
  `godot/data/electrodes_10_10.json`, generated from MNE by
  `tools/generate_electrodes.py`. See `docs/brain-panel.md`.
- Wheelchair scene: apartment from `scenarios/apartments/` (validated,
  exported for Godot), turn in place, drive, stop at once on `rest`, `action`
  opens the closed door in front and is ignored elsewhere, stop margin before
  walls and doors, timed waypoints, events on `openmind/v1/events`
  (`wheelchair`). `examples/keys-wheelchair.yaml` completes the default run.
- Bird scene: guided motor imagery calibration from
  `scenarios/calibration_default.yaml` (fixation 2 s, cue 1 s, imagery 4 s,
  random rest 1.5-3 s, balanced shuffled classes, blocks of about 6 min),
  markers `trial_start` / `cue` / `trial_end` and block events through the
  bridge to MQTT and LSL, bird centred while the scenery moves, assistance and
  stages (discovery, transition, thought), match share and score display.
  See `docs/calibration.md`.
- `OpenMind.feedback_alive()` (a `calibrating` decoder also counts, for virtual
  scenes only) and `OpenMind.assistance()`.
- Robot twin scene in the cockpit: robot of `robot.yaml` on a waypoint course,
  same kinematics, state machine and obstacle stop as the mock robot, timer,
  errors and collisions avoided, events on `openmind/v1/events`
  (`robot-twin`: telemetry, state, start, waypoint, finish).
- Courses in `scenarios/courses/` (YAML, validated), `mock-robot --course`,
  and `openmind-sandbox export-godot` writing JSON copies of `robot.yaml` and
  the courses for Godot (a test checks they are up to date).

### Changed

- Electrode positions come from the MNE `colin27_1005` template (the new name
  of `standard_1005`, identical positions) when MNE provides it.

### Fixed

- Mock robot: a robot stopped exactly at the obstacle stop distance is reported
  as `SAFETY_STOP` (`obstacle`) instead of `MOVING` at zero speed.
- Godot 4.5 cockpit (`godot/`): `OpenMind` autoload (WebSocket link to the
  bridge with automatic reconnection, signals for every message kind, decoder
  heartbeat, `send_marker` and `send_event`), `ObjectController` with the
  common safety rules per scene, main window with menus, collapsible panels
  (command, progress, connection; 3D brain and signal reserved), scene
  switching without restart, placeholder scenes, theme with the logo colors
  and Space Grotesk, keyboard shortcuts. Headless tests run in CI.
  See `docs/cockpit.md`.
- `bridge`: clear message when the WebSocket port is already taken.
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
