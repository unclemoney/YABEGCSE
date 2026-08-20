class_name EditorController
extends Node

## EditorController
##
## Root of the single persistent editor scene and the only node that knows
## all domains exist. Owns LevelData (sole source of truth) and the
## LevelSerializer. 2D/3D toggle flips visibility and input processing in
## place — same scene, same LevelData, zero reload.

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

@onready var _canvas_2d: Canvas2DView = get_node_or_null(canvas_2d_path)
@onready var _viewport_3d: Viewport3DView = get_node_or_null(viewport_3d_path)
@onready var _tool_system: ToolSystem = get_node_or_null(tool_system_path)
@onready var _undo_stack: UndoStack = get_node_or_null(undo_stack_path)
@onready var _ui_panels: UIPanels = get_node_or_null(ui_panels_path)


## _ready()
##
## Side-effects: creates the empty level, binds its change signal, wires
## UIPanels signals, applies the initial 2D mode.
func _ready() -> void:
	level_data = LevelData.create_empty()
	_rebind_level_data()
	if _ui_panels != null:
		_ui_panels.new_requested.connect(new_level)
		_ui_panels.open_path_selected.connect(open_level)
		_ui_panels.save_path_selected.connect(save_level)
	_apply_mode()


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
## in the UI, never thrown.
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
		_viewport_3d.rebuild()


func _apply_mode() -> void:
	var is_2d := mode == Mode.MODE_2D
	if _canvas_2d != null:
		_canvas_2d.visible = is_2d
		_canvas_2d.set_process(is_2d)
		_canvas_2d.set_process_input(is_2d)
	if _viewport_3d != null:
		_viewport_3d.visible = not is_2d
		_viewport_3d.set_process(not is_2d)
		_viewport_3d.set_process_input(not is_2d)
	if _ui_panels != null:
		_ui_panels.set_mode(mode)


func _report_error(message: String) -> void:
	push_warning(message)
	if _ui_panels != null:
		_ui_panels.set_status("Error: " + message)
