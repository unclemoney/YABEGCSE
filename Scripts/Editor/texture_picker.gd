class_name TexturePicker
extends Control

## TexturePicker
##
## Searchable list of every texture in ArtLibrary/ (library-relative
## names, via ArtCache.scan). Picked names are emitted upward; the picker
## never touches LevelData. Follows the DebugPanel construction pattern
## (full-rect overlay with keep_offsets=true, centered PanelContainer).

signal texture_picked(name: String)
signal closed

var _panel: PanelContainer
var _filter: LineEdit
var _list: ItemList
var _names: Array[String] = []


## _ready()
##
## Side-effects: sets modal input blocking and builds the UI. The
## full-rect anchor preset is applied by the parent (UIPanels) with
## keep_offsets=true.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_ui()


## open()
##
## Shows the picker and (re)scans the library on first use.
func open() -> void:
	visible = true
	_refresh_list()
	if _filter != null:
		_filter.text = ""
		_filter.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()


func _refresh_list() -> void:
	var needle := ""
	if _filter != null:
		needle = _filter.text.to_lower()
	_names.clear()
	for tex_name in ArtCache.scan():
		if needle.is_empty() or tex_name.to_lower().contains(needle):
			_names.append(tex_name)
	_list.clear()
	for tex_name in _names:
		_list.add_item(tex_name)


func _pick_selected() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	texture_picked.emit(_names[selected[0]])
	_close()


func _close() -> void:
	visible = false
	closed.emit()


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

	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter textures..."
	_filter.text_changed.connect(func(_text: String) -> void: _refresh_list())
	vbox.add_child(_filter)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_index: int) -> void: _pick_selected())
	vbox.add_child(_list)
	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_pick_selected)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close)
	buttons.add_child(cancel)
