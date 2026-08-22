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
## Canonical player marker state (synced both ways between the views).
var player_position := Vector3.ZERO
## 2D facing in radians: 0 = +X (east), positive toward +Y (map south).
var player_angle := 0.0

var _serializer := LevelSerializer.new()
var _current_path := ""
var _picker_brush_mode := false
var _picker_sky_mode := false

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
		_canvas_2d.player_moved_2d.connect(_on_player_moved_2d)
	if _viewport_3d != null:
		_viewport_3d.edit_input.connect(_on_3d_edit_input)
		_viewport_3d.edit_motion.connect(_on_3d_edit_motion)
		_viewport_3d.player_moved.connect(_on_player_moved)
		var gameplay := _viewport_3d.get_gameplay()
		if gameplay != null:
			gameplay.message_shown.connect(_on_gameplay_message)
			gameplay.warp_requested.connect(_on_gameplay_warp)
			gameplay.event_logged.connect(_on_gameplay_event)
			gameplay.registers_changed.connect(_on_gameplay_registers_changed)
	if _tool_system != null:
		_tool_system.mutation_committed.connect(_push_undo_snapshot)
		_tool_system.level_data_changed.connect(_on_level_data_changed)
		_tool_system.texture_pick_requested.connect(_on_texture_pick_requested)
		_tool_system.status_requested.connect(_on_tool_status)
		_tool_system.debug_log_requested.connect(_on_tool_debug_log)
	if _ui_panels != null:
		_ui_panels.new_requested.connect(new_level)
		_ui_panels.open_path_selected.connect(open_level)
		_ui_panels.save_path_selected.connect(save_level)
		_ui_panels.clear_confirmed.connect(_on_clear_level_confirmed)
		_ui_panels.import_confirmed.connect(_on_import_confirmed)
		_ui_panels.fixture_load_requested.connect(open_level)
		_ui_panels.texture_picked.connect(_on_texture_picked)
		_ui_panels.texture_pick_requested.connect(_on_texture_pick_requested.bind({}))
		_ui_panels.texture_picker_closed.connect(_on_texture_picker_closed)
		_ui_panels.brush_type_selected.connect(_on_brush_type_selected)
		_ui_panels.brush_art_requested.connect(_on_brush_art_requested)
		_ui_panels.debug_place_objects.connect(_on_debug_place_objects)
		_ui_panels.debug_import_fixture.connect(_on_debug_import_fixture)
		_ui_panels.environment_editor_requested.connect(_on_environment_editor_requested)
		_ui_panels.environment_applied.connect(_on_environment_applied)
		_ui_panels.sky_strip_pick_requested.connect(_on_sky_strip_pick_requested)
		_ui_panels.preferences_editor_requested.connect(_on_preferences_editor_requested)
		_ui_panels.preferences_applied.connect(_on_preferences_applied)
		_ui_panels.gameplay_editor_requested.connect(_on_gameplay_editor_requested)
		_ui_panels.gameplay_applied.connect(_on_gameplay_applied)
		_ui_panels.debug_cycle_tool.connect(_on_debug_cycle_tool)
		_ui_panels.panel_closed.connect(_on_texture_picker_closed)
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
			_canvas_2d.set_tool_mode("MODE: " + _tool_system.get_tool_mode_name())
			_tool_system.set_pick_scale(1.0 / maxf(_canvas_2d.get_zoom(), 0.0001))
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
	elif event.is_action_pressed("debug_import_fixture"):
		# Debug command (F10): import the bundled DOS 1.3 fixture pair.
		_on_debug_import_fixture()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_cycle_sky"):
		# Debug command (F11): cycle the level's sky mode (flat <-> strip).
		_on_debug_cycle_sky()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_gameplay_fixture"):
		# Debug command (F9): load the gameplay fixture (see DebugPanel).
		open_level("res://Tests/Fixtures/level_gameplay_v0.json")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help_panel"):
		# F1: editor controls reference (docs/EDITOR_CONTROLS.md viewer).
		if _ui_panels != null:
			_ui_panels.toggle_help_panel()
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
	if _ui_panels != null:
		_ui_panels.set_import_report({})


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
		_ui_panels.set_import_report({})
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


## _on_player_moved(position, angle) / _on_player_moved_2d(pos, angle)
##
## Player marker sync. The 3D view reports walk-mode motion upward; the
## 2D canvas reports WASD marker moves upward. This node stores the
## canonical state and calls the other view down. Setters never emit, so
## there is no signal cycle.
func _on_player_moved(position: Vector3, angle: float) -> void:
	player_position = position
	player_angle = angle
	if _canvas_2d != null:
		_canvas_2d.update_player_marker(Vector2(position.x, position.z), angle)


func _on_player_moved_2d(pos: Vector2, angle: float) -> void:
	player_position = Vector3(pos.x, player_position.y, pos.y)
	player_angle = angle
	if _viewport_3d != null:
		_viewport_3d.update_player_position(pos, angle)


## _on_tool_status(text) / _on_tool_debug_log(text)
##
## Tool feedback routed down to the UI: status line messages and debug
## panel log entries (vertex-move / wall-merge rejections).
func _on_tool_status(text: String) -> void:
	if _ui_panels != null:
		_ui_panels.set_status(text)


func _on_tool_debug_log(text: String) -> void:
	if _ui_panels != null:
		_ui_panels.log_editor_event(text)


## _on_debug_cycle_tool()
##
## Debug-panel command: advance the 2D tool cycle (same as Tab).
func _on_debug_cycle_tool() -> void:
	if _tool_system != null and mode == Mode.MODE_2D:
		_tool_system.cycle_tool(1)


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
		_picker_sky_mode = false
		_ui_panels.open_texture_picker()


func _on_texture_picked(tex_name: String) -> void:
	if _picker_sky_mode:
		_picker_sky_mode = false
		if _ui_panels != null:
			_ui_panels.set_sky_strip_art(tex_name.trim_suffix(".png"))
		return
	if _tool_system == null:
		return
	if _picker_brush_mode:
		_tool_system.set_brush_art(tex_name)
		_update_brush_status()
	else:
		_tool_system.commit_texture(tex_name)


## _on_environment_editor_requested() / _on_environment_applied(env)
##
## M6 environment panel: opened with the level's current environment;
## Apply commits through ToolSystem (one undo step).
func _on_environment_editor_requested() -> void:
	if _ui_panels != null:
		_ui_panels.open_environment_panel(level_data.environment)


func _on_environment_applied(env: Dictionary) -> void:
	if _tool_system != null:
		_tool_system.commit_environment(env)
		if _ui_panels != null:
			_ui_panels.set_status("Environment updated.")


func _on_sky_strip_pick_requested() -> void:
	if _ui_panels != null:
		_picker_brush_mode = false
		_picker_sky_mode = true
		_ui_panels.open_texture_picker()


## _on_preferences_editor_requested() / _on_preferences_applied(prefs)
##
## M6 preferences panel: writes GameSettings and persists to
## user://game_settings.cfg. Step height affects collision risers, so the
## 3D level rebuilds; eye height applies to the camera immediately.
func _on_preferences_editor_requested() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and _ui_panels != null:
		_ui_panels.open_preferences_panel(settings)


func _on_preferences_applied(prefs: Dictionary) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.walk_speed = prefs["walk_speed"]
	settings.mouse_sensitivity = prefs["mouse_sensitivity"]
	settings.eye_height = prefs["eye_height"]
	settings.step_height = prefs["step_height"]
	settings.fog_enabled = prefs["fog_enabled"]
	settings.save_settings()
	if _viewport_3d != null:
		_viewport_3d.apply_preferences()
		_viewport_3d.rebuild()
	if _ui_panels != null:
		_ui_panels.set_status("Preferences saved.")


## _on_gameplay_editor_requested() / _on_gameplay_applied(gameplay)
##
## M7 gameplay panel: opened with the level's current gameplay section;
## Apply commits through ToolSystem (one undo step).
func _on_gameplay_editor_requested() -> void:
	if _ui_panels != null:
		_ui_panels.open_gameplay_panel(level_data.gameplay)


func _on_gameplay_applied(gameplay: Dictionary) -> void:
	if _tool_system != null:
		_tool_system.commit_gameplay(gameplay)
		if _ui_panels != null:
			_ui_panels.set_status("Gameplay updated.")


## Play-test gameplay runtime signals (M7): messages to the status line,
## events to the debug panel's gameplay log, register watch refreshes on
## change.
func _on_gameplay_message(text: String) -> void:
	if _ui_panels != null:
		_ui_panels.set_status(text)


func _on_gameplay_event(text: String) -> void:
	if _ui_panels != null:
		_ui_panels.log_gameplay_event(text)


func _on_gameplay_registers_changed() -> void:
	if _ui_panels == null or _viewport_3d == null:
		return
	var gameplay := _viewport_3d.get_gameplay()
	if gameplay != null:
		_ui_panels.set_register_watch(gameplay.get_watch())


## _on_gameplay_warp(link)
##
## Warp action: loads the linked level (file resolved relative to the
## current level's directory) and restarts the play-test in it — the
## theaters.txt descendant, live in play-test (GCS kept warps inert in
## test mode; the editor can do better). A missing target is a debug-log
## entry, never a crash.
func _on_gameplay_warp(link: Dictionary) -> void:
	var file := str(link.get("file", ""))
	if _current_path.is_empty():
		_on_gameplay_event("warp to '%s' ignored: level has no file on disk" % file)
		if _ui_panels != null:
			_ui_panels.set_status("Warp ignored: save the level first.")
		return
	var path := (_current_path.get_base_dir() + "/" + file).simplify_path()
	if not FileAccess.file_exists(path):
		_on_gameplay_event("warp target missing: %s" % file)
		if _ui_panels != null:
			_ui_panels.set_status("Warp target not found: " + file)
		return
	var entry: Array = link.get("entry", [])
	open_level(path)
	if _viewport_3d != null:
		if not entry.is_empty():
			_viewport_3d.spawn_player_at(entry)
		_viewport_3d.restart_playtest()
	if _ui_panels != null:
		_ui_panels.set_status("Warped to: " + file)


func _on_brush_type_selected(type: String) -> void:
	if _tool_system != null:
		_tool_system.set_brush_type(type)
		_tool_system.set_object_mode(true)
		_update_brush_status()


func _on_brush_art_requested() -> void:
	if _ui_panels != null:
		_picker_brush_mode = true
		_picker_sky_mode = false
		_ui_panels.open_texture_picker()


func _on_debug_place_objects() -> void:
	if _tool_system != null:
		_tool_system.debug_place_test_set()
		if _ui_panels != null:
			_ui_panels.set_status("Test object set placed.")


## _on_debug_import_fixture()
##
## Debug-panel command: import the bundled DOS 1.3 fixture pair. Debug
## commands skip the confirm dialog (same as fixture loads).
func _on_debug_import_fixture() -> void:
	_on_import_confirmed("res://Tests/Fixtures/UNIV0.TXT")


## _on_debug_cycle_sky()
##
## Debug command (F11): toggles the level's sky between flat and a
## horizon strip (SOBJ_LIB/SKYSIDE). Goes through commit_environment, so
## it is an ordinary undoable edit.
func _on_debug_cycle_sky() -> void:
	if _tool_system == null or level_data == null:
		return
	var env := level_data.environment.duplicate(true)
	var sky: Dictionary = env.get("sky", {"mode": "flat", "color": "#202830", "strip": ""})
	if str(sky.get("mode", "flat")) == "horizon_strip":
		sky["mode"] = "flat"
		if _ui_panels != null:
			_ui_panels.set_status("Sky: flat")
	else:
		sky["mode"] = "horizon_strip"
		sky["strip"] = "SOBJ_LIB/SKYSIDE"
		if _ui_panels != null:
			_ui_panels.set_status("Sky: horizon strip (SOBJ_LIB/SKYSIDE)")
	env["sky"] = sky
	_tool_system.commit_environment(env)


## _on_import_confirmed(univ_path)
##
## M5 destructive-confirmed import: reads univ + sibling objdef (same
## level number), expands objdef "include" lines against the filesystem,
## runs the importer, and REPLACES the level. Outside the undo stack per
## charter (imports are confirmed destructive ops). Any read failure
## leaves the current level untouched.
func _on_import_confirmed(univ_path: String) -> void:
	var univ_text := FileAccess.get_file_as_string(univ_path)
	if univ_text.is_empty() and FileAccess.get_open_error() != OK:
		_report_error("Could not read file: " + univ_path)
		return
	var objdef_path := _derive_objdef_path(univ_path)
	var objdef_text := FileAccess.get_file_as_string(objdef_path)
	if objdef_text.is_empty() and FileAccess.get_open_error() != OK:
		_report_error("Could not read objdef sibling: " + objdef_path)
		return
	var expanded := _expand_includes(objdef_text, objdef_path)
	var result := GCSImporter.import_level(
		univ_text, str(expanded["text"]), univ_path.get_file(), expanded["notes"]
	)
	level_data = result["level"]
	_current_path = ""
	_undo_stack.clear()
	_rebind_level_data()
	if _ui_panels != null:
		var report: Dictionary = result["report"]
		_ui_panels.set_import_report(report)
		_ui_panels.set_status("Imported %d objects (%d skipped) from %s" % [
			int(report["imported"]), (report["skipped"] as Array).size(), univ_path.get_file(),
		])


## _derive_objdef_path(univ_path) -> String
##
## univ0.txt -> objdef0.txt in the same directory (the ?? digits are the
## level number and match across the pair).
func _derive_objdef_path(univ_path: String) -> String:
	var re := RegEx.create_from_string("(?i)^univ")
	var file := re.sub(univ_path.get_file(), "objdef")
	return univ_path.get_base_dir() + "/" + file


## _expand_includes(objdef_text, objdef_path) -> Dictionary
##
## One-pass textual expansion of objdef "include <dos path>" lines: found
## files are inlined after the directive, missing ones become a report
## note. GCS include paths are relative to the objdef file's directory.
## One pass only — includes-of-includes are not followed.
func _expand_includes(objdef_text: String, objdef_path: String) -> Dictionary:
	var notes: Array[String] = []
	var out: Array[String] = []
	var re := RegEx.create_from_string("(?i)^\\s*include\\s+(.+?)$")
	var base_dir := objdef_path.get_base_dir()
	for line in objdef_text.split("\n"):
		out.append(line)
		var match := re.search(line.strip_edges())
		if match == null:
			continue
		var rel := match.get_string(1).strip_edges().replace("\\", "/")
		var inc_path := (base_dir + "/" + rel).simplify_path()
		var inc_text := FileAccess.get_file_as_string(inc_path)
		if inc_text.is_empty() and FileAccess.get_open_error() != OK:
			notes.append("include not found: %s (objects it defines are skipped)" % rel)
		else:
			out.append("; ---- begin include: %s ----" % rel)
			out.append(inc_text)
			out.append("; ---- end include: %s ----" % rel)
			notes.append("include loaded: %s" % rel)
	return {"text": "\n".join(out), "notes": notes}


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
		"platforms": _duplicate_platforms(level_data.platforms),
		"environment": level_data.environment.duplicate(true),
		"gameplay": level_data.gameplay.duplicate(true),
	})


## _duplicate_platforms(platforms) -> Array[PlatformData]
##
## Deep copy for undo snapshots: PlatformData is a Resource and
## Resource.duplicate() mishandles its typed vertex array, so the
## explicit clone() is used.
func _duplicate_platforms(platforms: Array) -> Array[PlatformData]:
	var out: Array[PlatformData] = []
	for p in platforms:
		out.append((p as PlatformData).clone())
	return out


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
	level_data.platforms = _duplicate_platforms(snapshot.get("platforms", []))
	level_data.environment = snapshot.get("environment", level_data.environment).duplicate(true)
	level_data.gameplay = snapshot.get("gameplay", level_data.gameplay).duplicate(true)
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
		_ui_panels.set_import_report({})
		_ui_panels.set_status("Level cleared.")


func _rebind_level_data() -> void:
	level_data.level_changed.connect(_on_level_data_changed)
	if _canvas_2d != null:
		_canvas_2d.set_level_data(level_data)
		# Frame the (possibly far-off-origin, e.g. GCS import) content so
		# the 2D view never opens onto empty space.
		_canvas_2d.frame_level()
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
			_ui_panels.set_environment_notes(stats.get("environment_notes", []))
			_ui_panels.set_gameplay_notes(stats.get("gameplay_notes", []))
	if _ui_panels != null and level_data != null:
		_ui_panels.set_debug_flags(
			level_data.flagged_sectors, level_data.flagged_walls, level_data.flagged_objects,
			level_data.flagged_platforms
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
