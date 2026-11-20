class_name BrainPanel
extends VBoxContainer
## Live 3D brain: band power per electrode (openmind/v1/bandpower), coloured at the
## sensors on a schematic brain. Drag to rotate; Top / Left / Right views; mu or
## beta band; electrode names on demand.

const ELECTRODES_PATH := "res://data/electrodes_10_10.json"
const LEGEND := "Blue: decrease (desynchronization) · orange: increase · grey: electrode " \
		+ "not OK.\nActivity estimated at the sensors: this is not a source localisation."
## Time constant of the colour transitions, in seconds.
const SMOOTHING_S := 0.25
## Largest colouring rate (the fsaverage mesh has about 20,000 vertices).
const MAX_RECOLOR_HZ := 20.0
const VIEWS := {"Top": Vector2(0.0, -1.45), "Left": Vector2(-PI / 2.0, -0.2),
	"Right": Vector2(PI / 2.0, -0.2)}

## "rel_mu" or "rel_beta".
var band := "rel_mu"
var show_electrodes := false
## Current (smoothed) and target values: label -> float or null.
var values := {}
var targets := {}
var messages := 0

var mesh := BrainMesh.create()
var colors := BrainColors.new()
var positions := {}  # all 10-10 electrodes, MNE frame

var viewport: SubViewport
var _instance: MeshInstance3D
var _pivot: Node3D
var _camera: Camera3D
var _markers: Node3D
var _legend: Label
var _yaw := 0.0
var _pitch := -0.6
var _dirty := true
var _since_recolor := 0.0
var _channels_key := ""


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	positions = _load_positions()
	_build_viewport()
	_build_controls()
	_legend = Label.new()
	_legend.text = LEGEND + ("\nBrain: FreeSurfer fsaverage." if mesh.source == "fsaverage"
			else "\nSchematic brain (run tools/fetch_fsaverage.py for fsaverage).")
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.add_theme_font_size_override("font_size", 14)
	_legend.add_theme_color_override("font_color", OpenMindTheme.TEXT_MUTED)
	add_child(_legend)
	set_view("Top")
	var openmind := get_node_or_null("/root/OpenMind")
	if openmind != null:
		openmind.bandpower_received.connect(show_bandpower)
	_recolor()


## Apply a band power message (also the entry point of the tests).
func show_bandpower(message: Dictionary) -> void:
	messages += 1
	var channels: Array = message.get("channels", [])
	var key := ",".join(channels.map(func(c: Dictionary) -> String: return str(c["label"])))
	if key != _channels_key:
		_channels_key = key
		_prepare(channels)
	for c in channels:
		var label := str(c["label"])
		var value: Variant = c.get(band) if c.get("ok", false) else null
		targets[label] = value
		if value == null or values.get(label) == null:
			values[label] = value  # no smoothing into or out of "not OK"
	_dirty = true


func set_band(new_band: String) -> void:
	band = new_band
	targets.clear()
	values.clear()
	_dirty = true


func set_view(view_name: String) -> void:
	var angles: Vector2 = VIEWS[view_name]
	_yaw = angles.x
	_pitch = angles.y
	_update_camera()


func _process(delta: float) -> void:
	var alpha := 1.0 - exp(-delta / SMOOTHING_S)
	for label in targets:
		var target: Variant = targets[label]
		var current: Variant = values.get(label)
		if target == null or current == null:
			continue
		var next := lerpf(float(current), float(target), alpha)
		if absf(next - float(current)) > 1e-4:
			values[label] = next
			_dirty = true
	_since_recolor += delta
	if _dirty and _since_recolor >= 1.0 / MAX_RECOLOR_HZ:
		_recolor()


func _prepare(channels: Array) -> void:
	var used := {}
	for c in channels:
		var label := str(c["label"])
		if positions.has(label):
			used[label] = positions[label]
	colors.prepare(mesh.vertices, used)
	for child in _markers.get_children():
		child.queue_free()
	for label in used:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.003
		sphere.height = 0.006
		marker.mesh = sphere
		marker.position = BrainMesh.to_godot(mesh.project(used[label]) * 1.0)
		var text := Label3D.new()
		text.text = label
		text.font_size = 40
		text.pixel_size = 0.0004
		text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		text.no_depth_test = true
		text.position = Vector3(0, 0.008, 0)
		marker.add_child(text)
		_markers.add_child(marker)
	values.clear()
	targets.clear()


func _recolor() -> void:
	_dirty = false
	_since_recolor = 0.0
	_instance.mesh = mesh.build(colors.colorize(values) if not colors.labels.is_empty()
			else PackedColorArray())


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(300, 260)
	container.gui_input.connect(_on_view_input)
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # winding differs between sources
	_instance = MeshInstance3D.new()
	_instance.material_override = material
	world.add_child(_instance)
	_markers = Node3D.new()
	_markers.visible = show_electrodes
	world.add_child(_markers)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.9, 0.5, 0.0)
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(0.6, PI + 0.4, 0.0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	environment.background_mode = Environment.BG_CLEAR_COLOR
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	world.add_child(world_env)

	_pivot = Node3D.new()
	_pivot.position = BrainMesh.to_godot(mesh.centre)
	world.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 0.36)
	_camera.fov = 40.0
	_pivot.add_child(_camera)


func _build_controls() -> void:
	var row := HBoxContainer.new()
	var band_choice := OptionButton.new()
	band_choice.add_item("mu (8-13 Hz)")
	band_choice.add_item("beta (13-30 Hz)")
	band_choice.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	band_choice.item_selected.connect(func(i: int) -> void:
			set_band("rel_mu" if i == 0 else "rel_beta"))
	row.add_child(band_choice)
	for view_name in VIEWS:
		var button := Button.new()
		button.text = view_name
		button.custom_minimum_size = Vector2(OpenMindTheme.MIN_TARGET, OpenMindTheme.MIN_TARGET)
		button.pressed.connect(set_view.bind(view_name))
		row.add_child(button)
	add_child(row)
	var labels := CheckBox.new()
	labels.text = "Electrodes"
	labels.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	labels.toggled.connect(func(on: bool) -> void:
			show_electrodes = on
			_markers.visible = on)
	add_child(labels)


func _on_view_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= motion.relative.x * 0.01
		_pitch = clampf(_pitch - motion.relative.y * 0.01, -1.55, 1.2)
		_update_camera()


func _update_camera() -> void:
	if _pivot != null:
		_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


func _load_positions() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ELECTRODES_PATH))
	var result := {}
	if typeof(data) == TYPE_DICTIONARY:
		for label in data["electrodes"]:
			var p: Array = data["electrodes"][label]
			result[label] = Vector3(p[0], p[1], p[2])
	return result
