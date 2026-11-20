class_name BrainColors
extends RefCounted
## Sensor-level colouring of the brain surface from band power messages.
##
## Each vertex takes a distance-weighted mean of the electrodes around it
## (Gaussian weights, [member sigma]); far from every electrode it keeps the
## neutral base colour. Values are relative changes (rel_mu or rel_beta) shown on
## a diverging blue / orange scale: blue = decrease (desynchronization), orange =
## increase. Electrodes reported ok=false grey out their area.

const BASE := Color("#5A6378")
const ZERO := Color("#E9ECF2")
const DECREASE := Color("#2F6FDF")
const INCREASE := Color("#E8892B")
const BAD := Color("#8A8F99")

## Width of the influence of an electrode, in metres.
var sigma := 0.024
## |value| shown with the full colour.
var vmax := 0.5

var labels: PackedStringArray = []
## Per vertex: weights of the electrodes, in [member labels] order.
var _weights: Array[PackedFloat32Array] = []


## Precompute the weights of [param electrodes] (label -> position) for [param vertices].
func prepare(vertices: PackedVector3Array, electrodes: Dictionary) -> void:
	labels = PackedStringArray(electrodes.keys())
	_weights.clear()
	var positions: Array[Vector3] = []
	for label in labels:
		positions.append(electrodes[label])
	for v in vertices:
		var row := PackedFloat32Array()
		row.resize(labels.size())
		for i in labels.size():
			var d := v.distance_to(positions[i])
			row[i] = exp(-(d * d) / (sigma * sigma))
		_weights.append(row)


## Colour of every vertex. [param values]: label -> float, or null when the
## electrode is not OK (missing labels count as absent).
func colorize(values: Dictionary) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(_weights.size())
	for k in _weights.size():
		var row := _weights[k]
		var total := 0.0
		var good := 0.0
		var bad := 0.0
		for i in labels.size():
			if not values.has(labels[i]):
				continue
			var w := row[i]
			var value: Variant = values[labels[i]]
			if value == null:
				bad += w
			else:
				good += w
				total += w * float(value)
		var coverage := clampf(good + bad, 0.0, 1.0)
		var colour := BASE
		if good > 1e-6:
			colour = diverging(total / good)
		if bad > 1e-6:
			colour = colour.lerp(BAD, bad / (good + bad))
		colors[k] = BASE.lerp(colour, coverage)
	return colors


func diverging(value: float) -> Color:
	var t := clampf(value / vmax, -1.0, 1.0)
	return ZERO.lerp(DECREASE, -t) if t < 0.0 else ZERO.lerp(INCREASE, t)
