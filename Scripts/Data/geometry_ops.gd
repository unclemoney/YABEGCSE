class_name GeometryOps

## GeometryOps
##
## All sector-geometry mutation and validation. Static, pure functions over
## LevelData — no nodes, no input — so the whole geometry layer is
## headless-testable. Units: 1 unit = 6 mm, everywhere, forever.

const EPS := 0.001  # geometric epsilon, world units
const EPS_T := 0.001  # segment parameter epsilon
const MIN_OVERLAP_AREA := 1.0  # square units; touching edges are not overlap


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
