extends Control
## Wheelchair scene: drive through an apartment, open doors with `action`.
##
## Commands come through the ObjectController (decoder alive, confidence ≥ 0.8
## per command, newer seq; below it a command is ignored). `rest` stops at once; `action` opens the closed door in front and
## is ignored elsewhere. The run is timed and logged on openmind/v1/events with
## "object": "wheelchair". R restarts.

const OBJECT_NAME := "wheelchair"
const DEFAULT_APARTMENT := "res://data/apartments/apartment_default.json"
const TELEMETRY_PERIOD := 0.2

@export_file("*.json") var apartment_path := DEFAULT_APARTMENT

var chair: ChairModel
var course: TwinCourse
var last_command := "rest"
var ignored_actions := 0

var _data: Dictionary = {}
var _next_telemetry := 0.0
var _openmind: Node = null

@onready var _controller: ObjectController = $ObjectController
@onready var _view: ChairView = $ChairView
@onready var _status: Label = %Status
@onready var _progress: Label = %Progress


func _ready() -> void:
	_openmind = get_node_or_null("/root/OpenMind")
	_data = JSON.parse_string(FileAccess.get_file_as_string(apartment_path))
	chair = ChairModel.from_dict(_data)
	_controller.configure(chair.min_confidence, {})
	course = TwinCourse.new()
	course.name = str(_data["name"])
	var names := PackedStringArray()
	for w in _data["waypoints"]:
		course.waypoints.append(Vector3(w["x"], w["y"], w["radius"]))
		names.append(str(w["name"]))
	_view.chair = chair
	_view.course = course
	_view.names = names
	_controller.command_accepted.connect(_on_command)
	_controller.command_refused.connect(_on_refused)
	_controller.safety_stop.connect(func(_r: String) -> void: _stop())
	_controller.resumed.connect(chair.resume)
	restart()
	if not _controller.stopped:
		chair.resume()


func restart() -> void:
	chair.place(Vector2(_data["start"]["x"], _data["start"]["y"]),
			deg_to_rad(float(_data["start"].get("heading_deg", 0.0))))
	chair.collisions_avoided = 0
	ignored_actions = 0
	course.reset()
	if _controller.stopped:
		chair.halt()


func _physics_process(delta: float) -> void:
	chair.step(delta)
	for transition in chair.pop_transitions():
		_send("state", {"state": transition[0],
			"reason": null if transition[1].is_empty() else transition[1]})
	for event in course.update(chair.position, chair.state == ChairModel.MOVING, delta):
		var data: Dictionary = event[1]
		if event[0] == "finish":
			data["collisions_avoided"] = chair.collisions_avoided
			data["ignored_actions"] = ignored_actions
		_send(event[0], data)
	_next_telemetry -= delta
	if _next_telemetry <= 0.0:
		_next_telemetry = TELEMETRY_PERIOD
		_send("telemetry", chair.telemetry())
	_refresh_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		restart()
		get_viewport().set_input_as_handled()


func _on_command(command: Dictionary) -> void:
	var name := str(command.get("command", "rest"))
	last_command = name
	if name == "action":
		var opened := chair.apply("action")
		if opened.is_empty():
			ignored_actions += 1
			_send("action_ignored", {"reason": "no door in front"})
		else:
			_send("door_opened", {"door": opened})
	else:
		chair.apply(name)


func _on_refused(_command: Dictionary, reason: String) -> void:
	# Below its threshold a command is ignored; the run counts it as an error.
	if reason == "confidence" and course.started and not course.finished:
		course.errors += 1


func _stop() -> void:
	last_command = "rest"
	chair.halt()


func _send(kind: String, data: Dictionary) -> void:
	if _openmind != null and _openmind.connected:
		_openmind.send_event(OBJECT_NAME, kind, data)


func _refresh_hud() -> void:
	var reason := " (%s)" % chair.reason if not chair.reason.is_empty() else ""
	var free := "—" if chair.clearance == INF else "%.2f m" % chair.clearance
	_status.text = "%s%s · %s · %.2f m/s · free ahead %s" % [
		chair.state, reason, chair.command, chair.speed, free]
	var target := "finished" if course.finished else "next: %s" % _view.names[course.next_index]
	_progress.text = "%s · %.1f s · errors %d · stops %d · R: restart" % [
		target, course.elapsed, course.errors, chair.collisions_avoided]
