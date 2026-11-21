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
	ObjectController.settings_path = "user://openmind_tests.cfg"
	GraphicsQuality.settings_path = "user://openmind_tests.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ObjectController.settings_path))

	test_command_gate()
	test_frames_and_heartbeat()
	test_marker_and_event_frames()
	test_theme()
	test_bridge_url()
	test_twin_robot()
	test_twin_course()
	test_twin_full_course()
	test_calibration_protocol()
	await test_bird_scene()
	test_chair()
	await test_3d_worlds()
	await test_boat()
	await test_brain()
	await test_signal_panel()
	await test_cockpit()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(ObjectController.settings_path))
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
	var c := func(name: String, confidence: float, seq: int) -> Dictionary:
		return {"command": name, "confidence": confidence, "seq": seq}
	check(not gate.accept(c.call("left", 0.9, 1), false), "gate refuses a dead decoder")
	check(gate.last_refusal == "decoder", "refusal reason decoder")
	check(not gate.accept(c.call("left", 0.79, 1), true), "gate refuses low confidence")
	check(gate.last_refusal == "confidence", "refusal reason confidence")
	check(gate.accept(c.call("left", 0.8, 1), true), "gate accepts at the threshold")
	check(not gate.accept(c.call("left", 0.9, 1), true), "gate refuses a duplicate seq")
	check(gate.last_refusal == "stale", "refusal reason stale")
	check(gate.accept(c.call("rest", 0.05, 2), true), "rest has no threshold")
	gate.set_threshold("action", 0.9)
	check(not gate.accept(c.call("action", 0.85, 3), true), "per-command threshold")
	check(gate.accept(c.call("forward", 0.85, 3), true), "other commands keep theirs")
	gate.reset()
	check(gate.accept(c.call("left", 0.9, 0), true), "seq 0 accepted after reset")


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


func _twin(obstacles: Array[Vector3] = []) -> TwinRobot:
	var robot := TwinRobot.new(TwinRobot.load_config("res://data/robot.json"))
	robot.arena = Vector2(10, 10)
	robot.obstacles = obstacles
	robot.place(Vector2(5, 5), 0.0)
	robot.resume()
	return robot


func _drive(robot: TwinRobot, seconds: float) -> void:
	for i in roundi(seconds / 0.02):
		robot.step(0.02)


func test_twin_robot() -> void:
	var config := TwinRobot.load_config("res://data/robot.json")
	check(not config.is_empty(), "robot.json is readable")
	check(is_equal_approx(float(config["safety"]["obstacle_stop_m"]), 0.2), "stop at 20 cm")

	var robot := TwinRobot.new(config)
	robot.place(Vector2(5, 5), 0.0)
	robot.apply("forward")
	_drive(robot, 1.0)
	check(robot.state == TwinRobot.SAFETY_STOP and robot.position.x == 5.0,
			"no motion before the decoder is alive")

	robot = _twin()
	robot.apply("forward")
	_drive(robot, 1.0)
	check(absf(robot.speed - robot.acceleration) < 0.01, "forward speeds up")
	_drive(robot, 10.0)
	check(robot.speed == robot.max_speed or robot.state == TwinRobot.SAFETY_STOP,
			"speed bounded")

	robot = _twin([Vector3(6.0, 5.0, 0.1)])
	robot.apply("forward")
	_drive(robot, 20.0)
	check(robot.state == TwinRobot.SAFETY_STOP and robot.reason == "obstacle", "obstacle stop")
	check(absf(robot.obstacle - robot.obstacle_stop) < 0.01, "stops at the stop distance")
	check(robot.collisions_avoided == 1, "collision avoided counted once")
	robot.apply("left")
	_drive(robot, 1.0)
	check(robot.state == TwinRobot.PIVOTING, "can pivot away from the obstacle")

	robot = _twin()
	robot.apply("left")
	_drive(robot, 1.0)
	check(absf(rad_to_deg(robot.heading) - 90.0) < 3.0, "pivot at 90°/s")
	check(robot.position == Vector2(5, 5), "pivot in place")

	robot = _twin()
	robot.apply("action")
	_drive(robot, 0.1)
	robot.apply("rest")
	_drive(robot, 0.5)
	robot.apply("left")
	robot.apply("action")
	_drive(robot, 3.0)
	check(robot.state == TwinRobot.STOPPED and absf(absf(robot.heading) - PI) < 1e-4,
			"U-turn completes despite rest, left and action")

	robot = _twin()
	robot.apply("action")
	_drive(robot, 0.5)
	var heading := robot.heading
	robot.apply("right")
	_drive(robot, 0.5)
	check(robot.state == TwinRobot.STOPPED and is_equal_approx(robot.heading, heading),
			"right cancels the U-turn")

	robot = _twin()
	robot.apply("action")
	_drive(robot, 0.5)
	robot.apply("forward")
	_drive(robot, 0.2)
	check(robot.state == TwinRobot.MOVING, "forward interrupts the U-turn")

	robot = _twin()
	robot.apply("forward")
	_drive(robot, 0.2)
	robot.halt()
	_drive(robot, 0.2)
	check(robot.state == TwinRobot.SAFETY_STOP and robot.speed == 0.0, "decoder halt stops")
	robot.apply("forward")
	_drive(robot, 0.2)
	check(robot.speed == 0.0, "no command applied while halted")
	var telemetry := robot.telemetry()
	check(telemetry.has("x_m") and telemetry["state"] == "SAFETY_STOP", "telemetry fields")


func test_twin_course() -> void:
	var course := TwinCourse.from_file("res://data/courses/twin_default.json")
	check(course != null and course.waypoints.size() >= 2, "default course loads")
	check(course.update(Vector2(9, 9), false, 1.0).is_empty(), "timer waits for motion")
	var events := course.update(course.start_position, true, 0.5)
	check(events.size() == 1 and events[0][0] == "start", "course starts with motion")
	var kinds: Array = []
	for w in course.waypoints:
		for e in course.update(Vector2(w.x, w.y), true, 1.0):
			kinds.append(e[0])
	check(kinds.count("waypoint") == course.waypoints.size(), "each waypoint reached once")
	check(kinds.back() == "finish" and course.finished, "course finishes")
	check(is_equal_approx(course.elapsed, 0.5 + course.waypoints.size()), "elapsed time")


## Same plan as examples/keys-twin-course.yaml (and tests/test_course.py).
const COURSE_PLAN := [["rest", 1.0], ["forward", 8.5], ["right", 1.0], ["forward", 9.0],
	["right", 1.0], ["forward", 8.3], ["right", 1.0], ["forward", 5.5], ["rest", 2.0]]


func test_twin_full_course() -> void:
	var course := TwinCourse.from_file("res://data/courses/twin_default.json")
	var robot := TwinRobot.new(TwinRobot.load_config("res://data/robot.json"))
	robot.arena = course.arena
	robot.obstacles = course.obstacles
	robot.place(course.start_position, course.start_heading)
	robot.resume()
	for step in COURSE_PLAN:
		robot.apply(step[0])
		for i in roundi(step[1] / 0.02):
			robot.step(0.02)
			course.update(robot.position, robot.state == TwinRobot.MOVING, 0.02)
	check(course.finished, "the keyboard plan completes the default course in the twin")
	check(robot.collisions_avoided == 0, "the plan avoids every obstacle")


const QUICK_PROTOCOL := "res://tests/data/calibration_quick.json"


func _play(protocol: CalibrationProtocol, dt: float = 0.01) -> Array:
	## Returns [time, type, label, trial] for every marker of a whole session.
	var markers: Array = []
	var t := 0.0
	for e in protocol.start():
		if e[0] == "marker":
			markers.append([t, e[1], e[2], e[3]])
	while protocol.phase != CalibrationProtocol.FINISHED and t < 600.0:
		t += dt
		for e in protocol.advance(dt):
			if e[0] == "marker":
				markers.append([t, e[1], e[2], e[3]])
		if protocol.phase == CalibrationProtocol.BREAK and t > 100.0:
			protocol.skip_break()
	return markers


func test_calibration_protocol() -> void:
	var protocol := CalibrationProtocol.from_file("res://data/calibration_default.json")
	check(protocol != null and protocol.total_trials() == 120, "default: 3 blocks of 40 trials")
	var t := protocol.timing
	check(t["fixation_s"] == 2.0 and t["cue_s"] == 1.0 and t["imagery_s"] == 4.0,
			"default timing 2 / 1 / 4 s")

	protocol = CalibrationProtocol.from_file(QUICK_PROTOCOL)
	var markers := _play(protocol)
	var cues := markers.filter(func(m: Array) -> bool: return m[1] == "cue")
	check(cues.size() == protocol.total_trials(), "one cue per trial")
	for b in 2:
		var labels := cues.slice(b * 4, b * 4 + 4).map(func(m: Array) -> String: return m[2])
		labels.sort()
		check(labels == ["forward", "left", "rest", "right"], "balanced classes in block %d" % (b + 1))
	var ordered := true
	var timing_ok := true
	for n in range(1, protocol.total_trials() + 1):
		var of_trial := markers.filter(func(m: Array) -> bool: return m[3] == n)
		var kinds := of_trial.map(func(m: Array) -> String: return m[1])
		ordered = ordered and kinds == ["trial_start", "cue", "trial_end"]
		if of_trial.size() == 3:
			timing_ok = timing_ok and absf(of_trial[1][0] - of_trial[0][0] - 0.2) < 0.02 \
					and absf(of_trial[2][0] - of_trial[1][0] - 0.5) < 0.02
			ordered = ordered and of_trial[0][2] == of_trial[1][2] and of_trial[1][2] == of_trial[2][2]
	check(ordered, "trial_start, cue, trial_end with the same label for every trial")
	check(timing_ok, "cue after fixation, trial_end after cue + imagery")
	var rests_ok := true
	for n in range(1, protocol.trials_per_block()):
		var end_n: Array = markers.filter(func(m: Array) -> bool:
				return m[1] == "trial_end" and m[3] == n)[0]
		var next_start: Array = markers.filter(func(m: Array) -> bool:
				return m[1] == "trial_start" and m[3] == n + 1)[0]
		var gap: float = next_start[0] - end_n[0]
		rests_ok = rests_ok and gap >= 0.15 - 0.02 and gap <= 0.3 + 0.02
	check(rests_ok, "random rest within its range")
	var events := markers.filter(func(m: Array) -> bool: return m[1] == "event").map(
			func(m: Array) -> String: return m[2])
	check(events == ["block_1_start", "block_1_end", "block_2_start", "block_2_end"],
			"block markers")

	var again := _play(CalibrationProtocol.from_file(QUICK_PROTOCOL))
	check(again.map(func(m: Array) -> String: return m[2]) == markers.map(
			func(m: Array) -> String: return m[2]), "a seed makes the order reproducible")

	check(protocol.stage_for(0.9)["id"] == "discovery", "assistance 0.9 -> discovery")
	check(protocol.stage_for(0.5)["id"] == "transition", "assistance 0.5 -> transition")
	check(protocol.stage_for(0.1)["id"] == "thought", "assistance 0.1 -> thought")
	protocol.block = 2
	check(protocol.stage_for(-1.0)["id"] == "transition", "no assistance: stage of the block")

	protocol = CalibrationProtocol.from_file(QUICK_PROTOCOL)
	protocol.start()
	protocol.advance(0.25)  # in the cue
	var stopped := protocol.stop()
	check(stopped[0][1] == "trial_end" and protocol.phase == CalibrationProtocol.FINISHED,
			"stopping closes the current trial")


func test_bird_scene() -> void:
	var scene: Node = load("res://scenes/bird/bird.tscn").instantiate()
	scene.protocol_path = QUICK_PROTOCOL
	root.add_child(scene)
	await process_frame
	_go_live()
	_status("calibrating")
	check(_om.feedback_alive() and not _om.decoder_alive,
			"calibrating decoder gives feedback but drives no real object")
	scene.start_session()
	check(scene.running, "session starts")
	var seq := 100
	var matched := false
	while scene.running and seq < 2000:
		_now += 0.05
		_status("calibrating")
		if scene.protocol.phase == CalibrationProtocol.IMAGERY:
			_command(scene.protocol.label, 0.9, seq)  # a perfect user
		seq += 1
		scene._process(0.05)
		if scene.protocol.phase == CalibrationProtocol.BREAK:
			scene._handle(scene.protocol.skip_break())
		if scene.last_match > 0.9:
			matched = true
	check(not scene.running and scene.protocol.phase == CalibrationProtocol.FINISHED,
			"session runs to the end")
	check(matched, "matching commands are measured")
	# No bridge socket in tests: every marker is counted as not sent.
	check(scene.markers_failed == 2 + 3 * scene.protocol.total_trials() + 4,
			"session, trial and block markers are all emitted")
	var bird_world: BirdWorld = scene.get_node("BirdWorld")
	check(bird_world.camera != null and not scene.get_node("BirdView").draw_scenery,
			"bird drawn in 3D, texts on top")
	check(is_equal_approx(BirdWorld.height(10.0, 20.0), BirdWorld.height(10.0 + BirdWorld.TILE,
			20.0 - BirdWorld.TILE)), "terrain repeats seamlessly")
	scene.set_manual_stage("thought")
	check(scene.stage["id"] == "thought", "stage forced from the menu")
	scene.set_manual_stage("")
	check(scene.stage["id"] != "thought" or scene.protocol.block >= 3,
			"back to the automatic stage")
	scene.queue_free()
	await process_frame


const APARTMENT := "res://data/apartments/apartment_default.json"
## Plan for the default apartment, also in examples/keys-wheelchair.yaml.
const CHAIR_PLAN := [["rest", 1.0], ["forward", 7.0], ["rest", 0.5], ["action", 0.5],
	["forward", 5.0], ["left", 2.0], ["forward", 3.0], ["rest", 1.0]]


func test_chair() -> void:
	var chair := ChairModel.from_file(APARTMENT)
	check(chair != null and chair.doors.size() == 1, "apartment loads")
	chair.apply("forward")
	chair.step(0.1)
	check(chair.state == ChairModel.SAFETY_STOP and chair.speed == 0.0,
			"no motion before the decoder is alive")
	chair.resume()
	check(chair.apply("action") == "", "action far from a door does nothing")
	chair.apply("forward")
	for i in 600:
		chair.step(0.02)
	check(chair.state == ChairModel.SAFETY_STOP and chair.reason == "obstacle",
			"closed door stops the chair")
	check(absf(chair.clearance - chair.stop_margin) < 0.01, "stops at the margin")
	check(chair.apply("action") == "bedroom", "action in front of the door opens it")
	chair.apply("forward")
	chair.step(0.5)
	check(chair.state == ChairModel.MOVING, "drives through the open door")
	chair.apply("rest")
	check(chair.speed == 0.0 and chair.command == "rest", "rest stops at once")

	chair = ChairModel.from_file(APARTMENT)
	chair.resume()
	var course := TwinCourse.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(APARTMENT))
	for w in data["waypoints"]:
		course.waypoints.append(Vector3(w["x"], w["y"], w["radius"]))
	for step in CHAIR_PLAN:
		chair.apply(step[0])
		for i in roundi(step[1] / 0.02):
			chair.step(0.02)
			course.update(chair.position, chair.state == ChairModel.MOVING, 0.02)
	check(course.finished, "the keyboard plan completes the apartment course")


func _bandpower(rel: Dictionary, bad: Array = []) -> Dictionary:
	var channels: Array = []
	for label in ["FC3", "FC4", "C3", "Cz", "C4", "CP3", "CP4", "CPz"]:
		var ok: bool = label not in bad
		var v: Variant = rel.get(label, 0.0) if ok else null
		channels.append({"label": label, "alpha": 1.0, "mu": 1.0, "beta": 1.0,
			"rel_mu": v, "rel_beta": v, "ok": ok})
	return {"v": 1, "ts": 1.0, "user": "P00", "srate_hz": 250,
		"bands": {"mu": [8, 13]}, "channels": channels}


func _nearest_vertex(mesh: BrainMesh, p: Vector3) -> int:
	var best := 0
	for i in mesh.vertices.size():
		if mesh.vertices[i].distance_to(p) < mesh.vertices[best].distance_to(p):
			best = i
	return best


func test_brain() -> void:
	var mesh := BrainMesh.new()
	mesh.generate_schematic()
	mesh.prepare()
	check(mesh.vertices.size() > 3000 and mesh.indices.size() % 3 == 0, "brain mesh built")
	check(mesh.outwardness() > 0.5, "schematic normals point outwards")
	var built := mesh.build(PackedColorArray())
	check(built.get_surface_count() == 1, "mesh built without colours")
	var loaded := BrainMesh.create()
	if FileAccess.file_exists(BrainMesh.fsaverage_path()):
		check(loaded.source == "fsaverage" and loaded.vertices.size() > 10000,
				"fsaverage mesh loaded when exported")
		check(loaded.outwardness() > 0.3, "fsaverage normals point outwards")
	else:
		check(loaded.source == "schematic", "schematic surface without fsaverage")
	check(not BrainMesh.new().load_file("res://data/robot.json"),
			"a file that is not a mesh is refused")
	var colors := BrainColors.new()
	var c4 := Vector3(0.06712, -0.0109, 0.06358)
	var c3 := Vector3(-0.06536, -0.01163, 0.06436)
	colors.prepare(mesh.vertices, {"C3": c3, "C4": c4})
	var painted := colors.colorize({"C3": 0.0, "C4": -0.5})
	var under_c4 := painted[_nearest_vertex(mesh, mesh.project(c4))]
	var under_c3 := painted[_nearest_vertex(mesh, mesh.project(c3))]
	check(under_c4.b > under_c4.r + 0.2, "desynchronization on C4 is blue")
	check(under_c3.is_equal_approx(BrainColors.ZERO) or absf(under_c3.r - under_c3.b) < 0.1,
			"C3 at baseline stays neutral")
	painted = colors.colorize({"C3": 0.4, "C4": null})
	under_c4 = painted[_nearest_vertex(mesh, mesh.project(c4))]
	check(absf(under_c4.r - under_c4.g) < 0.06 and absf(under_c4.g - under_c4.b) < 0.06,
			"electrode not OK is grey")
	under_c3 = painted[_nearest_vertex(mesh, mesh.project(c3))]
	check(under_c3.r > under_c3.b + 0.2, "increase on C3 is orange")
	var back := painted[_nearest_vertex(mesh, Vector3(0, -0.09, 0.0))]
	check(back.is_equal_approx(BrainColors.BASE), "far from electrodes: base colour")

	var panel := BrainPanel.new()
	root.add_child(panel)
	await process_frame
	check(panel.positions.size() >= 70, "10-10 positions loaded")
	panel.show_bandpower(_bandpower({"C4": -0.45}, ["CPz"]))
	check(panel.values["C4"] == -0.45 or panel.targets["C4"] == -0.45, "C4 value received")
	check(panel.values["CPz"] == null, "CPz not OK")
	panel.show_bandpower(_bandpower({"C3": -0.45}))
	for i in 30:
		panel._process(0.05)
	check(float(panel.values["C3"]) < -0.4 and float(panel.values["C4"]) > -0.05,
			"values move smoothly to the new message")
	panel.set_view("Left")
	panel.set_band("rel_beta")
	check(panel.band == "rel_beta" and panel.values.is_empty(), "band switch resets")
	panel.queue_free()
	await process_frame


func test_signal_panel() -> void:
	var panel := SignalPanel.new()
	root.add_child(panel)
	await process_frame
	var labels := ["FC3", "FC4", "C3", "Cz", "C4", "CP3", "CP4", "CPz"]
	var received: Array = []
	_om.eeg_received.connect(func(f: Dictionary) -> void: received.append(f))
	var t := 0
	for chunk in 60:  # 6 s at 250 Hz, in frames of 25 samples
		var samples: Array = []
		for i in 25:
			var row: Array = []
			for c in labels.size():
				var v := 20.0 * sin(TAU * 10.0 * t / 250.0 + c)
				if labels[c] == "CPz":
					v = 3.0  # flat
				elif labels[c] == "FC4":
					v = 900.0  # saturated
				row.append(v)
			samples.append(row)
			t += 1
		var frame := {"kind": "eeg", "srate": 250.0, "labels": labels, "unit": "microvolts",
			"t0": 0.0, "samples": samples}
		_om.handle_frame(JSON.stringify(frame))
		panel.add_frame(frame)
	check(received.size() == 60, "eeg frames reach the eeg_received signal")
	check(panel.buffers.size() == 8 and panel.channel(0).size() == 1250,
			"8 channels, 5 s window at 250 Hz")
	check(panel.flags[labels.find("CPz")] == "flat", "flat channel flagged")
	check(panel.flags[labels.find("FC4")] == "saturated", "saturated channel flagged")
	check(panel.flags[labels.find("C3")] == "", "normal channel not flagged")
	var start := Time.get_ticks_usec()
	var strokes := 0
	for c in 8:
		strokes += panel.lane_points(c, Vector2(340, 240)).size()
	check(strokes > 8 * 200, "every channel is drawn across the plot")
	check(Time.get_ticks_usec() - start < 20000, "computing 8 channels takes < 20 ms")
	panel.set_window(10.0)
	check(panel.buffers[0].size() == 2500, "10 s window")
	panel.queue_free()
	await process_frame


func test_3d_worlds() -> void:
	var twin: Node = load("res://scenes/robot_twin/robot_twin.tscn").instantiate()
	root.add_child(twin)
	await process_frame
	var world: TwinWorld = twin.get_node("TwinWorld")
	check(world.camera != null and world.sun != null, "twin world built")
	twin.robot.resume()
	twin.robot.apply("forward")
	for i in 50:
		twin.robot.step(0.02)
	world.update(1.0)
	var node_pos: Vector3 = world._robot_node.position
	check(node_pos.is_equal_approx(TwinWorld.to_godot(twin.robot.position)),
			"3D robot follows the model")
	world.cycle_camera()
	world.update(1.0)
	check(world.camera_mode == "top", "camera modes cycle")
	twin.apply_quality(GraphicsQuality.LIGHT)
	check(not world.sun.shadow_enabled and not world.environment.ssao_enabled,
			"light quality removes shadows and ambient occlusion")
	twin.apply_quality(GraphicsQuality.REALISTIC)
	check(world.sun.shadow_enabled, "realistic quality restores shadows")
	twin.queue_free()

	var scene: Node = load("res://scenes/wheelchair/wheelchair.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var chair_world: ChairWorld = scene.get_node("ChairWorld")
	check(chair_world.door_angle(0) == 0.0, "door closed at start")
	scene.chair.resume()
	scene.chair.position = Vector2(2.9, 2.1)
	scene.chair.heading = 0.0
	check(scene.chair.apply("action") == "bedroom", "action opens the door in front")
	for i in 3:
		chair_world.update(0.5)
	check(is_equal_approx(chair_world.door_angle(0), -PI / 2.0), "door swings open in 3D")
	for mode in ["first_person", "top", "chase"]:
		chair_world.cycle_camera()
		check(chair_world.camera_mode == mode, "wheelchair camera %s" % mode)
	scene.queue_free()
	await process_frame


func _boat() -> BoatModel:
	var course := TwinCourse.from_file("res://data/courses/boat_sea.json")
	var boat := BoatModel.from_course(course)
	boat.resume()
	return boat


func _sail(boat: BoatModel, seconds: float) -> void:
	for i in roundi(seconds / 0.05):
		boat.step(0.05)


func test_boat() -> void:
	var boat := _boat()
	boat.apply("forward")
	_sail(boat, 2.0)
	check(boat.speed > 0.5 and boat.speed < boat.max_speed, "sail up: the boat speeds up slowly")
	_sail(boat, 15.0)
	check(boat.speed > 2.0, "sail up: cruising speed")
	var cruising := boat.speed
	boat.apply("rest")
	_sail(boat, 2.0)
	check(boat.speed > 0.5 * cruising and boat.speed < cruising, "sail down: slows down slowly")
	var heading := boat.heading
	boat.apply("left")
	_sail(boat, 2.0)
	check(boat.heading > heading + 0.3, "rudder turns the boat")
	boat.apply("action")
	_sail(boat, 4.0)
	var anchored_at := boat.position
	_sail(boat, 4.0)
	check(boat.state == BoatModel.ANCHORED and boat.position.is_equal_approx(anchored_at),
			"anchor: the boat stops and does not drift")
	boat = _boat()
	boat.islands = [Vector3(20.0, 25.0, 4.0)]  # an island straight ahead
	boat.apply("forward")
	_sail(boat, 20.0)
	var island := boat.islands[0]
	check(boat.bumps == 1 and boat.position.distance_to(Vector2(island.x, island.y))
			>= island.z + boat.radius - 1e-3, "stops on an island shore, one bump")
	check(_boat().islands.is_empty(), "the default sea has no island")
	boat = _boat()
	boat.heading = PI  # west: open sea, no boundary
	boat.apply("forward")
	_sail(boat, 20.0)
	check(boat.position.x < 0.0 and boat.bumps == 0, "open sea: no shore at the course edge")
	boat = _boat()
	boat.halt()
	boat.apply("forward")
	_sail(boat, 2.0)
	check(not boat.sail_up, "no command while the decoder is lost")

	var scene: Node = load("res://scenes/boat/boat.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.get_node("BoatWorld").camera != null, "boat scene built in 3D")
	scene.boat.resume()
	scene.boat.apply("forward")
	for i in 20:
		scene._physics_process(0.05)
		scene._process(0.05)
	check(scene.boat.speed > 0.0, "boat scene sails")
	scene.queue_free()
	await process_frame


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
	check(scene.last_command == "forward" and scene.robot.command == "forward",
			"low confidence command is ignored")
	_command("rest", 0.1, 12)
	check(scene.last_command == "rest", "rest stops whatever its confidence")
	check(main.command_panel.sliders.size() == 4, "one threshold slider per command")
	check(is_equal_approx(main.command_panel.sliders["action"].value, 0.85),
			"slider shows the robot.yaml threshold")
	main.command_panel.sliders["left"].value = 0.4
	check(is_equal_approx(scene.get_node("ObjectController").threshold("left"), 0.4),
			"slider changes the scene threshold")
	_command("left", 0.5, 13)
	check(scene.last_command == "left", "command above the new threshold applies")
	main.switch_scene("robot_twin")
	await process_frame
	scene = main.current_scene
	check(is_equal_approx(scene.get_node("ObjectController").threshold("left"), 0.4),
			"thresholds are remembered per scene")
	scene.get_node("ObjectController").reset_thresholds()
	check(is_equal_approx(main.command_panel.sliders["left"].value, 0.8),
			"default thresholds restored")
	_command("left", 0.9, 14)
	check(scene.last_command == "left", "next good command applies")
	_now += 2.5
	_om._update_alive()
	check(scene.last_command == "rest", "safety stop without status")
	_status("running")
	_command("right", 0.9, 0)  # decoder restarted: seq from 0
	check(scene.last_command == "right", "seq restart accepted after a silence")

	main.set_quality(GraphicsQuality.LIGHT)
	check(Engine.max_fps == 30 and is_equal_approx(main.viewport.scaling_3d_scale, 0.75),
			"light graphics: 30 fps, 3D at 75 %")
	check(GraphicsQuality.load_saved() == GraphicsQuality.LIGHT, "graphics choice remembered")
	main.set_quality(GraphicsQuality.REALISTIC)
	check(Engine.max_fps == 60, "realistic graphics: 60 fps")
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
