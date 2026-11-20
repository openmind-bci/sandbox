class_name GraphicsQuality
extends RefCounted
## Graphics quality of the cockpit: "realistic" (shadows, ambient occlusion,
## glow, full resolution, 60 fps) or "light" (no shadows nor effects, 3D at 75 %
## of the resolution, 30 fps) for when the decoder trains on the same machine.
## Scenes that support it implement `apply_quality(quality: String)`.
## The choice is remembered in user://openmind.cfg.

const REALISTIC := "realistic"
const LIGHT := "light"

## Where the choice is remembered; tests point it to a scratch file.
static var settings_path := "user://openmind.cfg"


static func load_saved() -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return REALISTIC
	var value := str(config.get_value("graphics", "quality", REALISTIC))
	return value if value in [REALISTIC, LIGHT] else REALISTIC


static func save(quality: String) -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("graphics", "quality", quality)
	config.save(settings_path)


## Engine-wide settings and the 3D viewport of the scenes.
static func apply_engine(quality: String, viewport: SubViewport) -> void:
	var light := quality == LIGHT
	Engine.max_fps = 30 if light else 60
	if viewport != null:
		viewport.scaling_3d_scale = 0.75 if light else 1.0
		viewport.msaa_3d = Viewport.MSAA_DISABLED if light else Viewport.MSAA_2X


## Apply [param quality] to a light and an environment of a scene.
static func apply_scene(quality: String, sun: DirectionalLight3D, environment: Environment) -> void:
	var realistic := quality == REALISTIC
	if sun != null:
		sun.shadow_enabled = realistic
	if environment != null:
		environment.ssao_enabled = realistic
		environment.glow_enabled = realistic
