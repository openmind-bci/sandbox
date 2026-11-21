class_name DemoDriver
extends Node
## Built-in fake decoder of the demo mode: no bridge, no headset.
##
## It feeds the OpenMind autoload with the frames a live decoder would send: a
## running status (4 Hz), commands (4 Hz, new seq each time) and band power
## (10 Hz) on the eight motor electrodes of montage C. Imagining a movement is
## mimicked as in OpenMind Sandbox's `keys --bandpower`: rel_mu drops over C4 for
## left, C3 for right, Cz / CPz for forward, and rel_beta rises everywhere for
## action (a jaw clench). Values move smoothly, with a little noise.
##
## The command follows [member follow] when it returns a command (the bird scene
## gives its current cue: a perfect user), else a fixed loop.

const LOOP: Array = [["rest", 2.0], ["left", 4.0], ["rest", 2.0], ["right", 4.0],
	["rest", 2.0], ["forward", 4.0], ["action", 1.5], ["rest", 1.5]]
const CHANNELS: Array[String] = ["FC3", "FC4", "C3", "Cz", "C4", "CP3", "CP4", "CPz"]
const STATUS_PERIOD := 0.25
const COMMAND_PERIOD := 0.25
const BANDPOWER_PERIOD := 0.1
const SMOOTHING_S := 0.4
const MU_DROP := 0.45
const CLENCH_BETA := 1.2

## Returns the command to send now, or "" to use the loop.
var follow: Callable = Callable()
## Command currently sent.
var command := "rest"
var confidence := 0.9

var _openmind: Node
var _time := 0.0
var _step := 0
var _step_left := 0.0
var _seq := 0
var _next_status := 0.0
var _next_command := 0.0
var _next_bandpower := 0.0
var _rel := {}
var _rng := RandomNumberGenerator.new()


func _init(openmind: Node = null) -> void:
	_openmind = openmind
	_rng.seed = 7
	for label in CHANNELS:
		_rel[label] = [0.0, 0.0]
	_step_left = LOOP[0][1]


func _process(delta: float) -> void:
	advance(delta)


## Move the demo forward by [param delta] seconds and send what is due.
func advance(delta: float) -> void:
	_time += delta
	_step_left -= delta
	while _step_left <= 0.0:
		_step = (_step + 1) % LOOP.size()
		_step_left += LOOP[_step][1]
	var wanted: String = LOOP[_step][0]
	if follow.is_valid():
		var cue: String = follow.call()
		if not cue.is_empty():
			wanted = cue
	if wanted != command:
		command = wanted
		_next_command = _time  # send a change at once
	if _time >= _next_status:
		_next_status = _time + STATUS_PERIOD
		_send({"kind": "status", "message": {"v": 1, "ts": _now(), "state": "running",
			"model": "demo", "user": "P00"}})
	if _time >= _next_command:
		_next_command = _time + COMMAND_PERIOD
		_send({"kind": "command", "message": {"v": 1, "ts": _now(), "command": command,
			"confidence": confidence, "user": "P00", "seq": _seq}})
		_seq += 1
	if _time >= _next_bandpower:
		_next_bandpower = _time + BANDPOWER_PERIOD
		_send(bandpower_frame(BANDPOWER_PERIOD))


## Weight (0-1) of the desynchronization of [param name] seen on [param label].
static func motor_weight(label: String, name: String) -> float:
	var region := 1.0 if label.begins_with("C") and not label.begins_with("CP") else (
			0.6 if label.begins_with("FC") or label.begins_with("CP") else 0.0)
	var side := label.substr(label.length() - 1)
	if side == "z":
		return region if name == "forward" else 0.0
	var right_hemisphere := int(side) % 2 == 0
	if (name == "left" and right_hemisphere) or (name == "right" and not right_hemisphere):
		return region
	return 0.0


## Band power frame after [param dt] seconds of smoothing towards the command.
func bandpower_frame(dt: float) -> Dictionary:
	var alpha := 1.0 - exp(-dt / SMOOTHING_S)
	var channels: Array = []
	for label in CHANNELS:
		var weight := motor_weight(label, command)
		var target_mu := -MU_DROP * weight
		var target_beta := CLENCH_BETA if command == "action" else -0.5 * MU_DROP * weight
		var state: Array = _rel[label]
		state[0] += alpha * (target_mu - state[0])
		state[1] += alpha * (target_beta - state[1])
		var rel_mu := maxf(-0.95, state[0] + _rng.randfn(0.0, 0.03))
		var rel_beta := maxf(-0.95, state[1] + _rng.randfn(0.0, 0.03))
		channels.append({"label": label, "alpha": 8.0 * (1.0 + rel_mu),
			"mu": 10.0 * (1.0 + rel_mu), "beta": 3.5 * (1.0 + rel_beta),
			"rel_mu": snappedf(rel_mu, 0.001), "rel_beta": snappedf(rel_beta, 0.001),
			"ok": true})
	return {"kind": "bandpower", "message": {"v": 1, "ts": _now(), "user": "P00",
		"srate_hz": 250.0, "bands": {"alpha": [8, 12], "mu": [8, 13], "beta": [13, 30]},
		"channels": channels}}


func _send(frame: Dictionary) -> void:
	if _openmind != null:
		_openmind.handle_frame(JSON.stringify(frame))


static func _now() -> float:
	return Time.get_unix_time_from_system()
