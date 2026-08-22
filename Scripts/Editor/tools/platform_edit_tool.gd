class_name PlatformEditTool
extends RefCounted

## PlatformEditTool (2D "Platform Edit" mode)
##
## Edits drawn platform overlays (LevelData.platforms) after creation:
## LMB selects the smallest platform under the cursor (2D
## point-in-polygon via GeometryOps.platform_at; empty space deselects),
## Delete removes it, V toggles visibility (invisible platforms skip 3D
## mesh generation and draw dashed-only in 2D), T opens the texture
## picker for it. Single selection only. All mutations are undoable and
## go through ToolSystem commit methods; the tool holds only the hover.
## The selection itself lives in ToolSystem so the 3D Edit3DTool and the
## texture picker share it.

signal finished
signal cancelled

var _system: ToolSystem
var _hover := -1


func _init(system: ToolSystem) -> void:
	_system = system


func activate() -> void:
	pass


func deactivate() -> void:
	_hover = -1


## get_preview() -> Dictionary
##
## Read-only transient state for the canvas view: platform hover and the
## shared selection (border highlights in _draw_platforms).
func get_preview() -> Dictionary:
	return {
		"tool_mode": &"platform_edit",
		"verts": [],
		"platform_hover": _hover,
		"platform_selected": _system.get_selected_platform(),
	}


## handle_input(event, world_pos, snapped_pos) -> bool
##
## Returns true when the event was consumed.
func handle_input(event: InputEvent, world_pos: Vector2, _snapped_pos: Vector2) -> bool:
	var data := _system.get_level_data()
	if data == null:
		return false
	if event is InputEventMouseMotion:
		_hover = GeometryOps.platform_at(data, world_pos)
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_system.select_platform(_hover)
			if _hover == -1:
				_system.request_status("No platform under cursor; selection cleared.")
			else:
				_system.request_status(
					"Platform %d selected. Delete removes, V toggles visibility, T textures." % _hover)
			return true
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var selected := _system.get_selected_platform()
		match key.keycode:
			KEY_DELETE:
				if selected != -1:
					_system.commit_platform_delete(selected)
					_system.request_status("Platform %d deleted." % selected)
					return true
			KEY_V:
				if selected != -1:
					var visible := _system.commit_platform_toggle_visible(selected)
					_system.request_status(
						"Platform %d %s." % [selected, "visible" if visible else "hidden"])
					return true
			KEY_T:
				if selected != -1:
					_system.request_texture_pick({"kind": &"platform", "platform_id": selected})
					return true
	return false
