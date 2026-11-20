extends SceneTree
## Plays the quick calibration protocol through a running bridge (no window):
##   openmind-sandbox bridge &
##   godot --headless --path godot --script res://tests/live_calibration.gd
## The markers then appear on MQTT and on the LSL stream openmind-markers.

const OpenMindScript := preload("res://addons/openmind/openmind.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var om: Node = root.get_node_or_null("OpenMind")
	if om == null:
		om = OpenMindScript.new()
		om.name = "OpenMind"
		root.add_child(om)
	var scene: Node = load("res://scenes/bird/bird.tscn").instantiate()
	scene.protocol_path = "res://tests/data/calibration_quick.json"
	root.add_child(scene)
	var start := Time.get_ticks_msec()
	while not om.connected and Time.get_ticks_msec() - start < 5000:
		await process_frame
	scene.start_session()
	while scene.running and Time.get_ticks_msec() - start < 30000:
		await process_frame
	await create_timer(0.5).timeout
	print("sent=%d failed=%d" % [scene.markers_sent, scene.markers_failed])
	quit(0 if scene.markers_failed == 0 and not scene.running else 1)
