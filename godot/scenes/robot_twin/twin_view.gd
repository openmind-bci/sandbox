class_name TwinView
extends Control
## Top view of the arena, the obstacles, the waypoints and the robot twin.

const TRAIL_LENGTH := 600

var robot: TwinRobot
var course: TwinCourse
var trail: PackedVector2Array = []
## Small map over the 3D view: translucent background, thin margin.
var minimap := false

var _scale := 100.0
var _origin := Vector2.ZERO


func _process(_delta: float) -> void:
	if robot != null:
		if trail.is_empty() or trail[trail.size() - 1].distance_to(robot.position) > 0.01:
			trail.append(robot.position)
			if trail.size() > TRAIL_LENGTH:
				trail.remove_at(0)
	queue_redraw()


## Screen position of a world point (metres, y forward).
func to_screen(point: Vector2) -> Vector2:
	return _origin + Vector2(point.x, course.arena.y - point.y) * _scale


func _draw() -> void:
	if robot == null or course == null:
		return
	var margin := 6.0 if minimap else 24.0
	if minimap:
		draw_rect(Rect2(Vector2.ZERO, size), Color(OpenMindTheme.BACKGROUND, 0.75))
	_scale = minf((size.x - 2 * margin) / course.arena.x, (size.y - 2 * margin) / course.arena.y)
	_origin = (size - course.arena * _scale) / 2.0
	draw_rect(Rect2(_origin, course.arena * _scale), OpenMindTheme.PANEL)
	draw_rect(Rect2(_origin, course.arena * _scale), OpenMindTheme.PANEL_BORDER, false, 2.0)
	for o in course.obstacles:
		draw_circle(to_screen(Vector2(o.x, o.y)), o.z * _scale, OpenMindTheme.TEXT_MUTED)
	for i in course.waypoints.size():
		var w := course.waypoints[i]
		var centre := to_screen(Vector2(w.x, w.y))
		var colour := OpenMindTheme.ACCENT if i == course.next_index else (
				OpenMindTheme.PANEL_BORDER if i < course.next_index else OpenMindTheme.PRIMARY_LIGHT)
		draw_arc(centre, w.z * _scale, 0, TAU, 48, colour, 3.0 if i == course.next_index else 1.5)
		draw_string(get_theme_default_font(), centre + Vector2(-5, 6), str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, colour)
	if trail.size() >= 2:
		var points := PackedVector2Array()
		for p in trail:
			points.append(to_screen(p))
		draw_polyline(points, OpenMindTheme.PRIMARY, 2.0)
	_draw_robot()


func _draw_robot() -> void:
	var direction := Vector2(cos(robot.heading), sin(robot.heading))
	var front := robot.position + direction * robot.length / 2.0
	if robot.obstacle >= 0.0:
		var hit := front + direction * robot.obstacle
		var ray_colour := OpenMindTheme.DANGER if robot.obstacle < robot.obstacle_stop * 1.5 \
				else OpenMindTheme.TEXT_MUTED
		draw_dashed_line(to_screen(front), to_screen(hit), ray_colour, 1.5, 6.0)
	var half := Vector2(robot.length, robot.width) / 2.0
	var corners := PackedVector2Array()
	for c in [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y)]:
		corners.append(to_screen(robot.position + c.rotated(robot.heading)))
	var body := OpenMindTheme.DANGER if robot.state == TwinRobot.SAFETY_STOP else OpenMindTheme.ACCENT
	draw_colored_polygon(corners, body)
	draw_line(to_screen(robot.position), to_screen(front), OpenMindTheme.BACKGROUND, 3.0)
