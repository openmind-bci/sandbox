extends SceneTree
## Record the cockpit in demo mode, frame by frame, for the README clips.
##
## Run from the repository root, with a fixed frame rate so that the clips do
## not depend on the speed of the machine:
##
##     godot --path godot --resolution 1600x900 --fixed-fps 20 --disable-vsync \
##         --script "$PWD/tools/record_demo.gd" -- /tmp/openmind-frames
##
## Writes <out>/<scene>/0000.jpg... (21 s per scene: one full demo loop), then
## run tools/make_demo_media.py. Mouse and keyboard are ignored meanwhile.

const SCENES: Array[String] = ["robot_twin", "wheelchair", "boat", "bird"]
const RECORD_S := 21.0

var out_dir := ""
var main: Node
var clip := ""
var frame := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_temp_dir().path_join("openmind-frames")
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	root.unfocusable = true
	main = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _process(_delta: float) -> bool:
	if clip != "":
		var image := root.get_texture().get_image()
		image.save_jpg(out_dir.path_join(clip).path_join("%04d.jpg" % frame), 0.9)
		frame += 1
	return false


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _record(scene_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(scene_id))
	frame = 0
	clip = scene_id
	await _wait(RECORD_S)
	clip = ""
	print("recorded %s: %d frames" % [scene_id, frame])


func _run() -> void:
	await _wait(2.0)
	main.set_quality(GraphicsQuality.REALISTIC, false)
	var signal_fold := main.find_child("SignalFold", true, false)
	if signal_fold != null:
		signal_fold.folded = true  # no EEG in demo mode: show the command panel instead
	main.command_panel.toggle_demo()
	for scene_id in SCENES:
		main.switch_scene(scene_id)
		await _wait(1.0)
		if scene_id == "bird":
			main.current_scene.start_session()  # the demo follows the calibration cues
			await _wait(1.5)
		await _record(scene_id)
	quit()
