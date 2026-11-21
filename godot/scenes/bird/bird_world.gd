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
## Camera: metres behind the bird and above it.
const CAMERA_DISTANCE := 2.0
const CAMERA_RISE := 1.2

var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D

const PIGEON := "res://assets/models/pigeon/pigeon.glb"
const SHRIKE := "res://assets/models/shrike/"
## Turn of the shrike so that it flies away from the camera (towards -Z).
const SHRIKE_YAW := PI
## Wing bones, root first, with the share of the beat they take and their lag
## (radians): the shoulder leads, the forearm and the hand follow.
const WING_BONES: Array[String] = ["shoulder.L", "shoulder.R", "Wing.001.L", "Wing.001.R",
	"Wing.002.L", "Wing.002.R", "w_feather.L", "w_feather.R"]
const WING_SHARE: Array[float] = [0.45, 0.45, 0.8, 0.8, 0.9, 0.9, 0.6, 0.6]
const WING_LAG: Array[float] = [0.0, 0.0, 0.9, 0.9, 1.7, 1.7, 2.2, 2.2]
## Share of the fold (wing tucked back on the up-stroke) taken by each bone.
const WING_FOLD: Array[float] = [0.0, 0.0, 0.9, 0.9, 0.6, 0.6, 0.3, 0.3]
## Local axis around which the forearm and hand fold back.
const FOLD_AXIS := Vector3(0, 0, 1)
## Wing beat: frequency (Hz) and amplitude (radians), cruising and climbing.
const BEAT_HZ := Vector2(2.0, 3.0)
## Clouds below the bird: number of small clusters, the half size of the area
## they loop over (metres), and their height band under the bird.
const CLOUD_CLUSTERS := 12
const CLOUD_AREA := 60.0
const CLOUD_DEPTH := Vector2(7.0, 15.0)
const BEAT_AMPLITUDE := Vector2(0.45, 0.65)
## Local axis of the wing bones around which the wings beat.
const WING_AXIS := Vector3(0, 1, 0)
const FLAP := "flap-wings-animation"

var _terrain: Node3D
var _animation: AnimationPlayer
var _skeleton: Skeleton3D
var _wing_bones: Array[int] = []
var _wing_rest: Array[Quaternion] = []
var _wing_index: Array[int] = []  # index in WING_BONES of each found bone
var _clouds: Array[Node3D] = []
var _cloud_base: Array[Vector3] = []
var _beat_phase := 0.0
var _beat_hz := BEAT_HZ.x
var _beat_amplitude := BEAT_AMPLITUDE.x
var _bird: Node3D
var _wings: Array[Node3D] = []
var _forward := 0.0


func setup() -> void:
	environment = WorldKit.environment(self, WorldKit.OUTDOOR_SKY, 0.9)
	environment.fog_enabled = true
	environment.fog_light_color = Color("#BFD0E6")
	environment.fog_density = 0.0025
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
	_build_clouds()
	_build_bird()
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 900.0
	add_child(camera)
	# Close behind the bird and slightly above it, aimed at it: the bird stays at
	# the centre of the screen, under the fixation cross and the cues.
	camera.position = Vector3(0, BIRD_HEIGHT + CAMERA_RISE, CAMERA_DISTANCE)
	camera.look_at(Vector3(0, BIRD_HEIGHT, 0), Vector3.UP)
	camera.current = true


func apply_quality(quality: String) -> void:
	GraphicsQuality.apply_scene(quality, sun, environment)


## Follow the 2D state of the scene: scroll (pixels), bank (radians), wing phase.
func update(scroll: Vector2, bank: float, flap: float, delta: float,
		flapping: bool = false) -> void:
	_forward = fposmod(_forward + FORWARD_SPEED * delta, TILE)
	var offset := Vector3(-scroll.x * METRES_PER_PIXEL, -scroll.y * METRES_PER_PIXEL * 0.5,
			_forward)
	_terrain.position = Vector3(fposmod(offset.x + TILE / 2.0, TILE) - TILE / 2.0,
			offset.y, offset.z)
	_bird.rotation = Vector3(0, 0, -bank)
	# Clouds move with the landscape; being closer, they pass faster: they show
	# that the bird moves forward. Each loops over the area around the bird.
	for i in _clouds.size():
		var p := _cloud_base[i] + Vector3(offset.x, offset.y * 0.6, _forward)
		p.x = wrapf(p.x, -CLOUD_AREA, CLOUD_AREA)
		p.z = wrapf(p.z, -CLOUD_AREA * 1.6, CLOUD_AREA * 0.4)
		_clouds[i].position = p
	if _animation != null:
		# Quick wing beats while climbing, slow ones while gliding.
		_animation.speed_scale = 1.6 if flapping else 0.35
	var lift := sin(flap)
	if not _wing_bones.is_empty():
		# Continuous, smooth beats: frequency and amplitude glide between
		# cruising and climbing instead of jumping.
		var blend := minf(1.0, 3.0 * delta)
		_beat_hz = lerpf(_beat_hz, BEAT_HZ.y if flapping else BEAT_HZ.x, blend)
		_beat_amplitude = lerpf(_beat_amplitude,
				BEAT_AMPLITUDE.y if flapping else BEAT_AMPLITUDE.x, blend)
		_beat_phase = fmod(_beat_phase + TAU * _beat_hz * delta, TAU)
		_pose_wings(_beat_phase, _beat_amplitude)
		# The body rises a little on each down-stroke.
		_bird.position.y = BIRD_HEIGHT + 0.035 * sin(_beat_phase - 0.8)
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation = Vector3(0, 0, side * (0.15 + 0.55 * lift))


## Terrain height at (x, z) of a tile: periodic over TILE in both directions.
static func height(x: float, z: float) -> float:
	var k := TAU / TILE
	return 7.0 * sin(2.0 * k * x) * cos(k * z) + 3.0 * sin(5.0 * k * (x + z)) \
			+ 1.5 * cos(9.0 * k * x - 4.0 * k * z) - 4.0


## A few soft clusters of billboard puffs, sparse, below the bird.
func _build_clouds() -> void:
	var puff := GradientTexture2D.new()
	puff.width = 128
	puff.height = 128
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	gradient.add_point(0.55, Color(1, 1, 1, 0.45))
	puff.gradient = gradient
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in CLOUD_CLUSTERS:
		var cluster := Node3D.new()
		add_child(cluster)
		for k in rng.randi_range(3, 6):
			var sprite := Sprite3D.new()
			sprite.texture = puff
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.shaded = false
			sprite.double_sided = true
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			sprite.pixel_size = rng.randf_range(0.05, 0.11)
			sprite.modulate = Color(1, 1, 1, rng.randf_range(0.55, 0.85))
			sprite.position = Vector3(rng.randf_range(-6, 6), rng.randf_range(-1, 1.5),
					rng.randf_range(-5, 5))
			cluster.add_child(sprite)
		_clouds.append(cluster)
		_cloud_base.append(Vector3(rng.randf_range(-CLOUD_AREA, CLOUD_AREA),
				BIRD_HEIGHT - rng.randf_range(CLOUD_DEPTH.x, CLOUD_DEPTH.y),
				rng.randf_range(-CLOUD_AREA * 1.6, CLOUD_AREA * 0.4)))


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
	if _build_shrike():
		return
	# CC0 pigeon by mujtaba-io (OpenGameArt), rigged and animated; it faces +Z
	# and flies here towards -Z: a half turn.
	var pigeon := WorldKit.model_file(_bird, PIGEON, Vector3(0, -0.3, 0), PI, 1.3)
	if pigeon != null:
		# The model has no texture: give it the slate grey of a pigeon.
		var feathers := WorldKit.plain(Color("#6F7A8C"), 0.85)
		var stack: Array[Node] = [pigeon]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is MeshInstance3D:
				(node as MeshInstance3D).material_override = feathers
		_animation = WorldKit.find_child_of_type(pigeon, "AnimationPlayer")
		if _animation != null and _animation.has_animation(FLAP):
			_animation.get_animation(FLAP).loop_mode = Animation.LOOP_LINEAR
			_animation.play(FLAP)
		return
	_simple_bird()


## CC0 yellow-billed shrike by pistachio (OpenGameArt): textured feathers with
## alpha, rigged without animation; the wings beat by turning their bones.
func _build_shrike() -> bool:
	var shrike := WorldKit.model_file(_bird, SHRIKE + "shrike.glb", Vector3(0, -0.45, 0),
			SHRIKE_YAW, 1.5)
	if shrike == null:
		return false
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(SHRIKE + "shrike_diff.png")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.4
	material.normal_enabled = true
	material.normal_texture = load(SHRIKE + "shrike_norm.png")
	material.roughness_texture = load(SHRIKE + "shrike_rgh.png")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # feathers seen from both sides
	var stack: Array[Node] = [shrike]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			(node as MeshInstance3D).material_override = material
	_skeleton = WorldKit.find_child_of_type(shrike, "Skeleton3D")
	if _skeleton != null:
		for k in WING_BONES.size():
			var index := _skeleton.find_bone(WING_BONES[k])
			if index >= 0:
				_wing_bones.append(index)
				_wing_rest.append(_skeleton.get_bone_pose_rotation(index))
				_wing_index.append(k)
	return true


## Beat the wings of the shrike at [param phase] with [param amplitude]: each
## bone turns by its share of the beat, later along the wing, mirrored between
## left and right.
func _pose_wings(phase: float, amplitude: float) -> void:
	for i in _wing_bones.size():
		var k := _wing_index[i]
		var side := 1.0 if WING_BONES[k].ends_with(".L") else -1.0
		var local := _stroke(phase - WING_LAG[k])
		var angle := amplitude * WING_SHARE[k] * local
		# Tuck the wing back while it rises, spread it while it beats down.
		var fold := amplitude * WING_FOLD[k] * maxf(0.0, local)
		_skeleton.set_bone_pose_rotation(_wing_bones[i], _wing_rest[i]
				* Quaternion(WING_AXIS, side * angle) * Quaternion(FOLD_AXIS, side * fold))


## Wing position along a beat, from -1 (down) to 1 (up): a smooth wave whose
## down-stroke lasts longer than the up-stroke, as in real flight.
static func _stroke(phase: float) -> float:
	var t := fposmod(phase, TAU) / TAU
	var down := 0.6  # share of the cycle spent beating down
	if t < down:
		return cos(PI * t / down)  # from 1 (up) to -1 (down)
	return -cos(PI * (t - down) / (1.0 - down))  # back up, faster


## Geometric bird when the pigeon model is not downloaded.
func _simple_bird() -> void:
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
