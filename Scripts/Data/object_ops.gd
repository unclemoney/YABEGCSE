class_name ObjectOps

## ObjectOps
##
## All object-layer logic (M4): defaults, picking, 8-way view resolution,
## art probing, validation. Static, pure functions over LevelData — no
## nodes, no input — so the whole layer is headless-testable. Objects clip
## geometry freely; there are no geometric validity rules for them, only
## schema-shape checks (tolerate + flag).
##
## Object schema (v0):
##   {"type": "billboard"|"wall_object"|"sprite_8way"|"fluid"|"platform",
##    "pos": [x, y], "z": float, "angle": float,
##    "art": "LIB/NAME"  (library-relative BASE name, no extension),
##    "params": {"scale": float, "fps": float (fluid),
##               "size": [w, d] (platform; M5 also wall_object/billboard),
##               "collide": bool (M5: object-wall blocks the walker),
##               "gcs": Dictionary (M5 import provenance),
##               "views": {"1".."8": base name} (sprite_8way)}}

const TYPES: Array[String] = ["billboard", "wall_object", "sprite_8way", "fluid", "platform"]
const DEFAULT_SIZE := 64.0  # world units square when no size/texture known
const MAX_FRAMES := 16


## defaults(type) -> Dictionary
##
## A fresh object of the given type (empty for unknown types).
static func defaults(type: String) -> Dictionary:
	if not TYPES.has(type):
		return {}
	var obj := {
		"type": type,
		"pos": [0.0, 0.0],
		"z": 0.0,
		"angle": 0.0,
		"art": "",
		"params": {"scale": 1.0},
	}
	if type == "fluid":
		obj["params"]["fps"] = 8.0
	elif type == "platform":
		obj["params"]["size"] = [64.0, 64.0]
	elif type == "sprite_8way":
		obj["params"]["views"] = {}
	return obj


## pick(data, pos, tolerance) -> int
##
## Nearest object index within tolerance (2D), or -1.
static func pick(data: LevelData, pos: Vector2, tolerance: float) -> int:
	var best := -1
	var best_dist := tolerance
	for i in range(data.objects.size()):
		var p := get_pos(data.objects[i])
		var dist := p.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


## ray_pick(objects, origin, dir) -> Dictionary
##
## Nearest object hit by a 3D ray, or {}. Objects are approximated as
## quads: billboards/fluids face the ray origin, wall_objects/8-way
## sprites face their angle, platforms lie flat at z. Half-extent comes
## from params.size / scale, defaulting to DEFAULT_SIZE.
static func ray_pick(objects: Array, origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for i in range(objects.size()):
		var hit := _ray_object_hit(objects[i], origin, dir)
		if hit.is_empty():
			continue
		if float(hit["distance"]) < best_t:
			best_t = hit["distance"]
			best = hit
			best["object_id"] = i
	return best


## view_for_angle(obj, obj_to_player_deg) -> Dictionary
##
## 8-way view resolution: {"name": base, "mirrored": bool}. Views are
## numbered 1..8 clockwise from front (1 = facing the player, 5 = back).
## Missing views fall back to the horizontal mirror partner, then to the
## nearest available view. Empty name = nothing to draw.
static func view_for_angle(obj: Dictionary, obj_to_player_deg: float) -> Dictionary:
	var views: Dictionary = obj.get("params", {}).get("views", {})
	if views.is_empty():
		return {"name": "", "mirrored": false}
	var rel := wrapf(obj_to_player_deg - float(obj.get("angle", 0.0)), 0.0, 360.0)
	var view := int(round(rel / 45.0)) % 8 + 1
	var name := _view_name(views, view)
	if not name.is_empty():
		return {"name": name, "mirrored": false}
	var partner := _mirror_view(view)
	name = _view_name(views, partner)
	if not name.is_empty():
		return {"name": name, "mirrored": true}
	# Nearest available view by circular distance.
	var best_name := ""
	var best_dist := 99
	for key in views:
		var v := int(key)
		var dist := mini(absi(v - view), 8 - absi(v - view))
		if dist < best_dist:
			best_dist = dist
			best_name = str(views[key])
	return {"name": best_name, "mirrored": false}


## probe_views(art) -> Dictionary
##
## BUG1BS-style probing: the first digit in the base name is the view
## slot; replacing it with 1..8 finds the rotation set. Returns the
## {"1": base, ...} map of views that exist in the library.
static func probe_views(art: String) -> Dictionary:
	var views := {}
	var digit := -1
	var file := art.get_file()
	for i in range(file.length()):
		if file[i] >= "0" and file[i] <= "9":
			digit = art.length() - file.length() + i
			break
	if digit == -1:
		return views
	for v in range(1, 9):
		var candidate := art.substr(0, digit) + str(v) + art.substr(digit + 1)
		if ArtCache.exists(candidate + ".png"):
			views[str(v)] = candidate
	return views


## validate(data)
##
## Recomputes flagged_objects. Schema-shape checks only — objects may clip
## geometry freely. Platforms are exempt from the art requirement (imported
## GCS platforms are artless trigger regions; they render as translucent
## placeholders). Unresolved art is not flagged here; ArtCache reports
## it to the debug panel when the renderer resolves textures.
static func validate(data: LevelData) -> void:
	data.flagged_objects.clear()
	for i in range(data.objects.size()):
		var o: Variant = data.objects[i]
		if not o is Dictionary:
			_flag(data, i, "not a dictionary")
			continue
		if not TYPES.has(str(o.get("type", ""))):
			_flag(data, i, "unknown type '%s'" % str(o.get("type", "")))
		if not o.get("pos") is Array or (o["pos"] as Array).size() < 2:
			_flag(data, i, "malformed pos")
		if str(o.get("art", "")).is_empty() and str(o.get("type", "")) != "platform":
			_flag(data, i, "no art reference")


## get_pos(obj) -> Vector2 — tolerant position read.
static func get_pos(obj: Dictionary) -> Vector2:
	var p: Variant = obj.get("pos", [0.0, 0.0])
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


## get_extent(obj) -> Vector2 — (width, height) world units.
static func get_extent(obj: Dictionary) -> Vector2:
	var params: Dictionary = obj.get("params", {})
	var scale := float(params.get("scale", 1.0))
	if params.get("size") is Array and (params["size"] as Array).size() >= 2:
		return Vector2(float(params["size"][0]), float(params["size"][1])) * scale
	return Vector2(DEFAULT_SIZE, DEFAULT_SIZE) * scale


static func _ray_object_hit(obj: Dictionary, origin: Vector3, dir: Vector3) -> Dictionary:
	if not obj is Dictionary:
		return {}
	var p2 := get_pos(obj)
	var z := float(obj.get("z", 0.0))
	var extent := get_extent(obj)
	var center := Vector3(p2.x, z + extent.y * 0.5, p2.y)
	var type := str(obj.get("type", ""))
	if type == "platform":
		var hit_flat: Variant = Plane(Vector3.UP, z).intersects_ray(origin, dir)
		if hit_flat == null:
			return {}
		var pf: Vector3 = hit_flat
		if absf(pf.x - p2.x) > extent.x * 0.5 or absf(pf.z - p2.y) > extent.y * 0.5:
			return {}
		return {"distance": origin.distance_to(pf), "point": pf}
	var normal := Vector3.FORWARD
	if type == "wall_object" or type == "sprite_8way":
		var facing := Vector2(0.0, 1.0).rotated(deg_to_rad(float(obj.get("angle", 0.0))))
		normal = Vector3(facing.x, 0.0, facing.y)
	else:
		# Billboard family: the quad faces the viewer.
		var to_origin := origin - center
		to_origin.y = 0.0
		if to_origin.length_squared() > 0.000001:
			normal = to_origin.normalized()
	var hit: Variant = Plane(normal, center).intersects_ray(origin, dir)
	if hit == null:
		return {}
	var p: Vector3 = hit
	if p.y < z - GeometryOps.EPS or p.y > z + extent.y + GeometryOps.EPS:
		return {}
	var lateral := (p - center).dot(Vector3(-normal.z, 0.0, normal.x))
	if absf(lateral) > extent.x * 0.5:
		return {}
	return {"distance": origin.distance_to(p), "point": p}


static func _view_name(views: Dictionary, view: int) -> String:
	if views.has(view):
		return str(views[view])
	return str(views.get(str(view), ""))


## _mirror_view(view) -> int
##
## Horizontal mirror partner in the 1..8 clockwise-from-front numbering:
## 2<->8, 3<->7, 4<->6; front (1) and back (5) mirror to themselves.
static func _mirror_view(view: int) -> int:
	var m := 10 - view
	if m == 9:
		return 1
	return m


static func _flag(data: LevelData, id: int, reason: String) -> void:
	if data.flagged_objects.has(id):
		data.flagged_objects[id] += "; " + reason
	else:
		data.flagged_objects[id] = reason
