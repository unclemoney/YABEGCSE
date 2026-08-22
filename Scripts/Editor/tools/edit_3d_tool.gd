class_name Edit3DTool
extends RefCounted

## Edit3DTool (M3)
##
## Crosshair-driven 3D editing against the walk-mode camera. The view
## computes the AimInfo (GeometryOps.aim_from_ray) and ToolSystem routes
## events here. Wheel = raise/lower the aimed face (Shift = opposite face)
## or shift wall offsets when a wall is aimed; LMB drag = corner-drag
## slope editing (grab the sector corner nearest the crosshair hit and
## drag vertically; the first motion seeds a valid 3-corner plane from the
## flat face, so one drag already tilts it); X clears the aimed face's
## slope; T requests the texture picker.
##
## All LevelData writes go through ToolSystem commit methods; the tool
## holds only transient drag state. A corner drag writes nothing until the
## first drag motion, so a bare LMB click never pollutes the slope data.

signal finished
signal cancelled

const HEIGHT_STEP := 8.0  # 48 mm per wheel tick
const OFFSET_STEP := 8.0  # texels per wheel tick
const DRAG_SCALE := 2.0  # world units of height per pixel of mouse-Y

var _system: ToolSystem
var _drag := {}  # empty = not dragging; else {sector_id, slope_key, point_id, height, committed}
var _obj_drag := {}  # empty = not dragging; else {object_id}


func _init(system: ToolSystem) -> void:
	_system = system


func activate() -> void:
	pass


func deactivate() -> void:
	_drag = {}
	_obj_drag = {}


func get_preview() -> Dictionary:
	return {}


## is_dragging() -> bool
##
## While a corner or object drag is active the view suppresses mouse-look.
func is_dragging() -> bool:
	return not _drag.is_empty() or not _obj_drag.is_empty()


## handle_input(event, aim) -> bool
##
## Aim is the AimInfo dict from GeometryOps.aim_from_ray for the current
## crosshair ray (object hits merged in by the view). Returns true when
## the event was consumed.
func handle_input(event: InputEvent, aim: Dictionary) -> bool:
	var kind: StringName = aim.get("kind", &"none")
	if event.is_action_pressed("pick_texture"):
		if kind != &"none":
			_system.request_texture_pick(aim)
		return true
	if event.is_action_pressed("reset_slope"):
		if kind == &"floor" or kind == &"ceiling":
			_system.commit_reset_slope(int(aim["sector_id"]), _slope_key(kind))
		elif kind == &"object":
			_system.commit_object_delete(int(aim["object_id"]))
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_DELETE and kind == &"object":
			_system.commit_object_delete(int(aim["object_id"]))
			return true
		# Platform Edit (3D): V toggles visibility, Delete removes.
		if kind == &"platform":
			var platform_id := int(aim.get("platform_id", -1))
			if key.keycode == KEY_V:
				var visible := _system.commit_platform_toggle_visible(platform_id)
				_system.request_status(
					"Platform %d %s." % [platform_id, "visible" if visible else "hidden"])
				return true
			if key.keycode == KEY_DELETE:
				_system.commit_platform_delete(platform_id)
				_system.request_status("Platform %d deleted." % platform_id)
				return true
		# Inner sector height shortcut: Shift+H raises the aimed sector's
		# ceiling to its surrounding sector's ceiling, Shift+L lowers its
		# floor to match (pillar UX).
		if key.shift_pressed and (key.keycode == KEY_H or key.keycode == KEY_L):
			_match_surrounding(aim, key.keycode == KEY_H)
			return true
	if event.is_action_pressed("grab_corner"):
		if kind == &"floor" or kind == &"ceiling":
			_begin_drag(aim)
		elif kind == &"object":
			_system.begin_object_drag()
			_obj_drag = {"object_id": int(aim["object_id"])}
		elif kind == &"platform":
			# Click selects the platform (shared Platform Edit selection).
			var platform_id := int(aim.get("platform_id", -1))
			_system.select_platform(platform_id)
			_system.request_status(
				"Platform %d selected. Delete removes, V toggles visibility, T textures." % platform_id)
		else:
			GeometryOps.slope_log("tool: grab_corner pressed but aim kind is '%s' (nothing grabbed)" % kind)
		return true
	if event.is_action_released("grab_corner"):
		_end_drag()
		if not _obj_drag.is_empty():
			_obj_drag = {}
			_system.end_object_drag()
		return true
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			_on_wheel(button == MOUSE_BUTTON_WHEEL_UP, event as InputEventMouseButton, aim)
			return true
	return false


## handle_motion(relative, aim) -> bool
##
## Mouse motion during a drag adjusts the corner height or object position
## live. The first motion of a corner drag takes the undo snapshot and
## performs the initial write (preview commits afterwards don't push undo).
func handle_motion(relative: Vector2, aim: Dictionary) -> bool:
	if not _obj_drag.is_empty():
		var ground: Variant = aim.get("ground_point", null)
		if ground is Vector3:
			_system.update_object_drag(int(_obj_drag["object_id"]), Vector2(ground.x, ground.z))
		return true
	if _drag.is_empty():
		return false
	if not bool(_drag.get("committed", false)):
		_drag["committed"] = true
		_system.begin_corner_drag()
		GeometryOps.slope_log("tool: first drag motion — committing sector %d %s point %d" % [
			int(_drag["sector_id"]), _drag["slope_key"], int(_drag["point_id"]),
		])
		_seed_slope_plane()
	_drag["height"] = float(_drag["height"]) - relative.y * DRAG_SCALE
	_drag["motions"] = int(_drag.get("motions", 0)) + 1
	if int(_drag["motions"]) % 20 == 1:
		GeometryOps.slope_log("tool: drag motion #%d rel=%s height=%.1f" % [
			int(_drag["motions"]), str(relative), float(_drag["height"]),
		])
	_system.update_corner_drag(
		int(_drag["sector_id"]), _drag["slope_key"], int(_drag["point_id"]), float(_drag["height"])
	)
	return true


## describe_aim(aim) -> String
##
## Status-line readout for the current crosshair target.
func describe_aim(aim: Dictionary) -> String:
	var kind: StringName = aim.get("kind", &"none")
	var data: LevelData = _system.get_level_data()
	if data == null or kind == &"none":
		return ""
	if kind == &"object":
		var object_id := int(aim.get("object_id", -1))
		if object_id < 0 or object_id >= data.objects.size():
			return ""
		var o: Dictionary = data.objects[object_id]
		return "object %d %s  art=%s  a=%d z=%d" % [
			object_id, o.get("type", "?"), o.get("art", ""),
			int(o.get("angle", 0.0)), int(o.get("z", 0.0)),
		]
	if kind == &"platform":
		var platform_id := int(aim.get("platform_id", -1))
		if platform_id < 0 or platform_id >= data.platforms.size():
			return ""
		var p: PlatformData = data.platforms[platform_id]
		var marker := ""
		if _system.get_selected_platform() == platform_id:
			marker = " [selected]"
		return "platform %d%s  h=%.1f..%.1f  tex=%s  %s [LMB: select | V: hide | Del | T: tex]" % [
			platform_id, marker, p.floor_height, p.ceiling_height, p.texture,
			"visible" if p.is_visible else "hidden",
		]
	var sector_id := int(aim.get("sector_id", -1))
	if kind == &"wall":
		var wall_id := int(aim.get("wall_id", -1))
		if wall_id < 0 or wall_id >= data.walls.size():
			return ""
		var w: Dictionary = data.walls[wall_id]
		return "wall %d  tex=%s  off(%d, %d)" % [
			wall_id, w.get("texture", ""), int(w.get("offset_u", 0.0)), int(w.get("offset_v", 0.0)),
		]
	if sector_id < 0 or sector_id >= data.sectors.size():
		return ""
	var sector: Dictionary = data.sectors[sector_id]
	var height_key := &"floor_height" if kind == &"floor" else &"ceiling_height"
	var slope: Array = sector.get(_slope_key(kind), [])
	var tex := str(sector.get(&"floor_texture" if kind == &"floor" else &"ceiling_texture", ""))
	return "sector %d %s  h=%.1f  slope %d/3  tex=%s  [LMB-drag: slope corner | X: clear]" % [
		sector_id, kind, float(sector.get(height_key, 0.0)), slope.size(), tex,
	]


func _slope_key(kind: StringName) -> StringName:
	return &"floor_slope" if kind == &"floor" else &"ceiling_slope"


## _match_surrounding(aim, ceiling)
##
## Shift+H / Shift+L. Any aimed face or wall of a sector selects it; the
## commit goes through ToolSystem (undoable, one step). A sector not fully
## contained in another is rejected with the status-bar message — the
## spec's "Not an inner sector" and "No surrounding sector" name the same
## condition, so the message carries both phrasings.
func _match_surrounding(aim: Dictionary, ceiling: bool) -> void:
	var kind: StringName = aim.get("kind", &"none")
	var sector_id := int(aim.get("sector_id", -1))
	if kind == &"none" or kind == &"object" or sector_id < 0:
		_system.request_status("No sector under crosshair")
		return
	var face := &"ceiling" if ceiling else &"floor"
	var result := _system.commit_match_surrounding(sector_id, face)
	if not bool(result["ok"]):
		_system.request_status("Not an inner sector: no surrounding sector")
		_system.report_debug(
			"inner-sector shortcut rejected: sector %d has no surrounding sector" % sector_id)
		return
	var data: LevelData = _system.get_level_data()
	var height := 0.0
	if data != null:
		var key := &"ceiling_height" if ceiling else &"floor_height"
		height = float(data.sectors[sector_id].get(key, 0.0))
	_system.request_status("Sector %d %s matched to surrounding sector %d (h=%.1f)" % [
		sector_id, face, int(result["surrounding"]), height,
	])


func _on_wheel(up: bool, event: InputEventMouseButton, aim: Dictionary) -> void:
	var kind: StringName = aim.get("kind", &"none")
	var step := HEIGHT_STEP if up else -HEIGHT_STEP
	if kind == &"object":
		# Wheel rotates the aimed object; Ctrl+wheel nudges its z.
		if event.ctrl_pressed:
			_system.commit_object_z(int(aim["object_id"]), step)
		else:
			_system.commit_object_rotate(int(aim["object_id"]), 15.0 if up else -15.0)
		return
	if kind == &"floor" or kind == &"ceiling":
		# Shift swaps to the opposite face of the same sector.
		var target := kind
		if event.shift_pressed:
			target = &"ceiling" if kind == &"floor" else &"floor"
		_system.commit_height(int(aim["sector_id"]), target, step)
	elif kind == &"wall":
		var offset_step := OFFSET_STEP if up else -OFFSET_STEP
		if event.shift_pressed:
			_system.commit_wall_offset(int(aim["wall_id"]), 0.0, offset_step)
		else:
			_system.commit_wall_offset(int(aim["wall_id"]), offset_step, 0.0)


## _begin_drag(aim)
##
## Grabs the outer-loop corner of the aimed sector nearest to the
## crosshair hit point. No tolerance cap: the old fixed 32-unit grab range
## was unreachable from a standing camera (the crosshair lands tens to
## hundreds of units from any corner), which made slopes uneditable.
## Nothing is written yet — the undo snapshot and the first
## set_slope_corner happen on the first drag motion (handle_motion), so a
## plain click on a floor/ceiling leaves the slope data untouched.
## The drag height starts at the face's current height at the grabbed
## corner, so the plane moves continuously from what the player sees.
func _begin_drag(aim: Dictionary) -> void:
	var data: LevelData = _system.get_level_data()
	if data == null:
		GeometryOps.slope_log("tool: _begin_drag aborted — no LevelData")
		return
	var sector_id := int(aim["sector_id"])
	var p: Vector3 = aim["point"]
	var pid := GeometryOps.nearest_corner(data, sector_id, Vector2(p.x, p.z), INF)
	if pid == -1:
		GeometryOps.slope_log("tool: _begin_drag aborted — no corner found in sector %d near %s" % [
			sector_id, str(Vector2(p.x, p.z)),
		])
		return
	var corner := GeometryOps.get_point(data, pid)
	var height := 0.0
	if aim["kind"] == &"floor":
		height = GeometryOps.floor_height_at(data, sector_id, corner)
	else:
		height = GeometryOps.ceiling_height_at(data, sector_id, corner)
	_drag = {
		"sector_id": sector_id,
		"slope_key": _slope_key(aim["kind"]),
		"point_id": pid,
		"height": height,
		"committed": false,
	}
	GeometryOps.slope_log("tool: grabbed sector %d %s corner point %d at %s, start height %.1f" % [
		sector_id, aim["kind"], pid, str(corner), height,
	])


func _end_drag() -> void:
	if _drag.is_empty():
		return
	var committed := bool(_drag.get("committed", false))
	var sector_id := int(_drag["sector_id"])
	var slope_key: StringName = _drag["slope_key"]
	_drag = {}
	if committed:
		_system.end_corner_drag()
	var data: LevelData = _system.get_level_data()
	var final: Variant = []
	if data != null and sector_id >= 0 and sector_id < data.sectors.size():
		final = data.sectors[sector_id].get(slope_key, [])
	GeometryOps.slope_log("tool: drag end (committed=%s) sector %d %s = %s" % [
		str(committed), sector_id, slope_key, str(final),
	])


## _seed_slope_plane()
##
## A slope plane needs exactly 3 corner heights; a bare drag writes only
## the grabbed corner, which validate() flags incomplete and the mesh
## builder degrades to flat — the drag looked dead (the "slopes don't
## work" bug). On the first drag motion, the plane is topped up to 3
## corners: existing entries keep their heights, the farthest
## non-collinear outer-loop corners are seeded at the face's flat height,
## and the drag's own grabbed-corner write completes the set. A complete
## plane that doesn't contain the grabbed corner swaps its nearest entry
## for the grab point rather than growing a flagged 4th entry.
func _seed_slope_plane() -> void:
	var data: LevelData = _system.get_level_data()
	if data == null:
		return
	var sector_id := int(_drag["sector_id"])
	var slope_key: StringName = _drag["slope_key"]
	var sector: Dictionary = data.sectors[sector_id]
	var slope: Array = sector.get(slope_key, [])
	var grabbed := int(_drag["point_id"])
	var members := {}
	for entry in slope:
		members[int(entry[0])] = true
	if slope.size() >= 3:
		if slope.size() == 3 and not members.has(grabbed):
			_remove_nearest_slope_entry(data, sector, slope_key, grabbed)
		return
	var need := 3 - slope.size() - (0 if members.has(grabbed) else 1)
	if need <= 0:
		return
	# The slope is incomplete here, so the face still evaluates flat.
	var height_key := &"floor_height" if slope_key == &"floor_slope" else &"ceiling_height"
	var base := float(sector.get(height_key, 0.0))
	# Outer-loop corner ids, farthest from the grabbed corner first.
	var corner_pos := GeometryOps.get_point(data, grabbed)
	var unique := {}
	for wid in sector["walls"]:
		var w: Dictionary = data.walls[wid]
		unique[int(w["a"])] = true
		unique[int(w["b"])] = true
	var cids := unique.keys()
	cids.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				GeometryOps.get_point(data, a).distance_squared_to(corner_pos)
				> GeometryOps.get_point(data, b).distance_squared_to(corner_pos)
			)
	)
	# Grabbed corner counts toward the plane even before its own write.
	var chosen: Array = [grabbed]
	for pid in cids:
		if need == 0:
			break
		if members.has(pid) or pid == grabbed:
			continue
		var prospective: Array = []
		for entry in slope:
			prospective.append(int(entry[0]))
		prospective.append_array(chosen)
		prospective.append(pid)
		if prospective.size() == 3 and _collinear(data, prospective):
			continue
		chosen.append(pid)
		need -= 1
		GeometryOps.slope_log("tool: seeding corner point %d at flat height %.1f" % [pid, base])
		_system.update_corner_drag(sector_id, slope_key, pid, base)


## _remove_nearest_slope_entry(data, sector, slope_key, grabbed)
##
## Drops the slope entry whose corner sits nearest the grabbed one, so
## the drag's write re-completes the plane at 3 entries.
func _remove_nearest_slope_entry(
	data: LevelData, sector: Dictionary, slope_key: StringName, grabbed: int
) -> void:
	var corner_pos := GeometryOps.get_point(data, grabbed)
	var best := -1
	var best_dist := INF
	for entry in sector.get(slope_key, []):
		var pid := int(entry[0])
		var dist := GeometryOps.get_point(data, pid).distance_squared_to(corner_pos)
		if dist < best_dist:
			best_dist = dist
			best = pid
	if best != -1:
		GeometryOps.slope_log("tool: swapping slope entry point %d for grabbed point %d" % [best, grabbed])
		GeometryOps.remove_slope_corner(sector, slope_key, best)


## _collinear(data, pids) -> bool
##
## True when three point ids sit on one map line (no usable slope plane).
func _collinear(data: LevelData, pids: Array) -> bool:
	var a := GeometryOps.get_point(data, int(pids[0]))
	var b := GeometryOps.get_point(data, int(pids[1]))
	var c := GeometryOps.get_point(data, int(pids[2]))
	return absf((b - a).cross(c - a)) < GeometryOps.EPS
