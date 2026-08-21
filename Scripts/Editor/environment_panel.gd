class_name EnvironmentPanel
extends Control

## EnvironmentPanel (M6)
##
## Modal editor for the level's v0 `environment` section: fog
## (enabled/color/near/far), sky mode (flat | horizon strip + art pick),
## ambient, void behavior. Built dynamically per the panel construction
## standards. The panel does NO validation — Apply emits the raw field
## values upward; malformed entries are tolerated and flagged by
## EnvironmentOps (debug panel notes), never crash.

signal environment_applied(env: Dictionary)
signal strip_pick_requested
## Emitted on Apply and Cancel so the controller can re-capture the mouse.
signal closed

var _fog_enabled: CheckBox
var _fog_color: LineEdit
var _fog_near: SpinBox
var _fog_far: SpinBox
var _sky_mode: OptionButton
var _sky_color: LineEdit
var _sky_strip: LineEdit
var _ambient: SpinBox
var _void_mode: OptionButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_ui()


## open_with(env)
##
## Fills the fields from the level's current environment and shows the
## panel. Called down by UIPanels.
func open_with(env: Dictionary) -> void:
	var fog: Dictionary = env.get("fog", {})
	var sky: Dictionary = env.get("sky", {})
	var void_cfg: Dictionary = env.get("void", {})
	_fog_enabled.button_pressed = bool(fog.get("enabled", true))
	_fog_color.text = str(fog.get("color", "#202830"))
	_fog_near.value = float(fog.get("near", 128.0))
	_fog_far.value = float(fog.get("far", 1536.0))
	_sky_mode.selected = EnvironmentOps.SKY_MODES.find(str(sky.get("mode", "flat")))
	if _sky_mode.selected < 0:
		_sky_mode.selected = 0
	_sky_color.text = str(sky.get("color", "#202830"))
	_sky_strip.text = str(sky.get("strip", ""))
	_ambient.value = float(env.get("ambient", 1.0))
	_void_mode.selected = EnvironmentOps.VOID_MODES.find(str(void_cfg.get("mode", "fog_color")))
	if _void_mode.selected < 0:
		_void_mode.selected = 0
	visible = true


## set_strip_art(base_name)
##
## Called down by UIPanels when the TexturePicker (sky-strip mode)
## returns a name.
func set_strip_art(base_name: String) -> void:
	_sky_strip.text = base_name


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(460, 340)
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER, true)
	panel.offset_left = -230
	panel.offset_top = -220
	panel.offset_right = 230
	panel.offset_bottom = 220
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.14, 0.98)
	style.border_color = Color(0.3, 0.25, 0.35, 1.0)
	style.set_border_width_all(4)
	style.set_corner_radius_all(20)
	style.corner_detail = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Environment (per level)"
	vbox.add_child(title)

	_fog_enabled = CheckBox.new()
	_fog_enabled.text = "Fog enabled"
	vbox.add_child(_fog_enabled)
	_fog_color = _row_edit(vbox, "Fog color", "#202830")
	_fog_near = _row_spin(vbox, "Fog near", 1.0, 65536.0, 128.0, 1.0)
	_fog_far = _row_spin(vbox, "Fog far", 2.0, 131072.0, 1536.0, 1.0)

	_sky_mode = _row_option(vbox, "Sky mode", EnvironmentOps.SKY_MODES)
	_sky_color = _row_edit(vbox, "Sky color", "#202830")
	var strip_row := HBoxContainer.new()
	vbox.add_child(strip_row)
	var strip_label := Label.new()
	strip_label.text = "Sky strip art"
	strip_label.custom_minimum_size = Vector2(140, 0)
	strip_row.add_child(strip_label)
	_sky_strip = LineEdit.new()
	_sky_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(_sky_strip)
	var pick := Button.new()
	pick.text = "Pick..."
	pick.pressed.connect(func() -> void: strip_pick_requested.emit())
	strip_row.add_child(pick)

	_ambient = _row_spin(vbox, "Ambient", 0.0, 4.0, 1.0, 0.05)
	_void_mode = _row_option(vbox, "Void renders as", EnvironmentOps.VOID_MODES)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_on_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		visible = false
		closed.emit()
	)
	buttons.add_child(cancel)


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


func _row_spin(parent: Control, label_text: String, min_value: float, max_value: float, initial: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _row_option(parent: Control, label_text: String, options: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var option := OptionButton.new()
	for item in options:
		option.add_item(item)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _on_apply() -> void:
	visible = false
	environment_applied.emit({
		"fog": {
			"enabled": _fog_enabled.button_pressed,
			"color": _fog_color.text.strip_edges(),
			"near": _fog_near.value,
			"far": _fog_far.value,
		},
		"ambient": _ambient.value,
		"sky": {
			"mode": _sky_mode.get_item_text(_sky_mode.selected),
			"color": _sky_color.text.strip_edges(),
			"strip": _sky_strip.text.strip_edges().trim_suffix(".png"),
		},
		"void": {"mode": _void_mode.get_item_text(_void_mode.selected)},
	})
	closed.emit()
