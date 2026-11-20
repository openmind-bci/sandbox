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

The cockpit connects to `ws://127.0.0.1:8765` and reconnects on its own. If that
port is taken on your machine, start the bridge with `--ws-port 8766` and give the
same address to the cockpit, either on the command line or in the environment:

```bash
godot --path godot -- --bridge=ws://127.0.0.1:8766
OPENMIND_BRIDGE_URL=ws://127.0.0.1:8766 godot --path godot
```

or from **Settings → Bridge address…** while it runs.

## Panels

| Panel | Content |
|---|---|
| 3D brain | band power at the sensors ([details](brain-panel.md)) |
| Signal | scrolling EEG channels, 5 or 10 s, scale ±25 to ±200 µV; a flat (< 0.3 µV over 1 s) or saturated (> 400 µV) channel is named in orange. Needs `bridge --eeg` and a Plug stream. |
| Command | last decoded command, confidence, decoder state |
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
| `command_accepted(command)` | decoder alive, confidence ≥ `min_confidence` of the scene, newer `seq` |
| `command_refused(command, reason)` | `reason` is `decoder`, `confidence` (stop the object) or `stale` |
| `safety_stop(reason)` | the decoder is no longer alive: stop the object now |
| `resumed` | the decoder is back; wait for a new command |

Set `min_confidence` per scene (0.8 for scenes that mirror a real object). Add
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
