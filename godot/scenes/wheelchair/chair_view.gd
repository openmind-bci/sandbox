class_name ChairView
extends Control
## Top view of the apartment and the wheelchair.

var chair: ChairModel
var course: TwinCourse
var names: PackedStringArray = []
## Small map over the 3D view.
var minimap := false

var _scale := 100.0
var _origin := Vector2.ZERO


func _process(_delta: float) -> void:
	queue_redraw()


func to_screen(point: Vector2) -> Vector2:
	return _origin + Vector2(point.x, chair.size.y - point.y) * _scale


func _draw() -> void:
	if chair == null:
		return
	var margin := 6.0 if minimap else 24.0
	if minimap:
		draw_rect(Rect2(Vector2.ZERO, size), Color(OpenMindTheme.BACKGROUND, 0.75))
	_scale = minf((size.x - 2 * margin) / chair.size.x, (size.y - 2 * margin) / chair.size.y)
	_origin = (size - chair.size * _scale) / 2.0
	draw_rect(Rect2(_origin, chair.size * _scale), OpenMindTheme.PANEL)
	for wall in chair.walls:
		draw_line(to_screen(wall[0]), to_screen(wall[1]), OpenMindTheme.TEXT_MUTED, 6.0)
	var font := get_theme_default_font()
	for door in chair.doors:
		var a := to_screen(door["a"])
		var b := to_screen(door["b"])
		if door["open"]:
			draw_line(a, a + (b - a).rotated(-PI / 2.0), OpenMindTheme.ACCENT, 3.0)
		else:
			draw_line(a, b, OpenMindTheme.WARNING, 6.0)
	if course != null:
		for i in course.waypoints.size():
			var w := course.waypoints[i]
			var centre := to_screen(Vector2(w.x, w.y))
			var colour := OpenMindTheme.ACCENT if i == course.next_index else (
					OpenMindTheme.PANEL_BORDER if i < course.next_index
					else OpenMindTheme.PRIMARY_LIGHT)
			draw_arc(centre, w.z * _scale, 0, TAU, 48, colour, 2.0)
			if i < names.size():
				draw_string(font, centre + Vector2(-40, -w.z * _scale - 6), names[i],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 15, colour)
	var body := OpenMindTheme.DANGER if chair.state == ChairModel.SAFETY_STOP \
			else OpenMindTheme.ACCENT
	var centre := to_screen(chair.position)
	draw_circle(centre, chair.radius * _scale, body)
	var direction := Vector2(cos(chair.heading), -sin(chair.heading))
	draw_line(centre, centre + direction * chair.radius * _scale, OpenMindTheme.BACKGROUND, 4.0)
	if not chair.door_in_front().is_empty():
		draw_string(font, centre + Vector2(-60, chair.radius * _scale + 22), "action: open",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, OpenMindTheme.WARNING)
