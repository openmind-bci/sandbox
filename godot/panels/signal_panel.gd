class_name SignalPanel
extends VBoxContainer
## Scrolling EEG channels from the bridge (`openmind-sandbox bridge --eeg`, read
## only). Window and scale are adjustable; a flat or saturated channel is flagged.

const WINDOWS_S: Array[float] = [5.0, 10.0]
const SCALES_UV: Array[float] = [25.0, 50.0, 100.0, 200.0]
## A channel whose last second varies less than this is flagged flat (µV).
const FLAT_STD_UV := 0.3
## A channel whose last second exceeds this is flagged saturated (µV).
const SATURATED_UV := 400.0

var window_s := 5.0
## Half height of a channel lane, in µV.
var scale_uv := 50.0
var srate := 0.0
var labels: PackedStringArray = []
## One ring buffer per channel.
var buffers: Array[PackedFloat32Array] = []
var flags: PackedStringArray = []
var frames := 0

var _write := 0
var _filled := 0
var _plot: Control
var _info: Label


func _ready() -> void:
	_plot = Control.new()
	_plot.custom_minimum_size = Vector2(300, 240)
	_plot.draw.connect(_draw_plot)
	add_child(_plot)
	var row := HBoxContainer.new()
	var window_choice := OptionButton.new()
	for w in WINDOWS_S:
		window_choice.add_item("%d s" % w)
	window_choice.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	window_choice.item_selected.connect(func(i: int) -> void: set_window(WINDOWS_S[i]))
	row.add_child(window_choice)
	var scale_choice := OptionButton.new()
	for s in SCALES_UV:
		scale_choice.add_item("±%d µV" % s)
	scale_choice.select(SCALES_UV.find(scale_uv))
	scale_choice.custom_minimum_size = Vector2(0, OpenMindTheme.MIN_TARGET)
	scale_choice.item_selected.connect(func(i: int) -> void: scale_uv = SCALES_UV[i])
	row.add_child(scale_choice)
	add_child(row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_color_override("font_color", OpenMindTheme.TEXT_MUTED)
	_info.text = "Waiting for EEG: start the bridge with --eeg and a Plug stream."
	add_child(_info)
	var openmind := get_node_or_null("/root/OpenMind")
	if openmind != null:
		openmind.eeg_received.connect(add_frame)


func set_window(seconds: float) -> void:
	window_s = seconds
	_reset(labels, srate)


func add_frame(frame: Dictionary) -> void:
	var new_labels := PackedStringArray(frame.get("labels", []))
	var new_srate := float(frame.get("srate", 0.0))
	if new_labels != labels or new_srate != srate:
		_reset(new_labels, new_srate)
	if buffers.is_empty():
		return
	var size := buffers[0].size()
	for row in frame.get("samples", []):
		for c in mini(row.size(), buffers.size()):
			buffers[c][_write] = float(row[c])
		_write = (_write + 1) % size
		_filled = mini(_filled + 1, size)
	frames += 1
	_update_flags()
	_info.text = "%d channels · %d Hz · %s" % [labels.size(), roundi(srate),
		"all channels OK" if flags.count("") == flags.size()
		else "check: " + ", ".join(_flagged())]
	_plot.queue_redraw()


## Channel values in time order (oldest first), for tests and drawing.
func channel(c: int) -> PackedFloat32Array:
	var size := buffers[c].size()
	var out := PackedFloat32Array()
	out.resize(_filled)
	for i in _filled:
		out[i] = buffers[c][(_write - _filled + i + size) % size]
	return out


func _reset(new_labels: PackedStringArray, new_srate: float) -> void:
	labels = new_labels
	srate = new_srate
	buffers.clear()
	flags.clear()
	_write = 0
	_filled = 0
	var size := maxi(1, int(window_s * maxf(srate, 1.0)))
	for label in labels:
		var buffer := PackedFloat32Array()
		buffer.resize(size)
		buffers.append(buffer)
		flags.append("")


func _update_flags() -> void:
	var last := mini(_filled, maxi(1, int(srate)))
	for c in buffers.size():
		var values := channel(c).slice(_filled - last)
		var mean := 0.0
		var peak := 0.0
		for v in values:
			mean += v
			peak = maxf(peak, absf(v))
		mean /= maxf(1.0, values.size())
		var variance := 0.0
		for v in values:
			variance += (v - mean) * (v - mean)
		var std := sqrt(variance / maxf(1.0, values.size()))
		flags[c] = "saturated" if peak > SATURATED_UV else ("flat" if std < FLAT_STD_UV else "")


func _flagged() -> PackedStringArray:
	var out := PackedStringArray()
	for c in flags.size():
		if not flags[c].is_empty():
			out.append("%s %s" % [labels[c], flags[c]])
	return out


func _draw_plot() -> void:
	var area := _plot.size
	_plot.draw_rect(Rect2(Vector2.ZERO, area), OpenMindTheme.BACKGROUND)
	if buffers.is_empty() or _filled < 2:
		return
	var lane_h := area.y / buffers.size()
	var font := get_theme_default_font()
	for c in buffers.size():
		var colour := OpenMindTheme.PRIMARY_LIGHT if flags[c].is_empty() else OpenMindTheme.WARNING
		_plot.draw_string(font, Vector2(4, lane_h * (c + 0.5) + 5), labels[c],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)
		var points := lane_points(c, area)
		if points.size() >= 2:
			_plot.draw_multiline(points, colour, 1.0)


## Strokes of channel [param c] in a plot of [param area]: one vertical min-max
## segment per pixel column (fast and faithful), newest samples on the right.
func lane_points(c: int, area: Vector2) -> PackedVector2Array:
	var label_w := 44.0
	var lane_h := area.y / buffers.size()
	var mid := lane_h * (c + 0.5)
	var values := channel(c)
	var points := PackedVector2Array()
	if values.size() < 2:
		return points
	var mean := 0.0
	for v in values:
		mean += v
	mean /= values.size()
	var capacity := buffers[c].size()
	var columns := maxi(1, int(area.x - label_w))
	var per_column := float(capacity) / columns
	var offset := capacity - values.size()
	for x in columns:
		var a := int(x * per_column) - offset
		var b := int((x + 1) * per_column) - offset
		if b <= 0 or a >= values.size():
			continue
		var lo := INF
		var hi := -INF
		for i in range(maxi(a, 0), mini(b, values.size())):
			lo = minf(lo, values[i])
			hi = maxf(hi, values[i])
		var y_hi := mid - clampf((hi - mean) / scale_uv, -1.0, 1.0) * lane_h * 0.45
		var y_lo := mid - clampf((lo - mean) / scale_uv, -1.0, 1.0) * lane_h * 0.45
		points.append(Vector2(label_w + x, y_hi))
		points.append(Vector2(label_w + x, y_lo + 0.5))
	return points
