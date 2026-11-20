class_name TwinWorld
extends Node3D
## 3D view of the robot twin: a room with a concrete floor and plaster walls,
## wooden posts for the obstacles, glowing rings for the waypoints, and the robot
## built from the dimensions of robot.yaml (chassis, wheels, caster, HC-SR04).
##
## World coordinates of the twin (metres, x right, y forward) map to Godot as
## (x, 0, -y); a heading θ (counter-clockwise from +x) is a rotation of θ around Y.
## Textures and the HDRI sky are CC0 assets from Poly Haven (see ASSETS.md).

const WALL_HEIGHT := 0.35
const WALL_THICKNESS := 0.06
const POST_HEIGHT := 0.32
const CHASSIS_HEIGHT := 0.045
const CLEARANCE := 0.012

## "chase" (behind the robot), "top" or "overview".
var camera_mode := "chase"

var robot: TwinRobot
var course: TwinCourse

var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D

var _robot_node: Node3D
var _wheels: Array[MeshInstance3D] = []
var _led_material: StandardMaterial3D
var _ring_materials: Array[StandardMaterial3D] = []
var _wheel_angles := [0.0, 0.0]


static func to_godot(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(p.x, height, -p.y)


## Build the room, the course and the robot.
func setup(twin_robot: TwinRobot, twin_course: TwinCourse) -> void:
	robot = twin_robot
	course = twin_course
	_build_environment()
	_build_room()
	_build_course()
	_build_robot()
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.02
	add_child(camera)
	camera.current = true
	_place_camera(1.0)


func apply_quality(quality: String) -> void:
	GraphicsQuality.apply_scene(quality, sun, environment)


func cycle_camera() -> void:
	var modes := ["chase", "top", "overview"]
	camera_mode = modes[(modes.find(camera_mode) + 1) % modes.size()]


## Follow the simulation: robot pose, wheel spin, status light, rings, camera.
func update(delta: float) -> void:
	if robot == null:
		return
	_robot_node.position = to_godot(robot.position)
	_robot_node.rotation.y = robot.heading
	# Differential drive: each wheel turns at (v -/+ omega * b / 2) / r.
	var wheel_radius := 0.0325
	var half_base := robot.width / 2.0
	for i in _wheels.size():
		var side := -1.0 if i == 0 else 1.0
		var surface := robot.speed - side * robot.turn_rate * half_base
		_wheel_angles[i] += surface / wheel_radius * delta
		_wheels[i].rotation = Vector3(0, -_wheel_angles[i], 0)
	match robot.state:
		TwinRobot.MOVING, TwinRobot.PIVOTING:
			_set_led(OpenMindTheme.ACCENT)
		TwinRobot.SAFETY_STOP:
			_set_led(OpenMindTheme.DANGER)
		_:
			_set_led(OpenMindTheme.WARNING)
	for i in _ring_materials.size():
		var colour := OpenMindTheme.ACCENT if i == course.next_index else (
				OpenMindTheme.PANEL_BORDER if i < course.next_index else OpenMindTheme.PRIMARY_LIGHT)
		_ring_materials[i].albedo_color = colour
		_ring_materials[i].emission = colour
		_ring_materials[i].emission_energy_multiplier = 2.0 if i == course.next_index else 0.6
	_place_camera(minf(1.0, 4.0 * delta))


# --- Building ----------------------------------------------------------------------


func _build_environment() -> void:
	environment = WorldKit.environment(self, WorldKit.INDOOR_SKY)
	sun = WorldKit.sun(self)


func _build_room() -> void:
	var size := course.arena
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size + Vector2(1.0, 1.0)
	floor.mesh = plane
	floor.position = to_godot(size / 2.0)
	floor.material_override = WorldKit.textured("concrete_floor_worn_001", 1.0)
	add_child(floor)
	var walls := [
		[Vector2(size.x / 2.0, -WALL_THICKNESS / 2.0), Vector2(size.x + 2 * WALL_THICKNESS, WALL_THICKNESS)],
		[Vector2(size.x / 2.0, size.y + WALL_THICKNESS / 2.0), Vector2(size.x + 2 * WALL_THICKNESS, WALL_THICKNESS)],
		[Vector2(-WALL_THICKNESS / 2.0, size.y / 2.0), Vector2(WALL_THICKNESS, size.y)],
		[Vector2(size.x + WALL_THICKNESS / 2.0, size.y / 2.0), Vector2(WALL_THICKNESS, size.y)],
	]
	var wall_material := WorldKit.textured("plastered_wall_04", 2.0)
	for wall in walls:
		var box := BoxMesh.new()
		box.size = Vector3(wall[1].x, WALL_HEIGHT, wall[1].y)
		var node := MeshInstance3D.new()
		node.mesh = box
		node.position = to_godot(wall[0], WALL_HEIGHT / 2.0)
		node.material_override = wall_material
		add_child(node)


func _build_course() -> void:
	var wood := WorldKit.textured("brown_planks_09", 4.0)
	for o in course.obstacles:
		# Scanned barrel (Poly Haven) as wide as the obstacle; a post without it.
		if WorldKit.model(self, "Barrel_01", to_godot(Vector2(o.x, o.y)), o.x, 2.0 * o.z) != null:
			continue
		var post := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = o.z
		cylinder.bottom_radius = o.z
		cylinder.height = POST_HEIGHT
		post.mesh = cylinder
		post.position = to_godot(Vector2(o.x, o.y), POST_HEIGHT / 2.0)
		post.material_override = wood
		add_child(post)
	for i in course.waypoints.size():
		var w := course.waypoints[i]
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = w.z - 0.015
		torus.outer_radius = w.z
		torus.rings = 48
		ring.mesh = torus
		ring.position = to_godot(Vector2(w.x, w.y), 0.004)
		ring.scale = Vector3(1, 0.15, 1)
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		_ring_materials.append(material)
		add_child(ring)
		var label := Label3D.new()
		label.text = str(i + 1)
		label.font_size = 64
		label.pixel_size = 0.0015
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = to_godot(Vector2(w.x, w.y), 0.08)
		label.modulate = OpenMindTheme.TEXT
		add_child(label)


func _build_robot() -> void:
	_robot_node = Node3D.new()
	add_child(_robot_node)
	var length := robot.length
	var width := robot.width
	var plastic := WorldKit.plain(Color("#2A2F3A"), 0.6)
	var chassis := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(length, CHASSIS_HEIGHT, width * 0.8)
	chassis.mesh = body
	chassis.position = Vector3(0, CLEARANCE + 0.0325, 0)
	chassis.material_override = plastic
	_robot_node.add_child(chassis)
	var board := MeshInstance3D.new()
	var pcb := BoxMesh.new()
	pcb.size = Vector3(length * 0.6, 0.004, width * 0.55)
	board.mesh = pcb
	board.position = Vector3(-length * 0.05, chassis.position.y + CHASSIS_HEIGHT / 2.0 + 0.002, 0)
	board.material_override = WorldKit.plain(Color("#1E6B4A"), 0.4)
	_robot_node.add_child(board)
	# Wheels on each side, at the centre (differential drive).
	var rubber := WorldKit.plain(Color("#111111"), 0.9)
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var tyre := CylinderMesh.new()
		tyre.top_radius = 0.0325
		tyre.bottom_radius = 0.0325
		tyre.height = 0.025
		wheel.mesh = tyre
		var holder := Node3D.new()
		holder.position = Vector3(0, 0.0325, side * (width / 2.0 + 0.004))
		holder.rotation = Vector3(PI / 2.0, 0, 0)
		holder.add_child(wheel)
		wheel.material_override = rubber
		_robot_node.add_child(holder)
		_wheels.append(wheel)
	var caster := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.012
	ball.height = 0.024
	caster.mesh = ball
	caster.position = Vector3(-length * 0.4, 0.012, 0)
	caster.material_override = WorldKit.plain(Color("#B9C0CC"), 0.3, 0.8)
	_robot_node.add_child(caster)
	# HC-SR04 at the front: a blue board and two silver "eyes".
	var sensor := MeshInstance3D.new()
	var sensor_board := BoxMesh.new()
	sensor_board.size = Vector3(0.004, 0.02, 0.045)
	sensor.mesh = sensor_board
	sensor.position = Vector3(length / 2.0, chassis.position.y + 0.01, 0)
	sensor.material_override = WorldKit.plain(Color("#1F4FA8"), 0.5)
	_robot_node.add_child(sensor)
	var metal := WorldKit.plain(Color("#D5D9E0"), 0.25, 0.9)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var can := CylinderMesh.new()
		can.top_radius = 0.008
		can.bottom_radius = 0.008
		can.height = 0.012
		eye.mesh = can
		eye.rotation = Vector3(0, 0, PI / 2.0)
		eye.position = sensor.position + Vector3(0.008, 0, side * 0.013)
		eye.material_override = metal
		_robot_node.add_child(eye)
	var led := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	led.mesh = dot
	led.position = Vector3(-length * 0.3, board.position.y + 0.006, 0)
	_led_material = StandardMaterial3D.new()
	_led_material.emission_enabled = true
	_led_material.emission_energy_multiplier = 3.0
	led.material_override = _led_material
	_robot_node.add_child(led)


func _set_led(colour: Color) -> void:
	_led_material.albedo_color = colour
	_led_material.emission = colour


func _place_camera(blend: float) -> void:
	var target := to_godot(robot.position, 0.05)
	var eye: Vector3
	match camera_mode:
		"top":
			var centre := to_godot(course.arena / 2.0)
			eye = centre + Vector3(0, maxf(course.arena.x, course.arena.y) * 1.25, 0.01)
			target = centre
		"overview":
			var centre := to_godot(course.arena / 2.0)
			eye = centre + Vector3(0, 2.2, course.arena.y * 0.9)
			target = centre
		_:
			# Behind and above the robot, above the low walls, kept inside the room.
			var back := Vector3(-cos(robot.heading), 0, sin(robot.heading))
			eye = target + back * 0.7 + Vector3(0, 0.6, 0)
			eye.x = clampf(eye.x, 0.05, course.arena.x - 0.05)
			eye.z = clampf(eye.z, -course.arena.y + 0.05, -0.05)
	camera.position = camera.position.lerp(eye, blend)
	if camera.position.distance_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)
