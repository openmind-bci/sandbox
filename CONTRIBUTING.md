# Contributing to OpenMind Sandbox

Thanks for your interest! New objects, scenes, adapters, bug reports and
documentation improvements are all welcome.

## Development setup

You need Python 3.11+ and [uv](https://docs.astral.sh/uv/).

```bash
git clone https://github.com/openmind-bci/sandbox.git
cd sandbox
uv sync                       # creates .venv with runtime + dev dependencies
uv run pre-commit install     # run the checks automatically before each commit
```

### Working on the protocol at the same time

`openmind-protocol` comes from the `protocol/` folder of the
[core repository](https://github.com/openmind-bci/core). To test sandbox against
a local, modified copy of core, install it in editable mode **in your environment
only** (never commit a relative path in `pyproject.toml`), and stop uv from
re-syncing it:

```bash
uv sync
uv pip install -e ../core/protocol
uv run --no-sync pytest
```

Run `uv sync` again to go back to the version pinned in `uv.lock`.

## Checks

Every change must pass:

```bash
uv run ruff check             # lint
uv run ruff format --check    # formatting
uv run mypy                   # strict typing on src/
uv run pytest                 # tests
```

Tests marked `broker` need an MQTT broker on `localhost:1883`
(see [docs/dev-broker.md](docs/dev-broker.md)); they are skipped when none is
reachable.

## Guidelines

- Code, comments, docstrings and docs are written in **English**.
- Public functions and classes are typed and documented.
- New behavior comes with tests. Safety rules (heartbeat, confidence threshold,
  obstacle stop) are tested on simulated clocks, never with real hardware.
- Every message sent or received is validated with `openmind-protocol`.
- `config/robot.yaml` is a contract shared by the firmware, the Godot twin and
  the mock robot: change all three together and bump its version.
- Assets: CC0 or explicitly compatible licenses only, credited in `ASSETS.md`;
  original designs only, never characters, vehicles or logos from protected works.
  Heavy binaries (`*.glb`, `*.png`, `*.wav`, `*.ogg`) go through Git LFS.
- No user data: messages use pseudonyms (`P01`...), never names.
