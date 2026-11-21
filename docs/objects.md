# Objects and commands

Every object receives the same five commands of the OpenMind protocol and decides
what they mean for it:

| Object | `left` / `right` | `forward` | `rest` | `action` |
|---|---|---|---|---|
| Real robot / twin / mock robot | pivot in place | move forward (speeds up while held) | stop | U-turn |
| Wheelchair | turn | move forward | stop at once | open a door (only in front of one) |
| Boat | rudder (while held) | hoist the sail | lower the sail and drift | drop the anchor |
| Bird | bank | flap (climb) | glide (descend) | dive / land |

`action` comes from a double jaw clench of the user (a muscle signal, see
OpenMind Core `docs/action-gesture.md`): it is a one-shot gesture, so objects
treat it as an event, not as a held command.

## Safety, on the object side

Objects that move apply the safety rules of the protocol themselves, so they stay
safe even if the decoder crashes: stop 2 s after the last `running` status (and
at once on any other state), ignore stale `seq`, stop on an invalid message or a
lost broker.

**Confidence thresholds, per command.** A command below its threshold is
**ignored**: the object keeps doing what it does. `rest` has no threshold: it
**always stops** the object, since stopping is never risky. Defaults for the
robot (`robot.yaml`): `left`, `right`, `forward` 0.80, `action` 0.85 (no U-turn by
mistake). They can be changed per scene in the cockpit (command panel), with
`mock-robot --threshold action=0.9`, or in `robot.yaml`; the real robot keeps the
values compiled from `robot.yaml` and never takes new ones over the network.

## Robot twin (Godot)

The first scene of the [cockpit](cockpit.md): the robot of
[`robot.yaml`](robot-config.md), seen from above, on a waypoint course. Its
kinematics, state machine and obstacle stop are the same as the mock robot below
(`godot/scenes/robot_twin/twin_robot.gd` mirrors `mock_robot.py`), with a
per-command confidence thresholds of `robot.yaml`, like the real robot.

The heads-up display shows the state, the speed, the distance ahead, the next
waypoint, the time, the **errors** (commands ignored below their confidence
threshold during the run) and the **collisions avoided** (times the obstacle stop
had to act). `R` restarts the course.

Courses are YAML files in `scenarios/courses/` (arena, start pose, round
obstacles, waypoints visited in order). Godot reads JSON copies in `godot/data/`:
after changing a course or `robot.yaml`, run

```bash
uv run openmind-sandbox export-godot
```

(a test fails when the copies are stale). `examples/keys-twin-course.yaml` drives
a complete run of the default course with `openmind-sandbox keys --script`; the
tests replay it on both the twin and the mock robot. The mock robot can run on the same
course, to compare both: `openmind-sandbox mock-robot --course scenarios/courses/twin_default.yaml`.

Events, with `"object": "robot-twin"`:

| `kind` | When | `data` |
|---|---|---|
| `telemetry` | `telemetry.rate_hz` | same fields as the mock robot |
| `state` | every change of state or reason | `state`, `reason` |
| `start` | first movement | `course` |
| `waypoint` | waypoint reached | `course`, `index` (from 0), `time_s` |
| `finish` | last waypoint | `course`, `time_s`, `errors`, `collisions_avoided` |

## Boat (Godot)

An 8 m sailing yacht at sea (`scenarios/courses/boat_sea.yaml`: open water to the
horizon and seven buoys to reach in order, as a slalom), forgiving on purpose: inertia and drift,
no time pressure. `forward` hoists the sails over about two seconds (the boat speeds up to 5 m/s),
`rest` lowers them (the boat slows down slowly and the wind pushes it), `left` /
`right` turn the rudder while held (more effect at speed), `action` drops the
anchor (the boat stops and stays until the sail is hoisted again). There is no
shore at sea; islands can be added to a course as obstacles (the boat stops
against them and counts a bump).

Events, with `"object": "boat"`: `telemetry` (position, heading, speed, sail,
anchor, state), `state`, `start`, `waypoint`, `finish` (`time_s`, `errors`,
`bumps`).

## Wheelchair (Godot)

A virtual wheelchair (a scanned CC0 model with a seated mannequin) in an apartment
(`scenarios/apartments/apartment_default.yaml`, exported by `export-godot`):
living room, a closed door, a bedroom. Confidence threshold 0.8.

| Command | Effect |
|---|---|
| `left` / `right` | turn in place (45°/s) |
| `forward` | drive, speeding up to 0.5 m/s |
| `rest` | **stop at once** |
| `action` | open the closed door in front (within 0.9 m and 40° of the heading); ignored elsewhere |

The chair never gets closer than 0.25 m to a wall or a closed door (three
parallel rays look ahead of its footprint). The run through the waypoints
(living room, bedroom, bedside) is timed; `R` restarts.
`examples/keys-wheelchair.yaml` completes it with `openmind-sandbox keys --script`.

Events, with `"object": "wheelchair"`: `telemetry` (position, heading, speed,
`clearance_m`, state), `state`, `start`, `waypoint`, `door_opened` (`door`),
`action_ignored`, `finish` (`time_s`, `errors`, `collisions_avoided`,
`ignored_actions`).

## Mock robot

```bash
openmind-sandbox mock-robot                     # reads config/robot.yaml
openmind-sandbox mock-robot --min-confidence 0.6          # every command
openmind-sandbox mock-robot --threshold action=0.9        # one command
openmind-sandbox mock-robot --course scenarios/courses/twin_default.yaml
```

A text-only robot with the kinematics of [`robot.yaml`](robot-config.md) and the
state machine of the firmware, in a 3 m × 3 m arena with one round obstacle
straight ahead of the start position (`x` 1.5 m, `y` 0.5 m, facing +y), or on a
course with `--course`. Drive it
with [`openmind-sandbox keys`](keys.md).

A command stays in force until the next accepted one. The U-turn of `action`
(180°, counter-clockwise) is a short maneuver started by a one-shot gesture:

| During a U-turn | Effect |
|---|---|
| `rest`, `left`, `action` | none, the U-turn goes on |
| `right` (opposite rotation) | cancels it: the robot stops |
| `forward` | interrupts it: the robot drives in its current direction |
| safety stop | stops at once, as always |

| State | When |
|---|---|
| `STOPPED` | `rest` (whatever its confidence), end or cancellation of a U-turn |
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
