# Guided calibration (bird scene)

The bird scene of the [cockpit](cockpit.md) plays a motor imagery calibration
protocol and emits its markers, so that OpenMind Core can cut labelled EEG
epochs (task CORE-090).

## Protocol

`scenarios/calibration_default.yaml` (exported to `godot/data/` by
`openmind-sandbox export-godot`):

```
fixation cross 2 s → cue 1 s → imagery 4 s → rest 1.5-3 s (random)
```

- Classes `left`, `right`, `forward`, `rest` (left hand, right hand, both feet,
  rest), **balanced and shuffled in every block**: 10 trials per class, 40 trials,
  about 6 minutes per block; 3 blocks with a 30 s break (N continues earlier).
- `seed: null` gives a new order each session; an integer makes it reproducible.
- The YAML is validated (`action` is refused: it is a jaw clench, not a motor
  imagery class); `export-godot` warns when a block is outside 5-7 minutes.

## Markers

Sent through the [bridge](bridge.md) to MQTT (`openmind/v1/markers`) and to the
LSL stream `openmind-markers`, with `"scene": "calibration"`:

| Marker | When | `label` | `trial` |
|---|---|---|---|
| `event` | session start / end | `session_start`, `session_end` | `null` |
| `event` | block start / end | `block_1_start`, `block_1_end`... | `null` |
| `trial_start` | fixation cross appears | class | 1, 2... (whole session) |
| `cue` | cue appears | class | same |
| `trial_end` | end of imagery | class | same |

Every trial gets the three markers, including a trial cut short by Escape.

## What the user sees

- During imagery the **bird stays at the centre** of the screen and only the
  scenery moves, to limit eye movements: sideways for `left` / `right`, up for
  `forward` (the bird flaps), gliding for `rest`.
- The bird follows the cue by itself in proportion to the **assistance** the
  decoder announces in `status` (1 = fully assisted), and fully when the decoded
  command matches the cue (confidence ≥ 0.6 by default, adjustable per command in
  the command panel; below it a command is ignored). Commands are taken into account
  while the decoder is `running` or `calibrating`: the bird is virtual, unlike
  scenes that mirror a real object.
- **Stages** adapt the instruction: *discovery* (make the movement gently),
  *transition* (start the movement, then imagine it), *thought* (imagine only).
  A menu in the scene forces a stage (for a demonstration or a supervised
  session); on *automatic*, the stage follows the assistance (≤ 1, ≤ 0.66, ≤ 0.33), or the block number
  when the decoder sends no assistance; a banner announces the next stage.
- The footer shows the block and trial, the share of the last imagery during
  which the decoded command matched the cue, and the score from
  `openmind/v1/score`.

Space or Enter starts a session, Escape stops it.

## Checking the markers in LSL

With the broker and the bridge running, play a short protocol without a window
and read the LSL stream (any LSL viewer works, or `pylsl`):

```bash
uv run openmind-sandbox bridge &
godot --headless --path godot --script res://tests/live_calibration.gd
```

On a laptop the intervals measured in LSL were within 10 ms of the protocol
(fixation 0.2 s, cue + imagery 0.5 s in the quick test protocol).
