class_name DebugPanel
extends Control

## DebugPanel (F12)
##
## Tolerate + flag: invalid sectors and unresolved art references surface
## here, plus debug commands (fixture loading) per the skill's rule that
## new features ship with debug-panel access.

signal fixture_load_requested(path: String)
signal texture_pick_requested
signal debug_place_objects
signal debug_import_fixture
signal environment_editor_requested
signal preferences_editor_requested
signal gameplay_editor_requested
## Debug command: advance the 2D tool cycle (Sector Draw -> Vertex Edit
## -> Wall Select), same as pressing Tab on the canvas.
signal debug_cycle_tool

var _panel: PanelContainer
var _list: Label
var _missing_textures: Array = []
var _flags_text := ""
var _import_text := ""
var _environment_text := ""
var _gameplay_text := ""
var _gameplay_log: Array[String] = []
var _watch_text := ""
## Ring buffer for editor-side tool events (vertex/merge rejections).
var _editor_log: Array[String] = []

## Cap for the rendered import report so a chatty import can't blow up
## the panel layout.
const MAX_REPORT_LINES := 14
## Ring buffer size for the M7 gameplay event log.
const MAX_LOG_LINES := 8


## _ready()
##
## Side-effects: sets modal input blocking and builds the UI.
## Note: the full-rect anchor preset is applied by the parent (UIPanels)
## after add_child, with keep_offsets=true — set_anchors_preset's default
## (false) rewrites offsets to preserve the current (zero) size.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_ui()


func toggle() -> void:
	visible = not visible


## set_flags(flagged_sectors, flagged_walls, flagged_objects, flagged_platforms)
##
## One line per flagged sector/wall/object/platform with its reason.
## Annotations are computed by GeometryOps/ObjectOps.validate — this panel
## displays.
func set_flags(flagged_sectors: Dictionary, flagged_walls: Dictionary, flagged_objects: Dictionary = {}, flagged_platforms: Dictionary = {}) -> void:
	var lines: Array[String] = []
	for id in flagged_sectors:
		lines.append("Sector %d: %s" % [id, flagged_sectors[id]])
	for id in flagged_walls:
		lines.append("Wall %d: %s" % [id, flagged_walls[id]])
	for id in flagged_objects:
		lines.append("Object %d: %s" % [id, flagged_objects[id]])
	for id in flagged_platforms:
		lines.append("Platform %d: %s" % [id, flagged_platforms[id]])
	if lines.is_empty():
		_flags_text = "No flagged sectors, walls, objects or platforms."
	else:
		_flags_text = "\n".join(lines)
	_render()


## set_missing_textures(names)
##
## Unresolved art-library references from the last mesh build (envelope:
## unresolved references log to the debug panel).
func set_missing_textures(names: Array) -> void:
	_missing_textures = names
	_render()


## set_import_report(report)
##
## The GCS importer's report (meta.import_report shape): counts plus the
## skipped/unreconstructable list. Empty dict clears the block.
func set_import_report(report: Dictionary) -> void:
	if report.is_empty():
		_import_text = ""
		_render()
		return
	var lines: Array[String] = []
	lines.append("GCS import: %d imported, %d skipped" % [
		int(report.get("imported", 0)), (report.get("skipped", []) as Array).size(),
	])
	for line in report.get("notes", []):
		lines.append("note: %s" % _clip(str(line)))
	for line in report.get("skipped", []):
		lines.append("skip: %s" % _clip(str(line)))
	if lines.size() > MAX_REPORT_LINES:
		var hidden := lines.size() - MAX_REPORT_LINES
		lines = lines.slice(0, MAX_REPORT_LINES)
		lines.append("... and %d more (see meta.import_report in the saved file)" % hidden)
	_import_text = "\n".join(lines)
	_render()


## _clip(text) -> String
##
## Long report lines (DOS paths) would stretch the panel past the screen;
## truncate them. The full text is always in meta.import_report.
func _clip(text: String) -> String:
	if text.length() <= 80:
		return text
	return text.substr(0, 77) + "..."


## set_environment_notes(notes)
##
## M6: environment fields that fell back to defaults (EnvironmentOps).
## Recomputed on every level change; empty list clears the block.
func set_environment_notes(notes: Array) -> void:
	if notes.is_empty():
		_environment_text = ""
	else:
		var lines: Array[String] = []
		for note in notes:
			lines.append("env: %s" % _clip(str(note)))
		_environment_text = "\n".join(lines)
	_render()


## set_gameplay_notes(notes)
##
## M7: gameplay entries skipped or defaulted by GameplayOps. Recomputed
## on every level change; empty list clears the block.
func set_gameplay_notes(notes: Array) -> void:
	if notes.is_empty():
		_gameplay_text = ""
	else:
		var lines: Array[String] = []
		for note in notes:
			lines.append("gp: %s" % _clip(str(note)))
		_gameplay_text = "\n".join(lines)
	_render()


## log_gameplay_event(text)
##
## M7: play-test runtime events (fired triggers, warps, sounds, game
## over) — a small ring buffer, newest last.
func log_gameplay_event(text: String) -> void:
	_gameplay_log.append(_clip(text))
	while _gameplay_log.size() > MAX_LOG_LINES:
		_gameplay_log.remove_at(0)
	_render()


## set_register_watch(text)
##
## M7: the live nonzero-register readout during play-test ("" hides it).
func set_register_watch(text: String) -> void:
	_watch_text = text
	_render()


## log_editor_event(text)
##
## Editor-side tool events (e.g. "Invalid vertex move: wall crossing",
## "Wall merge failed: invalid geometry") — a small ring buffer, newest
## last, same shape as the gameplay log.
func log_editor_event(text: String) -> void:
	_editor_log.append(_clip(text))
	while _editor_log.size() > MAX_LOG_LINES:
		_editor_log.remove_at(0)
	_render()


func _render() -> void:
	if _list == null:
		return
	var text := _flags_text
	if not _editor_log.is_empty():
		text = "edit: " + "\nedit: ".join(_editor_log) + "\n" + text
	if not _environment_text.is_empty():
		text = _environment_text + "\n" + text
	if not _gameplay_text.is_empty():
		text = _gameplay_text + "\n" + text
	if not _gameplay_log.is_empty():
		text = "log: " + "\nlog: ".join(_gameplay_log) + "\n" + text
	if not _watch_text.is_empty():
		text = "regs: " + _watch_text + "\n" + text
	if not _import_text.is_empty():
		text = _import_text + "\n" + text
	if not _missing_textures.is_empty():
		text += "\nMissing textures: " + ", ".join(_missing_textures)
	_list.text = "Debug — " + text


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(460, 340)
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER, true)
	_panel.offset_left = -230
	_panel.offset_top = -170
	_panel.offset_right = 230
	_panel.offset_bottom = 170
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.14, 0.98)
	style.border_color = Color(0.3, 0.25, 0.35, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(20)
	style.corner_detail = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_list = Label.new()
	_list.text = "Debug — no flagged sectors or walls."
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_list)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var two_room := Button.new()
	two_room.text = "Load two-room fixture"
	two_room.pressed.connect(
		func() -> void: fixture_load_requested.emit("res://Tests/Fixtures/level_geometry_v0.json")
	)
	buttons.add_child(two_room)
	var corrupt := Button.new()
	corrupt.text = "Load corrupt fixture"
	corrupt.pressed.connect(
		func() -> void: fixture_load_requested.emit("res://Tests/Fixtures/level_corrupt_v0.json")
	)
	buttons.add_child(corrupt)
	var slopes := Button.new()
	slopes.text = "Load slope fixture"
	slopes.pressed.connect(
		func() -> void: fixture_load_requested.emit("res://Tests/Fixtures/level_slopes_v0.json")
	)
	buttons.add_child(slopes)
	var pick := Button.new()
	pick.text = "Pick texture..."
	pick.pressed.connect(func() -> void: texture_pick_requested.emit())
	buttons.add_child(pick)
	var objects := Button.new()
	objects.text = "Place test object set"
	objects.pressed.connect(func() -> void: debug_place_objects.emit())
	buttons.add_child(objects)
	var gcs := Button.new()
	gcs.text = "Import GCS fixture"
	gcs.pressed.connect(func() -> void: debug_import_fixture.emit())
	buttons.add_child(gcs)
	var env_fixture := Button.new()
	env_fixture.text = "Load env fixture"
	env_fixture.pressed.connect(
		func() -> void: fixture_load_requested.emit("res://Tests/Fixtures/level_environment_v0.json")
	)
	buttons.add_child(env_fixture)
	var env_edit := Button.new()
	env_edit.text = "Environment..."
	env_edit.pressed.connect(func() -> void: environment_editor_requested.emit())
	buttons.add_child(env_edit)
	var prefs := Button.new()
	prefs.text = "Preferences..."
	prefs.pressed.connect(func() -> void: preferences_editor_requested.emit())
	buttons.add_child(prefs)
	var gp_fixture := Button.new()
	gp_fixture.text = "Load gameplay fixture"
	gp_fixture.pressed.connect(
		func() -> void: fixture_load_requested.emit("res://Tests/Fixtures/level_gameplay_v0.json")
	)
	buttons.add_child(gp_fixture)
	var gp_edit := Button.new()
	gp_edit.text = "Gameplay..."
	gp_edit.pressed.connect(func() -> void: gameplay_editor_requested.emit())
	buttons.add_child(gp_edit)
	var cycle := Button.new()
	cycle.text = "Cycle 2D tool"
	cycle.pressed.connect(func() -> void: debug_cycle_tool.emit())
	buttons.add_child(cycle)
