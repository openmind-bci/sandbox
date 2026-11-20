class_name BrainMesh
extends RefCounted
## Brain surface of the 3D panel.
##
## [method create] loads the FreeSurfer fsaverage mesh exported by
## tools/fetch_fsaverage.py ($OPENMIND_DATA_DIR/godot/brain_fsaverage.json, never
## committed) when it exists, and otherwise generates a schematic surface in code
## (two folded hemispheres and a fissure: an original drawing). Positions are in
## the frame of the electrode file (metres: x right, y front, z up);
## [method to_godot] converts to Godot (y up).

const FSAVERAGE_FILE := "godot/brain_fsaverage.json"
const SCHEMATIC_CENTRE := Vector3(0.0, -0.012, 0.028)
const SCHEMATIC_RADII := Vector3(0.068, 0.084, 0.062)
const FISSURE := 0.0025
const RINGS := 36
const SEGMENTS := 56

## "fsaverage" or "schematic".
var source := "schematic"
## Vertex positions in the electrode frame.
var vertices: PackedVector3Array = []
var indices: PackedInt32Array = []
## Middle of the surface (bounding box centre).
var centre := SCHEMATIC_CENTRE

var _godot_vertices: PackedVector3Array = []
var _normals: PackedVector3Array = []


static func to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


## fsaverage when its exported file exists, else the schematic surface.
static func create() -> BrainMesh:
	var mesh := BrainMesh.new()
	if not mesh.load_file(fsaverage_path()):
		mesh.generate_schematic()
	mesh.prepare()
	return mesh


## Where tools/fetch_fsaverage.py writes the mesh.
static func fsaverage_path() -> String:
	var root := OS.get_environment("OPENMIND_DATA_DIR")
	if root.is_empty():
		root = OS.get_environment("HOME").path_join("openmind-data")
	return root.path_join(FSAVERAGE_FILE)


func load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("vertices") or not data.has("indices"):
		push_warning("BrainMesh: %s is not a brain mesh, using the schematic surface" % path)
		return false
	var flat: Array = data["vertices"]
	vertices.clear()
	for i in range(0, flat.size() - 2, 3):
		vertices.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
	indices = PackedInt32Array(data["indices"])
	source = "fsaverage"
	return true


func generate_schematic() -> void:
	vertices.clear()
	indices.clear()
	for side in [-1.0, 1.0]:
		_hemisphere(side)
	source = "schematic"


## Centre, Godot positions and outward normals; call once after loading.
func prepare() -> void:
	var low := Vector3.INF
	var high := -Vector3.INF
	for v in vertices:
		low = low.min(v)
		high = high.max(v)
	centre = (low + high) / 2.0
	_godot_vertices = PackedVector3Array()
	for v in vertices:
		_godot_vertices.append(to_godot(v))
	_compute_normals()


## Mesh with one colour per vertex (geometry and normals are reused).
func build(colors: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _godot_vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	if colors.size() == vertices.size():
		arrays[Mesh.ARRAY_COLOR] = colors
	else:
		var grey := PackedColorArray()
		grey.resize(vertices.size())
		grey.fill(Color.GRAY)
		arrays[Mesh.ARRAY_COLOR] = grey
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Point of the surface in the direction of [param p] seen from the centre
## (used to place electrode markers on the brain).
func project(p: Vector3) -> Vector3:
	var direction := (p - centre).normalized()
	var best := centre
	var best_dot := -2.0
	for v in vertices:
		var dot := (v - centre).normalized().dot(direction)
		if dot > best_dot:
			best_dot = dot
			best = v
	return best


## Average of dot(normal, outward direction) over the vertices (tests: > 0).
func outwardness() -> float:
	var total := 0.0
	for i in vertices.size():
		total += _normals[i].dot(to_godot(vertices[i] - centre).normalized())
	return total / maxf(1.0, vertices.size())


func _compute_normals() -> void:
	# Each face normal is turned to point away from the centre of its
	# hemisphere, whatever the winding of the source triangles.
	var left := Vector3.ZERO
	var right := Vector3.ZERO
	var n_left := 0
	var n_right := 0
	for v in vertices:
		if v.x < centre.x:
			left += v
			n_left += 1
		else:
			right += v
			n_right += 1
	left /= maxf(1.0, n_left)
	right /= maxf(1.0, n_right)
	var accumulated := PackedVector3Array()
	accumulated.resize(vertices.size())
	for k in range(0, indices.size() - 2, 3):
		var a := vertices[indices[k]]
		var b := vertices[indices[k + 1]]
		var c := vertices[indices[k + 2]]
		var face := (b - a).cross(c - a)
		var middle := (a + b + c) / 3.0
		var hemi_centre := left if middle.x < centre.x else right
		if face.dot(middle - hemi_centre) < 0.0:
			face = -face
		for j in 3:
			accumulated[indices[k + j]] += face
	_normals = PackedVector3Array()
	for n in accumulated:
		_normals.append(to_godot(n).normalized())


func _hemisphere(side: float) -> void:
	var base := vertices.size()
	for ring in RINGS + 1:
		var theta := PI * ring / RINGS  # 0 at the top
		for seg in SEGMENTS + 1:
			var phi := TAU * seg / SEGMENTS
			var d := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta))
			var p := Vector3(d.x * SCHEMATIC_RADII.x * 0.52, d.y * SCHEMATIC_RADII.y,
					d.z * SCHEMATIC_RADII.z)
			# Gyri: gentle folds that make the shape read as a brain.
			var fold := 1.0 + 0.035 * sin(9.0 * theta + 3.0 * side) * sin(7.0 * phi) \
					+ 0.02 * sin(15.0 * phi + 5.0 * theta)
			p *= fold
			if p.z < 0.0:
				p.z *= 0.8  # flatter base, temporal lobes
			p.x += side * (SCHEMATIC_RADII.x * 0.5)
			if side * p.x < FISSURE:
				p.x = side * FISSURE  # flat medial wall
			vertices.append(SCHEMATIC_CENTRE + p)
	for ring in RINGS:
		for seg in SEGMENTS:
			var a := base + ring * (SEGMENTS + 1) + seg
			var b := a + SEGMENTS + 1
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
