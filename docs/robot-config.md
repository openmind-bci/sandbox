# Robot configuration (`config/robot.yaml`)

`config/robot.yaml` is a **contract**: the ESP32 firmware, the Godot twin and the
mock robot all read it, so that the virtual robots behave like the real one.

| Key | Unit | Value | Meaning |
|---|---|---|---|
| `geometry.wheel_base_m` | m | 0.13 | distance between the two wheel contact points |
| `geometry.wheel_diameter_m` | m | 0.065 | wheel diameter |
| `geometry.length_m`, `width_m` | m | 0.18, 0.15 | body size; the distance sensor sits at the front |
| `motion.max_speed_mps` | m/s | 0.25 | hard bound on forward speed |
| `motion.acceleration_mps2` | m/s² | 0.10 | `forward` speeds up while it stays commanded |
| `motion.pivot_speed_dps` | °/s | 90 | turning rate of `left` / `right`, in place |
| `motion.uturn_deg` | ° | 180 | turn made by `action` |
| `safety.obstacle_stop_m` | m | 0.20 | no forward motion when an obstacle is closer |
| `safety.sensor_range_m` | m | 4.0 | distance sensor range; beyond it nothing is seen |
| `safety.status_timeout_s` | s | 2.0 | stop after this long without decoder status (at most 2 s) |
| `safety.min_confidence` | 0-1 | 0.80 | default threshold: a command below its threshold is ignored |
| `safety.min_confidence_per_command` | 0-1 | `left`, `right`, `forward` 0.80, `action` 0.85 | threshold of each command; `rest` has none (it always stops) |
| `telemetry.rate_hz` | Hz | 5 | telemetry events on `openmind/v1/events` |

Values are first estimates for a small two-wheeled robot; they will be measured
on the real robot (task SBX-090) and adjusted here.

## Versions

| Version | Changes |
|---|---|
| 1.0.0 | First version. |
| 1.1.0 | `safety.min_confidence_per_command`; a command below its threshold is ignored instead of stopping the robot, `rest` always stops. |

## Changing the file

The file carries a [SemVer](https://semver.org) `version`:

- **patch** (1.0.x): a value changes;
- **minor** (1.x.0): a new key, with a default for older readers;
- **major** (x.0.0): a key is renamed or removed, or a meaning changes.

Readers refuse another major version and unknown keys. Any change must update the
firmware, the twin and the mock robot **together**, with a `CHANGELOG` entry.

The mock robot reads `config/robot.yaml` from the current directory, then the
copy installed with the package; `--config` picks another file.
