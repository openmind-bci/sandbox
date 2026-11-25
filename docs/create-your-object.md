# Connect your object in 10 minutes

Any object that can be commanded from Python can follow OpenMind BCI commands:
a lamp, a toy, a robot arm, a game character. You write two methods; the base
class `Adapter` handles the protocol and the safety.

## Safety rules you get for free

They are those of the protocol (OpenMind Core, `docs/protocol.md`, section 4)
and cannot be switched off by a subclass:

- nothing happens before a `running` status was received;
- no status for 2 s, or a status other than `running`: `stop()` is called (once,
  not repeatedly), and commands are refused until the decoder runs again;
- a command below `min_confidence` (default 0.7) is ignored; `rest` always
  passes, since stopping is never risky;
- a command whose `seq` is not newer than the last one is ignored;
- `action` is contextual: it only reaches you if `context_allows_action()` is
  true (default: false);
- an invalid message is logged and ignored.

## Confirming `action` (optional)

For an object acting in the real world, when the action cannot be undone (open a
door, toggle mains power, release something), ask for a confirmation:

```python
super().__init__("my-object", confirm_action=True, confirm_window_s=3.0)
```

The first accepted `action` then does not run `on_action`: the adapter is
"armed", publishes the event `action_armed` (`window_s`) and calls
`on_action_armed()` (override it for a light or sound cue; default: nothing). A
second `action` within the window runs `on_action` and publishes
`action_confirmed`. `rest` keeps it armed (`rest` is still applied): the
decoder repeats `rest` every 0.5 s between the two gestures. A movement command
(`left`, `right`, `forward`), a lost heartbeat, a decoder that is not
`running`, a context that no longer allows the action, or the end of the window
cancels it with `action_cancelled` (`reason`: `other_command`,
`heartbeat_lost`, `decoder_not_running`, `context_lost`, `timeout`,
`stopped`). The safety rules above still come first.

Off by default. The wheeled robot does not use it: its `action` (a U-turn) is
bounded and stopped by the obstacle sensor.

## Steps

1. Copy [`template/adapter/`](../template/adapter/) and rename `my_object.py`.
2. Implement `on_command(command, confidence)` for `left`, `right`, `forward`,
   `rest` and `action`, and `stop()`, which brings the object to a safe state.
3. Optionally override `context_allows_action()`; call `self.emit_event(kind,
   data)` to report what the object does (published on `openmind/v1/events`).
4. Start the broker (`docker compose -f dev/docker-compose.yml up -d`), run your
   file (`python my_object.py`) and, in another terminal, `openmind-sandbox keys`.
   Arrows and space drive your object. Stop the simulator: your object stops
   within 2 s.

## Try the lamp example

```bash
openmind-sandbox fake-lamp                 # a fake lamp on http://127.0.0.1:8781
openmind-sandbox adapter lamp              # the adapter (--url, --broker, --min-confidence)
openmind-sandbox keys                      # space toggles, left/right dim
```

The lamp talks to a local HTTP API only (no cloud). Its `stop()` keeps the light
as it is: a lamp has no motion, so its safe state is "no change". Read
`src/openmind_sandbox/adapters/examples/lamp.py` as a worked example.

## Checklist before a real object

- [ ] `stop()` really makes the object safe (motors off, valve closed), works when
      already stopped, and never raises on a lost connection.
- [ ] Tested by killing the simulator: the object stops within 2 s.
- [ ] `action` has a real-world effect? Keep `context_allows_action()` false
      until a sensor or a confirmation makes it clearly safe.
- [ ] Irreversible real-world `action`? Consider `confirm_action=True`.
- [ ] `on_command` returns quickly (it runs on the network thread).
- [ ] The object also has its own hardware limits (end stops, current limit):
      the adapter is not the last line of defence.
- [ ] Credentials and addresses stay in a local `.env`, never committed.

Research and experimentation project, not a medical device.
