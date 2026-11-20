extends SceneTree
## Headless tests of the cockpit:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Exit code 0 when every check passes.

const OpenMindScript := preload("res://addons/openmind/openmind.gd")

var _failures := 0
var _checks := 0
var _om: Node
var _now := 1000.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_om = root.get_node_or_null("OpenMind")
	if _om == null:
		_om = OpenMindScript.new()
		_om.name = "OpenMind"
		root.add_child(_om)
	_om.autoconnect = false
	_om.disconnect_from_bridge()
	_om.clock = func() -> float: return _now

	test_command_gate()
	test_frames_and_heartbeat()
	test_marker_and_event_frames()
	test_theme()
	test_bridge_url()
	await test_cockpit()

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, what: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", what)


func _go_live() -> void:
	_om.set_connected_for_test(true)
	_om.handle_frame('{"kind":"hello","bridge":"t","protocol":"1.0.1","mqtt_connected":true}')
	_status("running")


func _status(state: String) -> void:
	_om.handle_frame(JSON.stringify({"topic": "openmind/v1/status", "kind": "status",
		"message": {"v": 1, "ts": 1.0, "state": state, "model": "m", "user": "P00"}}))


func _command(name: String, confidence: float, seq: int) -> void:
	_om.handle_frame(JSON.stringify({"topic": "openmind/v1/commands", "kind": "command",
		"message": {"v": 1, "ts": 1.0, "command": name, "confidence": confidence,
			"user": "P00", "seq": seq}}))


# --- Tests ---------------------------------------------------------------------------


func test_command_gate() -> void:
	var gate := CommandGate.new(0.8)
	check(not gate.accept({"confidence": 0.9, "seq": 1}, false), "gate refuses a dead decoder")
	check(gate.last_refusal == "decoder", "refusal reason decoder")
	check(not gate.accept({"confidence": 0.79, "seq": 1}, true), "gate refuses low confidence")
	check(gate.last_refusal == "confidence", "refusal reason confidence")
	check(gate.accept({"confidence": 0.8, "seq": 1}, true), "gate accepts at the threshold")
	check(not gate.accept({"confidence": 0.9, "seq": 1}, true), "gate refuses a duplicate seq")
	check(gate.last_refusal == "stale", "refusal reason stale")
	gate.reset()
	check(gate.accept({"confidence": 0.9, "seq": 0}, true), "seq 0 accepted after reset")


func test_frames_and_heartbeat() -> void:
	var commands: Array = []
	var on_command := func(c: Dictionary) -> void: commands.append(c)
	_om.command_received.connect(on_command)

	check(not _om.decoder_alive, "not alive before any status")
	_go_live()
	check(_om.mqtt_connected, "hello sets the MQTT state")
	check(_om.protocol_version == "1.0.1", "hello gives the protocol version")
	check(_om.decoder_alive, "alive after a running status")
	_now += 1.9
	check(_om.compute_alive(), "still alive 1.9 s after the status")
	_now += 0.2
	check(not _om.compute_alive(), "not alive 2.1 s after the status")
	_status("running")
	check(_om.decoder_alive, "alive again with a new status")
	_status("calibrating")
	check(not _om.decoder_alive, "not alive when the decoder is calibrating")
	_status("running")
	_om.handle_frame('{"kind":"bridge","mqtt_connected":false}')
	check(not _om.decoder_alive, "not alive when the broker is lost")
	_om.handle_frame('{"kind":"bridge","mqtt_connected":true}')
	_status("running")

	_command("left", 0.9, 1)
	check(commands.size() == 1 and commands[0]["command"] == "left", "command signal")
	_om.handle_frame("not json")
	_om.handle_frame('{"kind":"command","message":"oops"}')
	_om.handle_frame('{"kind":"future_kind","message":{}}')
	check(commands.size() == 1, "malformed and unknown frames are ignored")
	_om.command_received.disconnect(on_command)

	_om.set_connected_for_test(false)
	check(not _om.decoder_alive and not _om.mqtt_connected, "closing the socket stops all")


func test_marker_and_event_frames() -> void:
	var marker: Dictionary = JSON.parse_string(
			OpenMindScript.build_marker_frame("cue", "left", 0, ""))
	check(marker["kind"] == "marker", "marker frame kind")
	check(marker["message"]["trial"] == null and marker["message"]["scene"] == null,
			"trial 0 and empty scene are sent as null")
	check(float(marker["message"]["ts"]) > 1.0e9, "marker ts is Unix time")
	marker = JSON.parse_string(OpenMindScript.build_marker_frame("cue", "right", 3, "bird"))
	check(int(marker["message"]["trial"]) == 3 and marker["message"]["scene"] == "bird",
			"trial and scene are kept")
	var event: Dictionary = JSON.parse_string(
			OpenMindScript.build_event_frame("twin", "lap", {"time_s": 4.2}))
	check(event["kind"] == "event" and event["message"]["data"]["time_s"] == 4.2, "event frame")
	check(not _om.send_marker("cue", "left"), "send_marker is false without a bridge")
	check(not _om.send_marker("unknown", "left"), "send_marker refuses unknown types")


func test_bridge_url() -> void:
	check(OpenMindScript.bridge_url_from(PackedStringArray(["--bridge=ws://h:1"]), "ws://e:2")
			== "ws://h:1", "command line wins over the environment")
	check(OpenMindScript.bridge_url_from(PackedStringArray([]), "ws://e:2") == "ws://e:2",
			"environment used without argument")
	check(OpenMindScript.bridge_url_from(PackedStringArray([]), "") == "", "default kept")


func test_theme() -> void:
	var theme := OpenMindTheme.build()
	check(theme.default_font != null, "Space Grotesk is loaded")
	check(theme.default_font_size >= 16, "readable font size")
	var normal: StyleBox = theme.get_stylebox("normal", "Button")
	var height := theme.default_font_size + normal.content_margin_top + normal.content_margin_bottom
	check(height >= OpenMindTheme.MIN_TARGET - 2, "buttons are about 44 px high or more")
	check(_contrast(OpenMindTheme.TEXT, OpenMindTheme.BACKGROUND) >= 7.0, "text contrast AAA")
	check(_contrast(OpenMindTheme.TEXT, OpenMindTheme.PANEL) >= 7.0, "panel text contrast AAA")
	check(_contrast(OpenMindTheme.TEXT_MUTED, OpenMindTheme.PANEL) >= 4.5, "muted text AA")
	check(_contrast(OpenMindTheme.WARNING, OpenMindTheme.PANEL) >= 4.5, "warning text AA")


func test_cockpit() -> void:
	var main: Node = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.current_scene_id == "robot_twin", "starts on the robot twin")
	check(main.find_child("CommandPanel", true, false) != null, "command panel present")
	for scene_id in main.SCENES:
		check(main.switch_scene(scene_id), "switch to %s" % scene_id)
		await process_frame
		check(main.viewport.get_child_count() == 1, "one scene at a time (%s)" % scene_id)
	check(not main.switch_scene("nope"), "unknown scene refused")

	main.switch_scene("robot_twin")  # threshold 0.8
	await process_frame
	var scene: Node = main.current_scene
	_go_live()
	_command("forward", 0.95, 10)
	check(scene.last_command == "forward", "scene receives an accepted command")
	check(main.command_panel.command_label.text == "forward", "command panel shows it")
	_command("left", 0.5, 11)
	check(scene.last_command == "rest", "low confidence stops the scene object")
	_command("left", 0.9, 12)
	check(scene.last_command == "left", "next good command applies")
	_now += 2.5
	_om._update_alive()
	check(scene.last_command == "rest", "safety stop without status")
	_status("running")
	_command("right", 0.9, 0)  # decoder restarted: seq from 0
	check(scene.last_command == "right", "seq restart accepted after a silence")

	main.set_panels_visible(false)
	check(not main.panels.visible, "panels can be hidden")
	main.queue_free()
	await process_frame


static func _luminance(color: Color) -> float:
	var channels: Array[float] = []
	for c in [color.r, color.g, color.b]:
		channels.append(c / 12.92 if c <= 0.03928 else pow((c + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
