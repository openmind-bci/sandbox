# Keyboard command simulator

`openmind-sandbox keys` stands in for the decoder of OpenMind Core. It publishes
what a live decoder publishes, so you can build and test an object without a
headset:

| Topic | Content | Rate |
|---|---|---|
| `openmind/v1/commands` | the command of the held key, with a new `seq` each time | on change, then every 0.25 s |
| `openmind/v1/status` | `running`, model `keyboard-sim` | 4 Hz (the protocol asks ≥ 2 Hz) |
| `openmind/v1/bandpower` | fake band power, with `--bandpower` | 10 Hz |

Every message is validated against the `openmind-protocol` schemas before it is
sent. Start the [development broker](dev-broker.md) first.

## Keyboard mode

```bash
openmind-sandbox keys                 # confidence 0.9, user P00
openmind-sandbox keys --confidence 0.6 --user P03
```

| Key | Command |
|---|---|
| ← / `a` (held) | `left` |
| → / `d` (held) | `right` |
| ↑ / `w` (held) | `forward` |
| no key, ↓ / `s` | `rest` |
| space | one `action` (the double jaw clench of the real decoder) |
| `+` / `-` | confidence ± 0.05 |
| `q`, Ctrl+C | quit |

Terminals report key presses but not releases: a key counts as held while its
auto-repeat keeps arriving, and the command returns to `rest` `--hold` seconds
(0.5 s by default) after the last repeat. If commands flicker to `rest` when the
key is pressed, your auto-repeat delay is longer: raise `--hold`, or use
`--latch`, where a command stays until another key is pressed.

`action` is a one-shot gesture: holding space sends one `action`, then at most
one more every 0.6 s.

When the simulator stops, it sends `rest` and then no more status: objects that
follow the protocol stop within 2 s, which is a good way to test them.

## Script mode

Replay a fixed sequence, for repeatable tests and demos:

```bash
openmind-sandbox keys --script examples/keys-demo.yaml
```

```yaml
user: P00          # optional, overrides --user
loop: false        # replay forever when true
steps:
  - {command: rest, duration: 2}
  - {command: forward, duration: 3}
  - {command: left, duration: 1.5, confidence: 0.92}
  - {command: action, duration: 1}   # one action, then rest until the step ends
```

`duration` is in seconds; `confidence` overrides `--confidence` for that step.
Invalid files are refused with the name of the faulty field.

## Fake band power

```bash
openmind-sandbox keys --bandpower
openmind-sandbox keys --bandpower --bad-channel CPz --seed 1
```

Publishes `bandpower` messages for the eight motor electrodes of montage `C`
(`FC3, FC4, C3, Cz, C4, CP3, CP4, CPz`; change them with `--channels`), to
develop the live 3D brain without EEG or decoder. **This is not a model of EEG**:
it gives a display a known answer.

| Held command | What changes |
|---|---|
| `left` | `rel_mu` drops to about −0.45 on C4 (−0.27 on FC4 and CP4), `rel_beta` by half of it |
| `right` | the same on C3 (and FC3, CP3) |
| `forward` | the same on Cz (and CPz) |
| `action` | `rel_beta` rises to about +1.2 on every electrode (jaw muscles) |
| `rest` | everything back to about 0 |

Values move smoothly towards their target (time constant 0.4 s) with a little
noise; `--seed` makes the sequence reproducible. `--bad-channel` reports an
electrode as `ok: false` with `null` values, as Core does for a flat or
saturated channel.
