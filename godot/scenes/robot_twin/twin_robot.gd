class_name TwinRobot
extends RefCounted
## Digital twin of the robot: same kinematics, state machine and obstacle stop
## as the firmware and the Python mock robot (src/openmind_sandbox/mock_robot.py).
##
## World frame in metres, top view: x to the right, y forward, heading in radians
## (0 = +x, counter-clockwise). Parameters come from godot/data/robot.json, the
## JSON copy of config/robot.yaml. Decoder safety (heartbeat, confidence, seq) is
## applied before by [ObjectController]; this class handles the rest.

const STOPPED := "STOPPED"
const MOVING := "MOVING"
const PIVOTING := "PIVOTING"
const SAFETY_STOP := "SAFETY_STOP"
## Metres within which the stop distance counts as reached (rounding).
const STOP_TOLERANCE := 1e-6

var max_speed := 0.25
var acceleration := 0.1
var pivot_speed := deg_to_rad(90.0)
var uturn := PI
var obstacle_stop := 0.2
var sensor_range := 4.0
var length := 0.18
var width := 0.15

var arena := Vector2(3, 3)
## Obstacles as Vector3(x, y, radius).
var obstacles: Array[Vector3] = []

var position := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var turn_rate := 0.0
var command := "rest"
var state := SAFETY_STOP
var reason := "no_status"
## Distance measured ahead by the simulated sensor, or -1 when out of range.
var obstacle := -1.0
## Number of times the obstacle stop had to act (collisions avoided).
var collisions_avoided := 0

var _uturn_left := 0.0
var _halted := true
var _command_reason := ""
var _transitions: Array[Array] = []


func _init(config: Dictionary = {}) -> void:
	if config.is_empty():
		return
	var motion: Dictionary = config["motion"]
	var safety: Dictionary = config["safety"]
	var geometry: Dictionary = config["geometry"]
	max_speed = float(motion["max_speed_mps"])
	acceleration = float(motion["acceleration_mps2"])
	pivot_speed = deg_to_rad(float(motion["pivot_speed_dps"]))
	uturn = deg_to_rad(float(motion["uturn_deg"]))
	obstacle_stop = float(safety["obstacle_stop_m"])
	sensor_range = float(safety["sensor_range_m"])
	length = float(geometry["length_m"])
	width = float(geometry["width_m"])


static func load_config(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	return data if typeof(data) == TYPE_DICTIONARY else {}


func place(at: Vector2, heading_rad: float) -> void:
	position = at
	heading = heading_rad
	_stop_command()
	obstacle = measure()


## Decoder safety stop (no status, bridge lost): stop until a new command.
func halt(why: String = "no_status") -> void:
	_halted = true
	_stop_command()
	_set_state(SAFETY_STOP, why)


## The decoder is back: wait for a new command, stopped.
func resume() -> void:
	_halted = false
	_command_reason = ""


## Apply a command already accepted by the ObjectController.
func apply(name: String) -> void:
	if _halted:
		return
	if name == "action":
		if command != "action":
			_uturn_left = uturn
	elif name == "rest" and command == "action":
		return  # a U-turn completes; only a movement command or safety ends it
	command = name
	_command_reason = ""


## A command below the confidence threshold stops the robot.
func refuse_low_confidence() -> void:
	if _halted:
		return
	_stop_command()
	_command_reason = "low_confidence"


func step(dt: float) -> void:
	obstacle = measure()
	if _halted:
		_stop_command()
		_set_state(SAFETY_STOP, reason if state == SAFETY_STOP else "no_status")
		return
	# At the stop distance counts as blocked (the motion is clamped to land on it).
	var blocked := obstacle >= 0.0 and obstacle <= obstacle_stop + STOP_TOLERANCE
	match command:
		"forward":
			turn_rate = 0.0
			if blocked:
				if state != SAFETY_STOP or reason != "obstacle":
					collisions_avoided += 1
				speed = 0.0
				_set_state(SAFETY_STOP, "obstacle")
				return
			speed = minf(max_speed, speed + acceleration * dt)
			_set_state(MOVING, "")
		"left", "right":
			speed = 0.0
			turn_rate = pivot_speed if command == "left" else -pivot_speed
			_set_state(PIVOTING, "")
		"action":
			speed = 0.0
			var turn := minf(_uturn_left, pivot_speed * dt)
			_uturn_left -= turn
			turn_rate = pivot_speed
			heading = wrapf(heading + turn, -PI, PI)
			if _uturn_left <= 1e-9:
				_stop_command()
				_set_state(STOPPED, "")
			else:
				_set_state(PIVOTING, "")
			obstacle = measure()
			return
		_:
			speed = 0.0
			turn_rate = 0.0
			_set_state(STOPPED, _command_reason)
	heading = wrapf(heading + turn_rate * dt, -PI, PI)
	var distance := speed * dt
	if distance > 0.0:
		var ahead := INF if obstacle < 0.0 else obstacle
		distance = maxf(0.0, minf(distance, ahead - obstacle_stop))
		position += Vector2(cos(heading), sin(heading)) * distance
	obstacle = measure()


## Simulated distance sensor at the front of the body; -1 out of range.
func measure() -> float:
	var front := position + Vector2(cos(heading), sin(heading)) * (length / 2.0)
	var distance := distance_ahead(front, heading)
	return -1.0 if distance > sensor_range else distance


## Distance from [param origin] to the first wall or obstacle along [param angle].
func distance_ahead(origin: Vector2, angle: float) -> float:
	var direction := Vector2(cos(angle), sin(angle))
	var hits: Array[float] = []
	if direction.x > 1e-12:
		hits.append((arena.x - origin.x) / direction.x)
	elif direction.x < -1e-12:
		hits.append(-origin.x / direction.x)
	if direction.y > 1e-12:
		hits.append((arena.y - origin.y) / direction.y)
	elif direction.y < -1e-12:
		hits.append(-origin.y / direction.y)
	for o in obstacles:
		var offset := origin - Vector2(o.x, o.y)
		var b := offset.dot(direction)
		var c := offset.length_squared() - o.z * o.z
		var disc := b * b - c
		if disc < 0.0:
			continue
		var root := sqrt(disc)
		for t in [-b - root, -b + root]:
			if t >= 0.0:
				hits.append(t)
				break
	if hits.is_empty():
		return INF
	return maxf(0.0, hits.min())


## State changes since the last call: [state, reason] pairs, oldest first.
func pop_transitions() -> Array[Array]:
	var result := _transitions
	_transitions = []
	return result


func telemetry() -> Dictionary:
	return {
		"x_m": snappedf(position.x, 0.0001),
		"y_m": snappedf(position.y, 0.0001),
		"heading_deg": snappedf(fposmod(rad_to_deg(heading), 360.0), 0.01),
		"speed_mps": snappedf(speed, 0.0001),
		"turn_dps": snappedf(rad_to_deg(turn_rate), 0.01),
		"obstacle_m": null if obstacle < 0.0 else snappedf(obstacle, 0.0001),
		"state": state,
		"reason": null if reason.is_empty() else reason,
		"command": command,
	}


func _stop_command() -> void:
	command = "rest"
	speed = 0.0
	turn_rate = 0.0
	_uturn_left = 0.0


func _set_state(new_state: String, new_reason: String) -> void:
	if new_state != state or new_reason != reason:
		_transitions.append([new_state, new_reason])
	state = new_state
	reason = new_reason
