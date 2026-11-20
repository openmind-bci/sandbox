# OpenMind Sandbox

[![CI](https://github.com/openmind-bci/sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/openmind-bci/sandbox/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**The sandbox of OpenMind BCI.** Virtual and real objects driven by the generic
commands of the [OpenMind protocol](https://github.com/openmind-bci/core/tree/main/protocol):
`left`, `right`, `forward`, `rest` and `action`.

> [!WARNING]
> **Research and experimentation project — not a medical device.**
> OpenMind Sandbox must not be used for diagnosis, treatment, or to drive any
> device that a person depends on.

Part of the [OpenMind BCI](https://github.com/openmind-bci) platform:

| Repository | Role |
|---|---|
| [plug](https://github.com/openmind-bci/plug) | EEG source → standard LSL stream |
| [core](https://github.com/openmind-bci/core) | LSL stream → user intent → MQTT commands |
| **sandbox** (this one) | Virtual and real objects driven by those commands |

The sandbox does no EEG processing and no decoding: you can build and test an
object here **without a headset and without knowing anything about EEG**. Commands
come either from OpenMind Core or from a keyboard simulator.

Safety lives **on the object side**: every object that moves stops when the
decoder goes silent for 2 s, ignores low-confidence commands, and fails safe on
malformed messages, even if Core crashes.

## Status

Pre-alpha: usable without hardware for command-side work. See [CHANGELOG.md](CHANGELOG.md).

| Component | Status |
|---|---|
| Local MQTT broker (Mosquitto, Docker) | available |
| Keyboard command simulator and fake band power (`keys`) | available |
| `robot.yaml` and mock robot (`mock-robot`) | planned |
| MQTT ↔ WebSocket ↔ LSL gateway (`bridge`) | planned |
| Godot cockpit: robot twin, bird, wheelchair, live 3D brain | planned |
| ESP32 robot firmware | planned |
| Adapter template for your own object | planned |

## Installation

Requires Python 3.11+ and [uv](https://docs.astral.sh/uv/).

```bash
git clone https://github.com/openmind-bci/sandbox.git
cd sandbox
uv sync
uv run openmind-sandbox --help
```

The `openmind-protocol` package is installed from the
[core repository](https://github.com/openmind-bci/core/tree/main/protocol).

## Local MQTT broker

The tools talk through an MQTT broker. For development, start Mosquitto with
Docker (anonymous access, **development only**, see [docs/dev-broker.md](docs/dev-broker.md)):

```bash
docker compose -f dev/docker-compose.yml up -d    # MQTT on 1883, WebSocket on 9001
docker compose -f dev/docker-compose.yml down     # stop it
```

## Quick start without a headset

With the broker running, simulate a live decoder from the keyboard (arrows, space
for `action`, `q` to quit) or from a script:

```bash
uv run openmind-sandbox keys
uv run openmind-sandbox keys --script examples/keys-demo.yaml --bandpower
```

Details: [docs/keys.md](docs/keys.md).

## Data and privacy

The sandbox never handles EEG. Messages identify users only by pseudonyms
(`P01`, `P02`...), never by name, and everything runs locally.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Graphic and sound assets must be CC0 or
under a compatible free license, credited in [ASSETS.md](ASSETS.md).

## License

Code: [Apache-2.0](LICENSE). Assets: see [ASSETS.md](ASSETS.md).
