extends Control
## Robot twin scene: the robot of config/robot.yaml on a waypoint course.
##
## Commands come through the ObjectController (decoder alive, per-command
## confidence thresholds of robot.yaml, newer seq; below its threshold a command
## is ignored, rest always stops); the twin applies the same obstacle stop as the
## firmware. Telemetry,
## state changes and course events are published on openmind/v1/events with
## "object": "robot-twin", for the evaluation and the comparison with the real
## robot. R restarts the course.

const OBJECT_NAME := "robot-twin"
const ROBOT_CONFIG := "res://data/robot.json"
const DEFAULT_COURSE := "res://data/courses/twin_default.json"

@export_file("*.json") var course_path := DEFAULT_COURSE

var robot: TwinRobot
var course: TwinCourse
var last_command := "rest"

var _telemetry_period := 0.2
var _next_telemetry := 0.0
var _openmind: Node = null

@onready var _controller: ObjectController = $ObjectController
@onready var _view: TwinView = $TwinView
@onready var _status: Label = %Status
@onready var _progress: Label = %Progress


func _ready() -> void:
	_openmind = get_node_or_null("/root/OpenMind")
	var config := TwinRobot.load_config(ROBOT_CONFIG)
	robot = TwinRobot.new(config)
	if config.has("safety"):
		_controller.configure(float(config["safety"]["min_confidence"]),
				config["safety"].get("min_confidence_per_command", {}))
	if config.has("telemetry"):
		_telemetry_period = 1.0 / float(config["telemetry"]["rate_hz"])
	course = TwinCourse.from_file(course_path)
	robot.arena = course.arena
	robot.obstacles = course.obstacles
	_view.robot = robot
	_view.course = course
	restart()
	_controller.command_accepted.connect(_on_command)
	_controller.command_refused.connect(_on_refused)
	_controller.safety_stop.connect(func(_r: String) -> void: _stop("no_status"))
	_controller.resumed.connect(robot.resume)
	if not _controller.stopped:
		robot.resume()


func restart() -> void:
	robot.place(course.start_position, course.start_heading)
	robot.collisions_avoided = 0
	course.reset()
	_view.trail.clear()
	if _controller != null and _controller.stopped:
		robot.halt()


func _physics_process(delta: float) -> void:
	robot.step(delta)
	for transition in robot.pop_transitions():
		_send("state", {"state": transition[0],
			"reason": null if transition[1].is_empty() else transition[1]})
	for event in course.update(robot.position, robot.state == TwinRobot.MOVING, delta):
		var data: Dictionary = event[1]
		if event[0] == "finish":
			data["collisions_avoided"] = robot.collisions_avoided
		_send(event[0], data)
	_next_telemetry -= delta
	if _next_telemetry <= 0.0:
		_next_telemetry = _telemetry_period
		_send("telemetry", robot.telemetry())
	_refresh_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R:
		restart()
		get_viewport().set_input_as_handled()


func _on_command(command: Dictionary) -> void:
	last_command = str(command.get("command", "rest"))
	robot.apply(last_command)


func _on_refused(_command: Dictionary, reason: String) -> void:
	# Below its threshold a command is ignored: the robot keeps going. The run
	# counts these hesitations as errors.
	if reason == "confidence" and course.started and not course.finished:
		course.errors += 1


func _stop(reason: String) -> void:
	last_command = "rest"
	robot.halt(reason)


func _send(kind: String, data: Dictionary) -> void:
	if _openmind != null and _openmind.connected:
		_openmind.send_event(OBJECT_NAME, kind, data)


func _refresh_hud() -> void:
	var reason := " (%s)" % robot.reason if not robot.reason.is_empty() else ""
	var distance := "—" if robot.obstacle < 0.0 else "%.2f m" % robot.obstacle
	_status.text = "%s%s · %s · %.2f m/s · obstacle %s" % [
		robot.state, reason, robot.command, robot.speed, distance]
	var target := "finished" if course.finished else "waypoint %d / %d" % [
		course.next_index + 1, course.waypoints.size()]
	_progress.text = "%s · %.1f s · errors %d · collisions avoided %d · R: restart" % [
		target, course.elapsed, course.errors, robot.collisions_avoided]
