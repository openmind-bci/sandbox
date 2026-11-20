# Objects and commands

Every object receives the same five commands of the OpenMind protocol and decides
what they mean for it:

| Object | `left` / `right` | `forward` | `rest` | `action` |
|---|---|---|---|---|
| Real robot / twin / mock robot | pivot in place | move forward (speeds up while held) | stop | U-turn |
| Wheelchair | turn | move forward | stop at once | open a door (only in front of one) |
| Boat | rudder | hoist the sail | drift | drop the anchor |
| Bird | bank | flap (climb) | glide (descend) | dive / land |

`action` comes from a double jaw clench of the user (a muscle signal, see
OpenMind Core `docs/action-gesture.md`): it is a one-shot gesture, so objects
treat it as an event, not as a held command.

## Safety, on the object side

Objects that move apply the safety rules of the protocol themselves, so they stay
safe even if the decoder crashes: stop 2 s after the last `running` status (and
at once on any other state), stop on a command below their confidence threshold,
ignore stale `seq`, stop on an invalid message or a lost broker. The Python
helper is `openmind_protocol.Watchdog`.

## Robot twin (Godot)

The first scene of the [cockpit](cockpit.md): the robot of
[`robot.yaml`](robot-config.md), seen from above, on a waypoint course. Its
kinematics, state machine and obstacle stop are the same as the mock robot below
(`godot/scenes/robot_twin/twin_robot.gd` mirrors `mock_robot.py`), with a
confidence threshold of 0.8 like the real robot.

The heads-up display shows the state, the speed, the distance ahead, the next
waypoint, the time, the **errors** (commands refused below the confidence
threshold during the run) and the **collisions avoided** (times the obstacle stop
had to act). `R` restarts the course.

Courses are YAML files in `scenarios/courses/` (arena, start pose, round
obstacles, waypoints visited in order). Godot reads JSON copies in `godot/data/`:
after changing a course or `robot.yaml`, run

```bash
uv run openmind-sandbox export-godot
```

(a test fails when the copies are stale). The mock robot can run on the same
course, to compare both: `openmind-sandbox mock-robot --course scenarios/courses/twin_default.yaml`.

Events, with `"object": "robot-twin"`:

| `kind` | When | `data` |
|---|---|---|
| `telemetry` | `telemetry.rate_hz` | same fields as the mock robot |
| `state` | every change of state or reason | `state`, `reason` |
| `start` | first movement | `course` |
| `waypoint` | waypoint reached | `course`, `index` (from 0), `time_s` |
| `finish` | last waypoint | `course`, `time_s`, `errors`, `collisions_avoided` |

## Mock robot

```bash
openmind-sandbox mock-robot                     # reads config/robot.yaml
openmind-sandbox mock-robot --min-confidence 0.6
openmind-sandbox mock-robot --course scenarios/courses/twin_default.yaml
```

A text-only robot with the kinematics of [`robot.yaml`](robot-config.md) and the
state machine of the firmware, in a 3 m × 3 m arena with one round obstacle
straight ahead of the start position (`x` 1.5 m, `y` 0.5 m, facing +y), or on a
course with `--course`. Drive it
with [`openmind-sandbox keys`](keys.md).

A command stays in force until the next accepted one. The U-turn of `action` is a
short maneuver: the `rest` that follows the gesture does not cut it; a movement
command or a safety stop does.

| State | When |
|---|---|
| `STOPPED` | `rest`, end of a U-turn, or a command below the confidence threshold (reason `low_confidence`) |
| `MOVING` | `forward` |
| `PIVOTING` | `left`, `right`, U-turn |
| `SAFETY_STOP` | `no_status` (at start, or decoder silent), `decoder_<state>` (status not `running`), `invalid_message`, `disconnected`, `obstacle` (closer than `obstacle_stop_m` ahead; pivoting away stays possible) |

After a safety stop the robot waits for a new command: it never resumes on its own.

### Events

Published on `openmind/v1/events` with `"object": "mock-robot"` (the real robot
will use `"robot"` with the same fields):

| `kind` | When | `data` |
|---|---|---|
| `telemetry` | `telemetry.rate_hz` | `x_m`, `y_m`, `heading_deg` (0 = +x, counter-clockwise), `speed_mps`, `turn_dps`, `obstacle_m` (`null` out of range), `state`, `reason`, `command` |
| `state` | every change of state or reason | `state`, `reason` |
