extends SceneTree
## Live check of the signal panel against `openmind-sandbox bridge --eeg` and an
## LSL EEG stream (for example Plug's synthetic source), without a window.

const OpenMindScript := preload("res://addons/openmind/openmind.gd")


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
	var panel: SignalPanel = main.signal_panel
	var start := Time.get_ticks_msec()
	while panel.frames == 0 and Time.get_ticks_msec() - start < 8000:
		await process_frame
	var first := Time.get_ticks_msec()
	var frames_at_first := panel.frames
	var slow_frames := 0
	var last := Time.get_ticks_msec()
	while Time.get_ticks_msec() - first < 4000:
		await process_frame
		var now := Time.get_ticks_msec()
		if now - last > 50:
			slow_frames += 1
		last = now
	var rate := (panel.frames - frames_at_first) / 4.0
	print("channels=%d srate=%d frames/s=%.1f samples=%d flags=%s slow_frames=%d" % [
		panel.labels.size(), panel.srate, rate, panel.channel(0).size(), panel.flags,
		slow_frames])
	quit(0 if panel.labels.size() == 8 and rate > 5.0 else 1)
