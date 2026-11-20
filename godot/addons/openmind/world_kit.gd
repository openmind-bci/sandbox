class_name WorldKit
extends RefCounted
## Shared helpers of the 3D scenes: CC0 Poly Haven materials, sky, sun, simple
## shapes. Every scene builds its world in code from its data files, so the
## scenes stay small and the assets are loaded only when present.

const TEXTURES := "res://assets/polyhaven/"
const INDOOR_SKY := "small_empty_room_3"
const OUTDOOR_SKY := "kloofendal_48d_partly_cloudy_puresky"


## Poly Haven material with world-space triplanar mapping, [param tiles] per metre.
static func textured(asset: String, tiles: float, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var base := TEXTURES + asset + "/" + asset
	if ResourceLoader.exists(base + "_diff_1k.jpg"):
		material.albedo_texture = load(base + "_diff_1k.jpg")
		material.normal_enabled = true
		material.normal_texture = load(base + "_nor_gl_1k.jpg")
		material.roughness_texture = load(base + "_rough_1k.jpg")
		material.albedo_color = tint
	else:
		material.albedo_color = Color("#8A8F99") * tint
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * tiles
	return material


static func plain(colour: Color, roughness: float = 0.6, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	return material


static func glowing(colour: Color, energy: float = 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## World environment lit by an HDRI sky (filmic tone mapping, soft exposure).
static func environment(parent: Node, sky_asset: String, exposure: float = 0.8) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var panorama := PanoramaSkyMaterial.new()
	var hdr := TEXTURES + sky_asset + "/" + sky_asset + "_1k.hdr"
	if ResourceLoader.exists(hdr):
		panorama.panorama = load(hdr)
	sky.sky_material = panorama
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposure
	env.ssao_radius = 0.15
	env.ssao_intensity = 1.5
	env.glow_intensity = 0.4
	var node := WorldEnvironment.new()
	node.environment = env
	parent.add_child(node)
	return env


static func sun(parent: Node, pitch_deg: float = -55.0, yaw_deg: float = 35.0,
		energy: float = 0.8, shadow_distance: float = 8.0) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0)
	light.light_energy = energy
	light.shadow_enabled = true
	light.directional_shadow_max_distance = shadow_distance
	parent.add_child(light)
	return light


static func box(parent: Node, size: Vector3, position: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(parent, mesh, position, material)


static func cylinder(parent: Node, radius: float, height: float, position: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return _instance(parent, mesh, position, material)


static func sphere(parent: Node, radius: float, position: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = 2.0 * radius
	return _instance(parent, mesh, position, material)


## Flat glowing ring on the ground (waypoints).
static func ring(parent: Node, radius: float, position: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.015
	mesh.outer_radius = radius
	mesh.rings = 48
	var node := _instance(parent, mesh, position, material)
	node.scale = Vector3(1, 0.15, 1)
	return node


static func label(parent: Node, text: String, position: Vector3, size: float = 0.0015) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.font_size = 64
	node.pixel_size = size
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.position = position
	node.modulate = OpenMindTheme.TEXT
	parent.add_child(node)
	return node


static func _instance(parent: Node, mesh: Mesh, position: Vector3,
		material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.material_override = material
	parent.add_child(node)
	return node
