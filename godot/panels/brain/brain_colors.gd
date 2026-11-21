class_name BrainColors
extends RefCounted
## Sensor-level colouring of the brain surface from band power messages, in the
## style of a functional scan: a grey cortex with coloured blobs on top.
##
## Each vertex takes a distance-weighted mean of the electrodes around it
## (Gaussian weights, [member sigma]). The strength of the change (|rel_mu| or
## |rel_beta|) is shown from blue (weak) through cyan, green and yellow to red
## (strong); below [member threshold] the cortex stays grey. The vertex alpha is
## the opacity of the blob over the cortex, so the shape of the brain always
## shows. Electrodes reported ok=false shade their area in neutral grey.

const BASE := Color("#8C93A0")
const BAD := Color("#6B7079")
## Scanner colour scale, weak to strong.
const SCALE: Array[Color] = [Color("#2B4CFF"), Color("#18C8F0"), Color("#38D46A"),
	Color("#F4E23A"), Color("#F0331E")]

## Width of the influence of an electrode, in metres.
var sigma := 0.03
## |value| shown with the full colour.
var vmax := 0.4
## Share of [member vmax] under which nothing is coloured.
var threshold := 0.12

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
			colors[k] = Color(BASE, 0.0)
			continue
		var mean := total / good if good > 1e-6 else 0.0
		var coverage := clampf(1.6 * (good + bad), 0.0, 1.0)
		var strength := clampf(absf(mean) / vmax, 0.0, 1.0) * coverage * good / (good + bad)
		var colour := Color(BASE, 0.0)
		if strength > threshold:
			colour = heat(strength)
			# Opacity rises smoothly from the threshold, never hiding the cortex.
			colour.a = 0.85 * smoothstep(threshold, threshold + 0.25, strength)
		if bad > 1e-6:
			var share := bad / (good + bad)
			colour = Color(colour.lerp(BAD, share), maxf(colour.a, 0.7 * share * coverage))
		colors[k] = colour
	return colors


## Colour of a strength between 0 and 1 on the scanner scale (blue to red).
static func heat(strength: float) -> Color:
	var t := clampf(strength, 0.0, 1.0) * (SCALE.size() - 1)
	var i := mini(int(t), SCALE.size() - 2)
	return SCALE[i].lerp(SCALE[i + 1], t - i)
