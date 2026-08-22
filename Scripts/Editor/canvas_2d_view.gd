class_name Canvas2DView
extends Node2D

## Canvas2DView
##
## Top-down 2D editing view. Read-only consumer of LevelData: it draws the
## grid, sectors, walls and the tool preview, forwards input upward via
## canvas_input, and owns its own camera (pan/zoom). All mutation goes
## through EditorController down to ToolSystem — never from here.

signal canvas_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2)
## The WASD-driven player marker moved (2D mode). Angle is the 2D facing:
## radians, 0 = +X (east), positive toward +Y (south on the canvas).
signal player_moved_2d(position: Vector2, angle: float)

const MIN_GRID_SCREEN_PX := 12.0
const ZOOM_MIN := 0.02  # low enough to frame a full ±10200 cm GCS import (~34k units)
const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.25

@export var camera_path: NodePath = ^"Camera2D"

var _level_data: LevelData
var _preview: Dictionary = {}
var _panning := false
var _last_world := Vector2.ZERO
var _last_snapped := Vector2.ZERO
var _marker_pos := Vector2.ZERO
var _marker_angle := 0.0
var _marker_set := false
var _tool_layer: CanvasLayer
var _tool_label: Label

@onready var _camera: Camera2D = get_node_or_null(camera_path)


## _ready()
##
## Side-effects: builds the screen-pinned tool-mode label (top-right, 8 px
## margins, semi-transparent black background — the top-left corner belongs
## to the 2D canvas UI buttons). A CanvasLayer keeps it fixed on screen
## over any geometry; UIPanels draws above it (later in tree order at the
## same layer).
func _ready() -> void:
	_tool_layer = CanvasLayer.new()
	_tool_layer.name = "ToolModeLayer"
	add_child(_tool_layer)
	_tool_label = Label.new()
	# Top-right pinned, growing leftward as the mode name changes length.
	_tool_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tool_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tool_label.offset_top = 8.0
	_tool_label.offset_right = -8.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_content_margin_all(4.0)
	_tool_label.add_theme_stylebox_override("normal", style)
	_tool_label.text = "MODE: SECTOR DRAW"
	_tool_layer.add_child(_tool_label)
	# CanvasLayer visibility does not follow the parent Node2D; sync it.
	visibility_changed.connect(
		func() -> void: _tool_layer.visible = visible
	)


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


## set_tool_mode(text)
##
## Called down by EditorController every frame with the ToolSystem's
## current mode name. Instant switches: the label just follows.
func set_tool_mode(text: String) -> void:
	if _tool_label != null and _tool_label.text != text:
		_tool_label.text = text


## update_player_marker(pos, angle)
##
## Called down by EditorController with the player's 2D map position and
## facing angle (radians, 0 = +X/east, positive toward +Y/south). The
## marker renders on top of sector geometry, below the UI panels.
func update_player_marker(pos: Vector2, angle: float) -> void:
	_marker_pos = pos
	_marker_angle = angle
	_marker_set = true
	queue_redraw()


func has_player_marker() -> bool:
	return _marker_set


func get_zoom() -> float:
	if _camera == null:
		return 1.0
	return _camera.zoom.x


## _process(delta)
##
## 2D-mode WASD: moves the player position marker (facing follows the
## movement direction) and signals upward so EditorController can mirror
## the move into the 3D view. Only runs while visible (the controller
## disables this node's processing in 3D mode).
func _process(delta: float) -> void:
	if not visible or _camera == null:
		return
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if dir == Vector2.ZERO:
		return
	if not _marker_set:
		_marker_pos = _camera.get_screen_center_position()
		_marker_set = true
	var speed := 500.0
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		speed = settings.walk_speed
	_marker_pos += dir * speed * delta
	_marker_angle = dir.angle()
	player_moved_2d.emit(_marker_pos, _marker_angle)
	queue_redraw()


func get_last_snapped() -> Vector2:
	return _last_snapped


## frame_level()
##
## Centers the camera on the content bounds (points + object positions)
## and zooms to fit with a small margin. Called down by EditorController
## whenever the level is (re)bound (open / import / new / clear):
## imported GCS levels live thousands of units from the origin (the
## fixture sits near (13000, 14000)), so without framing the 2D view
## showed empty space while the 3D view spawned inside the content.
## An empty level resets to the origin at zoom 1.
func frame_level() -> void:
	if _camera == null:
		return
	var bounds := Rect2()
	var has_content := false
	if _level_data != null:
		for p in _level_data.points:
			if p is Array and (p as Array).size() >= 2:
				var v := Vector2(float(p[0]), float(p[1]))
				if has_content:
					bounds = bounds.expand(v)
				else:
					bounds = Rect2(v, Vector2.ZERO)
					has_content = true
		for o in _level_data.objects:
			if o is Dictionary:
				var pos := ObjectOps.get_pos(o)
				if has_content:
					bounds = bounds.expand(pos)
				else:
					bounds = Rect2(pos, Vector2.ZERO)
					has_content = true
	if not has_content:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		queue_redraw()
		return
	_camera.position = bounds.get_center()
	var vp := get_viewport_rect().size
	var fit := minf(
		vp.x / maxf(bounds.size.x, 1.0), vp.y / maxf(bounds.size.y, 1.0)) * 0.9
	var z: float = clampf(fit, ZOOM_MIN, 1.0)
	_camera.zoom = Vector2(z, z)
	queue_redraw()


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
		if mb.pressed:
			# Canvas clicks drop stale Control focus so Tab reaches the
			# tool cycle instead of moving UI focus.
			get_viewport().gui_release_focus()
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
		_draw_platforms()
	_draw_preview()
	_draw_tool_overlay()
	_draw_player_marker()


## _draw_tool_overlay()
##
## Tool-mode rendering driven by the active tool's preview dict: vertex
## handles in Vertex mode (4 px squares at every wall endpoint; the
## selected vertex is larger and orange, the hovered one yellow), wall
## hover/selection highlights in Wall mode, and the red 0.3 s rejection
## flash both modes share. All screen-constant sizes divide by zoom.
func _draw_tool_overlay() -> void:
	var flash: Array = _preview.get("flash_walls", [])
	for wi in flash:
		_highlight_wall(int(wi), Color(1.0, 0.2, 0.2), 5.0)
	var mode: StringName = _preview.get("tool_mode", &"draw")
	if mode == &"vertex":
		_draw_vertex_handles()
	elif mode == &"wall":
		var hover := int(_preview.get("wall_hover", -1))
		var selected := int(_preview.get("wall_selected", -1))
		if hover != -1 and hover != selected:
			_highlight_wall(hover, Color(1.0, 0.95, 0.4), 4.0)
		if selected != -1:
			_highlight_wall(selected, Color(1.0, 0.6, 0.15), 4.0)


func _highlight_wall(wall_id: int, color: Color, width: float) -> void:
	if _level_data == null or wall_id < 0 or wall_id >= _level_data.walls.size():
		return
	var w: Dictionary = _level_data.walls[wall_id]
	var n := _level_data.points.size()
	if w["a"] < 0 or w["a"] >= n or w["b"] < 0 or w["b"] >= n:
		return
	draw_line(GeometryOps.get_point(_level_data, w["a"]),
		GeometryOps.get_point(_level_data, w["b"]), color, width)


func _draw_vertex_handles() -> void:
	if _level_data == null:
		return
	var px := 4.0 / _camera.zoom.x
	var hover := int(_preview.get("vertex_hover", -1))
	var selected := int(_preview.get("vertex_selected", -1))
	var drawn := {}
	for w in _level_data.walls:
		for pid in [w["a"], w["b"]]:
			var point_id := int(pid)
			if point_id < 0 or point_id >= _level_data.points.size() or drawn.has(point_id):
				continue
			drawn[point_id] = true
			var size := px
			var color := Color(0.85, 0.85, 0.9)
			if point_id == hover:
				size = px * 1.75
				color = Color(1.0, 0.9, 0.3)
			if point_id == selected:
				size = px * 2.0
				color = Color(1.0, 0.55, 0.1)
			var center := GeometryOps.get_point(_level_data, point_id)
			draw_rect(Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), color)


## _draw_player_marker()
##
## The player position marker: a 12 px radius triangle, bright green,
## rotated to the facing angle. Drawn after everything else on this
## canvas (on top of sector geometry); UIPanels is a CanvasLayer above.
func _draw_player_marker() -> void:
	if not _marker_set:
		return
	var r := 12.0 / _camera.zoom.x
	var color := Color(0.2, 1.0, 0.45)
	var tip := _marker_pos + Vector2(r, 0.0).rotated(_marker_angle)
	var back_left := _marker_pos + Vector2(r, 0.0).rotated(_marker_angle + deg_to_rad(140.0))
	var back_right := _marker_pos + Vector2(r, 0.0).rotated(_marker_angle - deg_to_rad(140.0))
	draw_colored_polygon(PackedVector2Array([tip, back_left, back_right]), color)


## _draw_objects()
##
## M4 markers: per-type colored circle + facing tick at the object's X/Y
## (the same ObjectOps.get_pos data the 3D view uses — no culling, so
## out-of-limit imports draw too). Flagged objects paint red
## (tolerate + flag); the hovered object gets a white ring; the
## ObjectTool brush ghost follows the cursor.
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


## _draw_platforms()
##
## Drawn platform overlays: filled polygon with a dotted border, orange —
## distinct from sectors (blue fill) and the M4 object markers. Flagged
## platforms (self-intersecting, <3 points) keep drawing but with a red
## border (tolerate + flag); a sub-3-point platform draws its open poly
## line only. Invisible platforms (is_visible, V toggle) skip the fill and
## draw as a dashed outline only. In Platform Edit mode the hovered /
## selected platform gets a border highlight (cyan selected, yellow
## hover). Dash/width scale with zoom to stay screen-constant.
const PLATFORM_FILL := Color(1.0, 0.55, 0.1, 0.18)
const PLATFORM_BORDER := Color(1.0, 0.6, 0.1)
const PLATFORM_FLAG_FILL := Color(1.0, 0.25, 0.25, 0.15)
const PLATFORM_FLAG_BORDER := Color(1.0, 0.25, 0.25)
const PLATFORM_HIDDEN_BORDER := Color(1.0, 0.6, 0.1, 0.45)
const PLATFORM_HOVER_BORDER := Color(1.0, 0.95, 0.4)
const PLATFORM_SELECTED_BORDER := Color(0.3, 0.9, 1.0)

func _draw_platforms() -> void:
	var hover := int(_preview.get("platform_hover", -1))
	var selected := int(_preview.get("platform_selected", -1))
	for i in range(_level_data.platforms.size()):
		var p: PlatformData = _level_data.platforms[i]
		if p == null or p.vertices.is_empty():
			continue
		var fill := PLATFORM_FILL
		var border := PLATFORM_BORDER
		if _level_data.flagged_platforms.has(i):
			fill = PLATFORM_FLAG_FILL
			border = PLATFORM_FLAG_BORDER
		if not p.is_visible:
			fill = Color(0, 0, 0, 0)  # invisible: dashed outline only
			border = PLATFORM_HIDDEN_BORDER
		var poly := PackedVector2Array(p.vertices)
		if poly.size() >= 3 and fill.a > 0.0:
			draw_colored_polygon(poly, fill)
		var dash := 6.0 / _camera.zoom.x
		var last := poly.size() - 1
		if poly.size() < 3:
			last -= 1  # open poly: no closing edge
		for k in range(last + 1):
			draw_dashed_line(poly[k], poly[(k + 1) % poly.size()], border,
				2.0 / _camera.zoom.x, dash)
		# Platform Edit selection/hover: solid border over the dashed one.
		var ring := Color(0, 0, 0, 0)
		if i == selected:
			ring = PLATFORM_SELECTED_BORDER
		elif i == hover:
			ring = PLATFORM_HOVER_BORDER
		if ring.a > 0.0 and poly.size() >= 3:
			var outline := poly
			outline.append(poly[0])
			draw_polyline(outline, ring, 3.0 / _camera.zoom.x)


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
