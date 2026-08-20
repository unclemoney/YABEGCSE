class_name EditorController
extends Node

## EditorController
##
## Root of the single persistent editor scene and the only node that knows
## all domains exist. Owns LevelData (sole source of truth) and the
## LevelSerializer. 2D/3D toggle flips visibility and input processing in
## place — same scene, same LevelData, zero reload.
##
## Wiring: views and ToolSystem signal up, this node calls down. Undo
## snapshots are pushed on ToolSystem.mutation_committed (before the
## mutation) and restored on Ctrl+Z. Clear Level is a confirmed
## destructive op and stays outside the undo stack.

enum Mode { MODE_2D, MODE_3D }

@export var canvas_2d_path: NodePath = ^"Canvas2D"
@export var viewport_3d_path: NodePath = ^"Viewport3D"
@export var tool_system_path: NodePath = ^"ToolSystem"
@export var undo_stack_path: NodePath = ^"UndoStack"
@export var ui_panels_path: NodePath = ^"UIPanels"

var level_data: LevelData
var mode: Mode = Mode.MODE_2D

var _serializer := LevelSerializer.new()
var _current_path := ""
var _picker_brush_mode := false

@onready var _canvas_2d: Canvas2DView = get_node_or_null(canvas_2d_path)
@onready var _viewport_3d: Viewport3DView = get_node_or_null(viewport_3d_path)
@onready var _tool_system: ToolSystem = get_node_or_null(tool_system_path)
@onready var _undo_stack: UndoStack = get_node_or_null(undo_stack_path)
@onready var _ui_panels: UIPanels = get_node_or_null(ui_panels_path)


## _ready()
##
## Side-effects: creates the empty level, binds all cross-domain signals,
## applies the initial 2D mode.
func _ready() -> void:
	level_data = LevelData.create_empty()
	_rebind_level_data()
	if _canvas_2d != null:
		_canvas_2d.canvas_input.connect(_on_canvas_input)
	if _viewport_3d != null:
		_viewport_3d.edit_input.connect(_on_3d_edit_input)
		_viewport_3d.edit_motion.connect(_on_3d_edit_motion)
	if _tool_system != null:
		_tool_system.mutation_committed.connect(_push_undo_snapshot)
		_tool_system.level_data_changed.connect(_on_level_data_changed)
		_tool_system.texture_pick_requested.connect(_on_texture_pick_requested)
	if _ui_panels != null:
		_ui_panels.new_requested.connect(new_level)
		_ui_panels.open_path_selected.connect(open_level)
		_ui_panels.save_path_selected.connect(save_level)
		_ui_panels.clear_confirmed.connect(_on_clear_level_confirmed)
		_ui_panels.fixture_load_requested.connect(open_level)
		_ui_panels.texture_picked.connect(_on_texture_picked)
		_ui_panels.texture_pick_requested.connect(_on_texture_pick_requested.bind({}))
		_ui_panels.texture_picker_closed.connect(_on_texture_picker_closed)
		_ui_panels.brush_type_selected.connect(_on_brush_type_selected)
		_ui_panels.brush_art_requested.connect(_on_brush_art_requested)
		_ui_panels.debug_place_objects.connect(_on_debug_place_objects)
	_apply_mode()


## _process(_delta)
##
## Side-effects: feeds the active tool's preview state down to the 2D
## view and refreshes the status bar cursor readout (2D mode), or the
## crosshair aim readout (3D mode).
func _process(_delta: float) -> void:
	if mode == Mode.MODE_2D:
		if _canvas_2d != null and _tool_system != null:
			_canvas_2d.set_preview(_tool_system.get_preview())
			if _ui_panels != null:
				var g := int(_canvas_2d.get_grid())
				var s: Vector2 = _canvas_2d.get_last_snapped()
				_ui_panels.set_cursor_info("grid %d  |  (%d, %d)" % [g, int(s.x), int(s.y)])
	elif _viewport_3d != null and _tool_system != null and _ui_panels != null:
		_ui_panels.set_cursor_info(_tool_system.describe_aim(_viewport_3d.get_aim()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mode"):
		if mode == Mode.MODE_2D:
			mode = Mode.MODE_3D
		else:
			mode = Mode.MODE_2D
		_apply_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_panel"):
		if _ui_panels != null:
			_ui_panels.toggle_debug_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_load_fixture"):
		# Debug command: load the two-room fixture (see DebugPanel buttons).
		open_level("res://Tests/Fixtures/level_geometry_v0.json")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_Z:
			_undo()
			get_viewport().set_input_as_handled()


## new_level()
##
## Replaces the level with a blank one. M1: confirmation dialog when dirty.
func new_level() -> void:
	level_data = LevelData.create_empty()
	_current_path = ""
	_rebind_level_data()


## open_level(path)
##
## Reads the file, hands the text to the serializer. Errors are reported
## in the UI, never thrown. Validity annotations are computed at load.
func open_level(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_report_error("Could not read file: " + path)
		return
	var data := _serializer.load_from_json(text)
	if data == null:
		_report_error(_serializer.last_error)
		return
	level_data = data
	_current_path = path
	_undo_stack.clear()
	_rebind_level_data()
	if _ui_panels != null:
		_ui_panels.set_status("Opened: " + path)


## save_level(path)
##
## Serializes LevelData to JSON and writes it. The serializer only sees
## strings; this method owns the filesystem side.
func save_level(path: String) -> void:
	var text := _serializer.save_to_json(level_data)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_report_error("Could not write file: " + path)
		return
	file.store_string(text)
	file.close()
	_current_path = path
	if _ui_panels != null:
		_ui_panels.set_status("Saved: " + path)


func _on_canvas_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> void:
	if mode != Mode.MODE_2D or _tool_system == null:
		return
	if _tool_system.handle_input(event, world_pos, snapped_pos):
		get_viewport().set_input_as_handled()


## _on_3d_edit_input(event, aim) / _on_3d_edit_motion(relative, aim)
##
## 3D edit route: the view signals crosshair-aimed input upward; the tool
## consumes it via ToolSystem. Look is suppressed while a corner drag is
## active (the tool decides, the view obeys).
func _on_3d_edit_input(event: InputEvent, aim: Dictionary) -> void:
	if mode != Mode.MODE_3D or _tool_system == null:
		return
	if _tool_system.handle_3d_input(event, aim):
		get_viewport().set_input_as_handled()
	if _viewport_3d != null:
		_viewport_3d.set_look_suppressed(_tool_system.is_3d_dragging())


func _on_3d_edit_motion(relative: Vector2, aim: Dictionary) -> void:
	if mode != Mode.MODE_3D or _tool_system == null:
		return
	_tool_system.handle_3d_motion(relative, aim)
	if _viewport_3d != null:
		_viewport_3d.set_look_suppressed(_tool_system.is_3d_dragging())


func _on_texture_pick_requested(_aim: Dictionary) -> void:
	if _ui_panels != null:
		_picker_brush_mode = false
		_ui_panels.open_texture_picker()


func _on_texture_picked(tex_name: String) -> void:
	if _tool_system == null:
		return
	if _picker_brush_mode:
		_tool_system.set_brush_art(tex_name)
		_update_brush_status()
	else:
		_tool_system.commit_texture(tex_name)


func _on_brush_type_selected(type: String) -> void:
	if _tool_system != null:
		_tool_system.set_brush_type(type)
		_tool_system.set_object_mode(true)
		_update_brush_status()


func _on_brush_art_requested() -> void:
	if _ui_panels != null:
		_picker_brush_mode = true
		_ui_panels.open_texture_picker()


func _on_debug_place_objects() -> void:
	if _tool_system != null:
		_tool_system.debug_place_test_set()
		if _ui_panels != null:
			_ui_panels.set_status("Test object set placed.")


func _update_brush_status() -> void:
	if _ui_panels != null and _tool_system != null:
		var brush := _tool_system.get_brush()
		_ui_panels.set_status("Brush: %s  art=%s" % [brush["type"], brush["art"]])


## _on_texture_picker_closed()
##
## The picker released the mouse; re-capture when back in 3D mode.
func _on_texture_picker_closed() -> void:
	if mode == Mode.MODE_3D:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _push_undo_snapshot() -> void:
	_undo_stack.push({
		"points": level_data.points.duplicate(true),
		"walls": level_data.walls.duplicate(true),
		"sectors": level_data.sectors.duplicate(true),
		"objects": level_data.objects.duplicate(true),
	})


func _undo() -> void:
	var snapshot: Variant = _undo_stack.pop_undo()
	if snapshot == null:
		if _ui_panels != null:
			_ui_panels.set_status("Nothing to undo.")
		return
	level_data.points = snapshot["points"].duplicate(true)
	level_data.walls = snapshot["walls"].duplicate(true)
	level_data.sectors = snapshot["sectors"].duplicate(true)
	level_data.objects = snapshot.get("objects", []).duplicate(true)
	GeometryOps.validate(level_data)
	_on_level_data_changed(LevelData.ChangeType.GEOMETRY)
	if _ui_panels != null:
		_ui_panels.set_status("Undo.")


## _on_clear_level_confirmed()
##
## Destructive op (confirmed in UIPanels): wipes the level and the undo
## stack. Outside undo by design, per charter.
func _on_clear_level_confirmed() -> void:
	level_data = LevelData.create_empty()
	_current_path = ""
	_undo_stack.clear()
	_rebind_level_data()
	if _ui_panels != null:
		_ui_panels.set_status("Level cleared.")


func _rebind_level_data() -> void:
	level_data.level_changed.connect(_on_level_data_changed)
	if _canvas_2d != null:
		_canvas_2d.set_level_data(level_data)
	if _viewport_3d != null:
		_viewport_3d.set_level_data(level_data)
	if _tool_system != null:
		_tool_system.set_level_data(level_data)
	_on_level_data_changed(LevelData.ChangeType.FULL_RELOAD)


func _on_level_data_changed(_change_type: LevelData.ChangeType) -> void:
	if _canvas_2d != null:
		_canvas_2d.redraw_level()
	if _viewport_3d != null:
		var stats := _viewport_3d.rebuild()
		if _ui_panels != null and stats.has("missing_textures"):
			_ui_panels.set_missing_textures(stats["missing_textures"])
	if _ui_panels != null and level_data != null:
		_ui_panels.set_debug_flags(
			level_data.flagged_sectors, level_data.flagged_walls, level_data.flagged_objects
		)


func _apply_mode() -> void:
	var is_2d := mode == Mode.MODE_2D
	if _canvas_2d != null:
		_canvas_2d.visible = is_2d
		if is_2d:
			_canvas_2d.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			_canvas_2d.process_mode = Node.PROCESS_MODE_DISABLED
	if _viewport_3d != null:
		_viewport_3d.visible = not is_2d
		if is_2d:
			_viewport_3d.process_mode = Node.PROCESS_MODE_DISABLED
			_viewport_3d.exit_3d()
		else:
			_viewport_3d.process_mode = Node.PROCESS_MODE_INHERIT
			_viewport_3d.enter_3d()
	if _ui_panels != null:
		_ui_panels.set_mode(mode)
	if _tool_system != null:
		_tool_system.set_mode_3d(not is_2d)


func _report_error(message: String) -> void:
	push_warning(message)
	if _ui_panels != null:
		_ui_panels.set_status("Error: " + message)
