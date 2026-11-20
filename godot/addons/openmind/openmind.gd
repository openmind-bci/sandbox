extends Node
## Link between the cockpit and the OpenMind bridge (autoload "OpenMind").
##
## Connects to `openmind-sandbox bridge` over WebSocket, reconnects on its own,
## and turns the frames of the bridge into signals. It also tracks whether the
## decoder is alive: a `running` status received less than 2 s ago, through a
## bridge that is connected to the MQTT broker. Scenes that move something
## must stop as soon as [member decoder_alive] is false.

signal connection_changed(connected: bool)
signal bridge_state_changed(mqtt_connected: bool)
signal decoder_alive_changed(alive: bool)
signal command_received(command: Dictionary)
signal status_changed(status: Dictionary)
signal score_received(score: Dictionary)
signal bandpower_received(bandpower: Dictionary)
signal marker_received(marker: Dictionary)
signal event_received(event: Dictionary)
signal message_rejected(error: String)

const DEFAULT_URL := "ws://127.0.0.1:8765"
## Seconds without status after which the decoder is considered gone.
const STATUS_TIMEOUT_S := 2.0
const RECONNECT_MIN_S := 0.5
const RECONNECT_MAX_S := 5.0
const MARKER_TYPES: Array[String] = ["cue", "trial_start", "trial_end", "event"]

## Address of the bridge; change it with [method connect_to].
var url := DEFAULT_URL
## Whether the WebSocket to the bridge is open.
var connected := false
## Whether the bridge reports a live MQTT connection.
var mqtt_connected := false
## Whether the decoder may drive objects (see class description).
var decoder_alive := false
## Last status message received, or an empty dictionary.
var last_status: Dictionary = {}
## Versions announced by the bridge.
var bridge_version := ""
var protocol_version := ""
## Time source in seconds; replaced in tests.
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
## Set to false to stop connecting (tests, offline use).
var autoconnect := true

var _peer: WebSocketPeer = null
var _last_status_at := -INF
var _next_attempt := 0.0
var _backoff := RECONNECT_MIN_S


func _ready() -> void:
	var configured := bridge_url_from(OS.get_cmdline_user_args(),
			OS.get_environment("OPENMIND_BRIDGE_URL"))
	if not configured.is_empty():
		url = configured


## Bridge address given as `-- --bridge=ws://...` on the command line, else by the
## OPENMIND_BRIDGE_URL environment variable, else "" (keep the default).
static func bridge_url_from(user_args: PackedStringArray, environment: String) -> String:
	for arg in user_args:
		if arg.begins_with("--bridge="):
			return arg.trim_prefix("--bridge=")
	return environment


func _process(_delta: float) -> void:
	_poll_socket()
	_update_alive()


## Connect to another bridge address; drops the current connection.
func connect_to(new_url: String) -> void:
	url = new_url
	disconnect_from_bridge()
	_next_attempt = 0.0
	_backoff = RECONNECT_MIN_S


func disconnect_from_bridge() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	_set_connected(false)


## Send a calibration or scene marker. [param trial] 0 means no trial number.
## Returns false when it cannot be sent (bridge not connected, invalid type).
func send_marker(type: String, label: String, trial: int = 0, scene: String = "") -> bool:
	if type not in MARKER_TYPES or label.is_empty():
		push_warning("OpenMind: invalid marker %s/%s" % [type, label])
		return false
	return _send(build_marker_frame(type, label, trial, scene))


## Send an object event (telemetry, lap time...). [param data] must be a dictionary.
func send_event(object_name: String, kind: String, data: Dictionary = {}) -> bool:
	if object_name.is_empty() or kind.is_empty():
		push_warning("OpenMind: event needs an object and a kind")
		return false
	return _send(build_event_frame(object_name, kind, data))


static func build_marker_frame(type: String, label: String, trial: int, scene: String) -> String:
	var message := {
		"type": type,
		"label": label,
		"trial": trial if trial > 0 else null,
		"scene": scene if not scene.is_empty() else null,
		"ts": Time.get_unix_time_from_system(),
	}
	return JSON.stringify({"kind": "marker", "message": message})


static func build_event_frame(object_name: String, kind: String, data: Dictionary) -> String:
	var message := {
		"object": object_name,
		"kind": kind,
		"data": data,
		"ts": Time.get_unix_time_from_system(),
	}
	return JSON.stringify({"kind": "event", "message": message})


## Handle one text frame of the bridge (public for tests).
func handle_frame(text: String) -> void:
	var json := JSON.new()
	var frame: Variant = json.data if json.parse(text) == OK else null
	if typeof(frame) != TYPE_DICTIONARY:
		push_warning("OpenMind: ignored a frame that is not a JSON object")
		return
	var kind: String = str(frame.get("kind", ""))
	var message: Variant = frame.get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		push_warning("OpenMind: ignored a %s frame without a message object" % kind)
		return
	match kind:
		"hello":
			bridge_version = str(frame.get("bridge", ""))
			protocol_version = str(frame.get("protocol", ""))
			_set_mqtt(bool(frame.get("mqtt_connected", false)))
		"bridge":
			_set_mqtt(bool(frame.get("mqtt_connected", false)))
		"error":
			message_rejected.emit(str(frame.get("error", "")))
		"status":
			last_status = message
			_last_status_at = clock.call()
			status_changed.emit(message)
		"command":
			command_received.emit(message)
		"score":
			score_received.emit(message)
		"bandpower":
			bandpower_received.emit(message)
		"marker":
			marker_received.emit(message)
		"event":
			event_received.emit(message)
		_:
			pass  # unknown kinds are ignored (forward compatibility)
	_update_alive()


## Whether the decoder is alive now (see class description).
func compute_alive() -> bool:
	if not connected or not mqtt_connected:
		return false
	if last_status.get("state", "") != "running":
		return false
	return clock.call() - _last_status_at < STATUS_TIMEOUT_S


## Force the connection flag (tests only).
func set_connected_for_test(value: bool) -> void:
	_set_connected(value)


func _send(frame: String) -> bool:
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _peer.send_text(frame) == OK


func _poll_socket() -> void:
	if _peer == null:
		if autoconnect and clock.call() >= _next_attempt:
			_peer = WebSocketPeer.new()
			if _peer.connect_to_url(url) != OK:
				_peer = null
				_schedule_retry()
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected:
				_backoff = RECONNECT_MIN_S
				_set_connected(true)
			while _peer.get_available_packet_count() > 0:
				handle_frame(_peer.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_peer = null
			_set_connected(false)
			_schedule_retry()


func _schedule_retry() -> void:
	_next_attempt = clock.call() + _backoff
	_backoff = minf(_backoff * 2.0, RECONNECT_MAX_S)


func _set_connected(value: bool) -> void:
	if value == connected:
		return
	connected = value
	if not value:
		_set_mqtt(false)
	connection_changed.emit(value)
	_update_alive()


func _set_mqtt(value: bool) -> void:
	if value == mqtt_connected:
		return
	mqtt_connected = value
	bridge_state_changed.emit(value)


func _update_alive() -> void:
	var alive := compute_alive()
	if alive != decoder_alive:
		decoder_alive = alive
		decoder_alive_changed.emit(alive)
