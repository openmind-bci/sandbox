# Full chain without a headset

`dev/run-chain.sh` starts the whole chain of OpenMind on one machine, with no
headset and no robot:

```
plug (EEG source) --LSL--> core (bandpower, online decoder) --MQTT--> mock robot
                                                                 \--> bridge --WebSocket--> Godot cockpit
```

It is a development convenience: anonymous broker, local processes only.

## Requirements

- The three repositories side by side (`plug/`, `core/`, `sandbox/`), each with
  `uv sync` done. The script defaults to the sibling directories of this
  repository **at run time only**; set `OPENMIND_PLUG_DIR` and
  `OPENMIND_CORE_DIR` (or pass `--plug-dir` / `--core-dir`) when yours are
  elsewhere. Nothing versioned refers to another repository.
- Docker for the broker, unless one already listens on port 1883
  ([dev-broker.md](dev-broker.md)).
- A model in the registry (`$OPENMIND_DATA_DIR/models/`). When the default model
  is missing, the script trains it (`ts-lr`, BNCI 2014-001 subjects 2-9,
  montage C, riemann alignment, name `ts-lr-bnci2014_001-c-riemann`); this needs
  the `research` extra of core and downloads the dataset the first time.
  `--model NAME` uses another registered model and never trains.
- For a replay of a public dataset: the `replay` extra of plug (the script runs
  `uv run --extra replay`) and the dataset, downloaded on first use.

Data and logs live in `${OPENMIND_DATA_DIR:-~/openmind-data}`, never in a
repository.

## Run

```bash
dev/run-chain.sh --synthetic            # no download: synthetic EEG, montage C
dev/run-chain.sh                        # replay of bnci2014_001, subject 1
dev/run-chain.sh --synthetic --brain    # also feeds the 3D brain (bandpower)
dev/run-chain.sh --synthetic --bridge   # gateway for the cockpit instead of the mock robot
godot --path godot                      # in another terminal, with --bridge
```

| Option | Meaning |
|---|---|
| `--synthetic` | synthetic EEG instead of a replay |
| `--dataset NAME`, `--subject N` | replayed dataset and subject (default `bnci2014_001`, 1) |
| `--model NAME` | registry model (default `ts-lr-bnci2014_001-c-riemann`) |
| `--profile ID` | profile (default `P00`, created when missing) |
| `--warmup-s SECONDS` | decoder warm-up (default 30) |
| `--brain` | run `openmind-core bandpower` too |
| `--bridge` | run the cockpit gateway instead of the mock robot |
| `--check`, `--duration S` | non-interactive test, see below |

Ctrl+C stops every process it started (decoder first). The mock robot receives
no more status, stops by itself within 2 s and ends stopped. The broker is left
running.

## What runs where

| Process | Started in | Port / stream | Log |
|---|---|---|---|
| broker | docker compose | 1883 MQTT, 9001 WebSocket | `chain-broker.log` |
| `openmind-plug stream` | plug | LSL `openmind-eeg`, `openmind-markers` | `chain-plug.log` |
| `openmind-core bandpower` (`--brain`) | core | MQTT `bandpower` | `chain-bandpower.log` |
| `openmind-core online` | core | MQTT `commands`, `status`, `events` | `chain-online.log` |
| `openmind-sandbox mock-robot` | sandbox | MQTT | terminal (`chain-robot.log` with `--check`) |
| `openmind-sandbox bridge` (`--bridge`, `--check`) | sandbox | `ws://127.0.0.1:8780` | `chain-bridge.log`, `chain-events.jsonl` |

Logs are in `${OPENMIND_DATA_DIR:-~/openmind-data}/logs/`.

## Check mode

```bash
dev/run-chain.sh --synthetic --check --duration 60
```

Runs for `--duration` seconds (the first `--warmup-s` seconds only produce
`rest` commands), then summarises the bridge log and exits with a non-zero code
when no command or no status arrived:

```
Full chain summary
  commands received   77 (forward 3, left 3, rest 60, right 11)
  statuses received   145 (calibrating 27, running 118)
  robot state changes 2 (SAFETY_STOP 1, STOPPED 1); last: STOPPED
  decoder latency     count 66, mean 2.9 ms, p50 2.3 ms, p95 4.9 ms, max 15.8 ms (4 events)
OK
```

The same log can be read with `openmind-sandbox report`
([report.md](report.md)); it holds one JSON object per message.

## Latency

The decoder publishes a `decoder` / `latency` event every 10 s: delay between
the arrival of the last EEG sample of a window and the publication of the
command, over all commands so far (`count`, `mean_ms`, `p50_ms`, `p95_ms`,
`max_ms`). It does not include the LSL transport, the 2 s window, the
averaging of `--windows` predictions (about 1 s) nor the robot. The summary
prints the last event; to follow it live:

```bash
grep '"latency"' ~/openmind-data/logs/chain-events.jsonl | tail -1
```

For an end-to-end figure, compare the `ts` of a command with the `received`
time of the bridge in the same log (same machine, same clock), and add the
window and averaging durations.

## Troubleshooting

- **No broker**: "no broker on port 1883 and docker is not installed" or
  "cannot start the broker": start Docker Desktop, or any MQTT broker on 1883.
- **Model not found**: with `--model`, train it first
  (`openmind-core train`, see the core pipeline guide).
- **Model channels vs stream**: the decoder picks the model channels in the
  stream by name. A model trained on montage C needs a stream with those
  electrodes: the script uses montage C for the synthetic source and the
  replay. A mismatch is reported in `chain-online.log`.
- **Model needs `torch`** (EEGNet, ShallowConvNet): install the `deep` extra of
  core; the default `ts-lr` model does not.
- **Robot does not move**: during the warm-up (30 s by default) the status is
  `calibrating`, commands stay `rest` and the robot stays stopped. Afterwards
  it moves only above its thresholds (0.80). A replay or synthetic stream
  mostly stays at rest unless the source simulates imagery.
- **`openmind-plug is required`**: the script adds plug to the decoder
  environment with `uv run --with-editable`; check `--plug-dir`.
- **Replay fails**: needs plug's `replay` extra and the dataset download.
- **Port 8780 busy** (`--bridge`, `--check`): another gateway is running.
