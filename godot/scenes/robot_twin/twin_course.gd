class_name TwinCourse
extends RefCounted
## Waypoint course of the robot twin (godot/data/courses/*.json, from
## scenarios/courses/*.yaml). Waypoints are visited in order; the timer starts
## with the first movement and stops at the last waypoint.

var name := ""
var title := ""
var arena := Vector2(3, 3)
var start_position := Vector2(0.5, 0.5)
var start_heading := PI / 2.0
## Obstacles and waypoints as Vector3(x, y, radius).
var obstacles: Array[Vector3] = []
var waypoints: Array[Vector3] = []

var next_index := 0
var started := false
var finished := false
var elapsed := 0.0
## Commands refused below the confidence threshold during the run.
var errors := 0


static func from_file(path: String) -> TwinCourse:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("TwinCourse: cannot read %s" % path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> TwinCourse:
	var course := TwinCourse.new()
	course.name = str(data.get("name", ""))
	course.title = str(data.get("title", ""))
	course.arena = Vector2(data["arena"]["width"], data["arena"]["height"])
	course.start_position = Vector2(data["start"]["x"], data["start"]["y"])
	course.start_heading = deg_to_rad(float(data["start"].get("heading_deg", 90.0)))
	for o in data.get("obstacles", []):
		course.obstacles.append(Vector3(o["x"], o["y"], o["radius"]))
	for w in data["waypoints"]:
		course.waypoints.append(Vector3(w["x"], w["y"], w["radius"]))
	return course


func reset() -> void:
	next_index = 0
	started = false
	finished = false
	elapsed = 0.0
	errors = 0


## Advance the course; returns the events that happened, as
## [kind, data] pairs ("start", "waypoint", "finish").
func update(position: Vector2, moving: bool, dt: float) -> Array[Array]:
	var events: Array[Array] = []
	if finished:
		return events
	if not started and moving:
		started = true
		events.append(["start", {"course": name}])
	if not started:
		return events
	elapsed += dt
	var target := waypoints[next_index]
	if position.distance_to(Vector2(target.x, target.y)) <= target.z:
		events.append(["waypoint", {"course": name, "index": next_index,
			"time_s": snappedf(elapsed, 0.01)}])
		next_index += 1
		if next_index >= waypoints.size():
			finished = true
			events.append(["finish", {"course": name, "time_s": snappedf(elapsed, 0.01),
				"errors": errors}])
	return events
