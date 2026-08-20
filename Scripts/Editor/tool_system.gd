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
var _active_tool: RefCounted
var _pending_texture_aim := {}
var _last_aim := {}


## _ready()
##
## Side-effects: creates the tool set (2D draw + M3 3D edit) and activates
## the draw tool.
func _ready() -> void:
	_draw_tool = DrawSectorTool.new(self)
	_edit_3d_tool = Edit3DTool.new(self)
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


func get_preview() -> Dictionary:
	if _active_tool == null:
		return {}
	return _active_tool.get_preview()


## handle_input(event, world_pos, snapped_pos) -> bool
##
## 2D canvas route. Returns true when consumed.
func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	if _active_tool != _draw_tool:
		return false
	return _draw_tool.handle_input(event, world_pos, snapped_pos)


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
	if kind == &"wall":
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
	mutation_committed.emit()


func update_corner_drag(sector_id: int, slope_key: StringName, point_id: int, height: float) -> void:
	if _level_data == null:
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		return
	GeometryOps.set_slope_corner(_level_data.sectors[sector_id], slope_key, point_id, height)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


func end_corner_drag() -> void:
	pass
