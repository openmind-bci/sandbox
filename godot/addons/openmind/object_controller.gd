class_name ObjectController
extends Node
## Safety and command filter of a scene object; add it as a child of the scene.
##
## Listens to the OpenMind autoload and applies the common safety rules:
## [signal command_accepted] only for commands that pass the [CommandGate]
## (decoder alive, confidence threshold of the scene, newer seq), and
## [signal safety_stop] as soon as the decoder is no longer alive (no running
## status for 2 s, bridge or broker lost). Works for 2D and 3D scenes alike.

signal command_accepted(command: Dictionary)
signal command_refused(command: Dictionary, reason: String)
signal safety_stop(reason: String)
signal resumed

## Confidence threshold of this scene (stricter for scenes that mirror real objects).
@export_range(0.0, 1.0, 0.01) var min_confidence := 0.7:
	set(value):
		min_confidence = value
		if gate != null:
			gate.min_confidence = value

var gate := CommandGate.new()
var stopped := true

var _openmind: Node = null


func _ready() -> void:
	gate.min_confidence = min_confidence
	_openmind = get_node_or_null("/root/OpenMind")
	if _openmind == null:
		push_warning("ObjectController: OpenMind autoload not found")
		return
	_openmind.command_received.connect(_on_command)
	_openmind.decoder_alive_changed.connect(_on_alive_changed)
	if _openmind.decoder_alive:
		stopped = false


func _on_command(command: Dictionary) -> void:
	var alive: bool = _openmind != null and _openmind.decoder_alive
	if gate.accept(command, alive):
		command_accepted.emit(command)
	else:
		command_refused.emit(command, gate.last_refusal)


func _on_alive_changed(alive: bool) -> void:
	if alive:
		gate.reset()  # the decoder may have restarted with seq 0
		stopped = false
		resumed.emit()
	else:
		stopped = true
		safety_stop.emit("decoder")
