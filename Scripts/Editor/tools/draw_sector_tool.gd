class_name DrawSectorTool
extends RefCounted

## DrawSectorTool
##
## Build-style sector loop drawing. Tools are classes, not nodes: this
## holds only transient state (in-progress loop, cursor, hover) and dies
## with deactivation. It mutates LevelData exclusively through ToolSystem
## methods and never touches a view.
##
## Auto-split on wall crossing, portal merge on shared edges, and inner
## loop detection all happen inside GeometryOps at loop-close time — the
## tool never implements them itself.

signal finished
signal cancelled

const CLOSE_TOLERANCE := 0.5  # world units; vertices are grid-snapped

var _system: ToolSystem
var _verts: Array[Vector2] = []
var _cursor := Vector2.ZERO
var _hover_sector := -1


func _init(system: ToolSystem) -> void:
	_system = system


func activate() -> void:
	pass


func deactivate() -> void:
	_verts.clear()
	_hover_sector = -1


## get_preview() -> Dictionary
##
## Read-only transient state for the canvas view, passed down by
## EditorController each frame.
func get_preview() -> Dictionary:
	return {
		"verts": _verts,
		"cursor": _cursor,
		"hover_sector": _hover_sector,
	}


## handle_input(event, world_pos, snapped_pos) -> bool
##
## Returns true when the event was consumed.
func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	if event is InputEventMouseMotion:
		_cursor = snapped_pos
		_hover_sector = _system.pick_sector(world_pos)
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_click(snapped_pos)
			return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		match key.keycode:
			KEY_ESCAPE:
				if not _verts.is_empty():
					_verts.clear()
					cancelled.emit()
					return true
			KEY_ENTER, KEY_KP_ENTER:
				return _try_close()
			KEY_DELETE:
				if _hover_sector != -1:
					_system.request_delete(_hover_sector)
					return true
	return false


func _on_click(pos: Vector2) -> void:
	if _verts.size() >= 3 and pos.distance_to(_verts[0]) <= CLOSE_TOLERANCE:
		_try_close()
		return
	_verts.append(pos)


func _try_close() -> bool:
	if _verts.size() < 3:
		return false
	_system.commit_loop(_verts.duplicate())
	_verts.clear()
	finished.emit()
	return true
