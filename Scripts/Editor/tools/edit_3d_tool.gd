class_name Edit3DTool
extends RefCounted

## Edit3DTool (M3)
##
## Crosshair-driven 3D editing against the walk-mode camera. The view
## computes the AimInfo (GeometryOps.aim_from_ray) and ToolSystem routes
## events here. Wheel = raise/lower the aimed face (Shift = opposite face)
## or shift wall offsets when a wall is aimed; LMB drag = corner-drag
## slope editing (three corner heights define the plane); X clears the
## aimed face's slope; T requests the texture picker.
##
## All LevelData writes go through ToolSystem commit methods; the tool
## holds only transient drag state.

signal finished
signal cancelled

const HEIGHT_STEP := 8.0  # 48 mm per wheel tick
const OFFSET_STEP := 8.0  # texels per wheel tick
const CORNER_SNAP := 32.0  # world units; grab range for corner drags
const DRAG_SCALE := 2.0  # world units of height per pixel of mouse-Y

var _system: ToolSystem
var _drag := {}  # empty = not dragging; else {sector_id, slope_key, point_id, height}
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
		if (event as InputEventKey).keycode == KEY_DELETE and kind == &"object":
			_system.commit_object_delete(int(aim["object_id"]))
			return true
	if event.is_action_pressed("grab_corner"):
		if kind == &"floor" or kind == &"ceiling":
			_begin_drag(aim)
		elif kind == &"object":
			_system.begin_object_drag()
			_obj_drag = {"object_id": int(aim["object_id"])}
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
## live (preview commits without undo pushes; the snapshot was taken at
## drag start).
func handle_motion(relative: Vector2, aim: Dictionary) -> bool:
	if not _obj_drag.is_empty():
		var ground: Variant = aim.get("ground_point", null)
		if ground is Vector3:
			_system.update_object_drag(int(_obj_drag["object_id"]), Vector2(ground.x, ground.z))
		return true
	if _drag.is_empty():
		return false
	_drag["height"] = float(_drag["height"]) - relative.y * DRAG_SCALE
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
	return "sector %d %s  h=%.1f  slope %d/3  tex=%s" % [
		sector_id, kind, float(sector.get(height_key, 0.0)), slope.size(), tex,
	]


func _slope_key(kind: StringName) -> StringName:
	return &"floor_slope" if kind == &"floor" else &"ceiling_slope"


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
## Grabs the nearest outer-loop corner of the aimed sector. The height
## starts at the face's current height at that corner so the drag is
## continuous from what the player sees.
func _begin_drag(aim: Dictionary) -> void:
	var data: LevelData = _system.get_level_data()
	if data == null:
		return
	var sector_id := int(aim["sector_id"])
	var p: Vector3 = aim["point"]
	var pid := GeometryOps.nearest_corner(data, sector_id, Vector2(p.x, p.z), CORNER_SNAP)
	if pid == -1:
		return
	var slope_key := _slope_key(aim["kind"])
	var height := 0.0
	if aim["kind"] == &"floor":
		height = GeometryOps.floor_height_at(data, sector_id, Vector2(p.x, p.z))
	else:
		height = GeometryOps.ceiling_height_at(data, sector_id, Vector2(p.x, p.z))
	_system.begin_corner_drag()
	_drag = {"sector_id": sector_id, "slope_key": slope_key, "point_id": pid, "height": height}
	_system.update_corner_drag(sector_id, slope_key, pid, height)


func _end_drag() -> void:
	if _drag.is_empty():
		return
	_drag = {}
	_system.end_corner_drag()
