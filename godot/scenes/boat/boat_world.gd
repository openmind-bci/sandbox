class_name BoatWorld
extends Node3D
## 3D lake of the boat scene: calm water (shader), grassy islands and shores,
## striped buoys, an outdoor sky, and a small sailing boat built in code whose
## sail rises and falls with the commands. Coordinates: (x, y) -> (x, 0, -y).

const SHORE_WIDTH := 30.0

var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D
## "chase" or "top".
var camera_mode := "chase"

var boat: BoatModel
var course: TwinCourse

var _boat_node: Node3D
var _sail: MeshInstance3D
var _rudder: Node3D
var _buoy_materials: Array[StandardMaterial3D] = []
var _sail_amount := 0.0
var _time := 0.0


static func to_godot(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(p.x, height, -p.y)


func setup(model: BoatModel, lake_course: TwinCourse) -> void:
	boat = model
	course = lake_course
	environment = WorldKit.environment(self, WorldKit.OUTDOOR_SKY, 0.9)
	environment.fog_enabled = true
	environment.fog_light_color = Color("#C7D6EA")
	environment.fog_density = 0.003
	sun = WorldKit.sun(self, -45.0, -35.0, 1.0, 80.0)
	_build_water()
	_build_land()
	_build_buoys()
	_build_boat()
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 800.0
	add_child(camera)
	camera.current = true
	_place_camera(1.0)


func apply_quality(quality: String) -> void:
	GraphicsQuality.apply_scene(quality, sun, environment)


func cycle_camera() -> void:
	camera_mode = "top" if camera_mode == "chase" else "chase"


func update(delta: float) -> void:
	_time += delta
	_boat_node.position = to_godot(boat.position, 0.05 * sin(_time * 1.3))
	_boat_node.rotation = Vector3(0.03 * sin(_time * 0.9), boat.heading,
			0.04 * sin(_time * 1.1) - 0.15 * boat.turn_rate)
	_sail_amount = move_toward(_sail_amount, 1.0 if boat.sail_up else 0.08, 0.8 * delta)
	_sail.scale = Vector3(1, _sail_amount, 1)
	_sail.position.y = 0.6 + 1.3 * _sail_amount
	_rudder.rotation.y = boat.rudder * 0.5
	for i in _buoy_materials.size():
		var colour := OpenMindTheme.ACCENT if i == course.next_index else (
				OpenMindTheme.PANEL_BORDER if i < course.next_index else OpenMindTheme.DANGER)
		_buoy_materials[i].albedo_color = colour
		_buoy_materials[i].emission = colour
	_place_camera(minf(1.0, 2.5 * delta))


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = course.arena + Vector2(2 * SHORE_WIDTH, 2 * SHORE_WIDTH)
	plane.subdivide_width = 160
	plane.subdivide_depth = 110
	water.mesh = plane
	water.position = to_godot(course.arena / 2.0)
	var material := ShaderMaterial.new()
	material.shader = load("res://scenes/boat/water.gdshader")
	water.material_override = material
	add_child(water)


func _build_land() -> void:
	var grass := WorldKit.textured("aerial_grass_rock", 0.1)
	var sand := WorldKit.plain(Color("#CDB98F"), 0.9)
	var size := course.arena
	# Shores around the lake: long gentle banks.
	var banks := [
		[Vector2(size.x / 2.0, -SHORE_WIDTH / 2.0), Vector2(size.x + 2 * SHORE_WIDTH, SHORE_WIDTH)],
		[Vector2(size.x / 2.0, size.y + SHORE_WIDTH / 2.0),
			Vector2(size.x + 2 * SHORE_WIDTH, SHORE_WIDTH)],
		[Vector2(-SHORE_WIDTH / 2.0, size.y / 2.0), Vector2(SHORE_WIDTH, size.y)],
		[Vector2(size.x + SHORE_WIDTH / 2.0, size.y / 2.0), Vector2(SHORE_WIDTH, size.y)],
	]
	for bank in banks:
		WorldKit.box(self, Vector3(bank[1].x, 1.2, bank[1].y), to_godot(bank[0], 0.4), grass)
	for island in course.obstacles:
		var centre := Vector2(island.x, island.y)
		var beach := WorldKit.cylinder(self, island.z, 0.5, to_godot(centre, 0.1), sand)
		beach.scale = Vector3(1.0, 1.0, 0.9)
		var hill := WorldKit.sphere(self, island.z * 0.85, to_godot(centre, 0.3), grass)
		hill.scale = Vector3(1.0, 0.45, 0.9)
		# A few trees: trunk and crown.
		for k in 3:
			var angle := TAU * k / 3.0 + island.x
			var spot := centre + Vector2(cos(angle), sin(angle)) * island.z * 0.35
			WorldKit.cylinder(self, 0.12, 1.6, to_godot(spot, 1.6),
					WorldKit.plain(Color("#5B4632"), 0.9))
			var crown := WorldKit.sphere(self, 0.9, to_godot(spot, 2.8),
					WorldKit.plain(Color("#2F6B3A"), 0.9))
			crown.scale = Vector3(1, 1.3, 1)


func _build_buoys() -> void:
	var white := WorldKit.plain(Color("#F3F5FA"), 0.5)
	for i in course.waypoints.size():
		var w := course.waypoints[i]
		var spot := Vector2(w.x, w.y)
		var material := WorldKit.glowing(OpenMindTheme.DANGER, 1.2)
		_buoy_materials.append(material)
		WorldKit.cylinder(self, 0.35, 0.6, to_godot(spot, 0.3), material)
		WorldKit.cylinder(self, 0.3, 0.5, to_godot(spot, 0.85), white)
		WorldKit.sphere(self, 0.12, to_godot(spot, 1.2), material)
		WorldKit.ring(self, w.z, to_godot(spot, 0.06), WorldKit.glowing(
				OpenMindTheme.PRIMARY_LIGHT, 0.6))
		WorldKit.label(self, str(i + 1), to_godot(spot, 2.0), 0.01)


func _build_boat() -> void:
	_boat_node = Node3D.new()
	add_child(_boat_node)
	var deck := WorldKit.textured("brown_planks_03", 1.5)
	var hull := WorldKit.plain(Color("#F3F5FA"), 0.4)
	var dark := WorldKit.plain(Color("#2A2F3A"), 0.5)
	# Local +X is the bow.
	WorldKit.box(_boat_node, Vector3(boat.length * 0.75, 0.5, boat.width), Vector3(-0.2, 0.1, 0),
			hull)
	var bow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(boat.width, boat.length * 0.3, 0.5)
	bow.mesh = prism
	bow.rotation = Vector3(PI / 2.0, 0, -PI / 2.0)
	bow.position = Vector3(boat.length * 0.33, 0.1, 0)
	bow.material_override = hull
	_boat_node.add_child(bow)
	WorldKit.box(_boat_node, Vector3(boat.length * 0.72, 0.04, boat.width * 0.92),
			Vector3(-0.2, 0.37, 0), deck)
	WorldKit.cylinder(_boat_node, 0.05, 3.2, Vector3(0.2, 1.95, 0), dark)
	_sail = WorldKit.box(_boat_node, Vector3(1.4, 2.6, 0.02), Vector3(-0.55, 1.9, 0),
			WorldKit.plain(Color("#FFFDF5"), 0.8))
	_rudder = Node3D.new()
	_rudder.position = Vector3(-boat.length * 0.58, 0.0, 0)
	_boat_node.add_child(_rudder)
	WorldKit.box(_rudder, Vector3(0.35, 0.6, 0.04), Vector3(-0.15, -0.1, 0), dark)


func _place_camera(blend: float) -> void:
	var at := to_godot(boat.position)
	var eye: Vector3
	var target: Vector3
	if camera_mode == "top":
		var centre := to_godot(course.arena / 2.0)
		eye = centre + Vector3(0, maxf(course.arena.x, course.arena.y) * 1.05, 0.01)
		target = centre
	else:
		var forward := Vector3(cos(boat.heading), 0, -sin(boat.heading))
		eye = at - forward * 11.0 + Vector3(0, 5.5, 0)
		target = at + forward * 6.0
	camera.position = camera.position.lerp(eye, blend)
	if camera.position.distance_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)
