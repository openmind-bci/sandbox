class_name BrainMesh
extends RefCounted
## Procedural brain-like surface: two folded hemispheres separated by a fissure.
##
## An original, schematic shape generated in code (no anatomical model, nothing to
## download): enough to show activity *at the sensors*. Positions are kept in the
## MNE head frame (metres: x right, y front, z up), the frame of the electrode
## file; [method to_godot] converts to Godot (y up).

const CENTRE := Vector3(0.0, -0.012, 0.028)
const RADII := Vector3(0.068, 0.084, 0.062)
const FISSURE := 0.0025
const RINGS := 36
const SEGMENTS := 56

## Vertex positions in the MNE head frame.
var vertices: PackedVector3Array = []
var indices: PackedInt32Array = []


static func to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)


func _init() -> void:
	for side in [-1.0, 1.0]:
		_hemisphere(side)


func _hemisphere(side: float) -> void:
	var base := vertices.size()
	for ring in RINGS + 1:
		var theta := PI * ring / RINGS  # 0 at the top
		for seg in SEGMENTS + 1:
			var phi := TAU * seg / SEGMENTS
			var d := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta))
			var p := Vector3(d.x * RADII.x * 0.52, d.y * RADII.y, d.z * RADII.z)
			# Gyri: gentle folds that make the shape read as a brain.
			var fold := 1.0 + 0.035 * sin(9.0 * theta + 3.0 * side) * sin(7.0 * phi) \
					+ 0.02 * sin(15.0 * phi + 5.0 * theta)
			p *= fold
			if p.z < 0.0:
				p.z *= 0.8  # flatter base, temporal lobes
			p.x += side * (RADII.x * 0.5)
			if side * p.x < FISSURE:
				p.x = side * FISSURE  # flat medial wall
			vertices.append(CENTRE + p)
	for ring in RINGS:
		for seg in SEGMENTS:
			var a := base + ring * (SEGMENTS + 1) + seg
			var b := a + SEGMENTS + 1
			if side > 0.0:
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])
			else:
				indices.append_array([a, a + 1, b, a + 1, b + 1, b])


## Build the mesh with one colour per vertex.
func build(colors: PackedColorArray) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in vertices.size():
		tool.set_color(colors[i] if i < colors.size() else Color.GRAY)
		tool.add_vertex(to_godot(vertices[i]))
	for index in indices:
		tool.add_index(index)
	tool.generate_normals()
	return tool.commit()


## Point of the surface in the direction of [param p] seen from the centre
## (used to place electrode markers on the brain).
func project(p: Vector3) -> Vector3:
	var direction := (p - CENTRE).normalized()
	var best := CENTRE
	var best_dot := -2.0
	for v in vertices:
		var dot := (v - CENTRE).normalized().dot(direction)
		if dot > best_dot:
			best_dot = dot
			best = v
	return best
