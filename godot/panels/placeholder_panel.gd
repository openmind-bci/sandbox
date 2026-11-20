class_name PlaceholderPanel
extends Label
## Panel reserved for a later task.


func _init(text_value: String = "") -> void:
	text = text_value
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_color_override("font_color", OpenMindTheme.TEXT_MUTED)
