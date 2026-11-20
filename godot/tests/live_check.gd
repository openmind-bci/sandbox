extends SceneTree
## Live check of the cockpit against a running bridge (no window needed):
##   openmind-sandbox bridge &
##   openmind-sandbox keys --script examples/keys-demo.yaml &
##   godot --headless --path godot --script res://tests/live_check.gd
## Exit code 0 when the cockpit received live commands and its scene applied them.

const OpenMindScript := preload("res://addons/openmind/openmind.gd")
const TIMEOUT_S := 15.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var om: Node = root.get_node_or_null("OpenMind")
	if om == null:
		om = OpenMindScript.new()
		om.name = "OpenMind"
		root.add_child(om)
	var main: Node = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	var seen := {}
	var applied := {}
	om.command_received.connect(func(c: Dictionary) -> void: seen[c["command"]] = true)
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < TIMEOUT_S:
		await process_frame
		applied[main.current_scene.last_command] = true
		if seen.has("forward") and seen.has("left") and applied.has("forward"):
			break
	print("connected=%s mqtt=%s alive=%s seen=%s applied=%s panel=%s" % [
		om.connected, om.mqtt_connected, om.decoder_alive, seen.keys(), applied.keys(),
		main.command_panel.command_label.text])
	var ok: bool = om.connected and seen.has("forward") and applied.has("forward")
	quit(0 if ok else 1)
