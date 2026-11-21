class_name BrainColors
extends RefCounted
## Sensor-level colouring of the brain surface from band power messages.
##
## Each vertex takes a distance-weighted mean of the electrodes around it
## (Gaussian weights, [member sigma]); far from every electrode it keeps the
## neutral base colour. Values are relative changes (rel_mu or rel_beta) shown on
## a diverging blue / orange scale: blue = decrease (desynchronization), orange =
## increase. Electrodes reported ok=false grey out their area.

const BASE := Color("#5E6779")
const ZERO := Color("#A9B1C0")
const DECREASE := Color("#1747D6")
const INCREASE := Color("#F07D14")
const BAD := Color("#8A8F99")

## Width of the influence of an electrode, in metres.
var sigma := 0.03
## |value| shown with the full colour.
var vmax := 0.4

## Weights below this are dropped (sparse weights: much faster colouring).
const MIN_WEIGHT := 0.01

var labels: PackedStringArray = []
## Per vertex: indices (in [member labels]) and weights of the electrodes that
## matter for it.
var _which: Array[PackedInt32Array] = []
var _weights: Array[PackedFloat32Array] = []


## Precompute the weights of [param electrodes] (label -> position) for [param vertices].
func prepare(vertices: PackedVector3Array, electrodes: Dictionary) -> void:
	labels = PackedStringArray(electrodes.keys())
	_which.clear()
	_weights.clear()
	var positions: Array[Vector3] = []
	for label in labels:
		positions.append(electrodes[label])
	var inv := 1.0 / (sigma * sigma)
	for v in vertices:
		var which := PackedInt32Array()
		var weights := PackedFloat32Array()
		for i in labels.size():
			var w := exp(-v.distance_squared_to(positions[i]) * inv)
			if w >= MIN_WEIGHT:
				which.append(i)
				weights.append(w)
		_which.append(which)
		_weights.append(weights)


## Colour of every vertex. [param values]: label -> float, or null when the
## electrode is not OK (missing labels count as absent).
func colorize(values: Dictionary) -> PackedColorArray:
	# Per electrode: 0 absent, 1 value, 2 not OK.
	var kind := PackedInt32Array()
	var value := PackedFloat32Array()
	kind.resize(labels.size())
	value.resize(labels.size())
	for i in labels.size():
		if values.has(labels[i]):
			var v: Variant = values[labels[i]]
			kind[i] = 2 if v == null else 1
			value[i] = 0.0 if v == null else float(v)
	var colors := PackedColorArray()
	colors.resize(_which.size())
	for k in _which.size():
		var which := _which[k]
		var weights := _weights[k]
		var total := 0.0
		var good := 0.0
		var bad := 0.0
		for j in which.size():
			var i := which[j]
			if kind[i] == 1:
				good += weights[j]
				total += weights[j] * value[i]
			elif kind[i] == 2:
				bad += weights[j]
		if good + bad <= 1e-6:
			colors[k] = BASE
			continue
		var colour := diverging(total / good) if good > 1e-6 else BASE
		if bad > 1e-6:
			colour = colour.lerp(BAD, bad / (good + bad))
		colors[k] = BASE.lerp(colour, clampf(good + bad, 0.0, 1.0))
	return colors


func diverging(v: float) -> Color:
	var t := clampf(v / vmax, -1.0, 1.0)
	return ZERO.lerp(DECREASE, -t) if t < 0.0 else ZERO.lerp(INCREASE, t)
