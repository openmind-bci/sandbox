class_name ChairModel
extends RefCounted
## Virtual wheelchair in an apartment (godot/data/apartments/*.json).
##
## left / right turn in place, forward drives and speeds up, rest stops at once,
## action opens the closed door in front (and does nothing elsewhere). The chair
## never moves closer to a wall or closed door than its stop margin: three
## parallel rays (centre and both sides of the footprint) look ahead.

const STOPPED := "STOPPED"
const MOVING := "MOVING"
const TURNING := "TURNING"
const SAFETY_STOP := "SAFETY_STOP"

var radius := 0.35
var max_speed := 0.5
var acceleration := 0.3
var turn_speed := deg_to_rad(45.0)
var stop_margin := 0.25
var door_reach := 0.9
var door_angle := deg_to_rad(40.0)
var min_confidence := 0.8

var size := Vector2(6, 4)
## Wall segments as [Vector2, Vector2].
var walls: Array[Array] = []
## Doors: {"id", "a", "b", "open"}.
var doors: Array[Dictionary] = []

var position := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var turn_rate := 0.0
var command := "rest"
var state := SAFETY_STOP
var reason := "no_status"
## Free distance ahead of the footprint (INF when nothing is in sight).
var clearance := INF
var collisions_avoided := 0

var _halted := true
var _command_reason := ""
var _transitions: Array[Array] = []


static func from_dict(data: Dictionary) -> ChairModel:
	var chair := ChairModel.new()
	var c: Dictionary = data["chair"]
	chair.radius = float(c["radius_m"])
	chair.max_speed = float(c["max_speed_mps"])
	chair.acceleration = float(c["acceleration_mps2"])
	chair.turn_speed = deg_to_rad(float(c["turn_speed_dps"]))
	chair.stop_margin = float(c["stop_margin_m"])
	chair.door_reach = float(c["door_reach_m"])
	chair.door_angle = deg_to_rad(float(c["door_angle_deg"]))
	chair.min_confidence = float(c["min_confidence"])
	chair.size = Vector2(data["size"]["width"], data["size"]["height"])
	var w := chair.size.x
	var h := chair.size.y
	for pair in [[Vector2(0, 0), Vector2(w, 0)], [Vector2(w, 0), Vector2(w, h)],
			[Vector2(w, h), Vector2(0, h)], [Vector2(0, h), Vector2(0, 0)]]:
		chair.walls.append(pair)
	for s in data.get("walls", []):
		chair.walls.append([Vector2(s["x1"], s["y1"]), Vector2(s["x2"], s["y2"])])
	for d in data.get("doors", []):
		chair.doors.append({"id": str(d["id"]), "a": Vector2(d["x1"], d["y1"]),
			"b": Vector2(d["x2"], d["y2"]), "open": false})
	chair.place(Vector2(data["start"]["x"], data["start"]["y"]),
			deg_to_rad(float(data["start"].get("heading_deg", 0.0))))
	return chair


static func from_file(path: String) -> ChairModel:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(data) if typeof(data) == TYPE_DICTIONARY else null


func place(at: Vector2, heading_rad: float) -> void:
	position = at
	heading = heading_rad
	_stop()
	for door in doors:
		door["open"] = false
	clearance = measure()


func halt(why: String = "no_status") -> void:
	_halted = true
	_stop()
	_set_state(SAFETY_STOP, why)


func resume() -> void:
	_halted = false
	_command_reason = ""


## Apply an accepted command. Returns the id of the door opened by an action,
## "" when the action had nothing to open (or for other commands).
func apply(name: String) -> String:
	if _halted:
		return ""
	if name == "action":
		var door := door_in_front()
		if door.is_empty():
			return ""
		door["open"] = true
		return str(door["id"])
	command = name
	_command_reason = ""
	if name == "rest":
		_stop()  # stop at once
	return ""


func refuse_low_confidence() -> void:
	if _halted:
		return
	_stop()
	_command_reason = "low_confidence"


## The closed door the chair faces within reach, or an empty dictionary.
func door_in_front() -> Dictionary:
	for door in doors:
		if door["open"]:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(position, door["a"], door["b"])
		var to_door := closest - position
		if to_door.length() - radius > door_reach:
			continue
		var direction := Vector2(cos(heading), sin(heading))
		var middle: Vector2 = (door["a"] + door["b"]) / 2.0
		if absf(direction.angle_to(middle - position)) <= door_angle:
			return door
	return {}


func step(dt: float) -> void:
	clearance = measure()
	if _halted:
		_stop()
		_set_state(SAFETY_STOP, reason if state == SAFETY_STOP else "no_status")
		return
	match command:
		"forward":
			turn_rate = 0.0
			if clearance <= stop_margin + 1e-6:
				if state != SAFETY_STOP:
					collisions_avoided += 1
				speed = 0.0
				_set_state(SAFETY_STOP, "obstacle")
				return
			speed = minf(max_speed, speed + acceleration * dt)
			var distance := minf(speed * dt, clearance - stop_margin)
			position += Vector2(cos(heading), sin(heading)) * maxf(0.0, distance)
			_set_state(MOVING, "")
		"left", "right":
			speed = 0.0
			turn_rate = turn_speed if command == "left" else -turn_speed
			heading = wrapf(heading + turn_rate * dt, -PI, PI)
			_set_state(TURNING, "")
		_:
			_stop()
			_set_state(STOPPED, _command_reason)
	clearance = measure()


## Free distance ahead of the footprint, along three parallel rays.
func measure() -> float:
	var direction := Vector2(cos(heading), sin(heading))
	var side := direction.orthogonal() * radius * 0.9
	var best := INF
	for offset in [Vector2.ZERO, side, -side]:
		best = minf(best, _ray(position + offset, direction))
	return best - radius if best < INF else INF


func _ray(origin: Vector2, direction: Vector2) -> float:
	var far := origin + direction * 100.0
	var best := INF
	var segments: Array[Array] = walls.duplicate()
	for door in doors:
		if not door["open"]:
			segments.append([door["a"], door["b"]])
	for s in segments:
		var hit: Variant = Geometry2D.segment_intersects_segment(origin, far, s[0], s[1])
		if hit != null:
			best = minf(best, origin.distance_to(hit))
	return best


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
		"clearance_m": null if clearance == INF else snappedf(clearance, 0.0001),
		"state": state,
		"reason": null if reason.is_empty() else reason,
		"command": command,
	}


func _stop() -> void:
	command = "rest"
	speed = 0.0
	turn_rate = 0.0


func _set_state(new_state: String, new_reason: String) -> void:
	if new_state != state or new_reason != reason:
		_transitions.append([new_state, new_reason])
	state = new_state
	reason = new_reason
