# Bridge: MQTT ↔ WebSocket ↔ LSL

Godot has no MQTT client. `openmind-sandbox bridge` relays the protocol messages
between the MQTT broker and WebSocket clients (the Godot cockpit, a browser
tool...), and publishes the markers of the scenes on LSL, so that OpenMind Core
can align cues with the EEG on the same clock.

```bash
openmind-sandbox bridge                      # ws://127.0.0.1:8780, LSL on
openmind-sandbox bridge --ws-port 9000 --no-lsl -v
```

`--log FILE` also appends every message to a JSON-lines file, for
[`openmind-sandbox report`](report.md).

The WebSocket listens on `127.0.0.1` (this machine only) unless `--ws-host` says
otherwise. There is no authentication: as for the development broker, keep it
on a trusted network.

## From MQTT to the clients

Every message published on `openmind/v1/#` is validated with `openmind-protocol`
and sent to every client as one JSON text frame:

```json
{"topic":"openmind/v1/commands","kind":"command",
 "message":{"v":1,"ts":1763478000.25,"command":"left","confidence":0.86,"user":"P03","seq":41}}
```

`kind` is `command`, `status`, `marker`, `event`, `score` or `bandpower`.
Invalid messages (bad JSON, schema violation, other major version) are logged
and **dropped**: a client never receives them. Objects in a scene still apply
the safety rules themselves (stop 2 s after the last `running` status).

The bridge also sends its own state:

| Frame | When |
|---|---|
| `{"kind":"hello","bridge":"0.1.0","protocol":"1.0.1","mqtt_connected":true}` | on connection |
| `{"kind":"bridge","mqtt_connected":false}` | when the broker link is lost or back |

A scene that moves something must stop when `mqtt_connected` is `false`.

## From the clients to MQTT and LSL

Clients may send **markers** and **events** only:

```json
{"kind":"marker","message":{"type":"cue","label":"left","trial":12,"scene":"bird"}}
{"kind":"event","message":{"object":"robot-twin","kind":"lap","data":{"time_s":42.1}}}
```

`v` and `ts` (Unix time, seconds) may be left out; the bridge fills them in.
Each message is validated, then published on MQTT (markers with QoS 1). Since the
bridge listens to every topic, clients also receive it back from MQTT. A rejected
frame is answered to its sender only:

```json
{"kind":"error","error":"invalid marker message: label: ...","problems":["label: ..."]}
```

## EEG for the signal panel (optional)

`openmind-sandbox bridge --eeg` also reads the LSL EEG stream `openmind-eeg` of
OpenMind Plug, **read only**, and sends it to the clients about 10 times per
second:

```json
{"kind":"eeg","srate":250.0,"labels":["FC3","FC4","C3","Cz","C4","CP3","CP4","CPz"],
 "unit":"microvolts","t0":1234.5678,"samples":[[1.2,-0.4,...],...]}
```

Values are rounded to 0.1 µV and a frame carries at most 1 s of samples, so a
slow client never builds a backlog (8 channels at 250 Hz is about 20 kB/s). When
the stream disappears, the bridge searches for it again. Nothing is stored.

## LSL markers stream

Markers received from clients are pushed on an LSL stream that follows the
markers part of the [OpenMind Plug stream specification](https://github.com/openmind-bci/plug/blob/main/docs/stream-spec.md)
1.1:

| Field | Value |
|---|---|
| `name` / `type` | `openmind-markers` / `Markers` |
| format | 1 channel, `string`, irregular rate |
| `source_id` | `openmind-sandbox:bridge:markers` |
| `desc/spec_version` | `1.1.0` |

Each sample is a JSON object: `{"type":"cue","label":"left","trial":12,"scene":"bird","source":"sandbox"}`.
`cue` markers follow the specification; `trial_start`, `trial_end` and `event`
keep their protocol type, which consumers of the specification ignore when they
do not know it.

Plug may publish its own `openmind-markers` stream at the same time (synthetic
or replayed cues): consumers tell them apart by `source_id`.

**Timestamps.** A marker is stamped with the LSL clock, back-dated by its transit
delay (its `ts` compared with the wall clock of the bridge machine), so that it
falls on the EEG sample shown at that moment. When the delay is negative or
above 1 s (client on another machine with another clock, stale message), the
reception time is used instead.
