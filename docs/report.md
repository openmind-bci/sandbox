# Course report

`openmind-sandbox report` summarises the runs found in a log of events: the same
figures for the robot twin, the mock robot and the real robot, so that runs can be
compared (task SBX-090).

## 1. Record a log

The bridge sees every message of `openmind/v1/#`, including the events the twin
(Godot) sends and those the real robot publishes, and can append them to a file:

```bash
openmind-sandbox bridge --log runs/twin-1.jsonl
```

One JSON object per line, flushed at once: the envelope of the bridge
(`topic`, `kind`, `message`) plus `received`, the wall-clock time of the bridge
(preferred for the report, since the real robot has no clock before NTP sync).
Band power is left out (about 10 Hz, not useful here). The file is appended to,
never truncated: use one file per session. Keep logs outside the repository
(or untracked): session data is not committed.

## 2. Read it

```bash
openmind-sandbox report runs/twin-1.jsonl          # text
openmind-sandbox report runs/twin-1.jsonl --json   # for a script or a spreadsheet
```

```
Run 1: robot-twin, course twin_default (finished)
  duration            31.2 s
  waypoints reached   4
  errors              2
  collisions avoided  1
  obstacle stops      1
  safety stops        none
  commands            forward 35, left 3, rest 12, right 3
  average speed       0.121 m/s (while moving 0.178 m/s)
```

| Figure | Source |
|---|---|
| duration | `time_s` of the `finish` event; else last event minus start |
| waypoints reached | `waypoint` events of the run |
| errors, collisions avoided | `finish` event of the twin (`n/a` when not finished or not reported) |
| obstacle stops | times the state changed to `SAFETY_STOP` with reason `obstacle` |
| safety stops | other changes to `SAFETY_STOP`, by reason (`no_status` = decoder silent, `decoder_<state>`, `disconnected`, `invalid_message`) |
| commands | `command` messages between the start and the end of the run, by type |
| average speed | mean of `speed_mps` over the telemetry of the run (all samples, then only samples above 0) |

## Runs

- An object that sends `start`, `waypoint` and `finish` events (the twin, the
  wheelchair, the boat) gets one run per `start`. It ends at `finish`, at the next
  `start` or at the last event of the log (then it says `not finished`).
- An object without such events (the mock robot, the **real robot**) gets one
  `session` run, from its first movement to its last event, with no waypoint,
  error or collision count (`n/a`). Compare its duration and stops with the twin;
  count the errors by hand.
- States are read from `state` events and from the `state` and `reason` fields of
  `telemetry`, so the real robot, which sends only telemetry, is counted as well.
- Commands are counted for the whole log, not per user or per object: log one
  session at a time.
- Lines that are not JSON or not an event or a command are skipped and counted.

Research and experimentation project, not a medical device.
