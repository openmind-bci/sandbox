extends Control
## Stand-in for an object scene until it is built (SBX-050 and later).
##
## Shows the command mapping of the object and the last accepted command, so
## that the cockpit, the bridge and the safety rules can be tried end to end.

@export var title := "Object"
@export_multiline var mapping := ""
@export var task := ""

var last_command := "rest"

@onready var _controller: ObjectController = $ObjectController
@onready var _command_label: Label = %CommandLabel
@onready var _state_label: Label = %StateLabel


func _ready() -> void:
	%TitleLabel.text = title
	%MappingLabel.text = mapping
	%TaskLabel.text = "Scene coming in %s" % task if not task.is_empty() else ""
	_controller.command_accepted.connect(_on_command)
	_controller.command_refused.connect(_on_refused)
	_controller.safety_stop.connect(_on_stop)
	_controller.resumed.connect(_on_resumed)
	_show_state("Waiting for the decoder" if _controller.stopped else "Ready")
	_command_label.text = "■ rest"


func _on_command(command: Dictionary) -> void:
	last_command = str(command.get("command", "rest"))
	_command_label.text = "%s %s" % [_symbol(last_command), last_command]
	_show_state("Confidence %.2f" % float(command.get("confidence", 0.0)))


func _on_refused(command: Dictionary, reason: String) -> void:
	if reason == "confidence":
		last_command = "rest"
		_command_label.text = "■ rest"
		_show_state("Stopped: confidence %.2f below %.2f" % [
			float(command.get("confidence", 0.0)), _controller.min_confidence])


func _on_stop(_reason: String) -> void:
	last_command = "rest"
	_command_label.text = "■ rest"
	_show_state("Safety stop: no decoder status")


func _on_resumed() -> void:
	_show_state("Ready")


func _show_state(text: String) -> void:
	_state_label.text = text


static func _symbol(command: String) -> String:
	match command:
		"left":
			return "◀"
		"right":
			return "▶"
		"forward":
			return "▲"
		"action":
			return "★"
		_:
			return "■"
