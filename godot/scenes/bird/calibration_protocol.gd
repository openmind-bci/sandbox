class_name CalibrationProtocol
extends RefCounted
## Timeline of a guided calibration (godot/data/calibration_*.json, exported from
## scenarios/calibration_*.yaml): blocks of balanced, shuffled trials, each made of
## fixation -> cue -> imagery -> rest (random duration), with breaks between blocks.
##
## Pure logic: [method advance] moves time forward and returns what happened, as
## arrays: ["phase", name], ["marker", type, label, trial], ["finished"]. The scene
## turns them into visuals and protocol markers.

const IDLE := "idle"
const FIXATION := "fixation"
const CUE := "cue"
const IMAGERY := "imagery"
const REST := "rest"
const BREAK := "break"
const FINISHED := "finished"

var name := ""
var title := ""
var classes: Array[String] = []
var trials_per_class := 1
var blocks := 1
var timing := {}
var stages: Array = []
var cue_text := {}

var phase := IDLE
## Current block, from 1 (0 before the start).
var block := 0
## Trial number in the session, from 1 (0 before the first trial).
var trial := 0
var trial_in_block := 0
## Label (class) of the current trial.
var label := ""
## Seconds left in the current phase.
var phase_left := 0.0

var _queue: Array[String] = []
var _rng := RandomNumberGenerator.new()


static func from_file(path: String) -> CalibrationProtocol:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CalibrationProtocol: cannot read %s" % path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> CalibrationProtocol:
	var protocol := CalibrationProtocol.new()
	protocol.name = str(data["name"])
	protocol.title = str(data.get("title", ""))
	for c in data["classes"]:
		protocol.classes.append(str(c))
	protocol.trials_per_class = int(data["trials_per_class"])
	protocol.blocks = int(data["blocks"])
	protocol.timing = data["timing"]
	protocol.stages = data["stages"]
	protocol.cue_text = data["cue_text"]
	if data.get("seed") != null:
		protocol._rng.seed = int(data["seed"])
	else:
		protocol._rng.randomize()
	return protocol


## Number of trials of a whole session.
func total_trials() -> int:
	return classes.size() * trials_per_class * blocks


func trials_per_block() -> int:
	return classes.size() * trials_per_class


## Start the session: first block, first fixation.
func start() -> Array[Array]:
	var events: Array[Array] = []
	block = 0
	trial = 0
	_start_block(events)
	return events


## Skip the rest of a break between blocks.
func skip_break() -> Array[Array]:
	var events: Array[Array] = []
	if phase == BREAK:
		_start_block(events)
	return events


## Stop the session now.
func stop() -> Array[Array]:
	var events: Array[Array] = []
	if phase not in [IDLE, FINISHED]:
		if phase in [FIXATION, CUE, IMAGERY]:
			events.append(["marker", "trial_end", label, trial])
		_enter(FINISHED, 0.0, events)
		events.append(["finished"])
	return events


func advance(dt: float) -> Array[Array]:
	var events: Array[Array] = []
	if phase in [IDLE, FINISHED]:
		return events
	phase_left -= dt
	var guard := 0
	while phase_left <= 0.0 and phase not in [IDLE, FINISHED] and guard < 8:
		guard += 1
		var carry := phase_left  # keep the overshoot so that timing does not drift
		match phase:
			FIXATION:
				_enter(CUE, timing["cue_s"], events)
				events.append(["marker", "cue", label, trial])
			CUE:
				_enter(IMAGERY, timing["imagery_s"], events)
			IMAGERY:
				events.append(["marker", "trial_end", label, trial])
				_enter(REST, _rng.randf_range(timing["rest_min_s"], timing["rest_max_s"]), events)
			REST:
				_next_trial(events)
			BREAK:
				_start_block(events)
		phase_left += carry
	return events


## Stage for the given assistance (0-1, or negative when the decoder sends none):
## the least assisted stage that still covers it, else the stage of the block.
func stage_for(assistance: float) -> Dictionary:
	if stages.is_empty():
		return {}
	if assistance >= 0.0:
		var chosen: Dictionary = stages[0]
		for stage in stages:
			if assistance <= float(stage["max_assistance"]) + 1e-9:
				chosen = stage
		return chosen
	return stages[clampi(block - 1, 0, stages.size() - 1)]


func _start_block(events: Array[Array]) -> void:
	block += 1
	trial_in_block = 0
	_queue.clear()
	for c in classes:
		for i in trials_per_class:
			_queue.append(c)
	# Fisher-Yates with the protocol RNG (reproducible when a seed is given).
	for i in range(_queue.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _queue[i]
		_queue[i] = _queue[j]
		_queue[j] = tmp
	events.append(["marker", "event", "block_%d_start" % block, null])
	_next_trial(events)


func _next_trial(events: Array[Array]) -> void:
	if _queue.is_empty():
		events.append(["marker", "event", "block_%d_end" % block, null])
		if block >= blocks:
			_enter(FINISHED, 0.0, events)
			events.append(["finished"])
		elif float(timing.get("break_s", 0.0)) > 0.0:
			_enter(BREAK, timing["break_s"], events)
		else:
			_start_block(events)
		return
	label = _queue.pop_back()
	trial += 1
	trial_in_block += 1
	_enter(FIXATION, timing["fixation_s"], events)
	events.append(["marker", "trial_start", label, trial])


func _enter(new_phase: String, duration: float, events: Array[Array]) -> void:
	phase = new_phase
	phase_left = float(duration)
	events.append(["phase", new_phase])
