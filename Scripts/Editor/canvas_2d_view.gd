class_name Canvas2DView
extends Node2D

## Canvas2DView
##
## Top-down 2D editing view. Read-only consumer of LevelData: it draws the
## grid, sectors, walls and the tool preview, forwards input upward via
## canvas_input, and owns its own camera (pan/zoom). All mutation goes
## through EditorController down to ToolSystem — never from here.

signal canvas_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2)

const MIN_GRID_SCREEN_PX := 12.0
const ZOOM_MIN := 0.1
const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.25

@export var camera_path: NodePath = ^"Camera2D"

var _level_data: LevelData
var _preview: Dictionary = {}
var _panning := false
var _last_world := Vector2.ZERO
var _last_snapped := Vector2.ZERO

@onready var _camera: Camera2D = get_node_or_null(camera_path)


## set_level_data(data)
##
## Called down by EditorController whenever the level is (re)bound.
func set_level_data(data: LevelData) -> void:
	_level_data = data
	queue_redraw()


func redraw_level() -> void:
	queue_redraw()


## set_preview(preview)
##
## Called down by EditorController every frame with the active tool's
## transient state (in-progress loop, cursor, hover target).
func set_preview(preview: Dictionary) -> void:
	_preview = preview
	queue_redraw()


## get_grid() -> float
##
## Zoom-dependent snapping: smallest ladder step whose on-screen size
## stays readable. Grid is editor behavior; file data stays in raw units.
func get_grid() -> float:
	var sizes: Array = [4, 8, 16, 32, 64, 128, 256]
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		sizes = settings.grid_sizes
	var zoom := 1.0
	if _camera != null:
		zoom = _camera.zoom.x
	for g in sizes:
		if float(g) * zoom >= MIN_GRID_SCREEN_PX:
			return float(g)
	return float(sizes[sizes.size() - 1])


func get_last_snapped() -> Vector2:
	return _last_snapped


## world_to_screen(world) -> Vector2
##
## Inverse of the event->world mapping; used by tests and overlays.
func world_to_screen(world: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return (world - _camera.get_screen_center_position()) * _camera.zoom.x + vp * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _panning:
		_camera.position -= (event as InputEventMouseMotion).relative / _camera.zoom.x
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	var world := _last_world
	if event is InputEventMouse:
		world = _event_to_world((event as InputEventMouse).position)
		_last_world = world
		_last_snapped = GeometryOps.snap(world, get_grid())
	canvas_input.emit(event, world, _last_snapped)


func _event_to_world(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return _camera.get_screen_center_position() + (screen_pos - vp * 0.5) / _camera.zoom.x


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _event_to_world(screen_pos)
	var z: float = clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	_camera.position += before - _event_to_world(screen_pos)
	queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	_draw_grid()
	if _level_data != null:
		_draw_sectors()
		_draw_walls()
		_draw_objects()
	_draw_preview()


## _draw_objects()
##
## M4 markers: per-type colored circle + facing tick + type initial.
## Flagged objects paint red (tolerate + flag); the hovered object gets a
## white ring; the ObjectTool brush ghost follows the cursor.
const OBJECT_COLORS := {
	"billboard": Color(0.4, 0.9, 0.4),
	"wall_object": Color(0.95, 0.6, 0.2),
	"sprite_8way": Color(0.9, 0.4, 0.9),
	"fluid": Color(0.3, 0.6, 1.0),
	"platform": Color(0.9, 0.9, 0.3),
}

func _draw_objects() -> void:
	for i in range(_level_data.objects.size()):
		var o: Variant = _level_data.objects[i]
		if not o is Dictionary:
			continue
		var pos := ObjectOps.get_pos(o)
		var color: Color = OBJECT_COLORS.get(str(o.get("type", "")), Color.GRAY)
		if _level_data.flagged_objects.has(i):
			color = Color(1.0, 0.25, 0.25)
		draw_circle(pos, 8.0 / _camera.zoom.x, color)
		var facing := Vector2(0.0, 1.0).rotated(deg_to_rad(float(o.get("angle", 0.0))))
		draw_line(pos, pos + facing * 16.0 / _camera.zoom.x, color, 2.0)
		if _preview.get("object_hover", -1) == i:
			draw_arc(pos, 12.0 / _camera.zoom.x, 0.0, TAU, 16, Color.WHITE, 2.0)
	var ghost: Variant = _preview.get("object_cursor", null)
	if ghost is Vector2:
		draw_arc(ghost, 8.0 / _camera.zoom.x, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.5), 1.0)


func _visible_world_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / _camera.zoom.x
	var center := _camera.get_screen_center_position()
	return Rect2(center - half, half * 2.0)


func _draw_grid() -> void:
	var grid := get_grid()
	var rect := _visible_world_rect().grow(grid)
	var minor := Color(0.25, 0.25, 0.28, 0.6)
	var major := Color(0.32, 0.32, 0.38, 0.8)
	var major_step := grid * 8.0
	var x := floorf(rect.position.x / grid) * grid
	while x <= rect.end.x:
		var c := major if fmod(x, major_step) == 0.0 else minor
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), c)
		x += grid
	var y := floorf(rect.position.y / grid) * grid
	while y <= rect.end.y:
		var c := major if fmod(y, major_step) == 0.0 else minor
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), c)
		y += grid
	draw_line(Vector2(rect.position.x, 0), Vector2(rect.end.x, 0), Color(0.5, 0.3, 0.3), 2.0)
	draw_line(Vector2(0, rect.position.y), Vector2(0, rect.end.y), Color(0.3, 0.5, 0.3), 2.0)


func _draw_sectors() -> void:
	for si in range(_level_data.sectors.size()):
		var poly := GeometryOps.loop_to_polygon(_level_data, _level_data.sectors[si]["walls"])
		if poly.size() < 3:
			continue
		var fill := Color(0.35, 0.45, 0.6, 0.25)
		if _level_data.flagged_sectors.has(si):
			fill = Color(0.8, 0.2, 0.2, 0.35)  # tolerate + flag: red paint
		draw_colored_polygon(poly, fill)
		if _preview.get("hover_sector", -1) == si:
			var outline := poly
			outline.append(poly[0])
			draw_polyline(outline, Color(1.0, 0.9, 0.2), 3.0)


func _draw_walls() -> void:
	for wi in range(_level_data.walls.size()):
		var w: Dictionary = _level_data.walls[wi]
		var n := _level_data.points.size()
		if w["a"] < 0 or w["a"] >= n or w["b"] < 0 or w["b"] >= n:
			continue  # out-of-range walls are flagged; nothing sane to draw
		var a := GeometryOps.get_point(_level_data, w["a"])
		var b := GeometryOps.get_point(_level_data, w["b"])
		var color := Color.WHITE
		if w["back"] != -1:
			color = Color(0.3, 0.9, 0.9)  # portal wall
		if _level_data.flagged_walls.has(wi):
			color = Color(1.0, 0.25, 0.25)
		draw_line(a, b, color, 2.0)


func _draw_preview() -> void:
	if _preview.is_empty():
		return
	var verts: Array = _preview.get("verts", [])
	var cursor: Vector2 = _preview.get("cursor", Vector2.ZERO)
	var line_color := Color(1.0, 0.9, 0.2)
	for i in range(verts.size()):
		draw_circle(verts[i], 3.0 / _camera.zoom.x, line_color)
		if i > 0:
			draw_line(verts[i - 1], verts[i], line_color, 2.0)
	if not verts.is_empty():
		draw_line(verts[verts.size() - 1], cursor, Color(1.0, 0.9, 0.2, 0.5), 1.0)
		if verts.size() >= 3:
			draw_circle(verts[0], 5.0 / _camera.zoom.x, Color(0.3, 1.0, 0.3))
