class_name BoatWorld
extends Node3D
## 3D sea of the boat scene: calm water to the horizon (shader), grassy islands,
## ocean buoys, an outdoor sky, and a CC0 sail boat model whose sail rises and
## falls with the commands. Coordinates: (x, y) -> (x, 0, -y).

const YACHT := "res://assets/models/sailing_yacht/sailing_yacht.glb"
## Turn of the yacht model so that its bow points along +X.
const YACHT_YAW := 0.0
## Depth of the keel under the water line, in metres.
const YACHT_DRAFT := 1.1
const SAIL_BOAT := "res://assets/models/sail_boat/sail_boat.glb"
## Turn of the boat model so that its bow points along +X (the boat's forward).
const MODEL_YAW := PI / 2.0
## Side of the detailed water patch that follows the boat, in metres.
const NEAR_WATER := 400.0

var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D
## "chase" or "top".
var camera_mode := "chase"

var boat: BoatModel
var course: TwinCourse

var _boat_node: Node3D
var _sail: MeshInstance3D
var _model_sail: Node3D
var _sail_parts: Array[Node3D] = []
var _near_water: MeshInstance3D
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
	environment.fog_density = 0.0012
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
	if _sail != null:
		_sail.scale = Vector3(1, _sail_amount, 1)
		_sail.position.y = 0.6 + 1.3 * _sail_amount
	for part in _sail_parts:
		part.visible = _sail_amount > 0.5
	if _model_sail != null:
		_model_sail.visible = _sail_amount > 0.1
		_model_sail.scale = Vector3(1, maxf(_sail_amount, 0.1), 1)
	# The detailed water follows the boat in 2 m steps.
	_near_water.position = (to_godot(boat.position) / 2.0).round() * 2.0
	_near_water.position.y = 0.0
	_rudder.rotation.y = boat.rudder * 0.5
	for i in _buoy_materials.size():
		var colour := OpenMindTheme.ACCENT if i == course.next_index else (
				OpenMindTheme.PANEL_BORDER if i < course.next_index else OpenMindTheme.DANGER)
		_buoy_materials[i].albedo_color = colour
		_buoy_materials[i].emission = colour
	_place_camera(minf(1.0, 2.5 * delta))


func _build_water() -> void:
	# Open sea to the horizon: a detailed patch that follows the boat (waves are
	# computed in world space, so it slides seamlessly) and a vast flat plane.
	var material := ShaderMaterial.new()
	material.shader = load("res://scenes/boat/water.gdshader")
	_near_water = MeshInstance3D.new()
	var near := PlaneMesh.new()
	near.size = Vector2(NEAR_WATER, NEAR_WATER)
	near.subdivide_width = 200
	near.subdivide_depth = 200
	_near_water.mesh = near
	_near_water.material_override = material
	add_child(_near_water)
	var far := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20000, 20000)
	far.mesh = plane
	far.position = Vector3(0, -0.05, 0)
	far.material_override = material
	add_child(far)


func _build_land() -> void:
	var grass := WorldKit.textured("aerial_grass_rock", 0.1)
	var sand := WorldKit.plain(Color("#CDB98F"), 0.9)
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
		# Scanned buoy (Poly Haven), partly under water; a light on top shows the
		# next one. Built buoy when the model is not downloaded.
		var buoy := WorldKit.model(self, "ocean_buoy", to_godot(spot, -0.55), i * 1.3, 1.0)
		if buoy == null:
			WorldKit.cylinder(self, 0.35, 0.6, to_godot(spot, 0.3), material)
			WorldKit.cylinder(self, 0.3, 0.5, to_godot(spot, 0.85), white)
		WorldKit.sphere(self, 0.12, to_godot(spot, 2.3 if buoy != null else 1.2), material)
		WorldKit.ring(self, w.z, to_godot(spot, 0.06), WorldKit.glowing(
				OpenMindTheme.PRIMARY_LIGHT, 0.6))
		WorldKit.label(self, str(i + 1), to_godot(spot, 3.0), 0.01)


func _build_boat() -> void:
	_boat_node = Node3D.new()
	add_child(_boat_node)
	# CC0 8 m sailing yacht by Innerscene (real scale); its sails are shown when
	# hoisted and hidden when lowered.
	var yacht := WorldKit.model_file(_boat_node, YACHT, Vector3(0, -YACHT_DRAFT, 0), YACHT_YAW,
			0.0)
	if yacht != null:
		var stack: Array[Node] = [yacht]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			var name := str(node.name).to_lower()
			if node is Node3D and ("mainsail" in name or "foresail" in name
					or "mainsheet" in name or "jibsheet" in name):
				_sail_parts.append(node)
		_rudder = Node3D.new()
		_boat_node.add_child(_rudder)
		return
	# CC0 sail boat by Quaternius (Poly Pizza); its "Sail" node rises and falls.
	var model := WorldKit.model_file(_boat_node, SAIL_BOAT, Vector3.ZERO, MODEL_YAW,
			boat.length)
	if model != null:
		_model_sail = model.find_child("Sail", true, false) as Node3D
		_rudder = Node3D.new()
		_boat_node.add_child(_rudder)
		return
	_simple_boat()


## Geometric boat when the model is not downloaded.
func _simple_boat() -> void:
	var deck := WorldKit.textured("brown_planks_03", 1.5)
	var hull := WorldKit.plain(Color("#F3F5FA"), 0.4)
	var dark := WorldKit.plain(Color("#2A2F3A"), 0.5)
	WorldKit.box(_boat_node, Vector3(boat.length * 0.75, 0.5, boat.width), Vector3(-0.2, 0.1, 0),
			hull)
	WorldKit.box(_boat_node, Vector3(boat.length * 0.72, 0.04, boat.width * 0.92),
			Vector3(-0.2, 0.37, 0), deck)
	WorldKit.cylinder(_boat_node, 0.05, 3.2, Vector3(0.2, 1.95, 0), dark)
	var boom := Node3D.new()
	boom.position = Vector3(0.2, 0, 0)
	boom.rotation.y = 0.6
	_boat_node.add_child(boom)
	_sail = WorldKit.box(boom, Vector3(1.4, 2.6, 0.02), Vector3(-0.75, 1.9, 0),
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
		# Three-quarter view from behind, so that the sails show their cloth.
		var side := Vector3(forward.z, 0, -forward.x)
		eye = at - forward * 16.0 + side * 8.0 + Vector3(0, 7.0, 0)
		target = at + forward * 4.0 + Vector3(0, 3.0, 0)
	camera.position = camera.position.lerp(eye, blend)
	if camera.position.distance_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)
