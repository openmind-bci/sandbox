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

## Mock robot

```bash
openmind-sandbox mock-robot                     # reads config/robot.yaml
openmind-sandbox mock-robot --min-confidence 0.6
```

A text-only robot with the kinematics of [`robot.yaml`](robot-config.md) and the
state machine of the firmware, in a 3 m × 3 m arena with one round obstacle
straight ahead of the start position (`x` 1.5 m, `y` 0.5 m, facing +y). Drive it
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
