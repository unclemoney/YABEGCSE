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
signal fixture_load_requested(path: String)

var _mode_label: Label
var _status_label: Label
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _clear_dialog: ConfirmationDialog
var _debug_panel: DebugPanel

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


func set_status(text: String) -> void:
	_message = text
	_refresh_status()


func set_cursor_info(text: String) -> void:
	_cursor_text = text
	_refresh_status()


func toggle_debug_panel() -> void:
	_debug_panel.toggle()


## set_debug_flags(flagged_sectors, flagged_walls)
##
## Pass-through to the debug panel; called down by EditorController after
## every validation pass.
func set_debug_flags(flagged_sectors: Dictionary, flagged_walls: Dictionary) -> void:
	if _debug_panel != null:
		_debug_panel.set_flags(flagged_sectors, flagged_walls)


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
	file_popup.id_pressed.connect(_on_file_menu_id_pressed)
	top_bar.add_child(file_menu)

	var edit_menu := MenuButton.new()
	edit_menu.text = "Edit"
	var edit_popup := edit_menu.get_popup()
	edit_popup.add_item("Clear Level", 0)
	edit_popup.id_pressed.connect(_on_edit_menu_id_pressed)
	top_bar.add_child(edit_menu)

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

	_debug_panel = DebugPanel.new()
	_debug_panel.visible = false
	add_child(_debug_panel)
	_debug_panel.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	_debug_panel.fixture_load_requested.connect(
		func(path: String) -> void: fixture_load_requested.emit(path)
	)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		0:
			new_requested.emit()
		1:
			_open_dialog.popup_centered()
		2:
			_save_dialog.popup_centered()


func _on_edit_menu_id_pressed(id: int) -> void:
	match id:
		0:
			_clear_dialog.popup_centered()
