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

var _level_data: LevelData
var _draw_tool: DrawSectorTool
var _active_tool: DrawSectorTool


## _ready()
##
## Side-effects: creates the M1 tool set and activates the draw tool.
func _ready() -> void:
	_draw_tool = DrawSectorTool.new(self)
	_active_tool = _draw_tool


func set_level_data(data: LevelData) -> void:
	_level_data = data
	if _active_tool != null:
		_active_tool.deactivate()


func get_active_tool() -> Object:
	return _active_tool


func get_preview() -> Dictionary:
	if _active_tool == null:
		return {}
	return _active_tool.get_preview()


## handle_input(event, world_pos, snapped_pos) -> bool
##
## Routes input to the active tool. Returns true when consumed.
func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	if _active_tool == null:
		return false
	return _active_tool.handle_input(event, world_pos, snapped_pos)


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
