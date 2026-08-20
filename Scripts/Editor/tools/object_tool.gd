class_name ObjectTool
extends RefCounted

## ObjectTool (M4, 2D mode)
##
## Places/moves/rotates/deletes objects on the 2D canvas. LMB on empty
## space places the current brush (ToolSystem.get_brush); LMB on an object
## drag-moves it (one undo step per drag); R rotates the hovered object
## (Shift = fine step); Delete removes it. All writes go through the
## ToolSystem commit methods; the tool holds only hover/drag state.

signal finished
signal cancelled

const PICK_TOLERANCE := 16.0  # world units

var _system: ToolSystem
var _hover := -1
var _drag := -1
var _cursor := Vector2.ZERO


func _init(system: ToolSystem) -> void:
	_system = system


func activate() -> void:
	pass


func deactivate() -> void:
	_hover = -1
	_drag = -1


func get_preview() -> Dictionary:
	var preview := {"object_hover": _hover, "verts": []}
	if _drag == -1 and _hover == -1 and not str(_system.get_brush()["art"]).is_empty():
		preview["object_cursor"] = _cursor
	return preview


func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	if event is InputEventMouseMotion:
		_cursor = snapped_pos
		if _drag != -1:
			_system.update_object_drag(_drag, snapped_pos)
		else:
			_hover = ObjectOps.pick(_system.get_level_data(), world_pos, PICK_TOLERANCE)
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			if _hover != -1:
				_drag = _hover
				_system.begin_object_drag()
			elif not str(_system.get_brush()["art"]).is_empty():
				_system.commit_object_place(snapped_pos)
			return true
		if _drag != -1:
			_drag = -1
			_system.end_object_drag()
			return true
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_DELETE:
				if _hover != -1:
					_system.commit_object_delete(_hover)
					_hover = -1
				return true
			KEY_R:
				if _hover != -1:
					var step := 5.0 if (event as InputEventKey).shift_pressed else 15.0
					_system.commit_object_rotate(_hover, step)
				return true
	return false
