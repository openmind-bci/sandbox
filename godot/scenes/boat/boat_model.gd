class_name BoatModel
extends RefCounted
## Sailing boat with inertia and drift, at sea (godot/data/courses/boat_sea.json:
## buoys to reach in order; the course area is not a boundary). Islands are
## supported (course obstacles) but the default sea has none.
##
## forward hoists the sail (the boat speeds up slowly), rest lowers it (the boat
## drifts and slows down slowly, pushed by the wind), left / right turn the rudder
## while held (the sail stays as it is; the boat turns faster when it moves),
## action drops the anchor (the boat stops and stays until the sail is hoisted
## again). The boat never enters an island: it stops against the shore and
## counts a bump. With [member bounded], the course area also acts as a shore. A virtual object: slow and forgiving on purpose.

const SAILING := "SAILING"
const DRIFTING := "DRIFTING"
const TURNING := "TURNING"
const ANCHORED := "ANCHORED"

var max_speed := 3.0
var thrust := 0.5
## Speed lost per second, as a fraction, sail up and sail down.
var drag_sail := 0.12
var drag_drift := 0.08
var turn_speed := deg_to_rad(25.0)
var anchor_brake := 1.5
## Wind pushing a drifting boat, metres per second (x, y).
var wind := Vector2(0.25, -0.1)
var radius := 1.6
var length := 3.2
var width := 1.3

var lake := Vector2(60, 40)
## Whether the edges of [member lake] stop the boat (open sea by default).
var bounded := false
## Islands as Vector3(x, y, radius).
var islands: Array[Vector3] = []

var position := Vector2.ZERO
var heading := 0.0
var speed := 0.0
var turn_rate := 0.0
var sail_up := false
var anchored := false
var rudder := 0.0
var command := "rest"
var state := DRIFTING
var bumps := 0

var _halted := true
var _touching := false


static func from_course(course: TwinCourse) -> BoatModel:
	var boat := BoatModel.new()
	boat.lake = course.arena
	boat.islands = course.obstacles
	boat.place(course.start_position, course.start_heading)
	return boat


func place(at: Vector2, heading_rad: float) -> void:
	position = at
	heading = heading_rad
	speed = 0.0
	sail_up = false
	anchored = false
	rudder = 0.0
	command = "rest"


## Decoder lost: lower the sail (the boat slows down and drifts).
func halt() -> void:
	_halted = true
	sail_up = false
	rudder = 0.0
	command = "rest"


func resume() -> void:
	_halted = false


func apply(name: String) -> void:
	if _halted:
		return
	command = name
	match name:
		"forward":
			sail_up = true
			anchored = false
			rudder = 0.0
		"rest":
			sail_up = false
			rudder = 0.0
		"left":
			rudder = 1.0
		"right":
			rudder = -1.0
		"action":
			anchored = true
			sail_up = false
			rudder = 0.0


func step(dt: float) -> void:
	if anchored:
		speed = move_toward(speed, 0.0, anchor_brake * dt)
	elif sail_up:
		speed = minf(max_speed, speed + thrust * dt)
		speed -= speed * drag_sail * dt
	else:
		speed -= speed * drag_drift * dt
	# The rudder bites more when the boat moves; a little even when still.
	turn_rate = rudder * turn_speed * clampf(0.25 + speed / max_speed, 0.0, 1.0)
	heading = wrapf(heading + turn_rate * dt, -PI, PI)
	var velocity := Vector2(cos(heading), sin(heading)) * speed
	if not anchored and not sail_up:
		velocity += wind
	var next := position + velocity * dt
	if _blocked(next):
		# Move up to the shore (bisection), then stop: one bump per real impact.
		var step := velocity * dt
		for i in 8:
			step /= 2.0
			if not _blocked(position + step):
				position += step
		if not _touching and velocity.length() > 0.2:
			bumps += 1
		_touching = true
		speed = 0.0
	else:
		if position.distance_to(next) > 0.01:
			_touching = false
		position = next
	if anchored:
		state = ANCHORED
	elif absf(rudder) > 0.0:
		state = TURNING
	elif sail_up:
		state = SAILING
	else:
		state = DRIFTING


func telemetry() -> Dictionary:
	return {
		"x_m": snappedf(position.x, 0.01),
		"y_m": snappedf(position.y, 0.01),
		"heading_deg": snappedf(fposmod(rad_to_deg(heading), 360.0), 0.1),
		"speed_mps": snappedf(speed, 0.01),
		"sail_up": sail_up,
		"anchored": anchored,
		"state": state,
		"command": command,
	}


func _blocked(p: Vector2) -> bool:
	if bounded and (p.x < radius or p.y < radius or p.x > lake.x - radius
			or p.y > lake.y - radius):
		return true
	for island in islands:
		if p.distance_to(Vector2(island.x, island.y)) < island.z + radius:
			return true
	return false
