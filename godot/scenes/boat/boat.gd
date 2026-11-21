extends Control
## Boat scene (SBX-075): sail a small boat around the islands of a lake.
##
## forward hoists the sail, rest lowers it (the boat drifts), left / right turn
## the rudder, action drops the anchor. Inertia and drift make it slow and
## forgiving: no time pressure. Commands come through the ObjectController
## (confidence thresholds per command; below it a command is ignored). The run
## is timed and logged on openmind/v1/events with "object": "boat". R restarts,
## C switches the camera.

const OBJECT_NAME := "boat"
const DEFAULT_COURSE := "res://data/courses/boat_sea.json"
const TELEMETRY_PERIOD := 0.5

@export_file("*.json") var course_path := DEFAULT_COURSE

var boat: BoatModel
var course: TwinCourse
var last_command := "rest"

var _next_telemetry := 0.0
var _last_state := ""
var _openmind: Node = null

@onready var _controller: ObjectController = $ObjectController
@onready var _world: BoatWorld = $BoatWorld
@onready var _view: BoatView = $BoatView
@onready var _status: Label = %Status
@onready var _progress: Label = %Progress


func _ready() -> void:
	_openmind = get_node_or_null("/root/OpenMind")
	course = TwinCourse.from_file(course_path)
	boat = BoatModel.from_course(course)
	_world.setup(boat, course)
	WorldKit.hud_backdrop($Hud)
	_view.boat = boat
	_view.course = course
	_controller.command_accepted.connect(_on_command)
	_controller.command_refused.connect(_on_refused)
	_controller.safety_stop.connect(func(_r: String) -> void:
			last_command = "rest"
			boat.halt())
	_controller.resumed.connect(boat.resume)
	if not _controller.stopped:
		boat.resume()


func restart() -> void:
	boat.place(course.start_position, course.start_heading)
	boat.bumps = 0
	course.reset()


func apply_quality(quality: String) -> void:
	_world.apply_quality(quality)


func _physics_process(delta: float) -> void:
	boat.step(delta)
	if boat.state != _last_state:
		_last_state = boat.state
		_send("state", {"state": boat.state})
	for event in course.update(boat.position, boat.speed > 0.2, delta):
		var data: Dictionary = event[1]
		if event[0] == "finish":
			data["bumps"] = boat.bumps
		_send(event[0], data)
	_next_telemetry -= delta
	if _next_telemetry <= 0.0:
		_next_telemetry = TELEMETRY_PERIOD
		_send("telemetry", boat.telemetry())
	_refresh_hud()


func _process(delta: float) -> void:
	_world.update(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		restart()
	elif key.keycode == KEY_C:
		_world.cycle_camera()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_command(command: Dictionary) -> void:
	last_command = str(command.get("command", "rest"))
	boat.apply(last_command)


func _on_refused(_command: Dictionary, reason: String) -> void:
	if reason == "confidence" and course.started and not course.finished:
		course.errors += 1


func _send(kind: String, data: Dictionary) -> void:
	if _openmind != null and _openmind.connected:
		_openmind.send_event(OBJECT_NAME, kind, data)


func _refresh_hud() -> void:
	var sail := "sail up" if boat.sail_up else ("anchored" if boat.anchored else "sail down")
	_status.text = "%s · %s · %.1f m/s · %s" % [boat.state, boat.command, boat.speed, sail]
	var target := "finished" if course.finished else "buoy %d / %d" % [
		course.next_index + 1, course.waypoints.size()]
	_progress.text = "%s · %.0f s · errors %d · bumps %d · R: restart · C: camera" % [
		target, course.elapsed, course.errors, boat.bumps]
