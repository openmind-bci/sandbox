class_name BirdWorld
extends Node3D
## 3D landscape of the calibration bird, kept calm on purpose: gentle grassy
## hills, a cloudy sky and light fog. The bird and the camera never move: the
## landscape slides under the bird (sideways for left / right, down when the bird
## climbs, always a little forward), so the eyes can stay on the centre.
## The bird is an original low-poly shape built in code.

## Size of the repeating terrain tile, in metres (heights are periodic on it).
const TILE := 400.0
const CELLS := 80
## Metres of landscape per pixel of scroll of the 2D view (shared with BirdView).
const METRES_PER_PIXEL := 0.12
const BIRD_HEIGHT := 30.0
const FORWARD_SPEED := 6.0

var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D

var _terrain: Node3D
var _bird: Node3D
var _wings: Array[Node3D] = []
var _forward := 0.0


func setup() -> void:
	environment = WorldKit.environment(self, WorldKit.OUTDOOR_SKY, 0.9)
	environment.fog_enabled = true
	environment.fog_light_color = Color("#BFD0E6")
	environment.fog_density = 0.004
	environment.fog_sky_affect = 0.2
	sun = WorldKit.sun(self, -40.0, -30.0, 1.0, 120.0)
	_terrain = Node3D.new()
	add_child(_terrain)
	var material := WorldKit.textured("aerial_grass_rock", 0.08)
	material.uv1_world_triplanar = false  # the texture moves with the hills
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var tile := MeshInstance3D.new()
			tile.mesh = _terrain_mesh()
			tile.material_override = material
			tile.position = Vector3(dx * TILE, 0, dz * TILE)
			_terrain.add_child(tile)
	_build_bird()
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 900.0
	add_child(camera)
	camera.position = Vector3(0, BIRD_HEIGHT + 1.4, 4.2)
	camera.look_at(Vector3(0, BIRD_HEIGHT, 0), Vector3.UP)
	camera.current = true


func apply_quality(quality: String) -> void:
	GraphicsQuality.apply_scene(quality, sun, environment)


## Follow the 2D state of the scene: scroll (pixels), bank (radians), wing phase.
func update(scroll: Vector2, bank: float, flap: float, delta: float) -> void:
	_forward = fposmod(_forward + FORWARD_SPEED * delta, TILE)
	var offset := Vector3(-scroll.x * METRES_PER_PIXEL, -scroll.y * METRES_PER_PIXEL * 0.5,
			_forward)
	_terrain.position = Vector3(fposmod(offset.x + TILE / 2.0, TILE) - TILE / 2.0,
			offset.y, offset.z)
	_bird.rotation = Vector3(0, 0, -bank)
	var lift := sin(flap)
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation = Vector3(0, 0, side * (0.15 + 0.55 * lift))


## Terrain height at (x, z) of a tile: periodic over TILE in both directions.
static func height(x: float, z: float) -> float:
	var k := TAU / TILE
	return 7.0 * sin(2.0 * k * x) * cos(k * z) + 3.0 * sin(5.0 * k * (x + z)) \
			+ 1.5 * cos(9.0 * k * x - 4.0 * k * z) - 4.0


func _terrain_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := TILE / CELLS
	for i in CELLS + 1:
		for j in CELLS + 1:
			var x := -TILE / 2.0 + i * step
			var z := -TILE / 2.0 + j * step
			tool.set_uv(Vector2(i, j) / CELLS)
			tool.add_vertex(Vector3(x, height(x, z), z))
	for i in CELLS:
		for j in CELLS:
			var a := i * (CELLS + 1) + j
			var b := a + CELLS + 1
			# Clockwise seen from above: the front faces of Godot point up.
			tool.add_index(a)
			tool.add_index(b)
			tool.add_index(a + 1)
			tool.add_index(a + 1)
			tool.add_index(b)
			tool.add_index(b + 1)
	tool.generate_normals()
	return tool.commit()


func _build_bird() -> void:
	_bird = Node3D.new()
	_bird.position = Vector3(0, BIRD_HEIGHT, 0)
	add_child(_bird)
	var feathers := WorldKit.plain(Color("#F3F5FA"), 0.7)
	var accent := WorldKit.plain(Color("#FFC857"), 0.5)
	var dark := WorldKit.plain(Color("#2A2F3A"), 0.4)
	# The bird flies towards -Z (away from the camera).
	var body := WorldKit.sphere(_bird, 0.18, Vector3.ZERO, feathers)
	body.scale = Vector3(0.9, 0.75, 1.6)
	WorldKit.sphere(_bird, 0.11, Vector3(0, 0.08, -0.3), feathers)
	var beak := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.035
	cone.height = 0.12
	beak.mesh = cone
	beak.rotation = Vector3(-PI / 2.0, 0, 0)
	beak.position = Vector3(0, 0.07, -0.44)
	beak.material_override = accent
	_bird.add_child(beak)
	for side in [-1.0, 1.0]:
		WorldKit.sphere(_bird, 0.018, Vector3(side * 0.06, 0.12, -0.38), dark)
	var tail := WorldKit.box(_bird, Vector3(0.22, 0.02, 0.2), Vector3(0, 0.02, 0.36), feathers)
	tail.rotation = Vector3(0.2, 0, 0)
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.12, 0.05, -0.02)
		_bird.add_child(shoulder)
		var wing := WorldKit.box(shoulder, Vector3(0.6, 0.02, 0.26),
				Vector3(side * 0.3, 0, 0.02), feathers)
		var tip := WorldKit.box(wing, Vector3(0.18, 0.018, 0.16), Vector3(side * 0.36, 0, 0.06),
				accent)
		tip.rotation = Vector3(0, side * 0.3, 0)
		_wings.append(shoulder)
