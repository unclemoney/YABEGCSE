class_name UIPanels
extends CanvasLayer

## UIPanels
##
## Menu bar, mode indicator, status line, file dialogs, confirm dialogs,
## debug panel. Emits signals upward (EditorController); never touches
## LevelData. UI is built dynamically in _build_ui().

signal new_requested
signal open_path_selected(path: String)
signal save_path_selected(path: String)
signal clear_confirmed
signal import_confirmed(path: String)
signal fixture_load_requested(path: String)
signal texture_picked(name: String)
signal texture_pick_requested
signal texture_picker_closed
signal brush_type_selected(type: String)
signal brush_art_requested
signal debug_place_objects
signal debug_import_fixture
signal environment_editor_requested
signal environment_applied(env: Dictionary)
signal sky_strip_pick_requested
signal preferences_editor_requested
signal preferences_applied(prefs: Dictionary)
signal gameplay_editor_requested
signal gameplay_applied(gameplay: Dictionary)
## Any modal panel closed (picker, environment, preferences): 3D mode
## re-captures the mouse.
signal panel_closed

var _mode_label: Label
var _status_label: Label
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _clear_dialog: ConfirmationDialog
var _import_dialog: FileDialog
var _import_confirm: ConfirmationDialog
var _pending_import := ""
var _debug_panel: DebugPanel
var _environment_panel: EnvironmentPanel
var _preferences_panel: PreferencesPanel
var _gameplay_panel: GameplayPanel
var _texture_picker: TexturePicker
var _crosshair: ColorRect

var _message := "YABEGCSE"
var _cursor_text := ""


## _ready()
##
## Side-effects: builds the full UI dynamically via _build_ui().
func _ready() -> void:
	_build_ui()


func set_mode(mode: EditorController.Mode) -> void:
	if mode == EditorController.Mode.MODE_2D:
		_mode_label.text = "  Mode: 2D"
	else:
		_mode_label.text = "  Mode: 3D"
	if _crosshair != null:
		_crosshair.visible = mode == EditorController.Mode.MODE_3D


func set_status(text: String) -> void:
	_message = text
	_refresh_status()


func set_cursor_info(text: String) -> void:
	_cursor_text = text
	_refresh_status()


func toggle_debug_panel() -> void:
	_debug_panel.toggle()


## set_debug_flags(flagged_sectors, flagged_walls, flagged_objects)
##
## Pass-through to the debug panel; called down by EditorController after
## every validation pass.
func set_debug_flags(flagged_sectors: Dictionary, flagged_walls: Dictionary, flagged_objects: Dictionary = {}) -> void:
	if _debug_panel != null:
		_debug_panel.set_flags(flagged_sectors, flagged_walls, flagged_objects)


## set_missing_textures(names)
##
## Pass-through to the debug panel: unresolved art references from the
## last 3D mesh rebuild.
func set_missing_textures(names: Array) -> void:
	if _debug_panel != null:
		_debug_panel.set_missing_textures(names)


## set_import_report(report)
##
## Pass-through to the debug panel: the GCS importer's skipped /
## unreconstructable list. Empty dict clears the block.
func set_import_report(report: Dictionary) -> void:
	if _debug_panel != null:
		_debug_panel.set_import_report(report)


## open_texture_picker()
##
## Releases the mouse so the picker is clickable; texture_picker_closed
## tells the controller when to re-capture (3D mode).
func open_texture_picker() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_texture_picker.open()


## open_environment_panel(env) / open_preferences_panel(settings)
##
## M6: called down by EditorController with the current values (the
## panels never touch LevelData or GameSettings themselves).
func open_environment_panel(env: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_environment_panel.open_with(env)


func open_preferences_panel(settings: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_preferences_panel.open_with(settings)


## open_gameplay_panel(gameplay)
##
## M7: called down by EditorController with the level's raw gameplay
## section (the panel never touches LevelData itself).
func open_gameplay_panel(gameplay: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_gameplay_panel.open_with(gameplay)


## set_sky_strip_art(base_name)
##
## Routes a sky-strip TexturePicker result into the environment panel.
func set_sky_strip_art(base_name: String) -> void:
	_environment_panel.set_strip_art(base_name)


## set_environment_notes(notes)
##
## Pass-through to the debug panel: environment fields that fell back to
## defaults (EnvironmentOps).
func set_environment_notes(notes: Array) -> void:
	if _debug_panel != null:
		_debug_panel.set_environment_notes(notes)


## set_gameplay_notes(notes)
##
## Pass-through to the debug panel: gameplay entries skipped or defaulted
## by GameplayOps (M7 tolerate + flag).
func set_gameplay_notes(notes: Array) -> void:
	if _debug_panel != null:
		_debug_panel.set_gameplay_notes(notes)


## log_gameplay_event(text) / set_register_watch(text)
##
## Pass-throughs to the debug panel: the play-test gameplay event log and
## the live register watch (M7).
func log_gameplay_event(text: String) -> void:
	if _debug_panel != null:
		_debug_panel.log_gameplay_event(text)


func set_register_watch(text: String) -> void:
	if _debug_panel != null:
		_debug_panel.set_register_watch(text)


func _refresh_status() -> void:
	if _status_label == null:
		return
	if _cursor_text.is_empty():
		_status_label.text = _message
	else:
		_status_label.text = "%s    |    %s" % [_message, _cursor_text]


func _build_ui() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)

	var file_menu := MenuButton.new()
	file_menu.text = "File"
	var file_popup := file_menu.get_popup()
	file_popup.add_item("New", 0)
	file_popup.add_item("Open...", 1)
	file_popup.add_item("Save As...", 2)
	file_popup.add_item("Import GCS Level...", 3)
	file_popup.id_pressed.connect(_on_file_menu_id_pressed)
	top_bar.add_child(file_menu)

	var edit_menu := MenuButton.new()
	edit_menu.text = "Edit"
	var edit_popup := edit_menu.get_popup()
	edit_popup.add_item("Clear Level", 0)
	edit_popup.add_item("Environment...", 1)
	edit_popup.add_item("Preferences...", 2)
	edit_popup.add_item("Gameplay...", 3)
	edit_popup.id_pressed.connect(_on_edit_menu_id_pressed)
	top_bar.add_child(edit_menu)

	# M4 object brush: type picker + art picker (opens the TexturePicker
	# in brush mode via brush_art_requested).
	var object_menu := MenuButton.new()
	object_menu.text = "Object"
	var object_popup := object_menu.get_popup()
	for i in range(ObjectOps.TYPES.size()):
		object_popup.add_item(ObjectOps.TYPES[i], i)
	object_popup.add_separator()
	object_popup.add_item("Art...", 100)
	object_popup.id_pressed.connect(_on_object_menu_id_pressed)
	top_bar.add_child(object_menu)

	_mode_label = Label.new()
	_mode_label.text = "  Mode: 2D"
	top_bar.add_child(_mode_label)

	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(_status_label)
	_refresh_status()

	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.size = Vector2i(600, 400)
	_open_dialog.add_filter("*.json", "YABEGCSE levels")
	_open_dialog.file_selected.connect(
		func(path: String) -> void: open_path_selected.emit(path)
	)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.size = Vector2i(600, 400)
	_save_dialog.add_filter("*.json", "YABEGCSE levels")
	_save_dialog.file_selected.connect(
		func(path: String) -> void: save_path_selected.emit(path)
	)
	add_child(_save_dialog)

	_clear_dialog = ConfirmationDialog.new()
	_clear_dialog.dialog_text = "Clear the entire level? This is destructive and cannot be undone."
	_clear_dialog.ok_button_text = "Clear"
	_clear_dialog.confirmed.connect(func() -> void: clear_confirmed.emit())
	add_child(_clear_dialog)

	# M5: GCS import. Picking the univ??.txt arms a destructive-confirm
	# dialog; confirming emits import_confirmed with the chosen path.
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.size = Vector2i(600, 400)
	_import_dialog.add_filter("univ*.txt", "GCS level (univ??.txt)")
	_import_dialog.file_selected.connect(_on_import_file_selected)
	add_child(_import_dialog)

	_import_confirm = ConfirmationDialog.new()
	_import_confirm.dialog_text = "Importing a GCS level replaces the current level and cannot be undone."
	_import_confirm.ok_button_text = "Import"
	_import_confirm.confirmed.connect(func() -> void: import_confirmed.emit(_pending_import))
	add_child(_import_confirm)

	_debug_panel = DebugPanel.new()
	_debug_panel.visible = false
	add_child(_debug_panel)
	_debug_panel.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_debug_panel.fixture_load_requested.connect(
		func(path: String) -> void: fixture_load_requested.emit(path)
	)
	_debug_panel.texture_pick_requested.connect(
		func() -> void: texture_pick_requested.emit()
	)
	_debug_panel.debug_place_objects.connect(
		func() -> void: debug_place_objects.emit()
	)
	_debug_panel.debug_import_fixture.connect(
		func() -> void: debug_import_fixture.emit()
	)
	_debug_panel.environment_editor_requested.connect(
		func() -> void: environment_editor_requested.emit()
	)
	_debug_panel.preferences_editor_requested.connect(
		func() -> void: preferences_editor_requested.emit()
	)
	_debug_panel.gameplay_editor_requested.connect(
		func() -> void: gameplay_editor_requested.emit()
	)

	# M6 panels, hosted here; created before the texture picker so the
	# picker (sky-strip art pick) draws on top of the environment panel.
	_environment_panel = EnvironmentPanel.new()
	_environment_panel.visible = false
	add_child(_environment_panel)
	_environment_panel.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_environment_panel.environment_applied.connect(
		func(env: Dictionary) -> void: environment_applied.emit(env)
	)
	_environment_panel.strip_pick_requested.connect(
		func() -> void: sky_strip_pick_requested.emit()
	)
	_environment_panel.closed.connect(func() -> void: panel_closed.emit())

	_preferences_panel = PreferencesPanel.new()
	_preferences_panel.visible = false
	add_child(_preferences_panel)
	_preferences_panel.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_preferences_panel.preferences_applied.connect(
		func(prefs: Dictionary) -> void: preferences_applied.emit(prefs)
	)
	_preferences_panel.closed.connect(func() -> void: panel_closed.emit())

	# M7 gameplay panel, hosted like the other modals.
	_gameplay_panel = GameplayPanel.new()
	_gameplay_panel.visible = false
	add_child(_gameplay_panel)
	_gameplay_panel.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_gameplay_panel.gameplay_applied.connect(
		func(gameplay: Dictionary) -> void: gameplay_applied.emit(gameplay)
	)
	_gameplay_panel.closed.connect(func() -> void: panel_closed.emit())

	_texture_picker = TexturePicker.new()
	_texture_picker.visible = false
	add_child(_texture_picker)
	_texture_picker.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_texture_picker.texture_picked.connect(
		func(tex_name: String) -> void: texture_picked.emit(tex_name)
	)
	_texture_picker.closed.connect(func() -> void: texture_picker_closed.emit())

	# Crosshair: the 3D edit cursor (mouse is captured in 3D mode).
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1.0, 1.0, 1.0, 0.8)
	_crosshair.custom_minimum_size = Vector2(5, 5)
	_crosshair.size = Vector2(5, 5)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.visible = false
	add_child(_crosshair)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER, true)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		0:
			new_requested.emit()
		1:
			_open_dialog.popup_centered()
		2:
			_save_dialog.popup_centered()
		3:
			_import_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	_pending_import = path
	_import_confirm.popup_centered()


func _on_edit_menu_id_pressed(id: int) -> void:
	match id:
		0:
			_clear_dialog.popup_centered()
		1:
			environment_editor_requested.emit()
		2:
			preferences_editor_requested.emit()
		3:
			gameplay_editor_requested.emit()


func _on_object_menu_id_pressed(id: int) -> void:
	if id == 100:
		brush_art_requested.emit()
	elif id >= 0 and id < ObjectOps.TYPES.size():
		brush_type_selected.emit(ObjectOps.TYPES[id])
