class_name BirdView
extends Control
## Drawing of the bird scene: the bird stays at the centre of the screen and only
## the scenery moves, to limit eye movements during imagery (original vector
## design, no external asset).

const SKY_TOP := Color("#16244A")
const SKY_BOTTOM := Color("#2F4FB8")
const HILLS := Color("#13897A")
const HILLS_FAR := Color("#0E5E58")
const CLOUD := Color(1, 1, 1, 0.16)
const BIRD := Color("#F3F5FA")
const BIRD_ACCENT := Color("#FFC857")

## What to show on top of the scenery: "", "fixation", "cue".
var overlay := ""
var cue_label := ""
var cue_text := ""
## Scenery offset (pixels): x scrolls sideways, y moves with altitude.
var scroll := Vector2.ZERO
## Bank angle of the bird (radians, positive = right wing down) and wing phase.
var bank := 0.0
var flap := 0.0
var flapping := false
var instruction := ""
## False when a 3D landscape (BirdWorld) is drawn underneath: only the cross,
## the cue and the texts are drawn, on translucent bands.
var draw_scenery := true
var footer := ""
var banner := ""

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	flap = flap + delta * (14.0 if flapping else 2.0)
	queue_redraw()


func _draw() -> void:
	var centre := size / 2.0
	if draw_scenery:
		_draw_sky()
		_draw_hills(HILLS_FAR, 0.35, 0.72, 140.0, 0.6)
		_draw_hills(HILLS, 0.8, 0.82, 90.0, 1.0)
		_draw_clouds()
		_draw_bird(centre)
	else:
		var band := Color(OpenMindTheme.BACKGROUND, 0.55)
		draw_rect(Rect2(0, 0, size.x, 56), band)
		draw_rect(Rect2(0, size.y - 52, size.x, 52), band)
	var font := get_theme_default_font()
	if not instruction.is_empty():
		draw_string(font, Vector2(24, 40), instruction, HORIZONTAL_ALIGNMENT_LEFT,
				size.x - 48, 22, OpenMindTheme.TEXT)
	if not footer.is_empty():
		draw_string(font, Vector2(24, size.y - 24), footer, HORIZONTAL_ALIGNMENT_LEFT,
				size.x - 48, 18, OpenMindTheme.TEXT_MUTED)
	if not banner.is_empty():
		draw_string(font, Vector2(0, 90), banner, HORIZONTAL_ALIGNMENT_CENTER, size.x, 28,
				OpenMindTheme.ACCENT_LIGHT)
	match overlay:
		"fixation":
			var arm := 26.0
			draw_line(centre - Vector2(arm, 0), centre + Vector2(arm, 0), OpenMindTheme.TEXT, 5.0)
			draw_line(centre - Vector2(0, arm), centre + Vector2(0, arm), OpenMindTheme.TEXT, 5.0)
		"cue":
			_draw_cue(centre, font)


func _draw_sky() -> void:
	var bands := 12
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(0, size.y * t, size.x, size.y / bands + 1),
				SKY_TOP.lerp(SKY_BOTTOM, t))


func _draw_hills(colour: Color, parallax: float, base: float, height: float, wave: float) -> void:
	var points := PackedVector2Array()
	var y0 := size.y * base + scroll.y * parallax
	points.append(Vector2(0, size.y))
	for i in 41:
		var x := size.x * i / 40.0
		var u := (x + scroll.x * parallax) / 180.0 * wave
		points.append(Vector2(x, y0 - height * (0.5 + 0.3 * sin(u) + 0.2 * sin(2.3 * u + 1.0))))
	points.append(Vector2(size.x, size.y))
	draw_colored_polygon(points, colour)


func _draw_clouds() -> void:
	for i in 6:
		var x := fposmod(i * 260.0 - scroll.x * 0.5 + _time * 8.0, size.x + 300.0) - 150.0
		var y := 110.0 + 60.0 * (i % 3) + scroll.y * 0.3
		for k in 3:
			draw_circle(Vector2(x + k * 34.0, y + (8.0 if k == 1 else 0.0)), 30.0 - 4.0 * k, CLOUD)


func _draw_bird(centre: Vector2) -> void:
	var wing := 0.5 + 0.5 * sin(flap)
	var xf := Transform2D(bank, centre)
	draw_set_transform_matrix(xf)
	var span := 70.0
	var lift := lerpf(-34.0, 22.0, wing)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, 0), Vector2(-span, lift),
			Vector2(-span * 0.55, lift * 0.3 + 10)]), BIRD)
	draw_colored_polygon(PackedVector2Array([Vector2(8, 0), Vector2(span, lift),
			Vector2(span * 0.55, lift * 0.3 + 10)]), BIRD)
	draw_circle(Vector2.ZERO, 16.0, BIRD)
	draw_circle(Vector2(0, -16), 10.0, BIRD)
	draw_colored_polygon(PackedVector2Array([Vector2(-4, -20), Vector2(4, -20),
			Vector2(0, -32)]), BIRD_ACCENT)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_cue(centre: Vector2, font: Font) -> void:
	var colour := OpenMindTheme.ACCENT_LIGHT
	var arrow := PackedVector2Array()
	match cue_label:
		"left":
			arrow = PackedVector2Array([Vector2(-150, 0), Vector2(-100, -36), Vector2(-100, 36)])
		"right":
			arrow = PackedVector2Array([Vector2(150, 0), Vector2(100, -36), Vector2(100, 36)])
		"forward":
			arrow = PackedVector2Array([Vector2(0, -150), Vector2(-36, -100), Vector2(36, -100)])
	if not arrow.is_empty():
		var shifted := PackedVector2Array()
		for p in arrow:
			shifted.append(centre + p)
		draw_colored_polygon(shifted, colour)
	else:
		draw_rect(Rect2(centre - Vector2(22, 22) - Vector2(0, 120), Vector2(44, 44)), colour)
	draw_string(font, Vector2(0, centre.y + 110), cue_text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 34, colour)
