class_name ObjectController
extends Node
## Safety and command filter of a scene object; add it as a child of the scene.
##
## Listens to the OpenMind autoload and applies the common safety rules:
## [signal command_accepted] only for commands that pass the [CommandGate]
## (decoder alive, confidence threshold of that command, newer seq);
## [signal command_refused] otherwise (a scene ignores a low-confidence command);
## [signal safety_stop] as soon as the decoder is no longer alive. Thresholds can
## be changed at run time (command panel) and are remembered per scene in
## user://openmind.cfg. Works for 2D and 3D scenes alike.

signal command_accepted(command: Dictionary)
signal command_refused(command: Dictionary, reason: String)
signal safety_stop(reason: String)
signal resumed
signal thresholds_changed

## Where thresholds are remembered; tests point it to a scratch file.
static var settings_path := "user://openmind.cfg"

## Default threshold of the scene (stricter for scenes that mirror real objects).
@export_range(0.0, 1.0, 0.01) var min_confidence := 0.7:
	set(value):
		min_confidence = value
		if gate != null:
			gate.min_confidence = value
## Default per-command thresholds, e.g. {"action": 0.85}.
@export var default_thresholds := {}
## Key under which the thresholds are remembered (defaults to the scene name).
@export var settings_key := ""
## Virtual scenes (the calibration bird) also give feedback while the decoder is
## `calibrating`; never set it on a scene that mirrors a real object.
@export var virtual_scene := false

var gate := CommandGate.new()
var stopped := true

var _openmind: Node = null


func _ready() -> void:
	gate.min_confidence = min_confidence
	for name in default_thresholds:
		gate.set_threshold(name, float(default_thresholds[name]))
	if settings_key.is_empty() and get_parent() != null:
		settings_key = str(get_parent().name)
	_load_thresholds()
	_openmind = get_node_or_null("/root/OpenMind")
	if _openmind == null:
		push_warning("ObjectController: OpenMind autoload not found")
		return
	_openmind.command_received.connect(_on_command)
	_openmind.decoder_alive_changed.connect(_on_alive_changed)
	_openmind.status_changed.connect(_on_status)
	if _alive():
		stopped = false


func threshold(command: String) -> float:
	return gate.threshold(command)


## Set the default thresholds of the scene (from robot.json, an apartment...),
## then re-apply the values remembered for it.
func configure(default_value: float, per_command: Dictionary) -> void:
	min_confidence = default_value
	default_thresholds = per_command
	gate.thresholds.clear()
	for name in per_command:
		gate.set_threshold(name, float(per_command[name]))
	_load_thresholds()
	thresholds_changed.emit()


## Change the threshold of one command and remember it for this scene.
func set_threshold(command: String, value: float) -> void:
	gate.set_threshold(command, value)
	var config := ConfigFile.new()
	config.load(settings_path)  # missing file: start empty
	config.set_value("thresholds/" + settings_key, command, gate.threshold(command))
	config.save(settings_path)
	thresholds_changed.emit()


## Back to the default thresholds of the scene.
func reset_thresholds() -> void:
	gate.thresholds.clear()
	for name in default_thresholds:
		gate.set_threshold(name, float(default_thresholds[name]))
	var config := ConfigFile.new()
	if config.load(settings_path) == OK and config.has_section("thresholds/" + settings_key):
		config.erase_section("thresholds/" + settings_key)
		config.save(settings_path)
	thresholds_changed.emit()


func _load_thresholds() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	var section := "thresholds/" + settings_key
	for name in CommandGate.THRESHOLDED:
		if config.has_section_key(section, name):
			gate.set_threshold(name, float(config.get_value(section, name)))


func _alive() -> bool:
	if _openmind == null:
		return false
	return _openmind.feedback_alive() if virtual_scene else _openmind.decoder_alive


func _on_command(command: Dictionary) -> void:
	if gate.accept(command, _alive()):
		command_accepted.emit(command)
	else:
		command_refused.emit(command, gate.last_refusal)


func _on_status(_status: Dictionary) -> void:
	if virtual_scene:
		_on_alive_changed(_alive())


func _on_alive_changed(_alive_now: bool) -> void:
	var alive := _alive()
	if alive and stopped:
		gate.reset()  # the decoder may have restarted with seq 0
		stopped = false
		resumed.emit()
	elif not alive and not stopped:
		stopped = true
		safety_stop.emit("decoder")
