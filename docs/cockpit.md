# Godot cockpit

`godot/` is a single [Godot 4.5](https://godotengine.org) application: the
cockpit from which every object scene is driven.

```
┌ Profile · Calibration · Objects · Settings ────────────────────────────┐
│                                              │ ▾ 3D brain              │
│                                              │ ▾ Signal                │
│        object scene (SubViewport)            │ ▾ Command  forward 0.92 │
│        robot twin, bird, wheelchair, boat    │ ▾ Progress              │
│                                              │ ▾ Connection            │
└──────────────────────────────────────────────┴─────────────────────────┘
```

## Run it

1. Start the broker, the bridge and a command source:

   ```bash
   docker compose -f dev/docker-compose.yml up -d
   uv run openmind-sandbox bridge
   uv run openmind-sandbox keys            # or OpenMind Core
   ```

2. Open `godot/project.godot` in Godot 4.5 and press F5, or run
   `godot --path godot`.

The cockpit connects to `ws://127.0.0.1:8780` and reconnects on its own. If that
port is taken on your machine, start the bridge with `--ws-port 8781` and give the
same address to the cockpit, either on the command line or in the environment:

```bash
godot --path godot -- --bridge=ws://127.0.0.1:8781
OPENMIND_BRIDGE_URL=ws://127.0.0.1:8781 godot --path godot
```

or from **Settings → Bridge address…** while it runs.

## Demo mode

**Start demo** in the command panel (or **Settings → Demo mode**, Ctrl+D) runs a
simulated decoder inside the cockpit: no bridge, no broker, no headset. It sends
a running status, commands in a loop (rest, left, rest, right, rest, forward,
action) and band power on the eight motor electrodes of montage C, so that the
scenes move and the 3D brain lights up: left turns the area of C4 blue, right
the area of C3, forward Cz / CPz, and action raises beta everywhere (orange). In
the bird scene the demo follows the calibration cues, like a perfect user. Stop
it with the same button: the status stops and objects stop within 2 s.

## Scenes and graphics

The four scenes are drawn in 3D, semi-realistic, with CC0 textures and skies from
Poly Haven (see `ASSETS.md`); a small 2D map stays in the corner. Shared helpers
are in `addons/openmind/world_kit.gd`.

| Scene | 3D view | C (camera) |
|---|---|---|
| Robot twin | room with concrete floor and plaster walls, wooden posts, glowing waypoint rings, robot built from `robot.yaml` | chase, top, overview |
| Bird | calm landscape (hills, cloudy sky, light fog); the bird stays at the centre and the landscape moves | — |
| Wheelchair | apartment with plaster walls, laminate floor, swinging wooden doors, furniture | chase, first person, top |
| Boat | lake with calm water, islands with trees, striped buoys, a boat whose sail rises and falls | chase, top |

**Settings → Graphics** switches between *realistic* (shadows, ambient
occlusion, glow, 60 fps) and *light* (no shadows nor effects, 3D at 75 % of the
resolution, 30 fps), for when the decoder trains on the same machine. The choice
is remembered. The project uses the Forward+ renderer (`godot --rendering-method
gl_compatibility` runs it on older GPUs, with simpler lighting).

## Panels

| Panel | Content |
|---|---|
| 3D brain | band power at the sensors ([details](brain-panel.md)) |
| Signal | scrolling EEG channels, 5 or 10 s, scale ±25 to ±200 µV; a flat (< 0.3 µV over 1 s) or saturated (> 400 µV) channel is named in orange. Needs `bridge --eeg` and a Plug stream. |
| Command | last decoded command, confidence, decoder state, and one **confidence threshold slider per command** for the current scene (remembered per scene; `rest` has none) |
| Progress | score from `openmind/v1/score` |
| Connection | bridge, broker and decoder heartbeat |

## Menus and keys

| Menu | Entries |
|---|---|
| Profile | user announced by the decoder |
| Calibration | guided calibration (bird scene), send a test marker |
| Objects | robot twin (Ctrl+1), bird (Ctrl+2), wheelchair (Ctrl+3), boat (Ctrl+4) |
| Settings | bridge address, reconnect, show / hide panels (Ctrl+P), full screen (F11), quit (Ctrl+Q) |

Menus open with the mouse, or with Tab and the arrow keys; entries are at least
44 px high, and text has a contrast ratio of at least 7:1 on the panels.
Panels fold with a click on their title. Scenes change without restarting.

## The `OpenMind` autoload

`addons/openmind/openmind.gd` is loaded as the `OpenMind` singleton. It turns the
frames of the [bridge](bridge.md) into signals:

| Signal | Argument |
|---|---|
| `command_received` | command message (`command`, `confidence`, `seq`...) |
| `status_changed` | status message |
| `decoder_alive_changed` | `true` when a `running` status arrived less than 2 s ago through a bridge connected to the broker |
| `score_received`, `bandpower_received`, `marker_received`, `event_received` | message |
| `connection_changed`, `bridge_state_changed` | WebSocket / MQTT link state |
| `message_rejected` | error text sent back by the bridge |

`OpenMind.send_marker(type, label, trial, scene)` and
`OpenMind.send_event(object, kind, data)` send markers (also relayed to LSL by
the bridge) and events.

## Writing a scene

Add an `ObjectController` node (`addons/openmind/object_controller.gd`) to the
scene and connect its signals; it applies the common safety rules for you:

| Signal | When |
|---|---|
| `command_accepted(command)` | decoder alive, confidence ≥ the threshold of that command (`rest`: none), newer `seq` |
| `command_refused(command, reason)` | `reason` is `decoder`, `confidence` (ignore it: the object keeps going) or `stale` |
| `safety_stop(reason)` | the decoder is no longer alive: stop the object now |
| `resumed` | the decoder is back; wait for a new command |

Set `min_confidence` and `default_thresholds` per scene (0.8 for scenes that
mirror a real object, or `configure()` from data such as `robot.json`); users
adjust them in the command panel and they are kept in `user://openmind.cfg`.
Set `virtual_scene` only for scenes that drive nothing real (the calibration
bird), so that a `calibrating` decoder also gives feedback. Add
the scene to `SCENES` in `app/main.gd`. The four scenes are placeholders until
their tasks (SBX-050 to SBX-075); they show the command mapping and the last
accepted command.

## Tests

```bash
godot --headless --path godot --import
godot --headless --path godot --script res://tests/run_tests.gd
```

`tests/run_tests.gd` checks the safety filter, the heartbeat, the frames, the
theme (font, 44 px targets, contrast) and the cockpit (scene switching, commands
reaching the scene, safety stop). `tests/live_check.gd` checks a running chain
(bridge + `keys`), `tests/live_signal.gd` the signal panel (bridge `--eeg` + an
LSL EEG stream) and `tests/live_calibration.gd` the calibration markers, all
without opening a window or using the GPU.

## README clips

The animated clips of the README (`docs/media/*.webp`) are recorded in demo mode
at a fixed frame rate, then encoded as animated WebP under 500 KB each:

```bash
godot --path godot --resolution 1600x900 --fixed-fps 20 --disable-vsync \
    --script "$PWD/tools/record_demo.gd" -- /tmp/openmind-frames
uv run --with pillow python tools/make_demo_media.py /tmp/openmind-frames
```

Record them again when a scene or a panel changes visibly.
