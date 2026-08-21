class_name ToolSystem
extends Node

## ToolSystem
##
## Owns the active tool and routes input to it. Tools are classes, not
## nodes; they mutate LevelData through the commit_* methods here and
## never touch views. mutation_committed fires BEFORE the mutation so
## EditorController can push an undo snapshot; level_data_changed fires
## after re-validation so views redraw.

signal level_data_changed(change_type: LevelData.ChangeType)
signal mutation_committed
signal texture_pick_requested(aim: Dictionary)

var _level_data: LevelData
var _draw_tool: DrawSectorTool
var _edit_3d_tool: Edit3DTool
var _object_tool: ObjectTool
var _active_tool: RefCounted
var _pending_texture_aim := {}
var _last_aim := {}
## M4 brush: what the ObjectTool places on click.
var _brush := {"type": "billboard", "art": ""}


## _ready()
##
## Side-effects: creates the tool set (2D draw + 2D objects + 3D edit) and
## activates the draw tool.
func _ready() -> void:
	_draw_tool = DrawSectorTool.new(self)
	_edit_3d_tool = Edit3DTool.new(self)
	_object_tool = ObjectTool.new(self)
	_active_tool = _draw_tool


func set_level_data(data: LevelData) -> void:
	_level_data = data
	if _active_tool != null:
		_active_tool.deactivate()


func get_level_data() -> LevelData:
	return _level_data


func get_active_tool() -> Object:
	return _active_tool


## set_mode_3d(is_3d)
##
## Called down by EditorController on mode switch. The 2D draw tool and
## the 3D edit tool are swapped; tool state dies on deactivation.
func set_mode_3d(is_3d: bool) -> void:
	if _active_tool != null:
		_active_tool.deactivate()
	if is_3d:
		_active_tool = _edit_3d_tool
	else:
		_active_tool = _draw_tool
	_active_tool.activate()


## set_object_mode(on)
##
## 2D tool switching (O key): draw sectors <-> place objects. 3D mode
## always uses the Edit3DTool; set_mode_3d wins over this.
func set_object_mode(on: bool) -> void:
	if _active_tool == _edit_3d_tool:
		return
	_active_tool.deactivate()
	if on:
		_active_tool = _object_tool
	else:
		_active_tool = _draw_tool
	_active_tool.activate()


func get_brush() -> Dictionary:
	return _brush


func set_brush_type(type: String) -> void:
	_brush["type"] = type


## set_brush_art(tex_name)
##
## Object art is stored as a library-relative BASE name (no extension) so
## frame/view expansion rules apply.
func set_brush_art(tex_name: String) -> void:
	_brush["art"] = tex_name.trim_suffix(".png")


func get_preview() -> Dictionary:
	if _active_tool == null:
		return {}
	return _active_tool.get_preview()


## handle_input(event, world_pos, snapped_pos) -> bool
##
## 2D canvas route. Returns true when consumed.
func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	if _active_tool != _draw_tool and _active_tool != _object_tool:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_O:
			set_object_mode(_active_tool != _object_tool)
			return true
	return _active_tool.handle_input(event, world_pos, snapped_pos)


## handle_3d_input(event, aim) -> bool
## handle_3d_motion(relative, aim) -> bool
##
## 3D route: the Viewport3DView computes the crosshair AimInfo and signals
## upward; EditorController calls these down in 3D mode.
func handle_3d_input(event: InputEvent, aim: Dictionary) -> bool:
	if _active_tool != _edit_3d_tool:
		return false
	if not aim.is_empty():
		_last_aim = aim
	return _edit_3d_tool.handle_input(event, aim)


func handle_3d_motion(relative: Vector2, aim: Dictionary) -> bool:
	if _active_tool != _edit_3d_tool:
		return false
	if not aim.is_empty():
		_last_aim = aim
	return _edit_3d_tool.handle_motion(relative, aim)


func is_3d_dragging() -> bool:
	if _active_tool != _edit_3d_tool:
		return false
	return _edit_3d_tool.is_dragging()


func describe_aim(aim: Dictionary) -> String:
	if _active_tool != _edit_3d_tool:
		return ""
	return _edit_3d_tool.describe_aim(aim)


## pick_sector(world_pos) -> int
##
## Picking helper exposed to tools (smallest containing sector).
func pick_sector(world_pos: Vector2) -> int:
	if _level_data == null:
		return -1
	return GeometryOps.sector_at(_level_data, world_pos)


## commit_loop(verts)
##
## Closes a drawn loop into a sector. One mutation = one undo step.
func commit_loop(verts: Array) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	GeometryOps.close_loop_from_positions(_level_data, verts)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## request_delete(sector_id)
##
## Single-sector delete: an ordinary undoable edit. Batch deletes (Clear
## Level) are confirmed destructive ops handled by EditorController.
func request_delete(sector_id: int) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	GeometryOps.delete_sector(_level_data, sector_id)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_height(sector_id, kind, delta)
##
## M3: raise/lower a sector's floor or ceiling by delta (one wheel tick =
## one undo step). kind is &"floor" or &"ceiling".
func commit_height(sector_id: int, kind: StringName, delta: float) -> void:
	if _level_data == null:
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		return
	mutation_committed.emit()
	var sector: Dictionary = _level_data.sectors[sector_id]
	var key := &"floor_height" if kind == &"floor" else &"ceiling_height"
	sector[key] = float(sector.get(key, 0.0)) + delta
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_wall_offset(wall_id, du, dv)
##
## M3: nudge a wall's texture alignment (offset_u/offset_v, in texels).
func commit_wall_offset(wall_id: int, du: float, dv: float) -> void:
	if _level_data == null:
		return
	if wall_id < 0 or wall_id >= _level_data.walls.size():
		return
	mutation_committed.emit()
	var w: Dictionary = _level_data.walls[wall_id]
	w["offset_u"] = float(w.get("offset_u", 0.0)) + du
	w["offset_v"] = float(w.get("offset_v", 0.0)) + dv
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## request_texture_pick(aim)
##
## The Edit3DTool asks for the texture picker (T key). The aim is kept so
## commit_texture knows what to apply the picked name to.
func request_texture_pick(aim: Dictionary) -> void:
	_pending_texture_aim = aim.duplicate()
	texture_pick_requested.emit(aim)


## commit_texture(tex_name)
##
## Applies a library-relative texture name to the face/wall remembered by
## request_texture_pick. One mutation = one undo step.
func commit_texture(tex_name: String) -> void:
	if _level_data == null:
		return
	var aim := _pending_texture_aim
	if aim.is_empty():
		aim = _last_aim
	if aim.is_empty():
		return
	var kind: StringName = aim.get("kind", &"none")
	mutation_committed.emit()
	if kind == &"object":
		var object_id := int(aim.get("object_id", -1))
		if object_id >= 0 and object_id < _level_data.objects.size():
			var o: Dictionary = _level_data.objects[object_id]
			o["art"] = tex_name.trim_suffix(".png")
			if o.get("type") == "sprite_8way":
				o["params"]["views"] = ObjectOps.probe_views(o["art"])
	elif kind == &"wall":
		var wall_id := int(aim.get("wall_id", -1))
		if wall_id >= 0 and wall_id < _level_data.walls.size():
			_level_data.walls[wall_id]["texture"] = tex_name
	else:
		var sector_id := int(aim.get("sector_id", -1))
		if sector_id >= 0 and sector_id < _level_data.sectors.size():
			var key := &"floor_texture" if kind == &"floor" else &"ceiling_texture"
			_level_data.sectors[sector_id][key] = tex_name
	_pending_texture_aim = {}
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_reset_slope(sector_id, slope_key)
##
## M3: clears a face's slope corners (X key). Undoable, no confirm dialog.
func commit_reset_slope(sector_id: int, slope_key: StringName) -> void:
	if _level_data == null:
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		return
	mutation_committed.emit()
	_level_data.sectors[sector_id][slope_key] = []
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## Corner-drag slope editing: begin takes the undo snapshot once (the drag
## is ONE undo step), update mutates + revalidates for live preview, end
## closes the gesture.
func begin_corner_drag() -> void:
	GeometryOps.slope_log("system: begin_corner_drag (undo snapshot)")
	mutation_committed.emit()


func update_corner_drag(sector_id: int, slope_key: StringName, point_id: int, height: float) -> void:
	if _level_data == null:
		GeometryOps.slope_log("system: update_corner_drag dropped — no LevelData")
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		GeometryOps.slope_log("system: update_corner_drag dropped — bad sector %d" % sector_id)
		return
	GeometryOps.set_slope_corner(_level_data.sectors[sector_id], slope_key, point_id, height)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


func end_corner_drag() -> void:
	GeometryOps.slope_log("system: end_corner_drag")


## --- M4 object commits -------------------------------------------------
## Same discipline as geometry: mutation_committed (undo snapshot) ->
## mutate -> validate -> level_data_changed. Drags take the snapshot once
## at begin and preview through update.

## commit_object_place(pos)
##
## Places the current brush at pos. 8-way sprites get their rotation views
## probed from the library at placement time.
func commit_object_place(pos: Vector2) -> void:
	if _level_data == null:
		return
	var obj := ObjectOps.defaults(str(_brush["type"]))
	if obj.is_empty():
		return
	obj["pos"] = [pos.x, pos.y]
	obj["art"] = str(_brush["art"])
	if obj["type"] == "sprite_8way":
		obj["params"]["views"] = ObjectOps.probe_views(obj["art"])
	mutation_committed.emit()
	_level_data.objects.append(obj)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func commit_object_move(idx: int, pos: Vector2, z: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	_level_data.objects[idx]["pos"] = [pos.x, pos.y]
	_level_data.objects[idx]["z"] = z
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func commit_object_rotate(idx: int, delta_deg: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	var o: Dictionary = _level_data.objects[idx]
	o["angle"] = fmod(float(o.get("angle", 0.0)) + delta_deg, 360.0)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func commit_object_delete(idx: int) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	_level_data.objects.remove_at(idx)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


## commit_object_z(idx, delta)
##
## Ctrl+wheel z nudge in 3D. One tick = one undo step.
func commit_object_z(idx: int, delta: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	var o: Dictionary = _level_data.objects[idx]
	o["z"] = float(o.get("z", 0.0)) + delta
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func begin_object_drag() -> void:
	mutation_committed.emit()


func update_object_drag(idx: int, pos: Vector2) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	_level_data.objects[idx]["pos"] = [pos.x, pos.y]
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func update_object_drag_z(idx: int, z: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	_level_data.objects[idx]["z"] = z
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func end_object_drag() -> void:
	pass


## commit_environment(env)
##
## M6: replaces the level's environment section (Environment panel
## Apply). One mutation = one undo step. The panel passes raw field
## values; malformed entries are tolerated and flagged by
## EnvironmentOps at consumption time.
func commit_environment(env: Dictionary) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	_level_data.environment = env.duplicate(true)
	level_data_changed.emit(LevelData.ChangeType.ENVIRONMENT)


## commit_gameplay(gameplay)
##
## M7: replaces the level's gameplay section (Gameplay panel Apply). One
## mutation = one undo step. The panel passes raw field values; malformed
## entries are tolerated and flagged by GameplayOps at consumption time.
func commit_gameplay(gameplay: Dictionary) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	_level_data.gameplay = gameplay.duplicate(true)
	level_data_changed.emit(LevelData.ChangeType.GAMEPLAY)


## debug_place_test_set()
##
## Debug-panel command: one object of each type near the origin, using
## real ArtLibrary art (BUG_ENEM 8-view set, ANIM_LIB fluid).
func debug_place_test_set() -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	var specs := [
		{"type": "billboard", "pos": [0.0, -192.0], "art": "SOBJ_LIB/BARSTOOL"},
		{"type": "wall_object", "pos": [128.0, -192.0], "art": "ANIM_LIB/BARREL"},
		{"type": "sprite_8way", "pos": [256.0, -192.0], "art": "BUG_ENEM/BUG1BS"},
		{"type": "fluid", "pos": [384.0, -192.0], "art": "ANIM_LIB/BURN"},
		{"type": "platform", "pos": [512.0, -192.0], "art": "BASICLIB/BOX1"},
	]
	for spec in specs:
		var obj := ObjectOps.defaults(spec["type"])
		obj["pos"] = spec["pos"]
		obj["art"] = spec["art"]
		if obj["type"] == "sprite_8way":
			obj["params"]["views"] = ObjectOps.probe_views(obj["art"])
		_level_data.objects.append(obj)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)
