extends Control
## Bird scene: guided motor imagery calibration.
##
## Plays the protocol of godot/data/calibration_default.json and sends its markers
## (trial_start, cue, trial_end, block events) through the bridge, which relays
## them to MQTT and LSL for OpenMind Core. During imagery the bird stays at the
## centre and only the scenery moves; it follows the cue by itself in proportion
## to the assistance announced by the decoder, and fully when the decoded command
## matches the cue. The stage follows the assistance (else the block), or the
## stage chosen in the menu. Space or Enter starts, Escape stops, N skips a break.

const SCENE_NAME := "calibration"
const DEFAULT_PROTOCOL := "res://data/calibration_default.json"
## Scenery speed of a full movement, in pixels per second.
const SPEED := Vector2(160, 110)
const MAX_BANK := 0.5

@export_file("*.json") var protocol_path := DEFAULT_PROTOCOL

var protocol: CalibrationProtocol
var running := false
var markers_sent := 0
var markers_failed := 0
## Share of the imagery time during which the decoded command matched the cue.
var last_match := -1.0
var last_command := "rest"
var stage: Dictionary = {}
## Stage forced from the menu ("" = automatic: assistance, else block number).
var manual_stage := ""

var _decoded := "rest"
var _match_time := 0.0
var _imagery_time := 0.0
var _banner_left := 0.0
var _score_text := ""
var _openmind: Node = null

@onready var _view: BirdView = $BirdView
@onready var _start: Button = %StartButton
@onready var _controller: ObjectController = $ObjectController
@onready var _stage_choice: OptionButton = %StageChoice


func _ready() -> void:
	_openmind = get_node_or_null("/root/OpenMind")
	protocol = CalibrationProtocol.from_file(protocol_path)
	_controller.command_accepted.connect(_on_command)
	if _openmind != null:
		_openmind.score_received.connect(_on_score)
	_stage_choice.add_item("Stage: automatic")
	for s in protocol.stages:
		_stage_choice.add_item("Stage: %s" % s["title"])
	_stage_choice.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	_stage_choice.item_selected.connect(func(i: int) -> void:
			set_manual_stage("" if i == 0 else str(protocol.stages[i - 1]["id"])))
	_start.pressed.connect(start_session)
	_start.text = "Start calibration (%d trials)" % protocol.total_trials()
	_start.custom_minimum_size = Vector2(320, OpenMindTheme.MIN_TARGET)
	stage = protocol.stage_for(-1.0)
	_refresh_texts()
	_start.grab_focus.call_deferred()


func start_session() -> void:
	if running:
		return
	running = true
	markers_sent = 0
	markers_failed = 0
	_start.visible = false
	_send_marker("event", "session_start", null)
	_handle(protocol.start())


func stop_session() -> void:
	if not running:
		return
	_handle(protocol.stop())


func _process(delta: float) -> void:
	if running:
		_handle(protocol.advance(delta))
	_animate(delta)
	if _banner_left > 0.0:
		_banner_left -= delta
		if _banner_left <= 0.0:
			_view.banner = ""
	_refresh_texts()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			stop_session()
		KEY_N:
			_handle(protocol.skip_break())
		_:
			return
	get_viewport().set_input_as_handled()


func _handle(events: Array[Array]) -> void:
	for event in events:
		match event[0]:
			"marker":
				_send_marker(event[1], event[2], event[3])
			"phase":
				_on_phase(event[1])
			"finished":
				running = false
				_send_marker("event", "session_end", null)
				_start.text = "Start a new session"
				_start.visible = true


func _on_phase(phase: String) -> void:
	_view.overlay = ""
	match phase:
		CalibrationProtocol.FIXATION:
			_view.overlay = "fixation"
			_update_stage()
		CalibrationProtocol.CUE:
			_view.overlay = "cue"
			_view.cue_label = protocol.label
			_view.cue_text = str(protocol.cue_text.get(protocol.label, protocol.label))
		CalibrationProtocol.IMAGERY:
			_match_time = 0.0
			_imagery_time = 0.0
		CalibrationProtocol.REST:
			last_match = _match_time / _imagery_time if _imagery_time > 0.0 else 0.0


## Move the scenery: assisted share of the cue movement, full when decoded matches.
func _animate(delta: float) -> void:
	var target := "rest"
	var amount := 0.0
	if running and protocol.phase == CalibrationProtocol.IMAGERY:
		target = protocol.label
		var alive: bool = _openmind != null and _openmind.feedback_alive()
		var matched := alive and _decoded == target
		_imagery_time += delta
		if matched:
			_match_time += delta
		amount = 1.0 if matched else maxf(0.0, _assistance())
	var bank_target := 0.0
	match target:
		"left":
			_view.scroll.x -= SPEED.x * amount * delta
			bank_target = -MAX_BANK * amount
		"right":
			_view.scroll.x += SPEED.x * amount * delta
			bank_target = MAX_BANK * amount
		"forward":
			_view.scroll.y += SPEED.y * amount * delta
		_:
			_view.scroll.y = move_toward(_view.scroll.y, 0.0, 30.0 * delta)  # glide down
	_view.scroll.x += 40.0 * delta  # steady flight
	_view.flapping = target == "forward" and amount > 0.0
	_view.bank = lerpf(_view.bank, bank_target, minf(1.0, 6.0 * delta))


## Force a stage by id, or "" to go back to the automatic choice.
func set_manual_stage(stage_id: String) -> void:
	manual_stage = stage_id
	_update_stage()


func _on_command(command: Dictionary) -> void:
	# Accepted by the ObjectController (virtual scene: a calibrating decoder
	# counts). Below its threshold a command is ignored and the bird keeps going.
	_decoded = str(command.get("command", "rest"))
	last_command = _decoded


func _on_score(score: Dictionary) -> void:
	_score_text = "score %d %%%s" % [roundi(float(score.get("overall", 0.0)) * 100),
		" · ready" if score.get("ready", false) else ""]


func _assistance() -> float:
	var announced: float = _openmind.assistance() if _openmind != null else -1.0
	if announced >= 0.0 and manual_stage.is_empty():
		return announced
	return float(stage.get("max_assistance", 1.0))


func _update_stage() -> void:
	var announced: float = _openmind.assistance() if _openmind != null else -1.0
	var new_stage := protocol.stage_for(announced)
	if not manual_stage.is_empty():
		for s in protocol.stages:
			if s["id"] == manual_stage:
				new_stage = s
	if not stage.is_empty() and new_stage.get("id") != stage.get("id"):
		_view.banner = "Next stage: %s" % new_stage.get("title", "")
		_banner_left = 4.0
	stage = new_stage


func _send_marker(type: String, label: String, trial: Variant) -> void:
	var ok: bool = _openmind != null and _openmind.send_marker(
			type, label, int(trial) if trial != null else 0, SCENE_NAME)
	if ok:
		markers_sent += 1
	else:
		markers_failed += 1


func _refresh_texts() -> void:
	_view.instruction = "%s — %s" % [stage.get("title", ""), stage.get("instruction", "")]
	var parts: PackedStringArray = []
	if running:
		parts.append("block %d / %d · trial %d / %d" % [protocol.block, protocol.blocks,
			protocol.trial_in_block, protocol.trials_per_block()])
		if protocol.phase == CalibrationProtocol.BREAK:
			parts.append("break %d s (N: continue)" % ceili(protocol.phase_left))
	else:
		parts.append(protocol.title)
	if last_match >= 0.0:
		parts.append("last trial matched %d %%" % roundi(last_match * 100))
	if not _score_text.is_empty():
		parts.append(_score_text)
	if markers_failed > 0:
		parts.append("⚠ %d markers not sent (bridge?)" % markers_failed)
	_view.footer = " · ".join(parts)
