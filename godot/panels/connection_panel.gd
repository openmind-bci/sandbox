class_name ConnectionPanel
extends VBoxContainer
## State of the chain: bridge WebSocket, MQTT broker, decoder heartbeat.

var bridge_label := Label.new()
var mqtt_label := Label.new()
var decoder_label := Label.new()

var _openmind: Node = null


func _ready() -> void:
	for label in [bridge_label, mqtt_label, decoder_label]:
		add_child(label)
	_openmind = get_node_or_null("/root/OpenMind")
	if _openmind != null:
		_openmind.connection_changed.connect(_refresh.unbind(1))
		_openmind.demo_changed.connect(_refresh.unbind(1))
		_openmind.bridge_state_changed.connect(_refresh.unbind(1))
		_openmind.decoder_alive_changed.connect(_refresh.unbind(1))
	_refresh()


func _refresh() -> void:
	var connected: bool = _openmind != null and _openmind.connected
	var mqtt: bool = _openmind != null and _openmind.mqtt_connected
	var alive: bool = _openmind != null and _openmind.decoder_alive
	var url: String = _openmind.url if _openmind != null else "?"
	_show(bridge_label, connected, "Bridge: connected" if connected else "Bridge: waiting (%s)" % url)
	_show(mqtt_label, mqtt, "MQTT broker: connected" if mqtt else "MQTT broker: not connected")
	var demo: bool = _openmind != null and _openmind.demo != null
	_show(decoder_label, alive, ("Decoder: demo (simulated)" if demo else "Decoder: alive")
			if alive else "Decoder: no running status")


static func _show(label: Label, ok: bool, text: String) -> void:
	label.text = ("● " if ok else "○ ") + text
	label.add_theme_color_override(
			"font_color", OpenMindTheme.ACCENT_LIGHT if ok else OpenMindTheme.WARNING)
