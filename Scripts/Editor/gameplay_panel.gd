class_name GameplayPanel
extends Control

## GameplayPanel (M7)
##
## Modal editor for the level's v0 `gameplay` section: music (WAV base
## name), universe-register initial values + labels, level-to-level links,
## triggers and scripts. Built dynamically per the panel construction
## standards. The panel does NO semantic validation — Apply emits the raw
## field values upward; malformed entries are tolerated and flagged by
## GameplayOps (debug panel notes), never crash.
##
## Design call: music / registers / links get structured row editors;
## triggers and scripts are edited as JSON text (with template buttons) —
## a fully structured trigger editor is Blender-disease scope, and the
## envelope treats hand-editability as a debugging convenience. Apply
## JSON.parses the two text areas; a parse error keeps the panel open and
## never touches LevelData.
##
## Layout: the panel is clamped to the viewport minus a 20 px margin on
## all sides (600x360 at the 640x400 internal viewport). The header row
## (title + X close button) sits outside the ScrollContainer so it never
## scrolls away; the content scrolls. Escape, X and Cancel all close via
## the same animated path. Per the Panel Construction Standards the
## open/close tweens animate position and modulate only — never scale.
## z_index 100: above the gameplay view, below the windowed modal dialogs
## (FileDialog/ConfirmationDialog) and the TexturePicker (later sibling).

signal gameplay_applied(gameplay: Dictionary)
## Emitted on Apply and Cancel so the controller can re-capture the mouse.
signal closed

const VIEWPORT_MARGIN := 20.0
const MAX_PANEL_SIZE := Vector2(600, 520)  # desired size; clamped to the viewport
const ANIM_OFFSET := 20.0  # px slide for open/close tweens (keeps the panel on-screen)

const TRIGGER_TEMPLATE := """[
	{
		"id": "example",
		"event": "enter_sector",
		"sector": 0,
		"once": true,
		"condition": {"reg": 5, "op": "eq", "value": 1},
		"actions": [
			{"do": "message", "text": "Hello"},
			{"do": "set_register", "reg": 5, "value": 2}
		]
	}
]"""
const SCRIPT_TEMPLATE := """[
	{
		"id": "example_script",
		"steps": [
			{"do": "message", "text": "Script ran"},
			{"do": "add_register", "reg": 9, "value": 1}
		]
	}
]"""

var _music_enabled: CheckBox
var _music_track: LineEdit
var _register_list: VBoxContainer
var _link_list: VBoxContainer
var _triggers_edit: TextEdit
var _scripts_edit: TextEdit
var _error: Label
var _overlay: ColorRect
var _panel: PanelContainer
var _tween: Tween
var _closing := false

var _register_rows: Array = []  # {"box", "reg", "value", "name"}
var _link_rows: Array = []  # {"box", "id", "file", "x", "y", "z", "theta"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_ui()


## open_with(gameplay)
##
## Fills the fields from the level's current gameplay section and shows
## the panel. Called down by UIPanels.
func open_with(gameplay: Dictionary) -> void:
	var music: Dictionary = gameplay.get("music", {})
	_music_enabled.button_pressed = bool(music.get("enabled", false))
	_music_track.text = str(music.get("track", ""))
	_clear_rows(_register_rows, _register_list)
	_clear_rows(_link_rows, _link_list)
	var registers: Dictionary = gameplay.get("registers", {})
	var initial: Dictionary = registers.get("initial", {})
	var names: Dictionary = registers.get("names", {})
	for key in initial:
		_add_register_row(int(str(key)), int(initial[key]), str(names.get(key, "")))
	var links: Array = gameplay.get("links", [])
	for link in links:
		if link is Dictionary:
			_add_link_row(link)
	_error.text = ""
	var triggers: Variant = gameplay.get("triggers", [])
	_triggers_edit.text = JSON.stringify(triggers, "\t") if triggers is Array else "[]"
	var scripts: Variant = gameplay.get("scripts", [])
	_scripts_edit.text = JSON.stringify(scripts, "\t") if scripts is Array else "[]"
	_show_animated()


## _unhandled_input(event)
##
## Escape closes the panel from anywhere — even when the close button is
## unreachable (focused JSON editor, scrolled content).
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_request_close()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER, true)
	_layout_panel()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.14, 0.98)
	style.border_color = Color(0.3, 0.25, 0.35, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(20)
	style.corner_detail = 8
	_panel.add_theme_stylebox_override("panel", style)

	# Fixed frame: the header (title + close button) never scrolls away;
	# only the ScrollContainer content below it moves.
	var body := VBoxContainer.new()
	_panel.add_child(body)

	var header := HBoxContainer.new()
	header.name = "Header"
	body.add_child(header)
	var title := Label.new()
	title.text = "Gameplay (per level)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.tooltip_text = "Close (Esc)"
	close_button.pressed.connect(_request_close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_music_enabled = CheckBox.new()
	_music_enabled.text = "Music enabled"
	vbox.add_child(_music_enabled)
	_music_track = _row_edit(vbox, "Music track (WAV base)", "")

	vbox.add_child(_section_label("Registers (initial values + labels)"))
	_register_list = VBoxContainer.new()
	vbox.add_child(_register_list)
	var add_reg := Button.new()
	add_reg.text = "Add register"
	add_reg.pressed.connect(func() -> void: _add_register_row(1, 0, ""))
	vbox.add_child(add_reg)

	vbox.add_child(_section_label("Links (level-to-level)"))
	_link_list = VBoxContainer.new()
	vbox.add_child(_link_list)
	var add_link := Button.new()
	add_link.text = "Add link"
	add_link.pressed.connect(func() -> void: _add_link_row({}))
	vbox.add_child(add_link)

	vbox.add_child(_section_label("Triggers (JSON array — events: level_start, enter_sector, near_object, timer)"))
	_triggers_edit = _json_area(vbox)
	var trig_tpl := Button.new()
	trig_tpl.text = "Insert trigger template"
	trig_tpl.pressed.connect(func() -> void: _triggers_edit.text = TRIGGER_TEMPLATE)
	vbox.add_child(trig_tpl)

	vbox.add_child(_section_label("Scripts (JSON array — named action lists for run_script)"))
	_scripts_edit = _json_area(vbox)
	var script_tpl := Button.new()
	script_tpl.text = "Insert script template"
	script_tpl.pressed.connect(func() -> void: _scripts_edit.text = SCRIPT_TEMPLATE)
	vbox.add_child(script_tpl)

	_error = Label.new()
	_error.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_error)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_on_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_request_close)
	buttons.add_child(cancel)


## _layout_panel()
##
## Clamps the panel's minimum size and actual size to the viewport minus
## VIEWPORT_MARGIN on every side (600x360 at the 640x400 internal
## viewport) and re-centers it. Called at build time and on every open,
## so window resizes (stretch aspect "expand") can never push the panel
## — or its close button — off-screen.
func _layout_panel() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 64.0 or vp.y < 64.0:
		vp = Vector2(640, 400)  # not in the tree yet; assume the design viewport
	var size := Vector2(
		minf(MAX_PANEL_SIZE.x, vp.x - VIEWPORT_MARGIN * 2.0),
		minf(MAX_PANEL_SIZE.y, vp.y - VIEWPORT_MARGIN * 2.0)
	)
	_panel.custom_minimum_size = size
	_panel.offset_left = -size.x * 0.5
	_panel.offset_top = -size.y * 0.5
	_panel.offset_right = size.x * 0.5
	_panel.offset_bottom = size.y * 0.5


## _show_animated()
##
## Opens the panel: clamp to the viewport, then slide/fade in (position +
## modulate only — scaling a PanelContainer would stretch its content).
func _show_animated() -> void:
	_closing = false
	_layout_panel()
	visible = true
	if _tween != null:
		_tween.kill()
	var home := (get_viewport_rect().size - _panel.custom_minimum_size) * 0.5
	_panel.position = home - Vector2(0, ANIM_OFFSET)
	_panel.modulate.a = 0.0
	_overlay.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_panel, "position", home, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_panel, "modulate:a", 1.0, 0.2)
	_tween.parallel().tween_property(_overlay, "modulate:a", 1.0, 0.2)


## _request_close()
##
## The single close path (X button, Cancel, Escape): exit tween downward
## + fade on panel and overlay, then hide and emit closed so the
## controller can re-capture the mouse.
func _request_close() -> void:
	if _closing:
		return
	_closing = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "position", _panel.position + Vector2(0, ANIM_OFFSET), 0.2)
	_tween.parallel().tween_property(_panel, "modulate:a", 0.0, 0.2)
	_tween.parallel().tween_property(_overlay, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	# Restore full opacity for the next open (position is reset by
	# _layout_panel via the anchor offsets).
	_panel.modulate.a = 1.0
	_overlay.modulate.a = 1.0
	closed.emit()


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.9))
	return label


func _json_area(parent: Control) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 110)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit


func _row_edit(parent: Control, label_text: String, initial: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = initial
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _add_register_row(reg: int, value: int, label_text: String) -> void:
	var row := HBoxContainer.new()
	_register_list.add_child(row)
	var reg_spin := SpinBox.new()
	reg_spin.min_value = 1
	reg_spin.max_value = 255
	reg_spin.value = reg
	row.add_child(reg_spin)
	var value_spin := SpinBox.new()
	value_spin.min_value = 0
	value_spin.max_value = 255
	value_spin.value = value
	row.add_child(value_spin)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "label (optional)"
	name_edit.text = label_text
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	var remove := Button.new()
	remove.text = "X"
	row.add_child(remove)
	var record := {"box": row, "reg": reg_spin, "value": value_spin, "name": name_edit}
	remove.pressed.connect(func() -> void:
		_register_rows.erase(record)
		row.queue_free()
	)
	_register_rows.append(record)


func _add_link_row(link: Dictionary) -> void:
	var row := HBoxContainer.new()
	_link_list.add_child(row)
	var id_edit := LineEdit.new()
	id_edit.placeholder_text = "id"
	id_edit.text = str(link.get("id", ""))
	id_edit.custom_minimum_size = Vector2(80, 0)
	row.add_child(id_edit)
	var file_edit := LineEdit.new()
	file_edit.placeholder_text = "level.json"
	file_edit.text = str(link.get("file", ""))
	file_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(file_edit)
	var entry: Array = link.get("entry", [])
	var spins: Array[SpinBox] = []
	var keys: Array[String] = ["x", "y", "z", "theta"]
	for k in range(4):
		var spin := SpinBox.new()
		spin.min_value = -100000.0
		spin.max_value = 100000.0
		spin.step = 1.0
		spin.value = float(entry[k]) if entry.size() >= 4 else 0.0
		spin.tooltip_text = keys[k]
		spin.custom_minimum_size = Vector2(70, 0)
		row.add_child(spin)
		spins.append(spin)
	var remove := Button.new()
	remove.text = "X"
	row.add_child(remove)
	var record := {
		"box": row, "id": id_edit, "file": file_edit,
		"x": spins[0], "y": spins[1], "z": spins[2], "theta": spins[3],
	}
	remove.pressed.connect(func() -> void:
		_link_rows.erase(record)
		row.queue_free()
	)
	_link_rows.append(record)


func _clear_rows(rows: Array, list: VBoxContainer) -> void:
	for record in rows:
		(record["box"] as HBoxContainer).queue_free()
	rows.clear()
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _on_apply() -> void:
	var triggers: Variant = _parse_json_array(_triggers_edit.text, "triggers")
	if triggers == null:
		return
	var scripts: Variant = _parse_json_array(_scripts_edit.text, "scripts")
	if scripts == null:
		return
	var initial := {}
	var names := {}
	for record in _register_rows:
		var reg := int((record["reg"] as SpinBox).value)
		initial[str(reg)] = int((record["value"] as SpinBox).value)
		var label_text: String = (record["name"] as LineEdit).text.strip_edges()
		if not label_text.is_empty():
			names[str(reg)] = label_text
	var links: Array = []
	for record in _link_rows:
		var id := (record["id"] as LineEdit).text.strip_edges()
		var file := (record["file"] as LineEdit).text.strip_edges()
		if id.is_empty() or file.is_empty():
			continue
		links.append({
			"id": id,
			"file": file,
			"entry": [
				(record["x"] as SpinBox).value, (record["y"] as SpinBox).value,
				(record["z"] as SpinBox).value, (record["theta"] as SpinBox).value,
			],
		})
	gameplay_applied.emit({
		"registers": {"initial": initial, "names": names},
		"triggers": triggers,
		"scripts": scripts,
		"music": {
			"enabled": _music_enabled.button_pressed,
			"track": _music_track.text.strip_edges().trim_suffix(".wav"),
		},
		"links": links,
	})
	# Apply commits first; the panel then takes the standard animated
	# close path (same as X / Cancel / Escape).
	_request_close()


## _parse_json_array(text, field) -> Array (null on error; reported)
##
## The panel's only gate: syntactically bad JSON never reaches LevelData.
## Semantic validation stays with GameplayOps.
func _parse_json_array(text: String, field: String) -> Variant:
	if text.strip_edges().is_empty():
		return []
	var json := JSON.new()
	if json.parse(text) != OK:
		_error.text = "%s: invalid JSON at line %d: %s" % [
			field, json.get_error_line(), json.get_error_message(),
		]
		return null
	if not json.data is Array:
		_error.text = "%s: must be a JSON array" % field
		return null
	_error.text = ""
	return json.data
