class_name BoatView
extends Control
## Small map of the lake over the 3D view: islands, buoys, the boat.

var boat: BoatModel
var course: TwinCourse


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if boat == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(OpenMindTheme.BACKGROUND, 0.75))
	var scale := minf((size.x - 12) / course.arena.x, (size.y - 12) / course.arena.y)
	var origin := (size - course.arena * scale) / 2.0
	var to_screen := func(p: Vector2) -> Vector2:
		return origin + Vector2(p.x, course.arena.y - p.y) * scale
	draw_rect(Rect2(origin, course.arena * scale), Color("#1E4E66"))
	for island in course.obstacles:
		draw_circle(to_screen.call(Vector2(island.x, island.y)), island.z * scale, Color("#2F6B3A"))
	for i in course.waypoints.size():
		var w := course.waypoints[i]
		var colour := OpenMindTheme.ACCENT if i == course.next_index else (
				OpenMindTheme.PANEL_BORDER if i < course.next_index else OpenMindTheme.DANGER)
		draw_circle(to_screen.call(Vector2(w.x, w.y)), 3.0, colour)
	var forward := Vector2(cos(boat.heading), sin(boat.heading))
	var side := forward.orthogonal()
	# Out of the map at open sea: show the boat on its edge.
	var at := Vector2(clampf(boat.position.x, 0.0, course.arena.x),
			clampf(boat.position.y, 0.0, course.arena.y))
	var tip: Vector2 = to_screen.call(at + forward * 2.0)
	var left: Vector2 = to_screen.call(at - forward * 1.5 + side * 1.0)
	var right: Vector2 = to_screen.call(at - forward * 1.5 - side * 1.0)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), OpenMindTheme.TEXT)
