class_name SectorMeshBuilder

## SectorMeshBuilder
##
## Reads LevelData geometry and produces Godot meshes plus a static
## collision body. This is the ONLY place Geometry2D.triangulate_polygon
## is used (skill rule). Reads LevelData; never mutates it.
##
## Graceful degradation: flagged or degenerate sectors are skipped and
## counted in the returned stats; nothing here ever errors out on bad
## geometry — the 2D view keeps the red flags, the 3D view just omits
## the broken parts.
##
## Mapping: map (x, y) -> 3D (x, height, y). Units: 1 unit = 6 mm.

const DEFAULT_FLOOR := 0.0
const DEFAULT_CEILING := 256.0
const MIN_PIECE_AREA := 1.0


## build_level(root, data, step_height) -> Dictionary
##
## Clears root and rebuilds FloorMesh / CeilingMesh / WallMesh /
## CollisionBody under it. Returns stats: sectors_built, sectors_skipped,
## wall_quads, collision_faces, floor_area.
static func build_level(root: Node3D, data: LevelData, step_height: float) -> Dictionary:
	var stats := {
		"sectors_built": 0,
		"sectors_skipped": 0,
		"wall_quads": 0,
		"collision_faces": 0,
		"floor_area": 0.0,
	}
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	if data == null:
		return stats

	var floor_tris := PackedVector3Array()
	var floor_uvs := PackedVector2Array()
	var ceil_tris := PackedVector3Array()
	var ceil_uvs := PackedVector2Array()
	var wall_tris := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	var wall_uvs := PackedVector2Array()
	var collision := PackedVector3Array()

	for si in range(data.sectors.size()):
		if _build_sector(data, si, floor_tris, floor_uvs, ceil_tris, ceil_uvs, stats):
			stats["sectors_built"] += 1
		else:
			stats["sectors_skipped"] += 1
	_build_walls(data, step_height, wall_tris, wall_normals, wall_uvs, collision, stats)

	_commit_surface(root, "FloorMesh", floor_tris, floor_uvs, _material(Color(0.45, 0.42, 0.38)))
	_commit_surface(root, "CeilingMesh", ceil_tris, ceil_uvs, _material(Color(0.32, 0.30, 0.28)))
	_commit_surface(root, "WallMesh", wall_tris, wall_uvs, _material(Color(0.55, 0.55, 0.58)), wall_normals)
	if not collision.is_empty():
		var body := StaticBody3D.new()
		body.name = "CollisionBody"
		var shape := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(collision)
		shape.shape = concave
		body.add_child(shape)
		root.add_child(body)
	return stats


## _build_sector(...) -> bool
##
## Floors and ceilings of one sector. Concave loops triangulate directly;
## inner loops are cut out with clip_polygons and the pieces triangulated
## separately (the hole stays a real hole). Returns false when the sector
## must be skipped (flagged or degenerate).
static func _build_sector(
	data: LevelData,
	si: int,
	floor_tris: PackedVector3Array,
	floor_uvs: PackedVector2Array,
	ceil_tris: PackedVector3Array,
	ceil_uvs: PackedVector2Array,
	stats: Dictionary
) -> bool:
	if data.flagged_sectors.has(si):
		return false
	var sector: Dictionary = data.sectors[si]
	var outer := GeometryOps.loop_to_polygon(data, sector["walls"])
	if outer.size() < 3:
		return false
	var holes: Array = []
	for loop in sector["inner"]:
		var hole := GeometryOps.loop_to_polygon(data, loop)
		if hole.size() >= 3:
			holes.append(hole)
	# Geometry2D.clip_polygons does NOT cut rings — it returns the hole as
	# a separate negative-orientation polygon. So holes are bridged into
	# the outer loop with zero-width channels (keyhole technique) and the
	# merged simple polygon is triangulated.
	var pieces: Array = []
	if holes.is_empty():
		pieces.append(outer)
	else:
		var merged := _merge_holes(outer, holes)
		if merged.size() >= 3:
			pieces.append(merged)
	var floor_y := float(sector.get("floor_height", DEFAULT_FLOOR))
	var ceil_y := float(sector.get("ceiling_height", DEFAULT_CEILING))
	for piece in pieces:
		var tris := Geometry2D.triangulate_polygon(piece)
		if tris.is_empty():
			continue
		for i in range(0, tris.size(), 3):
			var a2: Vector2 = piece[tris[i]]
			var b2: Vector2 = piece[tris[i + 1]]
			var c2: Vector2 = piece[tris[i + 2]]
			var fa := Vector3(a2.x, floor_y, a2.y)
			var fb := Vector3(b2.x, floor_y, b2.y)
			var fc := Vector3(c2.x, floor_y, c2.y)
			floor_tris.append_array([fa, fb, fc])
			floor_uvs.append_array([Vector2(a2.x, a2.y), Vector2(b2.x, b2.y), Vector2(c2.x, c2.y)])
			stats["floor_area"] += 0.5 * (fb - fa).cross(fc - fa).length()
			# Ceiling: same polygon, reversed winding, facing down.
			var ca := Vector3(a2.x, ceil_y, a2.y)
			var cb := Vector3(b2.x, ceil_y, b2.y)
			var cc := Vector3(c2.x, ceil_y, c2.y)
			ceil_tris.append_array([ca, cc, cb])
			ceil_uvs.append_array([Vector2(a2.x, a2.y), Vector2(c2.x, c2.y), Vector2(b2.x, b2.y)])
	return true


## _build_walls(...)
##
## Solid wall: full quad, front floor->ceiling. Portal wall: per side, a
## riser quad (my floor -> other floor, when the other floor is higher)
## and a lintel quad (my ceiling -> other ceiling, when lower). Collision:
## every solid quad, plus risers taller than step_height.
static func _build_walls(
	data: LevelData,
	step_height: float,
	wall_tris: PackedVector3Array,
	wall_normals: PackedVector3Array,
	wall_uvs: PackedVector2Array,
	collision: PackedVector3Array,
	stats: Dictionary
) -> void:
	for w in data.walls:
		var a_id: int = w["a"]
		var b_id: int = w["b"]
		if a_id < 0 or a_id >= data.points.size() or b_id < 0 or b_id >= data.points.size():
			continue
		var a2 := GeometryOps.get_point(data, a_id)
		var b2 := GeometryOps.get_point(data, b_id)
		var front := _sector_heights(data, w["front"])
		var back := _sector_heights(data, w["back"])
		var normal := _wall_normal(a2, b2, data, w["front"])
		if w["back"] == -1:
			_quad(a2, b2, front.x, front.y, normal, wall_tris, wall_normals, wall_uvs)
			_quad_collision(a2, b2, front.x, front.y, collision)
			stats["wall_quads"] += 1
			stats["collision_faces"] += 4
		else:
			# Front side: riser up to the back floor, lintel down from the back ceiling.
			if back.x > front.x:
				_quad(a2, b2, front.x, back.x, normal, wall_tris, wall_normals, wall_uvs)
				stats["wall_quads"] += 1
			if back.y < front.y:
				_quad(a2, b2, back.y, front.y, normal, wall_tris, wall_normals, wall_uvs)
				stats["wall_quads"] += 1
			# Back side, mirrored.
			if front.x > back.x:
				_quad(a2, b2, back.x, front.x, -normal, wall_tris, wall_normals, wall_uvs)
				stats["wall_quads"] += 1
			if front.y < back.y:
				_quad(a2, b2, front.y, back.y, -normal, wall_tris, wall_normals, wall_uvs)
				stats["wall_quads"] += 1
			# Riser too tall to step over blocks movement.
			if absf(back.x - front.x) > step_height:
				_quad_collision(a2, b2, minf(front.x, back.x), maxf(front.x, back.x), collision)
				stats["collision_faces"] += 4


## _merge_holes(outer, holes) -> PackedVector2Array
##
## Keyhole technique: each hole is stitched into the outer loop via a
## zero-width channel at the closest vertex pair, producing one simple
## polygon that triangulate_polygon can ear-clip.
static func _merge_holes(outer: PackedVector2Array, holes: Array) -> PackedVector2Array:
	var poly := outer
	for hole in holes:
		poly = _bridge_hole(poly, hole)
	return poly


static func _bridge_hole(outer: PackedVector2Array, hole: PackedVector2Array) -> PackedVector2Array:
	var best_oi := -1
	var best_hi := -1
	var best_dist := INF
	for oi in range(outer.size()):
		for hi in range(hole.size()):
			var dist := outer[oi].distance_squared_to(hole[hi])
			if dist < best_dist:
				best_dist = dist
				best_oi = oi
				best_hi = hi
	if best_oi == -1 or best_hi == -1:
		return outer
	# The hole must wind opposite to the outer loop, otherwise the ear
	# clipper fills it instead of cutting it. Reversing shifts the anchor
	# vertex's index; track the same physical vertex.
	var anchored := hole
	if signf(GeometryOps.polygon_area(hole)) == signf(GeometryOps.polygon_area(outer)):
		anchored = hole.duplicate()
		anchored.reverse()
		best_hi = anchored.size() - 1 - best_hi
	# Godot's ear clipping rejects coincident points, so the return leg of
	# the bridge is nudged by a hair — the channel is 0.05 units wide
	# (0.3 mm), invisible at editor scale.
	var dir := outer[best_oi] - anchored[best_hi]
	var perp := Vector2(-dir.y, dir.x).normalized() * 0.05
	if perp.length_squared() < 0.000001:
		perp = Vector2(0.05, 0.0)
	var out := PackedVector2Array()
	for i in range(best_oi + 1):
		out.append(outer[i])
	for k in range(anchored.size()):
		out.append(anchored[(best_hi + k) % anchored.size()])
	out.append(anchored[best_hi] + perp)  # close the hole loop (nudged)
	out.append(outer[best_oi] + perp)  # bridge back (nudged)
	for i in range(best_oi + 1, outer.size()):
		out.append(outer[i])
	return out


static func _sector_heights(data: LevelData, sector_id: int) -> Vector2:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return Vector2(DEFAULT_FLOOR, DEFAULT_CEILING)
	var s: Dictionary = data.sectors[sector_id]
	return Vector2(
		float(s.get("floor_height", DEFAULT_FLOOR)),
		float(s.get("ceiling_height", DEFAULT_CEILING))
	)


static func _wall_normal(a2: Vector2, b2: Vector2, data: LevelData, front: int) -> Vector3:
	var d := b2 - a2
	var n := Vector3(-d.y, 0.0, d.x)
	if n.length_squared() < 0.000001:
		return Vector3.FORWARD
	n = n.normalized()
	# Flip toward the front sector's interior when we can find it.
	var poly := GeometryOps.loop_to_polygon(data, data.sectors[front]["walls"]) if front >= 0 and front < data.sectors.size() else PackedVector2Array()
	if poly.size() >= 3:
		var centroid := Vector2.ZERO
		for p in poly:
			centroid += p
		centroid /= float(poly.size())
		var to_centroid := centroid - (a2 + b2) * 0.5
		if n.x * to_centroid.x + n.z * to_centroid.y < 0.0:
			n = -n
	return n


## _quad(a2, b2, y0, y1, normal, ...) — two triangles, world-unit UVs.
static func _quad(
	a2: Vector2,
	b2: Vector2,
	y0: float,
	y1: float,
	normal: Vector3,
	tris: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array
) -> void:
	var v0 := Vector3(a2.x, y0, a2.y)
	var v1 := Vector3(b2.x, y0, b2.y)
	var v2 := Vector3(b2.x, y1, b2.y)
	var v3 := Vector3(a2.x, y1, a2.y)
	tris.append_array([v0, v1, v2, v0, v2, v3])
	for i in range(6):
		normals.append(normal)
	var u1 := a2.distance_to(b2)
	var v := y1 - y0
	uvs.append_array([
		Vector2(0, 0), Vector2(u1, 0), Vector2(u1, v),
		Vector2(0, 0), Vector2(u1, v), Vector2(0, v),
	])


## _quad_collision(a2, b2, y0, y1, collision)
##
## Appends the quad in BOTH windings: GodotPhysics concave trimeshes
## collide only from the backface side, so a single-wound quad is a
## one-way door. Two windings = solid from both sides.
static func _quad_collision(a2: Vector2, b2: Vector2, y0: float, y1: float, collision: PackedVector3Array) -> void:
	var v0 := Vector3(a2.x, y0, a2.y)
	var v1 := Vector3(b2.x, y0, b2.y)
	var v2 := Vector3(b2.x, y1, b2.y)
	var v3 := Vector3(a2.x, y1, a2.y)
	collision.append_array([v0, v1, v2, v0, v2, v3])
	collision.append_array([v0, v2, v1, v0, v3, v2])


static func _commit_surface(
	root: Node3D,
	name: String,
	tris: PackedVector3Array,
	uvs: PackedVector2Array,
	material: Material,
	normals: PackedVector3Array = PackedVector3Array()
) -> void:
	if tris.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if normals.is_empty():
		var flat := PackedVector3Array()
		flat.resize(tris.size())
		var up := Vector3.UP if name != "CeilingMesh" else Vector3.DOWN
		for i in range(flat.size()):
			flat[i] = up
		arrays[Mesh.ARRAY_NORMAL] = flat
	else:
		arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	root.add_child(instance)


## _material(color) — unshaded placeholder. Real art lands in M3.
static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat
