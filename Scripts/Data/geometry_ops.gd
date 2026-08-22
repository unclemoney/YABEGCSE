class_name GeometryOps

## GeometryOps
##
## All sector-geometry mutation and validation. Static, pure functions over
## LevelData — no nodes, no input — so the whole geometry layer is
## headless-testable. Units: 1 unit = 6 mm, everywhere, forever.

const EPS := 0.001  # geometric epsilon, world units
const EPS_T := 0.001  # segment parameter epsilon
const MIN_OVERLAP_AREA := 1.0  # square units; touching edges are not overlap

# TODO: flip to false once the live slope-drag failure is pinned down.
static var debug_slopes := true


## slope_log(text)
##
## One switch for the whole slope pipeline's debug output (view input ->
## tool drag -> LevelData write -> validate -> mesh build). Prints to the
## editor Output panel and headless stdout with a [slope] prefix.
static func slope_log(text: String) -> void:
	if debug_slopes:
		print("[slope] " + text)


## snap(v, grid) -> Vector2
##
## Grid snapping. Grid sizes are editor behavior, never file data.
static func snap(v: Vector2, grid: float) -> Vector2:
	if grid <= 0.0:
		return v
	return Vector2(snappedf(v.x, grid), snappedf(v.y, grid))


static func get_point(data: LevelData, id: int) -> Vector2:
	var p: Array = data.points[id]
	return Vector2(p[0], p[1])


static func find_point_at(data: LevelData, v: Vector2, tolerance: float) -> int:
	for i in range(data.points.size()):
		if get_point(data, i).distance_to(v) <= tolerance:
			return i
	return -1


## add_point(data, v) -> int
##
## Returns the existing point id when one sits within EPS of v.
static func add_point(data: LevelData, v: Vector2) -> int:
	var existing := find_point_at(data, v, EPS)
	if existing != -1:
		return existing
	data.points.append([v.x, v.y])
	return data.points.size() - 1


## add_segment(data, p0, p1) -> Array[int]
##
## Inserts a drawn segment into the point table. Every existing wall it
## crosses is auto-split with a new shared vertex; T-junctions and
## collinear partial overlaps split too; passing through an existing
## vertex subdivides the drawn segment there. Returns the ordered point
## ids along p0->p1. Does NOT create walls (that is close-loop time).
static func add_segment(data: LevelData, p0: Vector2, p1: Vector2) -> Array[int]:
	var marks: Array = []
	marks.append({"t": 0.0, "point": add_point(data, p0)})
	marks.append({"t": 1.0, "point": add_point(data, p1)})
	var splits: Array = []
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if not _valid_wall(data, w):
			continue
		var wa := get_point(data, w["a"])
		var wb := get_point(data, w["b"])
		var d := p1 - p0
		var e := wb - wa
		var denom := d.cross(e)
		if absf(denom) < EPS:
			# Parallel: handle collinear overlap (shared or partial edges).
			if _collinear(p0, p1, wa, wb):
				for ep in [p0, p1]:
					if _point_strictly_on_segment(ep, wa, wb):
						splits.append({"wall": wi, "point": add_point(data, ep)})
				for pair in [[wa, w["a"]], [wb, w["b"]]]:
					if _point_strictly_on_segment(pair[0], p0, p1):
						marks.append({
							"t": _param_on_segment(pair[0], p0, p1),
							"point": pair[1],
						})
			continue
		var f := wa - p0
		var t := f.cross(e) / denom
		var u := f.cross(d) / denom
		var t_inside := t > EPS_T and t < 1.0 - EPS_T
		var u_inside := u > EPS_T and u < 1.0 - EPS_T
		var t_on_end := absf(t) <= EPS_T or absf(t - 1.0) <= EPS_T
		var u_on_end := absf(u) <= EPS_T or absf(u - 1.0) <= EPS_T
		if t_inside and u_inside:
			# Proper crossing: split the existing wall, subdivide here.
			var pid := add_point(data, p0 + d * t)
			splits.append({"wall": wi, "point": pid})
			marks.append({"t": t, "point": pid})
		elif u_inside and t_on_end:
			# T-junction: a segment endpoint lands on the wall.
			if absf(t) <= EPS_T:
				splits.append({"wall": wi, "point": add_point(data, p0)})
			else:
				splits.append({"wall": wi, "point": add_point(data, p1)})
		elif t_inside and u_on_end:
			# Segment passes through an existing wall endpoint.
			if absf(u) <= EPS_T:
				marks.append({"t": t, "point": w["a"]})
			else:
				marks.append({"t": t, "point": w["b"]})
		# Otherwise the lines miss both segments: no interaction.
	for split in splits:
		split_wall(data, split["wall"], split["point"])
	marks.sort_custom(func(a, b): return a["t"] < b["t"])
	var ids: Array[int] = []
	for mark in marks:
		if ids.is_empty() or ids[ids.size() - 1] != mark["point"]:
			ids.append(mark["point"])
	return ids


## close_loop_from_positions(data, verts) -> int
##
## Single-mutation sector creation from a list of Vector2 vertices.
## Edges are inserted via add_segment (auto-split), then each ring edge
## reuses an existing wall with identical endpoints (making it a portal)
## or creates a new solid wall. A loop strictly inside another sector is
## registered as an inner loop (sector-within-sector) and its walls become
## two-sided. Returns the new sector id, or -1 for degenerate input.
static func close_loop_from_positions(data: LevelData, verts: Array) -> int:
	if verts.size() < 3:
		return -1
	var ring: Array[int] = []
	for i in range(verts.size()):
		var p0: Vector2 = verts[i]
		var p1: Vector2 = verts[(i + 1) % verts.size()]
		if p0.distance_to(p1) < EPS:
			continue
		var ids := add_segment(data, p0, p1)
		if ids.size() < 2:
			continue
		if ring.is_empty():
			ring.append_array(ids)
		else:
			ring.append_array(ids.slice(1))
	if ring.size() >= 2 and ring[0] == ring[ring.size() - 1]:
		ring.remove_at(ring.size() - 1)
	if ring.size() < 3:
		return -1

	var sector_id := data.sectors.size()
	var centroid := Vector2.ZERO
	for id in ring:
		centroid += get_point(data, id)
	centroid /= float(ring.size())

	var ring_walls: Array[int] = []
	for i in range(ring.size()):
		var a: int = ring[i]
		var b: int = ring[(i + 1) % ring.size()]
		var existing := find_wall_between(data, a, b)
		if existing != -1:
			var wall: Dictionary = data.walls[existing]
			if wall["front"] == -1:
				wall["front"] = sector_id
			elif wall["back"] == -1:
				wall["back"] = sector_id
			# Both sides taken: overlap; validate() flags it.
			ring_walls.append(existing)
		else:
			var pa := get_point(data, a)
			var pb := get_point(data, b)
			# Orient so the new sector interior (centroid side) is front.
			if (pb - pa).cross(centroid - pa) < 0.0:
				var tmp := a
				a = b
				b = tmp
			data.walls.append({
				"a": a, "b": b, "front": sector_id, "back": -1,
				"texture": "", "offset_u": 0.0, "offset_v": 0.0,
			})
			ring_walls.append(data.walls.size() - 1)

	data.sectors.append({
		"walls": ring_walls,
		"inner": [],
		"floor_height": 0.0,
		"ceiling_height": 256.0,
		"floor_texture": "",
		"ceiling_texture": "",
		"floor_slope": [],
		"ceiling_slope": [],
		"flags": 0,
	})

	# Containment: strictly inside another sector -> inner loop.
	var poly := PackedVector2Array()
	for id in ring:
		poly.append(get_point(data, id))
	for si in range(data.sectors.size() - 1):
		var outer := loop_to_polygon(data, data.sectors[si]["walls"])
		if outer.size() < 3:
			continue
		var all_inside := true
		for id in ring:
			if not point_strictly_inside(get_point(data, id), outer):
				all_inside = false
				break
		if all_inside:
			data.sectors[si]["inner"].append(ring_walls.duplicate())
			for wid in ring_walls:
				var w: Dictionary = data.walls[wid]
				if w["front"] == sector_id and w["back"] == -1:
					w["back"] = si
			break
	return sector_id


## delete_sector(data, sector_id)
##
## Shared (portal) walls revert to solid; exclusive walls and orphaned
## points are removed with full index remapping.
static func delete_sector(data: LevelData, sector_id: int) -> void:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return
	var doomed_walls: Array[int] = []
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if w["front"] == sector_id:
			if w["back"] == -1:
				doomed_walls.append(wi)
			else:
				w["front"] = w["back"]
				w["back"] = -1
		elif w["back"] == sector_id:
			w["back"] = -1
	data.sectors.remove_at(sector_id)
	for w in data.walls:
		if w["front"] > sector_id:
			w["front"] -= 1
		if w["back"] > sector_id:
			w["back"] -= 1
	_remove_walls(data, doomed_walls)
	_remove_orphan_points(data)


## validate(data)
##
## Recomputes flagged_sectors / flagged_walls. Tolerate + flag: nothing
## here errors out, whatever the input. Called after every load and every
## geometry mutation. Annotations are computed, never serialized.
static func validate(data: LevelData) -> void:
	data.flagged_walls.clear()
	data.flagged_sectors.clear()
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if not _valid_wall(data, w):
			_flag_wall(data, wi, "point index out of range")
			continue
		var pa := get_point(data, w["a"])
		var pb := get_point(data, w["b"])
		if pa.distance_to(pb) < EPS:
			_flag_wall(data, wi, "zero-length wall")
	var polys := {}
	for si in range(data.sectors.size()):
		var sector: Dictionary = data.sectors[si]
		var poly := loop_to_polygon(data, sector["walls"])
		polys[si] = poly
		if poly.size() < 3:
			_flag_sector(data, si, "unclosed or degenerate loop")
		for loop in sector["inner"]:
			if loop_to_polygon(data, loop).size() < 3:
				_flag_sector(data, si, "unclosed inner loop")
	# Load-time verification: wall segments must never cross unsplit.
	for wi in range(data.walls.size()):
		var w1: Dictionary = data.walls[wi]
		if not _valid_wall(data, w1):
			continue
		var a1 := get_point(data, w1["a"])
		var b1 := get_point(data, w1["b"])
		for wj in range(wi + 1, data.walls.size()):
			var w2: Dictionary = data.walls[wj]
			if not _valid_wall(data, w2):
				continue
			var a2 := get_point(data, w2["a"])
			var b2 := get_point(data, w2["b"])
			var d := b1 - a1
			var e := b2 - a2
			var denom := d.cross(e)
			if absf(denom) < EPS:
				continue
			var f := a2 - a1
			var t := f.cross(e) / denom
			var u := f.cross(d) / denom
			if t > EPS_T and t < 1.0 - EPS_T and u > EPS_T and u < 1.0 - EPS_T:
				_flag_wall(data, wi, "crossing without split vertex")
				_flag_wall(data, wj, "crossing without split vertex")
				_flag_wall_sectors(data, wi, "contains crossing walls")
				_flag_wall_sectors(data, wj, "contains crossing walls")
	# No room-over-room: sectors must not overlap in 2D unless one fully
	# contains the other (inner loop). Touching edges are not overlap.
	for si in range(data.sectors.size()):
		var p1: PackedVector2Array = polys[si]
		if p1.size() < 3:
			continue
		for sj in range(si + 1, data.sectors.size()):
			var p2: PackedVector2Array = polys[sj]
			if p2.size() < 3:
				continue
			var inter := Geometry2D.intersect_polygons(p1, p2)
			var area := 0.0
			for piece in inter:
				area += absf(polygon_area(piece))
			if area < MIN_OVERLAP_AREA:
				continue
			var one_way := _polygon_contains(p1, p2) != _polygon_contains(p2, p1)
			if not one_way:
				_flag_sector(data, si, "2D overlap (no room-over-room)")
				_flag_sector(data, sj, "2D overlap (no room-over-room)")
	# Slope planes (M3): tolerate + flag. Anything but exactly 3 valid,
	# non-collinear corner heights degrades to flat rendering.
	for si in range(data.sectors.size()):
		var sector: Dictionary = data.sectors[si]
		for key in [&"floor_slope", &"ceiling_slope"]:
			var slope: Array = sector.get(key, [])
			if slope.is_empty():
				continue
			var corners := _slope_corners(data, sector, key)
			if slope.size() != 3 or corners.size() != 3:
				_flag_sector(data, si, "%s: incomplete slope (%d/3 corners)" % [key, corners.size()])
				slope_log("validate: sector %d %s flagged incomplete (entries=%d, resolved=%d/3): %s" % [
					si, key, slope.size(), corners.size(), str(slope),
				])
			elif not _corners_form_plane(corners):
				_flag_sector(data, si, "%s: collinear slope corners" % key)
				slope_log("validate: sector %d %s flagged collinear: %s" % [si, key, str(slope)])
		var floor_y := float(sector.get("floor_height", 0.0))
		var ceil_y := float(sector.get("ceiling_height", 256.0))
		if floor_y >= ceil_y:
			_flag_sector(data, si, "floor at or above ceiling")
	# M4: object schema-shape checks live in ObjectOps but run from the
	# same single validation entry point.
	ObjectOps.validate(data)


## loop_to_polygon(data, wall_ids) -> PackedVector2Array
##
## Chains loop walls (any stored direction) into a closed polygon.
## Returns an empty array for broken or unclosed loops.
static func loop_to_polygon(data: LevelData, wall_ids: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if wall_ids.is_empty():
		return polygon
	var first: Dictionary = data.walls[wall_ids[0]]
	if not _valid_wall(data, first):
		return PackedVector2Array()
	polygon.append(get_point(data, first["a"]))
	polygon.append(get_point(data, first["b"]))
	var current_id: int = first["b"]
	var remaining: Array = wall_ids.slice(1)
	var guard := 0
	while not remaining.is_empty() and guard < 10000:
		guard += 1
		var found := -1
		var found_next := -1
		for i in range(remaining.size()):
			var w: Dictionary = data.walls[remaining[i]]
			if not _valid_wall(data, w):
				continue
			if w["a"] == current_id:
				found = i
				found_next = w["b"]
				break
			if w["b"] == current_id:
				found = i
				found_next = w["a"]
				break
		if found == -1:
			return PackedVector2Array()
		polygon.append(get_point(data, found_next))
		current_id = found_next
		remaining.remove_at(found)
	if current_id != first["a"]:
		return PackedVector2Array()
	polygon.remove_at(polygon.size() - 1)
	return polygon


## sector_at(data, p) -> int
##
## Smallest sector containing p (inner loops win over their container).
static func sector_at(data: LevelData, p: Vector2) -> int:
	var best := -1
	var best_area := INF
	for si in range(data.sectors.size()):
		var poly := loop_to_polygon(data, data.sectors[si]["walls"])
		if poly.size() < 3:
			continue
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var area := absf(polygon_area(poly))
		if area < best_area:
			best_area = area
			best = si
	return best


static func point_in_sector(data: LevelData, sector_id: int, p: Vector2) -> bool:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return false
	var poly := loop_to_polygon(data, data.sectors[sector_id]["walls"])
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(p, poly)


static func wall_near(data: LevelData, p: Vector2, tolerance: float) -> int:
	var best := -1
	var best_dist := tolerance
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if not _valid_wall(data, w):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(
			p, get_point(data, w["a"]), get_point(data, w["b"]))
		var dist := p.distance_to(closest)
		if dist < best_dist:
			best_dist = dist
			best = wi
	return best


static func find_wall_between(data: LevelData, a: int, b: int) -> int:
	for i in range(data.walls.size()):
		var w: Dictionary = data.walls[i]
		if (w["a"] == a and w["b"] == b) or (w["a"] == b and w["b"] == a):
			return i
	return -1


## split_wall(data, wall_id, point_id) -> int
##
## wall a->b becomes a->point plus a new wall point->b, attributes
## preserved. Sector loops referencing the wall get both ids in sequence.
static func split_wall(data: LevelData, wall_id: int, point_id: int) -> int:
	var w: Dictionary = data.walls[wall_id]
	var new_wall := w.duplicate()
	new_wall["a"] = point_id
	w["b"] = point_id
	data.walls.append(new_wall)
	var new_id := data.walls.size() - 1
	for sector in data.sectors:
		sector["walls"] = _split_in_loop(sector["walls"], wall_id, new_id)
		var inner: Array = sector["inner"]
		for li in range(inner.size()):
			inner[li] = _split_in_loop(inner[li], wall_id, new_id)
	return new_id


static func polygon_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(poly.size()):
		var j := (i + 1) % poly.size()
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return area * 0.5


## floor_height_at(data, sector_id, pos) -> float
## ceiling_height_at(data, sector_id, pos) -> float
##
## Height of a sector face at a 2D position. A valid slope plane (exactly 3
## non-collinear corner heights) is evaluated; anything else falls back to
## the flat floor_height / ceiling_height. Never errors.
static func floor_height_at(data: LevelData, sector_id: int, pos: Vector2) -> float:
	return _face_height_at(data, sector_id, pos, &"floor_slope", &"floor_height", 0.0)


static func ceiling_height_at(data: LevelData, sector_id: int, pos: Vector2) -> float:
	return _face_height_at(data, sector_id, pos, &"ceiling_slope", &"ceiling_height", 256.0)


static func _face_height_at(
	data: LevelData,
	sector_id: int,
	pos: Vector2,
	slope_key: StringName,
	height_key: StringName,
	default_height: float
) -> float:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return default_height
	var sector: Dictionary = data.sectors[sector_id]
	var base := float(sector.get(height_key, default_height))
	var corners := _slope_corners(data, sector, slope_key)
	if corners.size() != 3 or not _corners_form_plane(corners):
		return base
	# Plane through 3 corners: n . (p - c0) = 0, solved for y at (x, z).
	var n: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
	if absf(n.y) < EPS:
		return base  # vertical plane: not a usable floor/ceiling
	return corners[0].y - (n.x * (pos.x - corners[0].x) + n.z * (pos.y - corners[0].z)) / n.y


## set_slope_corner(sector, slope_key, point_id, height)
##
## Adds or replaces one corner-height entry in a slope array. Order of
## insertion is kept; the plane is defined once 3 distinct valid corners
## exist. Pure dict surgery — callers own commit/validate.
static func set_slope_corner(sector: Dictionary, slope_key: StringName, point_id: int, height: float) -> void:
	var slope: Array = sector.get(slope_key, [])
	for entry in slope:
		if int(entry[0]) == point_id:
			entry[1] = height
			slope_log("set_slope_corner: %s point %d -> %.1f (replaced; %d entries)" % [
				slope_key, point_id, height, slope.size(),
			])
			return
	slope.append([point_id, height])
	sector[slope_key] = slope
	slope_log("set_slope_corner: %s point %d -> %.1f (added; %d entries)" % [
		slope_key, point_id, height, slope.size(),
	])


## remove_slope_corner(sector, slope_key, point_id)
##
## Deletes one corner entry from a slope array. Pure dict surgery —
## callers own commit/validate.
static func remove_slope_corner(sector: Dictionary, slope_key: StringName, point_id: int) -> void:
	var slope: Array = sector.get(slope_key, [])
	for i in range(slope.size()):
		if int(slope[i][0]) == point_id:
			slope.remove_at(i)
			sector[slope_key] = slope
			slope_log("remove_slope_corner: %s point %d removed (%d entries)" % [
				slope_key, point_id, slope.size(),
			])
			return


## _slope_corners(data, sector, slope_key) -> Array[Vector3]
##
## Resolves slope entries to 3D corners (map x, height, map y). Entries
## with out-of-range point ids are dropped; validate() flags the sector.
static func _slope_corners(data: LevelData, sector: Dictionary, slope_key: StringName) -> Array:
	var corners: Array = []
	for entry in sector.get(slope_key, []):
		if not entry is Array or entry.size() != 2:
			continue
		var pid := int(entry[0])
		if pid < 0 or pid >= data.points.size():
			continue
		var p := get_point(data, pid)
		corners.append(Vector3(p.x, float(entry[1]), p.y))
	return corners


## _corners_form_plane(corners) -> bool
##
## Three corners are a usable face plane iff their 2D positions are not
## collinear — any three 3D points define some plane, but a vertical one
## (collinear 2D projection) cannot be a floor or ceiling.
static func _corners_form_plane(corners: Array) -> bool:
	if corners.size() != 3:
		return false
	var d1 := Vector2(corners[1].x - corners[0].x, corners[1].z - corners[0].z)
	var d2 := Vector2(corners[2].x - corners[0].x, corners[2].z - corners[0].z)
	return absf(d1.cross(d2)) >= EPS


## is_sector_buildable(data, sector_id) -> bool
##
## Tolerate + flag, but some flags are fatal for meshing: broken loops,
## crossings, 2D overlap. M3 flags (slope problems, floor >= ceiling) are
## cosmetic — the sector still builds, degraded to flat heights.
const STRUCTURAL_FLAG_MARKERS: Array[String] = ["unclosed", "crossing", "overlap"]

static func is_sector_buildable(data: LevelData, sector_id: int) -> bool:
	if not data.flagged_sectors.has(sector_id):
		return true
	var reason: String = data.flagged_sectors[sector_id]
	for marker in STRUCTURAL_FLAG_MARKERS:
		if reason.contains(marker):
			return false
	return true


## aim_from_ray(data, origin, dir) -> Dictionary
##
## M3 3D-mode picking: casts a ray (camera through crosshair) against all
## sector floors, ceilings and walls — pure math, no physics, so it runs
## headless. Returns the nearest hit:
##   {"kind": &"floor"|&"ceiling"|&"wall", "sector_id": int,
##    "wall_id": int (-1 unless wall), "point": Vector3, "distance": float}
## or {"kind": &"none"} when nothing is hit within MAX_AIM_DIST.
const MAX_AIM_DIST := 4096.0

static func aim_from_ray(data: LevelData, origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {"kind": &"none"}
	var best_t := MAX_AIM_DIST
	if dir.length_squared() < EPS * EPS:
		return best
	for si in range(data.sectors.size()):
		var poly := loop_to_polygon(data, data.sectors[si]["walls"])
		if poly.size() < 3:
			continue
		for is_floor in [true, false]:
			var hit := _ray_face_hit(data, si, origin, dir, is_floor)
			if hit.x < 0.0 or hit.x >= best_t:
				continue
			var p := origin + dir * hit.x
			if not point_in_sector(data, si, Vector2(p.x, p.z)):
				continue
			best_t = hit.x
			best = {
				"kind": &"floor" if is_floor else &"ceiling",
				"sector_id": si,
				"wall_id": -1,
				"point": p,
				"distance": hit.x,
			}
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if not _valid_wall(data, w):
			continue
		var a2 := get_point(data, w["a"])
		var b2 := get_point(data, w["b"])
		var a3 := Vector3(a2.x, 0.0, a2.y)
		var n := Vector3(-(b2.y - a2.y), 0.0, b2.x - a2.x)
		if n.length_squared() < EPS * EPS:
			continue
		var hit_variant: Variant = Plane(n.normalized(), a3).intersects_ray(origin, dir)
		if hit_variant == null:
			continue
		var p: Vector3 = hit_variant
		var t := origin.distance_to(p)
		if t >= best_t or t < EPS:
			continue
		# Within the wall segment and its vertical span?
		var u := _param_on_segment(Vector2(p.x, p.z), a2, b2)
		if u < -EPS_T or u > 1.0 + EPS_T:
			continue
		var span := _wall_vertical_span(data, w)
		if p.y < span.x - EPS or p.y > span.y + EPS:
			continue
		best_t = t
		best = {
			"kind": &"wall",
			"sector_id": w["front"],
			"wall_id": wi,
			"point": p,
			"distance": t,
		}
	return best


## nearest_corner(data, sector_id, pos, tolerance) -> int
##
## Point id of the nearest outer-loop corner of a sector, or -1.
static func nearest_corner(data: LevelData, sector_id: int, pos: Vector2, tolerance: float) -> int:
	if sector_id < 0 or sector_id >= data.sectors.size():
		return -1
	var best := -1
	var best_dist := tolerance
	for wid in data.sectors[sector_id]["walls"]:
		var w: Dictionary = data.walls[wid]
		if not _valid_wall(data, w):
			continue
		for pid in [w["a"], w["b"]]:
			var dist := get_point(data, pid).distance_to(pos)
			if dist < best_dist:
				best_dist = dist
				best = pid
	return best


## nearest_point(data, v, tolerance) -> int
##
## Closest point-table entry within tolerance, or -1. The vertex edit
## tool's pick radius (8 px, zoom-scaled by the caller).
static func nearest_point(data: LevelData, v: Vector2, tolerance: float) -> int:
	var best := -1
	var best_dist := tolerance
	for i in range(data.points.size()):
		var dist := get_point(data, i).distance_to(v)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


## move_point(data, point_id, new_pos)
##
## Vertex edit drag: repositions one point-table entry. Connected walls
## follow automatically (walls reference point ids). Pure data surgery —
## callers own snapshot/validate/notify.
static func move_point(data: LevelData, point_id: int, new_pos: Vector2) -> void:
	if point_id < 0 or point_id >= data.points.size():
		return
	data.points[point_id] = [new_pos.x, new_pos.y]


## move_causes_crossing(data, point_id, new_pos) -> bool
##
## Vertex edit validity: true when moving point_id to new_pos would make
## any wall connected to it strictly cross another wall (touching at
## shared endpoints is not a crossing — that is how loops join). A move
## collapsing a wall to zero length counts as invalid too.
static func move_causes_crossing(data: LevelData, point_id: int, new_pos: Vector2) -> bool:
	if point_id < 0 or point_id >= data.points.size():
		return true
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if w["a"] != point_id and w["b"] != point_id:
			continue
		if not _valid_wall(data, w):
			continue
		var other_id: int = w["b"] if w["a"] == point_id else w["a"]
		var b1 := get_point(data, other_id)
		if new_pos.distance_to(b1) < EPS:
			return true
		for wj in range(data.walls.size()):
			if wj == wi:
				continue
			var w2: Dictionary = data.walls[wj]
			if w2["a"] == point_id or w2["b"] == point_id:
				continue  # shares the moved vertex
			if not _valid_wall(data, w2):
				continue
			if _segments_cross_strict(new_pos, b1, get_point(data, w2["a"]), get_point(data, w2["b"])):
				return true
	return false


## check_portal_merge(data, wall_id) -> Dictionary
##
## Wall-select tool's merge gate. Pure: computes the full merge plan for
## a portal wall without mutating anything. Returns {"ok", "reason",
## "merged_walls", "survivor", "removed"}. Rejects boundary walls,
## multi-wall portals, sectors with inner loops, and merged loops that
## would be self-intersecting, degenerate or non-closed. The survivor is
## the larger-area sector (heights/textures inherit from it).
static func check_portal_merge(data: LevelData, wall_id: int) -> Dictionary:
	if wall_id < 0 or wall_id >= data.walls.size():
		return _merge_fail("wall index out of range")
	var w: Dictionary = data.walls[wall_id]
	if not _valid_wall(data, w):
		return _merge_fail("invalid wall")
	if w["back"] == -1:
		return _merge_fail("boundary wall")
	var s1: int = w["front"]
	var s2: int = w["back"]
	if s1 == s2 or s1 < 0 or s1 >= data.sectors.size() or s2 < 0 or s2 >= data.sectors.size():
		return _merge_fail("invalid sector sides")
	if not (data.sectors[s1]["inner"] as Array).is_empty():
		return _merge_fail("sector %d has inner loops" % s1)
	if not (data.sectors[s2]["inner"] as Array).is_empty():
		return _merge_fail("sector %d has inner loops" % s2)
	var shared := 0
	for w2 in data.walls:
		if (w2["front"] == s1 and w2["back"] == s2) or (w2["front"] == s2 and w2["back"] == s1):
			shared += 1
	if shared != 1:
		return _merge_fail("sectors share %d portal walls" % shared)
	var ring1 := _loop_point_ids(data, data.sectors[s1]["walls"])
	var ring2 := _loop_point_ids(data, data.sectors[s2]["walls"])
	if ring1.size() < 3 or ring2.size() < 3:
		return _merge_fail("unclosed loop")
	var merged_ring := _stitch_rings(ring1, ring2, w["a"], w["b"])
	if merged_ring.size() < 3:
		return _merge_fail("could not stitch loops")
	var merged_walls: Array[int] = []
	var seen := {}
	for i in range(merged_ring.size()):
		var a: int = merged_ring[i]
		var b: int = merged_ring[(i + 1) % merged_ring.size()]
		var wid := find_wall_between(data, a, b)
		if wid == -1 or wid == wall_id or seen.has(wid):
			return _merge_fail("non-closed stitched loop")
		seen[wid] = true
		merged_walls.append(wid)
	var poly := PackedVector2Array()
	for pid in merged_ring:
		poly.append(get_point(data, pid))
	if absf(polygon_area(poly)) < EPS:
		return _merge_fail("degenerate merged loop")
	for i in range(poly.size()):
		for j in range(i + 1, poly.size()):
			if j == i + 1 or (i == 0 and j == poly.size() - 1):
				continue  # adjacent edges share a vertex by construction
			if _segments_cross_strict(
				poly[i], poly[(i + 1) % poly.size()],
				poly[j], poly[(j + 1) % poly.size()]):
				return _merge_fail("self-intersecting merged loop")
	var area1 := absf(polygon_area(loop_to_polygon(data, data.sectors[s1]["walls"])))
	var area2 := absf(polygon_area(loop_to_polygon(data, data.sectors[s2]["walls"])))
	var survivor := s1
	var removed := s2
	if area2 > area1:
		survivor = s2
		removed = s1
	return {
		"ok": true,
		"reason": "",
		"merged_walls": merged_walls,
		"survivor": survivor,
		"removed": removed,
	}


## merge_sectors_at_portal(data, wall_id) -> Dictionary
##
## Applies the check_portal_merge plan: the survivor keeps its loop
## (replaced by the stitched ring), heights and textures; the portal wall
## record and the smaller sector are removed with full index remapping.
## Objects are untouched (world positions, no sector references). Returns
## the check result; on failure nothing has been mutated.
static func merge_sectors_at_portal(data: LevelData, wall_id: int) -> Dictionary:
	var plan := check_portal_merge(data, wall_id)
	if not plan["ok"]:
		return plan
	var survivor: int = plan["survivor"]
	var removed: int = plan["removed"]
	var sector: Dictionary = data.sectors[survivor]
	sector["walls"] = (plan["merged_walls"] as Array).duplicate()
	# The removed sector's walls now bound the survivor.
	for wid in plan["merged_walls"]:
		var mw: Dictionary = data.walls[wid]
		if mw["front"] == removed:
			mw["front"] = survivor
		if mw["back"] == removed:
			mw["back"] = survivor
	data.sectors.remove_at(removed)
	for mw in data.walls:
		if mw["front"] > removed:
			mw["front"] -= 1
		if mw["back"] > removed:
			mw["back"] -= 1
	_remove_walls(data, [wall_id])
	_remove_orphan_points(data)
	return plan


## _ray_face_hit(...) -> Vector2 (t, 0) or (-1, 0)
##
## Ray vs a sector face: its slope plane when valid, else the flat height.
static func _ray_face_hit(data: LevelData, sector_id: int, origin: Vector3, dir: Vector3, is_floor: bool) -> Vector2:
	var sector: Dictionary = data.sectors[sector_id]
	var slope_key := &"floor_slope" if is_floor else &"ceiling_slope"
	var height_key := &"floor_height" if is_floor else &"ceiling_height"
	var default_h := 0.0 if is_floor else 256.0
	var corners := _slope_corners(data, sector, slope_key)
	var plane: Plane
	if corners.size() == 3 and _corners_form_plane(corners):
		plane = Plane(corners[0], corners[1], corners[2])
	else:
		var h := float(sector.get(height_key, default_h))
		plane = Plane(Vector3.UP, h)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector2(-1.0, 0.0)
	var t := origin.distance_to(hit)
	if t < EPS:
		return Vector2(-1.0, 0.0)
	return Vector2(t, 0.0)


## _wall_vertical_span(data, w) -> Vector2
##
## Lowest floor to highest ceiling across both sides of a wall.
static func _wall_vertical_span(data: LevelData, w: Dictionary) -> Vector2:
	var lo := INF
	var hi := -INF
	for si in [w["front"], w["back"]]:
		if si < 0 or si >= data.sectors.size():
			continue
		var s: Dictionary = data.sectors[si]
		lo = minf(lo, float(s.get("floor_height", 0.0)))
		hi = maxf(hi, float(s.get("ceiling_height", 256.0)))
	if lo > hi:
		return Vector2(0.0, 256.0)
	return Vector2(lo, hi)


static func point_strictly_inside(p: Vector2, poly: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, poly):
		return false
	for i in range(poly.size()):
		var closest := Geometry2D.get_closest_point_to_segment(
			p, poly[i], poly[(i + 1) % poly.size()])
		if p.distance_to(closest) < EPS:
			return false
	return true


static func _polygon_contains(outer: PackedVector2Array, inner: PackedVector2Array) -> bool:
	for p in inner:
		if not point_strictly_inside(p, outer):
			return false
	return true


static func _valid_wall(data: LevelData, w: Dictionary) -> bool:
	if w["a"] < 0 or w["a"] >= data.points.size():
		return false
	if w["b"] < 0 or w["b"] >= data.points.size():
		return false
	return true


static func _collinear(p0: Vector2, p1: Vector2, q0: Vector2, q1: Vector2) -> bool:
	var d := p1 - p0
	var length := d.length()
	if length < EPS:
		return false
	if absf(d.cross(q0 - p0)) / length >= EPS:
		return false
	return absf(d.cross(q1 - p0)) / length < EPS


static func _point_strictly_on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var length := d.length()
	if length < EPS:
		return false
	if absf(d.cross(p - a)) / length > EPS:
		return false
	var t := _param_on_segment(p, a, b)
	return t > EPS_T and t < 1.0 - EPS_T


static func _param_on_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var len_sq := d.length_squared()
	if len_sq < EPS * EPS:
		return 0.0
	return (p - a).dot(d) / len_sq


static func _split_in_loop(loop: Array, old_id: int, new_id: int) -> Array:
	var out: Array = []
	for wid in loop:
		out.append(wid)
		if wid == old_id:
			out.append(new_id)
	return out


static func _remove_walls(data: LevelData, ids: Array) -> void:
	if ids.is_empty():
		return
	ids.sort()
	var index_map := {}
	var kept: Array = []
	for i in range(data.walls.size()):
		if ids.has(i):
			continue
		index_map[i] = kept.size()
		kept.append(data.walls[i])
	data.walls = kept
	for sector in data.sectors:
		sector["walls"] = _remap_loop(sector["walls"], index_map)
		var inner: Array = sector["inner"]
		for li in range(inner.size()):
			inner[li] = _remap_loop(inner[li], index_map)


static func _remap_loop(loop: Array, index_map: Dictionary) -> Array:
	var out: Array = []
	for wid in loop:
		if index_map.has(wid):
			out.append(index_map[wid])
	return out


static func _remove_orphan_points(data: LevelData) -> void:
	var used := {}
	for w in data.walls:
		used[w["a"]] = true
		used[w["b"]] = true
	var doomed: Array[int] = []
	for i in range(data.points.size()):
		if not used.has(i):
			doomed.append(i)
	if doomed.is_empty():
		return
	doomed.sort()
	var index_map := {}
	var kept: Array = []
	for i in range(data.points.size()):
		if doomed.has(i):
			continue
		index_map[i] = kept.size()
		kept.append(data.points[i])
	data.points = kept
	for w in data.walls:
		w["a"] = index_map.get(w["a"], w["a"])
		w["b"] = index_map.get(w["b"], w["b"])


## _loop_point_ids(data, wall_ids) -> Array[int]
##
## loop_to_polygon's id-level twin: chains a wall loop into ordered point
## ids (no closing duplicate). Empty on broken or unclosed loops.
static func _loop_point_ids(data: LevelData, wall_ids: Array) -> Array[int]:
	var ids: Array[int] = []
	if wall_ids.is_empty():
		return ids
	var first: Dictionary = data.walls[wall_ids[0]]
	if not _valid_wall(data, first):
		return ids
	ids.append(first["a"])
	ids.append(first["b"])
	var current_id: int = first["b"]
	var remaining: Array = wall_ids.slice(1)
	var guard := 0
	while not remaining.is_empty() and guard < 10000:
		guard += 1
		var found := -1
		var found_next := -1
		for i in range(remaining.size()):
			var w: Dictionary = data.walls[remaining[i]]
			if not _valid_wall(data, w):
				continue
			if w["a"] == current_id:
				found = i
				found_next = w["b"]
				break
			if w["b"] == current_id:
				found = i
				found_next = w["a"]
				break
		if found == -1:
			return []
		ids.append(found_next)
		current_id = found_next
		remaining.remove_at(found)
	if current_id != first["a"]:
		return []
	ids.remove_at(ids.size() - 1)
	return ids


## _edge_direction(ring, a, b) -> int
##
## +1 when the ring traverses a->b as a consecutive pair (incl. wrap),
## -1 for b->a, 0 when the two points are not adjacent in the ring.
static func _edge_direction(ring: Array[int], a: int, b: int) -> int:
	for i in range(ring.size()):
		if ring[i] == a and ring[(i + 1) % ring.size()] == b:
			return 1
		if ring[i] == b and ring[(i + 1) % ring.size()] == a:
			return -1
	return 0


static func _rotate_ring(ring: Array[int], start_index: int) -> Array[int]:
	var out: Array[int] = []
	for k in range(ring.size()):
		out.append(ring[(start_index + k) % ring.size()])
	return out


## _stitch_rings(ring1, ring2, a, b) -> Array[int]
##
## Joins two closed point rings that share the edge a<->b into one ring
## covering both: the long way around one ring from b to a, then the long
## way around the other from a back to b. Requires the two rings to
## traverse the shared edge in opposite directions (front/back semantics);
## anything else returns empty.
static func _stitch_rings(ring1: Array[int], ring2: Array[int], a: int, b: int) -> Array[int]:
	var merged: Array[int] = []
	var dir1 := _edge_direction(ring1, a, b)
	var dir2 := _edge_direction(ring2, a, b)
	if dir1 == 0 or dir2 == 0 or dir1 == dir2:
		return merged
	var long_ba: Array[int] = []
	var long_ab: Array[int] = []
	# A ring traversing a->b walks the portal edge that way; its long path
	# (everything but the portal) runs b->a, starting right after a.
	if dir1 == 1:
		long_ba = _rotate_ring(ring1, (ring1.find(a) + 1) % ring1.size())
	else:
		long_ab = _rotate_ring(ring1, (ring1.find(b) + 1) % ring1.size())
	if dir2 == 1:
		long_ba = _rotate_ring(ring2, (ring2.find(a) + 1) % ring2.size())
	else:
		long_ab = _rotate_ring(ring2, (ring2.find(b) + 1) % ring2.size())
	merged = long_ba.duplicate()
	# long_ab = [a, ..., b]: drop a (already the last of long_ba) and b
	# (the wrap-around returns to long_ba's first element).
	for i in range(1, long_ab.size() - 1):
		merged.append(long_ab[i])
	return merged


## _segments_cross_strict(a1, b1, a2, b2) -> bool
##
## Proper interior crossing only (shared or touching endpoints are not
## crossings). The same test validate() uses for unsplit wall crossings.
static func _segments_cross_strict(a1: Vector2, b1: Vector2, a2: Vector2, b2: Vector2) -> bool:
	var d := b1 - a1
	var e := b2 - a2
	var denom := d.cross(e)
	if absf(denom) < EPS:
		return false
	var f := a2 - a1
	var t := f.cross(e) / denom
	var u := f.cross(d) / denom
	return t > EPS_T and t < 1.0 - EPS_T and u > EPS_T and u < 1.0 - EPS_T


static func _merge_fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "merged_walls": [], "survivor": -1, "removed": -1}


static func _flag_wall(data: LevelData, id: int, reason: String) -> void:
	if data.flagged_walls.has(id):
		data.flagged_walls[id] += "; " + reason
	else:
		data.flagged_walls[id] = reason


static func _flag_sector(data: LevelData, id: int, reason: String) -> void:
	if data.flagged_sectors.has(id):
		data.flagged_sectors[id] += "; " + reason
	else:
		data.flagged_sectors[id] = reason


static func _flag_wall_sectors(data: LevelData, wall_id: int, reason: String) -> void:
	var w: Dictionary = data.walls[wall_id]
	for s in [w["front"], w["back"]]:
		if s >= 0 and s < data.sectors.size():
			_flag_sector(data, s, reason)
