# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `Adapter` with `confirm_action=True`: `rest` no longer cancels an armed
  `action`. The decoder repeats `rest` every 0.5 s between the two gestures, so
  the second `action` could never confirm with a real decoder. Only a movement
  command, a timeout, a lost heartbeat or a stop cancels it; the `rest` reason
  of `action_cancelled` is gone.
- The source distribution ships the adapter template (`template/`): only its
  README was included, so `tests/test_adapters.py` failed when run from the sdist.

### Added

- `dev/run-chain.sh`: starts the broker, a synthetic or replayed EEG source, the
  decoder and the mock robot (or the cockpit gateway) in one command, with logs
  and a `--check` mode that summarises commands, statuses and decoder latency;
  see `docs/full-chain.md`.
- "Live sources" section of `docs/brain-panel.md`: feed the 3D brain from the
  synthetic source or a public replay through `openmind-core bandpower`.
- `openmind-sandbox keys --assistance VALUE | --assistance-ramp SECONDS` and
  `--score-every SECONDS` simulate the calibration feedback of the decoder
  (assistance in `status`, simulated `score`), to test the bird stages and the
  score panel; documented in `docs/keys.md` and `docs/calibration.md`.
- `openmind-sandbox report <events.jsonl> [--json]` summarises the course runs
  of an events log (duration, waypoints, errors, obstacle and safety stops,
  commands, average speed), and `openmind-sandbox bridge --log FILE` records
  the messages as JSON lines. See `docs/report.md`.
- Robot hardware guide `docs/hardware/robot.md`: parts, wiring, flashing and
  the validation procedure of SBX-090.
- Opt-in confirmation of `action` in `Adapter` (`confirm_action`,
  `confirm_window_s`, hook `on_action_armed`, events `action_armed`,
  `action_confirmed`, `action_cancelled`), documented in
  `docs/create-your-object.md`.
- Adapter base class (`openmind_sandbox.adapters.Adapter`) with the protocol
  safety rules built in and not overridable: no command before the first
  status, stop on heartbeat loss, low confidence and stale `seq` ignored,
  contextual `action`. Subclasses only implement `on_command` and `stop`.
- Lamp example adapter driven through a local HTTP API, a fake lamp server,
  and the commands `openmind-sandbox adapter lamp` and `fake-lamp`.
- `template/adapter/` to copy for a new object, and the guide
  `docs/create-your-object.md` (connect your object in 10 minutes).
- README clips of the cockpit in demo mode (animated WebP in `docs/media/`),
  recorded by `tools/record_demo.gd` and encoded by `tools/make_demo_media.py`.
- Demo mode in the cockpit (Start demo, Ctrl+D): a built-in simulated decoder
  sends status, commands and band power without bridge nor headset, so that
  scenes move and the 3D brain shows the areas of each command; it follows the
  calibration cues in the bird scene.
- A neutral mannequin seated in the scanned wheelchair, an 8 m sailing yacht
  at open sea with a buoy slalom, and a textured shrike for the calibration.
- Semi-realistic 3D scenes: robot twin (room, posts, waypoint rings, robot
  built from `robot.yaml`), wheelchair (apartment with swinging doors and
  furniture), calm landscape under the calibration bird, and a new **boat**
  scene (SBX-075: inertia, drift, rudder, anchor, buoys around islands, water
  shader). CC0 textures and skies from Poly Haven (`tools/fetch_polyhaven.py`,
  Git LFS); camera modes on C; 2D minimaps.
- Graphics quality menu: realistic or light (no shadows nor effects, 3D at
  75 %, 30 fps), remembered; the project moves to the Forward+ renderer.
- FreeSurfer fsaverage brain for the 3D panel: `tools/fetch_fsaverage.py`
  downloads it with MNE into `$OPENMIND_DATA_DIR` (never committed) and exports
  a 20,484-vertex mesh; the panel uses it when present, the schematic surface
  otherwise. Faster colouring (sparse weights, at most 20 updates per second).
- ESP32 robot firmware (`firmware/esp32-robot/`, PlatformIO): portable core
  with the protocol parsing, state machine and safety rules, unit-tested on the
  host (`pio test -e native`), and Arduino glue for Wi-Fi, MQTT, TB6612FNG and
  HC-SR04. Parameters in `include/robot_config.h`, generated from
  `robot.yaml` by `openmind-sandbox export-firmware`. See `docs/firmware.md`.
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

- Confidence thresholds per command (`robot.yaml` 1.1.0:
  `safety.min_confidence_per_command`, `action` 0.85 by default). A command
  below its threshold is now **ignored** instead of stopping the object;
  `rest` always stops, whatever its confidence. Applied in the mock robot
  (`--threshold COMMAND=VALUE`), the Godot scenes (one slider per command in
  the command panel, remembered per scene) and the firmware (compiled, never
  changed over the network).
- U-turn of `action`: `rest`, `left` and a repeated `action` no longer affect
  it, `right` cancels it and stops, `forward` interrupts it (mock robot, twin,
  firmware).
- Bird scene: a menu forces the calibration stage; the scene uses the common
  `ObjectController` (with `virtual_scene`).
- Default WebSocket port of the bridge and the cockpit: 8780 instead of 8765,
  a port that many WebSocket examples use and that is often already taken.
- Electrode positions come from the MNE `colin27_1005` template (the new name
  of `standard_1005`, identical positions) when MNE provides it.

### Fixed

- The 3D brain no longer disappears when the panel is resized or clicked, and
  its activity colours are no longer washed out.
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
  MQTT to WebSocket clients (`ws://127.0.0.1:8780`), drops and logs invalid
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
