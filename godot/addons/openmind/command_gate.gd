class_name CommandGate
extends RefCounted
## Safety filter of one scene, mirroring openmind_protocol.Watchdog.
##
## A command is accepted only when the decoder is alive, its confidence reaches
## the scene threshold, and its `seq` is newer than the last accepted one. When
## the decoder comes back after a silence, its `seq` may restart from 0: call
## [method reset] (scenes do it on [signal OpenMind.decoder_alive_changed]).

## Commands below this confidence are refused.
var min_confidence := 0.7
## Reason of the last refusal: "", "decoder", "confidence" or "stale".
var last_refusal := ""

var _last_seq := -1


func _init(threshold: float = 0.7) -> void:
	min_confidence = clampf(threshold, 0.0, 1.0)


## Whether [param command] may be applied now; records its seq when accepted.
func accept(command: Dictionary, decoder_alive: bool) -> bool:
	if not decoder_alive:
		last_refusal = "decoder"
		return false
	if float(command.get("confidence", 0.0)) < min_confidence:
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
