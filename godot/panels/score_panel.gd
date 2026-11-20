class_name ScorePanel
extends VBoxContainer
## Progress of the user, from openmind/v1/score.

var overall_label := Label.new()
var detail_label := Label.new()


func _ready() -> void:
	overall_label.add_theme_font_size_override("font_size", 24)
	overall_label.text = "No score yet"
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(overall_label)
	add_child(detail_label)
	var openmind := get_node_or_null("/root/OpenMind")
	if openmind != null:
		openmind.score_received.connect(show_score)


func show_score(score: Dictionary) -> void:
	var ready_text := " · ready for real objects" if score.get("ready", false) else ""
	overall_label.text = "%d %%%s" % [roundi(float(score.get("overall", 0.0)) * 100), ready_text]
	var parts: PackedStringArray = []
	var per_command: Dictionary = score.get("per_command", {})
	for name in per_command:
		parts.append("%s %d %%" % [name, roundi(float(per_command[name]) * 100)])
	detail_label.text = " · ".join(parts)
