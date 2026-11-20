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
	var lowest := {"C4": 0.0}  # a dictionary: lambdas capture locals by value
	var brain: BrainPanel = main.brain_panel
	om.command_received.connect(func(c: Dictionary) -> void:
			if c["command"] == "left" and brain.values.get("C4") != null:
				lowest["C4"] = minf(lowest["C4"], float(brain.values["C4"])))
	while (Time.get_ticks_msec() - start) / 1000.0 < TIMEOUT_S:
		await process_frame
		applied[main.current_scene.last_command] = true
		var brain_ok: bool = brain.messages == 0 or float(lowest["C4"]) < -0.2
		if seen.has("forward") and seen.has("left") and applied.has("forward") and brain_ok:
			break
	print("brain messages=%d lowest C4 rel_mu during left=%.2f" % [brain.messages,
		lowest["C4"]])
	print("connected=%s mqtt=%s alive=%s seen=%s applied=%s panel=%s" % [
		om.connected, om.mqtt_connected, om.decoder_alive, seen.keys(), applied.keys(),
		main.command_panel.command_label.text])
	var ok: bool = om.connected and seen.has("forward") and applied.has("forward")
	quit(0 if ok else 1)
