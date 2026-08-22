class_name VertexEditTool
extends RefCounted

## VertexEditTool (2D "Vertex" mode)
##
## Moves existing sector vertices — never creates or deletes them. LMB
## near a vertex (8 px radius, zoom-scaled via ToolSystem) selects and
## grabs it; the drag previews live through ToolSystem (one undo snapshot
## per drag, walls stretch because they reference point ids); release
## validates: a move that would cross any wall snaps the vertex back,
## flashes the connected walls red for 0.3 s, and logs to the debug
## panel. Single selection only.

signal finished
signal cancelled

const PICK_PX := 8.0
const FLASH_MS := 300

var _system: ToolSystem
var _hover := -1
var _selected := -1
var _dragging := false
var _drag_start := Vector2.ZERO
var _flash_walls: Array[int] = []
var _flash_until := 0


func _init(system: ToolSystem) -> void:
	_system = system


func activate() -> void:
	pass


func deactivate() -> void:
	_hover = -1
	_selected = -1
	_dragging = false
	_flash_walls.clear()


## get_preview() -> Dictionary
##
## Read-only transient state for the canvas view: vertex handles are
## drawn by the canvas whenever tool_mode is "vertex"; flash_walls only
## appears while the rejection flash is alive (time-checked here, the
## tool has no _process).
func get_preview() -> Dictionary:
	var preview := {
		"tool_mode": &"vertex",
		"verts": [],
		"vertex_hover": _hover,
		"vertex_selected": _selected,
	}
	if Time.get_ticks_msec() < _flash_until:
		preview["flash_walls"] = _flash_walls
	return preview


## handle_input(event, world_pos, snapped_pos) -> bool
##
## Drag target is grid-snapped (grid discipline); picking is not.
func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	var data := _system.get_level_data()
	if data == null:
		return false
	if event is InputEventMouseMotion:
		if _dragging:
			_system.update_vertex_drag(_selected, snapped_pos)
		else:
			_hover = GeometryOps.nearest_point(
				data, world_pos, PICK_PX * _system.get_pick_scale())
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_selected = _hover
			if _selected == -1:
				return false
			_dragging = true
			_drag_start = GeometryOps.get_point(data, _selected)
			_system.begin_vertex_drag()
			return true
		if _dragging:
			_dragging = false
			if not _system.finish_vertex_drag(_selected, _drag_start):
				_flash_connected(data, _selected)
				_system.request_status("Invalid vertex move: wall crossing")
				_system.report_debug("Invalid vertex move: wall crossing")
			return true
		return false
	return false


## _flash_connected(data, point_id)
##
## The 0.3 s red flash paints every wall connected to the rejected vertex.
func _flash_connected(data: LevelData, point_id: int) -> void:
	_flash_walls.clear()
	for wi in range(data.walls.size()):
		var w: Dictionary = data.walls[wi]
		if w["a"] == point_id or w["b"] == point_id:
			_flash_walls.append(wi)
	_flash_until = Time.get_ticks_msec() + FLASH_MS
