class_name WallSelectTool
extends RefCounted

## WallSelectTool (2D "Wall" mode)
##
## Hover highlights a wall (brighter, thicker); LMB selects portal walls
## only — boundary walls report "Boundary wall: cannot select" to the
## status line. Delete merges the two sectors across the selected portal
## (GeometryOps.check_portal_merge gates; the merge is one undo step via
## ToolSystem). Rejected merges flash the wall red for 0.3 s and log to
## the debug panel. No wall creation, no wall deletion without a merge.

signal finished
signal cancelled

const HOVER_PX := 8.0
const FLASH_MS := 300

var _system: ToolSystem
var _hover := -1
var _selected := -1
var _flash_walls: Array[int] = []
var _flash_until := 0


func _init(system: ToolSystem) -> void:
	_system = system


func activate() -> void:
	pass


func deactivate() -> void:
	_hover = -1
	_selected = -1
	_flash_walls.clear()


## get_preview() -> Dictionary
##
## Read-only transient state for the canvas view (hover/selection
## highlight + the rejection flash).
func get_preview() -> Dictionary:
	var preview := {
		"tool_mode": &"wall",
		"verts": [],
		"wall_hover": _hover,
		"wall_selected": _selected,
	}
	if Time.get_ticks_msec() < _flash_until:
		preview["flash_walls"] = _flash_walls
	return preview


func handle_input(event: InputEvent, world_pos: Vector2, _snapped_pos: Vector2) -> bool:
	var data := _system.get_level_data()
	if data == null:
		return false
	if event is InputEventMouseMotion:
		_hover = GeometryOps.wall_near(data, world_pos, HOVER_PX * _system.get_pick_scale())
		if _hover != -1:
			if (data.walls[_hover] as Dictionary)["back"] == -1:
				_system.request_status("Boundary wall: cannot select")
			else:
				_system.request_status("Portal wall: click to select, Delete to merge sectors")
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return false
		if _hover != -1 and (data.walls[_hover] as Dictionary)["back"] != -1:
			_selected = _hover
			_system.request_status("Wall %d selected (portal). Delete merges the sectors." % _selected)
			return true
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_DELETE and _selected != -1:
			_merge_selected(data)
			return true
	return false


## _merge_selected(data)
##
## Success clears the selection (the wall record is gone); failure keeps
## it, flashes the wall, and surfaces the rejection in status + debug
## panel. The status/debug text leads with the exact spec message.
func _merge_selected(data: LevelData) -> void:
	var wall_id := _selected
	var result := _system.commit_merge_portal(wall_id)
	if result["ok"]:
		_system.request_status("Sectors merged across wall %d." % wall_id)
		_selected = -1
		_hover = -1
		return
	_flash_walls = [wall_id]
	_flash_until = Time.get_ticks_msec() + FLASH_MS
	var message := "Wall merge failed: invalid geometry"
	if not str(result["reason"]).is_empty():
		message += " (%s)" % result["reason"]
	_system.request_status(message)
	_system.report_debug(message)
