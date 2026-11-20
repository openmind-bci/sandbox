class_name CommandGate
extends RefCounted
## Safety filter of one scene, mirroring the mock robot and the firmware.
##
## A command is accepted when the decoder is alive, its confidence reaches the
## threshold of that command, and its `seq` is newer than the last accepted one.
## `rest` has no threshold: stopping is always allowed. A command refused for low
## confidence is simply ignored by the scene (the object keeps going). When the
## decoder comes back after a silence, call [method reset] (its seq restarts).

## Commands that have a threshold, in display order.
const THRESHOLDED: Array[String] = ["left", "right", "forward", "action"]

## Threshold used for commands without their own value.
var min_confidence := 0.7
## Per-command thresholds (left, right, forward, action).
var thresholds := {}
## Reason of the last refusal: "", "decoder", "confidence" or "stale".
var last_refusal := ""

var _last_seq := -1


func _init(threshold: float = 0.7) -> void:
	min_confidence = clampf(threshold, 0.0, 1.0)


func threshold(command: String) -> float:
	if command == "rest":
		return 0.0
	return float(thresholds.get(command, min_confidence))


func set_threshold(command: String, value: float) -> void:
	if command in THRESHOLDED:
		thresholds[command] = clampf(value, 0.0, 1.0)


## Whether [param command] may be applied now; records its seq when accepted.
func accept(command: Dictionary, decoder_alive: bool) -> bool:
	if not decoder_alive:
		last_refusal = "decoder"
		return false
	var name := str(command.get("command", ""))
	if float(command.get("confidence", 0.0)) < threshold(name):
		last_refusal = "confidence"
		return false
	var seq := int(command.get("seq", -1))
	if seq <= _last_seq:
		last_refusal = "stale"
		return false
	_last_seq = seq
	last_refusal = ""
	return true


## Forget the last seq (decoder restarted).
func reset() -> void:
	_last_seq = -1
