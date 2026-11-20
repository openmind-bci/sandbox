class_name ChairWorld
extends Node3D
## 3D view of the wheelchair scene: the apartment of the data file (walls, wooden
## doors that swing open, laminate floor), a little furniture placed away from the
## driving paths, and a wheelchair model. Same coordinates as the twin:
## (x, y) in metres -> Godot (x, 0, -y).

const WALL_HEIGHT := 2.4
const WALL_THICKNESS := 0.1
const DOOR_HEIGHT := 2.0
const DOOR_THICKNESS := 0.04
## Seconds a door takes to swing open.
const DOOR_SWING_S := 1.0

## "chase", "first_person" or "top".
var camera_mode := "chase"

var chair: ChairModel
var course: TwinCourse

var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D

var _chair_node: Node3D
var _wheels: Array[Node3D] = []
var _wheel_angles := [0.0, 0.0]
var _doors: Array[Node3D] = []
var _ring_materials: Array[StandardMaterial3D] = []


static func to_godot(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(p.x, height, -p.y)


func setup(model: ChairModel, chair_course: TwinCourse, names: PackedStringArray) -> void:
	chair = model
	course = chair_course
	environment = WorldKit.environment(self, WorldKit.INDOOR_SKY, 0.85)
	sun = WorldKit.sun(self, -62.0, 25.0, 0.9, 10.0)
	_build_apartment()
	_build_furniture()
	_build_waypoints(names)
	_build_chair()
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	_place_camera(1.0)


func apply_quality(quality: String) -> void:
	GraphicsQuality.apply_scene(quality, sun, environment)


func cycle_camera() -> void:
	var modes := ["chase", "first_person", "top"]
	camera_mode = modes[(modes.find(camera_mode) + 1) % modes.size()]


func update(delta: float) -> void:
	if chair == null:
		return
	_chair_node.position = to_godot(chair.position)
	_chair_node.rotation.y = chair.heading
	var half := chair.radius * 0.85
	for i in _wheels.size():
		var side := -1.0 if i == 0 else 1.0
		var surface := chair.speed - side * chair.turn_rate * half
		_wheel_angles[i] += surface / 0.3 * delta
		_wheels[i].rotation = Vector3(0, -_wheel_angles[i], 0)
	for i in _doors.size():
		var target := -PI / 2.0 if chair.doors[i]["open"] else 0.0
		var hinge := _doors[i]
		hinge.rotation.y = move_toward(hinge.rotation.y, target, PI / 2.0 / DOOR_SWING_S * delta)
	for i in _ring_materials.size():
		var colour := OpenMindTheme.ACCENT if i == course.next_index else (
				OpenMindTheme.PANEL_BORDER if i < course.next_index else OpenMindTheme.PRIMARY_LIGHT)
		_ring_materials[i].albedo_color = colour
		_ring_materials[i].emission = colour
	_place_camera(minf(1.0, 4.0 * delta))


## Swing angle of door [param index] (0 closed, -PI/2 open), for tests.
func door_angle(index: int) -> float:
	return _doors[index].rotation.y


func _build_apartment() -> void:
	var size := chair.size
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	floor.mesh = plane
	floor.position = to_godot(size / 2.0)
	floor.material_override = WorldKit.textured("laminate_floor_02", 0.8)
	add_child(floor)
	var plaster := WorldKit.textured("white_plaster_02", 1.0)
	for wall in chair.walls:
		_segment_box(wall[0], wall[1], WALL_HEIGHT, WALL_THICKNESS, plaster, self)
	var wood := WorldKit.textured("wood_planks_grey", 1.5)
	for door in chair.doors:
		var a: Vector2 = door["a"]
		var b: Vector2 = door["b"]
		var hinge := Node3D.new()
		hinge.position = to_godot(a)
		var direction := b - a
		hinge.rotation.y = 0.0
		add_child(hinge)
		var panel := Node3D.new()
		panel.rotation.y = atan2(direction.y, direction.x)
		hinge.add_child(panel)
		WorldKit.box(panel, Vector3(direction.length(), DOOR_HEIGHT, DOOR_THICKNESS),
				Vector3(direction.length() / 2.0, DOOR_HEIGHT / 2.0, 0), wood)
		WorldKit.sphere(panel, 0.03, Vector3(direction.length() * 0.85, 1.0, 0.04),
				WorldKit.plain(Color("#C9CED6"), 0.3, 0.9))
		# Lintel above the opening.
		_segment_box(a, b, WALL_HEIGHT - DOOR_HEIGHT, WALL_THICKNESS, plaster, self,
				DOOR_HEIGHT)
		_doors.append(hinge)


func _build_furniture() -> void:
	var fabric := WorldKit.textured("fabric_pattern_07", 2.0)
	var wood := WorldKit.textured("brown_planks_09", 2.0)
	var white := WorldKit.plain(Color("#E9ECF2"), 0.7)
	# Living room: sofa against the left wall and a low table.
	WorldKit.box(self, Vector3(0.7, 0.45, 1.4), to_godot(Vector2(0.4, 0.95), 0.225), fabric)
	WorldKit.box(self, Vector3(0.18, 0.4, 1.4), to_godot(Vector2(0.12, 0.95), 0.65), fabric)
	WorldKit.box(self, Vector3(0.7, 0.05, 0.7), to_godot(Vector2(1.6, 0.8), 0.42), wood)
	for corner in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
		WorldKit.box(self, Vector3(0.04, 0.4, 0.04),
				to_godot(Vector2(1.6, 0.8) + corner, 0.2), wood)
	# Kitchen counter on its wall.
	WorldKit.box(self, Vector3(1.4, 0.9, 0.6), to_godot(Vector2(0.7, 3.55), 0.45), white)
	WorldKit.box(self, Vector3(1.42, 0.04, 0.62), to_godot(Vector2(0.7, 3.55), 0.92), wood)
	# Bedroom: bed and bedside table along the top wall.
	WorldKit.box(self, Vector3(0.9, 0.35, 1.35), to_godot(Vector2(4.1, 3.27), 0.175), wood)
	WorldKit.box(self, Vector3(0.88, 0.18, 1.3), to_godot(Vector2(4.1, 3.25), 0.44), white)
	WorldKit.box(self, Vector3(0.7, 0.12, 0.3), to_godot(Vector2(4.1, 3.75), 0.58), fabric)
	WorldKit.box(self, Vector3(0.4, 0.5, 0.4), to_godot(Vector2(4.75, 3.75), 0.25), wood)


func _build_waypoints(names: PackedStringArray) -> void:
	for i in course.waypoints.size():
		var w := course.waypoints[i]
		var material := WorldKit.glowing(OpenMindTheme.PRIMARY_LIGHT, 1.5)
		WorldKit.ring(self, w.z, to_godot(Vector2(w.x, w.y), 0.005), material)
		_ring_materials.append(material)
		if i < names.size():
			WorldKit.label(self, names[i], to_godot(Vector2(w.x, w.y), 1.3), 0.002)


func _build_chair() -> void:
	_chair_node = Node3D.new()
	add_child(_chair_node)
	var frame := WorldKit.plain(Color("#3A4150"), 0.35, 0.8)
	var seat := WorldKit.plain(Color("#1B2230"), 0.8)
	var rubber := WorldKit.plain(Color("#111111"), 0.9)
	# Local +X is forward.
	WorldKit.box(_chair_node, Vector3(0.42, 0.06, 0.44), Vector3(0.0, 0.5, 0), seat)
	WorldKit.box(_chair_node, Vector3(0.06, 0.45, 0.44), Vector3(-0.22, 0.78, 0), seat)
	WorldKit.box(_chair_node, Vector3(0.14, 0.02, 0.36), Vector3(0.3, 0.12, 0), frame)
	for side in [-1.0, 1.0]:
		WorldKit.box(_chair_node, Vector3(0.5, 0.03, 0.03), Vector3(0.05, 0.45, side * 0.22),
				frame)
		WorldKit.box(_chair_node, Vector3(0.03, 0.4, 0.03), Vector3(0.25, 0.28, side * 0.2),
				frame)
		var holder := Node3D.new()
		holder.position = Vector3(-0.05, 0.3, side * 0.28)
		holder.rotation = Vector3(PI / 2.0, 0, 0)
		_chair_node.add_child(holder)
		var wheel := WorldKit.cylinder(holder, 0.3, 0.03, Vector3.ZERO, rubber)
		WorldKit.cylinder(wheel, 0.27, 0.035, Vector3.ZERO, frame)
		_wheels.append(wheel)
		WorldKit.sphere(_chair_node, 0.05, Vector3(0.28, 0.05, side * 0.2), rubber)


func _place_camera(blend: float) -> void:
	var at := to_godot(chair.position)
	var forward := Vector3(cos(chair.heading), 0, -sin(chair.heading))
	var eye: Vector3
	var target: Vector3
	match camera_mode:
		"first_person":
			eye = at + Vector3(0, 1.2, 0) + forward * 0.1
			target = eye + forward + Vector3(0, -0.15, 0)
		"top":
			var centre := to_godot(chair.size / 2.0)
			eye = centre + Vector3(0, maxf(chair.size.x, chair.size.y) * 1.1, 0.01)
			target = centre
		_:
			eye = at - forward * 1.6 + Vector3(0, 1.5, 0)
			target = at + forward * 0.6 + Vector3(0, 0.5, 0)
	camera.position = camera.position.lerp(eye, blend)
	if camera.position.distance_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)


func _segment_box(a: Vector2, b: Vector2, height: float, thickness: float,
		material: Material, parent: Node, base: float = 0.0) -> void:
	var direction := b - a
	var node := WorldKit.box(parent, Vector3(direction.length() + thickness, height, thickness),
			to_godot((a + b) / 2.0, base + height / 2.0), material)
	node.rotation.y = atan2(direction.y, direction.x)
