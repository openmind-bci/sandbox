class_name CommandPanel
extends VBoxContainer
## Current decoded command, its confidence, the decoder state, and the
## confidence thresholds of the current scene (one slider per command; `rest`
## has none: it always stops).

var command_label := Label.new()
var confidence_bar := ProgressBar.new()
var decoder_label := Label.new()
## Starts or stops the built-in demo decoder.
var demo_button := Button.new()
## Gives the demo the command to send (the scene's cue), or "" for its loop.
var demo_follow: Callable = Callable()
## Slider of each thresholded command.
var sliders := {}

var _controller: ObjectController = null
var _values := {}
var _thresholds_box := VBoxContainer.new()


func _ready() -> void:
	command_label.add_theme_font_size_override("font_size", 30)
	command_label.text = "—"
	confidence_bar.min_value = 0.0
	confidence_bar.max_value = 1.0
	confidence_bar.step = 0.01
	confidence_bar.custom_minimum_size = Vector2(0, 24)
	decoder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	decoder_label.text = "Decoder: no status yet"
	demo_button.text = "Start demo"
	demo_button.tooltip_text = "Simulated decoder and brain activity, no headset (Ctrl+D)"
	demo_button.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	demo_button.pressed.connect(toggle_demo)
	add_child(demo_button)
	add_child(command_label)
	add_child(confidence_bar)
	add_child(decoder_label)
	_build_thresholds()
	var openmind := get_node_or_null("/root/OpenMind")
	if openmind != null:
		openmind.demo_changed.connect(func(active: bool) -> void:
				demo_button.text = "Stop demo" if active else "Start demo")
		openmind.command_received.connect(show_command)
		openmind.status_changed.connect(show_status)
		openmind.decoder_alive_changed.connect(_on_alive)


## Start the demo decoder, or stop it when it runs.
func toggle_demo() -> void:
	var openmind := get_node_or_null("/root/OpenMind")
	if openmind == null:
		return
	if openmind.demo != null:
		openmind.stop_demo()
	else:
		openmind.start_demo(demo_follow)


func show_command(command: Dictionary) -> void:
	command_label.text = str(command.get("command", "?"))
	confidence_bar.value = float(command.get("confidence", 0.0))


func show_status(status: Dictionary) -> void:
	var user: Variant = status.get("user")
	decoder_label.text = "Decoder: %s · model %s · user %s" % [
		status.get("state", "?"), status.get("model", "?"), user if user != null else "—"]
	if status.has("message") and status["message"] != null:
		decoder_label.text += "\n" + str(status["message"])


func _on_alive(alive: bool) -> void:
	if not alive:
		command_label.text = "—"
		confidence_bar.value = 0.0
		decoder_label.text = "Decoder: silent (objects stopped)"


## Show and edit the thresholds of [param controller] (null: none to show).
func bind_controller(controller: ObjectController) -> void:
	_controller = controller
	_thresholds_box.visible = controller != null
	_refresh_thresholds()
	if controller != null and not controller.thresholds_changed.is_connected(
			_refresh_thresholds):
		controller.thresholds_changed.connect(_refresh_thresholds)


func _build_thresholds() -> void:
	var title := Label.new()
	title.text = "Confidence thresholds (rest always stops)"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", OpenMindTheme.TEXT_MUTED)
	_thresholds_box.add_child(title)
	for name in CommandGate.THRESHOLDED:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = name
		label.custom_minimum_size = Vector2(72, 0)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
		slider.focus_mode = Control.FOCUS_ALL  # keyboard: Tab, then arrows
		var value := Label.new()
		value.custom_minimum_size = Vector2(44, 0)
		slider.value_changed.connect(func(v: float) -> void:
				value.text = "%.2f" % v
				if _controller != null and not is_equal_approx(_controller.threshold(name), v):
					_controller.set_threshold(name, v))
		row.add_child(label)
		row.add_child(slider)
		row.add_child(value)
		_thresholds_box.add_child(row)
		sliders[name] = slider
		_values[name] = value
	var reset := Button.new()
	reset.text = "Default thresholds"
	reset.pressed.connect(func() -> void:
			if _controller != null:
				_controller.reset_thresholds())
	_thresholds_box.add_child(reset)
	_thresholds_box.visible = false
	add_child(_thresholds_box)


func _refresh_thresholds() -> void:
	if _controller == null:
		return
	for name in sliders:
		var v := _controller.threshold(name)
		sliders[name].set_value_no_signal(v)
		_values[name].text = "%.2f" % v
