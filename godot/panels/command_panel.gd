class_name CommandPanel
extends VBoxContainer
## Current decoded command, its confidence and the decoder state.

var command_label := Label.new()
var confidence_bar := ProgressBar.new()
var decoder_label := Label.new()


func _ready() -> void:
	command_label.add_theme_font_size_override("font_size", 30)
	command_label.text = "—"
	confidence_bar.min_value = 0.0
	confidence_bar.max_value = 1.0
	confidence_bar.step = 0.01
	confidence_bar.custom_minimum_size = Vector2(0, 24)
	decoder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	decoder_label.text = "Decoder: no status yet"
	add_child(command_label)
	add_child(confidence_bar)
	add_child(decoder_label)
	var openmind := get_node_or_null("/root/OpenMind")
	if openmind != null:
		openmind.command_received.connect(show_command)
		openmind.status_changed.connect(show_status)
		openmind.decoder_alive_changed.connect(_on_alive)


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
