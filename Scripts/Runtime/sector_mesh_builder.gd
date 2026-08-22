class_name SectorMeshBuilder

## SectorMeshBuilder
##
## Reads LevelData geometry and produces Godot meshes plus a static
## collision body. This is the ONLY place Geometry2D.triangulate_polygon
## is used (skill rule). Reads LevelData; never mutates it.
##
## Graceful degradation: flagged or degenerate sectors are skipped and
## counted in the returned stats; invalid slope planes fall back to flat
## heights (GeometryOps validates and flags them). Nothing here ever
## errors out on bad geometry.
##
## Textures: floor_texture / ceiling_texture / wall texture are
## library-relative ArtLibrary names resolved through ArtCache; unknown
## names render as a magenta checker and are reported in the returned
## stats["missing_textures"]. Wall offset_u/offset_v shift UVs in texels.
##
## Mapping: map (x, y) -> 3D (x, height, y). Units: 1 unit = 6 mm.

const DEFAULT_FLOOR := 0.0
const DEFAULT_CEILING := 256.0
const FALLBACK_FLOOR_COLOR := Color(0.45, 0.42, 0.38)
const FALLBACK_CEILING_COLOR := Color(0.32, 0.30, 0.28)
const FALLBACK_WALL_COLOR := Color(0.55, 0.55, 0.58)
const FALLBACK_PLATFORM_COLOR := Color(0.75, 0.52, 0.24)


## build_level(root, data, step_height) -> Dictionary
##
## Clears root and rebuilds floor/ceiling/wall mesh instances (one per
## distinct texture name; the untextured "" groups keep the legacy names
## FloorMesh/CeilingMesh/WallMesh), platform overlay meshes
## (PlatformMesh*), plus CollisionBody. Returns stats:
## sectors_built, sectors_skipped, wall_quads, collision_faces,
## platforms_built, platforms_skipped, floor_area, missing_textures.
static func build_level(root: Node3D, data: LevelData, step_height: float) -> Dictionary:
	var stats := {
		"sectors_built": 0,
		"sectors_skipped": 0,
		"wall_quads": 0,
		"collision_faces": 0,
		"object_collision_quads": 0,
		"platforms_built": 0,
		"platforms_skipped": 0,
		"floor_area": 0.0,
		"missing_textures": [],
	}
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	if data == null:
		return stats

	# Texture name -> {"tris": ..., "uvs": ..., "normals": ...}. World-unit
	# UVs; scaled to texels at commit time per texture size.
	var floors := {}
	var ceilings := {}
	var walls := {}
	var platforms := {}
	var collision := PackedVector3Array()

	for si in range(data.sectors.size()):
		if _build_sector(data, si, floors, ceilings, stats):
			stats["sectors_built"] += 1
		else:
			stats["sectors_skipped"] += 1
	_build_walls(data, step_height, walls, collision, stats)
	_build_object_collision(data, collision, stats)
	_build_platforms(data, platforms, stats)

	_commit_groups(root, "FloorMesh", floors, FALLBACK_FLOOR_COLOR)
	_commit_groups(root, "CeilingMesh", ceilings, FALLBACK_CEILING_COLOR)
	_commit_groups(root, "WallMesh", walls, FALLBACK_WALL_COLOR)
	_commit_groups(root, "PlatformMesh", platforms, FALLBACK_PLATFORM_COLOR)
	stats["missing_textures"] = ArtCache.take_missing()
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
## inner loops are keyhole-bridged into the outer loop. Vertex heights come
## from the slope plane when one is valid, else the flat face height.
## Returns false when the sector must be skipped (flagged or degenerate).
static func _build_sector(data: LevelData, si: int, floors: Dictionary, ceilings: Dictionary, stats: Dictionary) -> bool:
	if not GeometryOps.is_sector_buildable(data, si):
		return false
	var sector: Dictionary = data.sectors[si]
	var outer := GeometryOps.loop_to_polygon(data, sector["walls"])
	if outer.size() < 3:
		return false
	# Slope debug: report what the mesh build actually sees for this sector.
	for key in [&"floor_slope", &"ceiling_slope"]:
		var slope: Array = sector.get(key, [])
		if not slope.is_empty():
			var height_at := GeometryOps.floor_height_at if key == &"floor_slope" else GeometryOps.ceiling_height_at
			GeometryOps.slope_log(
				(
					"mesh: sector %d %s entries=%s — heights: first vertex %.1f, mid vertex %.1f"
					% [
						si, key, str(slope),
						height_at.call(data, si, outer[0]),
						height_at.call(data, si, outer[outer.size() / 2]),
					]
				)
			)
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
	var floor_tex := str(sector.get("floor_texture", ""))
	var ceil_tex := str(sector.get("ceiling_texture", ""))
	for piece in pieces:
		var tris := Geometry2D.triangulate_polygon(piece)
		if tris.is_empty():
			continue
		for i in range(0, tris.size(), 3):
			var a2: Vector2 = piece[tris[i]]
			var b2: Vector2 = piece[tris[i + 1]]
			var c2: Vector2 = piece[tris[i + 2]]
			var fa := Vector3(a2.x, GeometryOps.floor_height_at(data, si, a2), a2.y)
			var fb := Vector3(b2.x, GeometryOps.floor_height_at(data, si, b2), b2.y)
			var fc := Vector3(c2.x, GeometryOps.floor_height_at(data, si, c2), c2.y)
			_group(floors, floor_tex)["tris"].append_array([fa, fb, fc])
			_group(floors, floor_tex)["uvs"].append_array([a2, b2, c2])
			var floor_n := _face_normal(fa, fb, fc, true)
			_group(floors, floor_tex)["normals"].append_array([floor_n, floor_n, floor_n])
			stats["floor_area"] += 0.5 * (fb - fa).cross(fc - fa).length()
			# Ceiling: same polygon, reversed winding, facing down.
			var ca := Vector3(a2.x, GeometryOps.ceiling_height_at(data, si, a2), a2.y)
			var cb := Vector3(b2.x, GeometryOps.ceiling_height_at(data, si, b2), b2.y)
			var cc := Vector3(c2.x, GeometryOps.ceiling_height_at(data, si, c2), c2.y)
			_group(ceilings, ceil_tex)["tris"].append_array([ca, cc, cb])
			_group(ceilings, ceil_tex)["uvs"].append_array([a2, c2, b2])
			var ceil_n := _face_normal(ca, cc, cb, false)
			_group(ceilings, ceil_tex)["normals"].append_array([ceil_n, ceil_n, ceil_n])
	return true


## _build_platforms(data, platforms, stats)
##
## Drawn platform overlays (LevelData.platforms): each polygon triangulates
## into a top face at floor_height and a bottom face at ceiling_height
## (the underside), both with the platform texture. No side walls (v1:
## a flat floating polygon). Flagged platforms (self-intersecting, <3
## points) are skipped and counted, as are invisible ones (is_visible,
## Platform Edit V toggle); nothing here ever errors.
static func _build_platforms(data: LevelData, platforms: Dictionary, stats: Dictionary) -> void:
	for i in range(data.platforms.size()):
		var p: PlatformData = data.platforms[i]
		if p == null or not p.is_visible or data.flagged_platforms.has(i):
			stats["platforms_skipped"] = int(stats["platforms_skipped"]) + 1
			continue
		var poly := PackedVector2Array(p.vertices)
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			stats["platforms_skipped"] = int(stats["platforms_skipped"]) + 1
			continue
		var tex := p.texture
		var top := p.floor_height
		var bottom := p.ceiling_height
		for t in range(0, tris.size(), 3):
			var a2: Vector2 = poly[tris[t]]
			var b2: Vector2 = poly[tris[t + 1]]
			var c2: Vector2 = poly[tris[t + 2]]
			# Top face (the surface), facing up.
			var ta := Vector3(a2.x, top, a2.y)
			var tb := Vector3(b2.x, top, b2.y)
			var tc := Vector3(c2.x, top, c2.y)
			_group(platforms, tex)["tris"].append_array([ta, tb, tc])
			_group(platforms, tex)["uvs"].append_array([a2, b2, c2])
			var top_n := _face_normal(ta, tb, tc, true)
			_group(platforms, tex)["normals"].append_array([top_n, top_n, top_n])
			# Bottom face (the underside), reversed winding, facing down.
			var ba := Vector3(a2.x, bottom, a2.y)
			var bb := Vector3(b2.x, bottom, b2.y)
			var bc := Vector3(c2.x, bottom, c2.y)
			_group(platforms, tex)["tris"].append_array([ba, bc, bb])
			_group(platforms, tex)["uvs"].append_array([a2, c2, b2])
			var bottom_n := _face_normal(ba, bc, bb, false)
			_group(platforms, tex)["normals"].append_array([bottom_n, bottom_n, bottom_n])
		stats["platforms_built"] = int(stats["platforms_built"]) + 1


## build_sector_highlight(data, sector_id, y_offset) -> ArrayMesh
##
## The 3D crosshair sector highlight (inner-sector shortcut UX): a flat
## translucent overlay of the sector's floor, y_offset above it, inner
## loops keyhole-bridged out and slope planes honored per vertex. The
## view owns the node and material; triangulation lives here per the
## skill rule. Returns null for degenerate sectors.
static func build_sector_highlight(data: LevelData, sector_id: int, y_offset: float) -> ArrayMesh:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return null
	var sector: Dictionary = data.sectors[sector_id]
	var outer := GeometryOps.loop_to_polygon(data, sector["walls"])
	if outer.size() < 3:
		return null
	var holes: Array = []
	for loop in sector["inner"]:
		var hole := GeometryOps.loop_to_polygon(data, loop)
		if hole.size() >= 3:
			holes.append(hole)
	var poly := outer
	if not holes.is_empty():
		poly = _merge_holes(outer, holes)
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return null
	var verts := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		for k in range(3):
			var p2: Vector2 = poly[tris[i + k]]
			verts.append(Vector3(
				p2.x, GeometryOps.floor_height_at(data, sector_id, p2) + y_offset, p2.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## _build_walls(...)
##
## Solid wall: full quad, front floor->ceiling. Portal wall: per side, a
## riser quad (my floor -> other floor, when the other floor is higher)
## and a lintel quad (my ceiling -> other ceiling, when lower). Heights
## are per-endpoint so sloped sectors get sheared quads. Collision: every
## solid quad, plus risers taller than step_height.
static func _build_walls(data: LevelData, step_height: float, walls: Dictionary, collision: PackedVector3Array, stats: Dictionary) -> void:
	for w in data.walls:
		var a_id: int = w["a"]
		var b_id: int = w["b"]
		if a_id < 0 or a_id >= data.points.size() or b_id < 0 or b_id >= data.points.size():
			continue
		var a2 := GeometryOps.get_point(data, a_id)
		var b2 := GeometryOps.get_point(data, b_id)
		var front: int = w["front"]
		var back: int = w["back"]
		# Per-endpoint face heights: (floor_a, floor_b, ceil_a, ceil_b).
		var ff := _face_heights(data, front, a2, b2, true)
		var fc := _face_heights(data, front, a2, b2, false)
		var bf := _face_heights(data, back, a2, b2, true)
		var bc := _face_heights(data, back, a2, b2, false)
		var normal := _wall_normal(a2, b2, data, front)
		var tex := str(w.get("texture", ""))
		var ou := float(w.get("offset_u", 0.0))
		var ov := float(w.get("offset_v", 0.0))
		if back == -1:
			_quad(a2, b2, ff.x, ff.y, fc.x, fc.y, normal, tex, ou, ov, walls)
			_quad_collision(a2, b2, minf(ff.x, ff.y), maxf(fc.x, fc.y), collision)
			stats["wall_quads"] += 1
			stats["collision_faces"] += 4
		else:
			# Front side: riser up to the back floor, lintel down from the
			# back ceiling. Back side, mirrored. Per-endpoint heights, so
			# sloped sectors shear these quads.
			_riser_lintel(a2, b2, ff, bf, true, normal, tex, ou, ov, walls, stats)
			_riser_lintel(a2, b2, fc, bc, false, normal, tex, ou, ov, walls, stats)
			_riser_lintel(a2, b2, bf, ff, true, -normal, tex, ou, ov, walls, stats)
			_riser_lintel(a2, b2, bc, fc, false, -normal, tex, ou, ov, walls, stats)
			# Riser too tall to step over (at either endpoint) blocks movement.
			var step_up := maxf(bf.x - ff.x, bf.y - ff.y)
			var step_down := maxf(ff.x - bf.x, ff.y - bf.y)
			if maxf(step_up, step_down) > step_height:
				_quad_collision(a2, b2, minf(ff.x, bf.x), maxf(ff.y, bf.y), collision)
				stats["collision_faces"] += 4


## _riser_lintel(a2, b2, mine, theirs, up, ...) — the face between my
## floor/ceiling and the neighbour's, only where the neighbour's is more
## extreme (up=true: riser, neighbour floor higher; up=false: lintel,
## neighbour ceiling lower). Per-endpoint heights; sliver endpoints are
## tolerated, fully-flat quads are skipped.
static func _riser_lintel(
	a2: Vector2,
	b2: Vector2,
	mine: Vector2,
	theirs: Vector2,
	up: bool,
	normal: Vector3,
	tex: String,
	ou: float,
	ov: float,
	walls: Dictionary,
	stats: Dictionary
) -> void:
	var y0a: float
	var y0b: float
	var y1a: float
	var y1b: float
	if up:
		y0a = mine.x
		y0b = mine.y
		y1a = maxf(mine.x, theirs.x)
		y1b = maxf(mine.y, theirs.y)
	else:
		y0a = minf(mine.x, theirs.x)
		y0b = minf(mine.y, theirs.y)
		y1a = mine.x
		y1b = mine.y
	if y1a <= y0a and y1b <= y0b:
		return
	_quad(a2, b2, y0a, y0b, y1a, y1b, normal, tex, ou, ov, walls)
	stats["wall_quads"] += 1


## _face_heights(data, sector_id, a2, b2, is_floor) -> Vector4 as 2 Vector2
##
## Returns Vector2(height_at_a, height_at_b) for one face of a sector.
static func _face_heights(data: LevelData, sector_id: int, a2: Vector2, b2: Vector2, is_floor: bool) -> Vector2:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return Vector2(DEFAULT_FLOOR, DEFAULT_FLOOR) if is_floor else Vector2(DEFAULT_CEILING, DEFAULT_CEILING)
	if is_floor:
		return Vector2(GeometryOps.floor_height_at(data, sector_id, a2), GeometryOps.floor_height_at(data, sector_id, b2))
	return Vector2(GeometryOps.ceiling_height_at(data, sector_id, a2), GeometryOps.ceiling_height_at(data, sector_id, b2))


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


static func _face_normal(a: Vector3, b: Vector3, c: Vector3, up: bool) -> Vector3:
	var n := (b - a).cross(c - a).normalized()
	if up and n.y < 0.0:
		return -n
	if not up and n.y > 0.0:
		return -n
	return n


## _quad(a2, b2, ya0, yb0, ya1, yb1, normal, tex, ou, ov, walls)
##
## Two triangles with per-endpoint heights (sloped sectors shear the quad).
## UVs: u = distance along the wall + offset_u, v = world y + offset_v;
## scaled to texels at commit time.
static func _quad(
	a2: Vector2,
	b2: Vector2,
	ya0: float,
	yb0: float,
	ya1: float,
	yb1: float,
	normal: Vector3,
	tex: String,
	ou: float,
	ov: float,
	walls: Dictionary
) -> void:
	var g: Dictionary = _group(walls, tex)
	var v0 := Vector3(a2.x, ya0, a2.y)
	var v1 := Vector3(b2.x, yb0, b2.y)
	var v2 := Vector3(b2.x, yb1, b2.y)
	var v3 := Vector3(a2.x, ya1, a2.y)
	g["tris"].append_array([v0, v1, v2, v0, v2, v3])
	for i in range(6):
		g["normals"].append(normal)
	var u1 := a2.distance_to(b2)
	g["uvs"].append_array([
		Vector2(ou, ya0 + ov), Vector2(u1 + ou, yb0 + ov), Vector2(u1 + ou, yb1 + ov),
		Vector2(ou, ya0 + ov), Vector2(u1 + ou, yb1 + ov), Vector2(ou, ya1 + ov),
	])


## _build_object_collision(data, collision, stats)
##
## M5: objects with params.collide == true (imported GCS object-walls)
## get a double-wound collision quad so the walk test bumps into them.
## Editor-placed objects default to no collision (objects clip freely).
static func _build_object_collision(data: LevelData, collision: PackedVector3Array, stats: Dictionary) -> void:
	for i in range(data.objects.size()):
		if data.flagged_objects.has(i):
			continue
		var obj: Variant = data.objects[i]
		if not obj is Dictionary:
			continue
		if not bool((obj as Dictionary).get("params", {}).get("collide", false)):
			continue
		var extent := ObjectOps.get_extent(obj)
		var center := ObjectOps.get_pos(obj)
		# Lateral = the quad's run direction: normal rotated by +90 deg.
		var angle := deg_to_rad(float(obj.get("angle", 0.0)) + 90.0)
		var half := Vector2(0.0, 1.0).rotated(angle) * extent.x * 0.5
		var z := float(obj.get("z", 0.0))
		_quad_collision(center - half, center + half, z, z + extent.y, collision)
		stats["object_collision_quads"] = int(stats["object_collision_quads"]) + 1


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


static func _group(groups: Dictionary, tex: String) -> Dictionary:
	if not groups.has(tex):
		groups[tex] = {
			"tris": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"normals": PackedVector3Array(),
		}
	return groups[tex]


## _commit_groups(root, base_name, groups, fallback_color)
##
## One MeshInstance3D per distinct texture name. The untextured "" group
## keeps the plain base name (FloorMesh etc.) for test/tool compatibility;
## textured groups are suffixed with a sanitized texture name. UVs are
## world units on input, scaled by 1/texture_size here.
static func _commit_groups(root: Node3D, base_name: String, groups: Dictionary, fallback_color: Color) -> void:
	for tex in groups:
		var g: Dictionary = groups[tex]
		var tris: PackedVector3Array = g["tris"]
		if tris.is_empty():
			continue
		var size := ArtCache.texture_size(tex)
		var uvs := PackedVector2Array()
		for uv in g["uvs"]:
			uvs.append(Vector2(uv.x / size.x, uv.y / size.y))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = tris
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_NORMAL] = g["normals"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, ArtCache.material_for(tex, fallback_color))
		var instance := MeshInstance3D.new()
		if tex.is_empty():
			instance.name = base_name
		else:
			instance.name = "%s_%s" % [base_name, tex.replace("/", "_").replace(".", "_")]
		instance.mesh = mesh
		root.add_child(instance)
