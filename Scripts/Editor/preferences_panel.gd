class_name PreferencesPanel
extends Control

## PreferencesPanel (M6)
##
## Modal editor for the persisted player-preference knobs (GameSettings):
## walk speed, mouse sensitivity, eye height, step height, plus the
## fog-enabled default. Built dynamically per the panel construction
## standards. Apply emits the raw values upward; EditorController writes
## them to GameSettings and persists (user://game_settings.cfg).

signal preferences_applied(prefs: Dictionary)
## Emitted on Apply and Cancel so the controller can re-capture the mouse.
signal closed

var _walk_speed: SpinBox
var _mouse_sensitivity: SpinBox
var _eye_height: SpinBox
var _step_height: SpinBox
var _fog_enabled: CheckBox


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_ui()


## open_with(settings)
##
## Fills the fields from GameSettings and shows the panel. Called down by
## UIPanels.
func open_with(settings: Node) -> void:
	_walk_speed.value = settings.walk_speed
	_mouse_sensitivity.value = settings.mouse_sensitivity
	_eye_height.value = settings.eye_height
	_step_height.value = settings.step_height
	_fog_enabled.button_pressed = settings.fog_enabled
	visible = true


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT, true)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(460, 300)
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER, true)
	panel.offset_left = -230
	panel.offset_top = -170
	panel.offset_right = 230
	panel.offset_bottom = 170
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
	title.text = "Preferences (persisted)"
	vbox.add_child(title)

	_walk_speed = _row_spin(vbox, "Walk speed", 50.0, 2000.0, 500.0, 10.0)
	_mouse_sensitivity = _row_spin(vbox, "Mouse sensitivity", 0.0005, 0.01, 0.0025, 0.0005)
	_eye_height = _row_spin(vbox, "Eye height", 40.0, 400.0, 140.0, 1.0)
	_step_height = _row_spin(vbox, "Step height", 1.0, 96.0, 24.0, 1.0)
	_fog_enabled = CheckBox.new()
	_fog_enabled.text = "Fog enabled by default (F toggles in 3D)"
	vbox.add_child(_fog_enabled)

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


func _row_spin(parent: Control, label_text: String, min_value: float, max_value: float, initial: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _on_apply() -> void:
	visible = false
	preferences_applied.emit({
		"walk_speed": _walk_speed.value,
		"mouse_sensitivity": _mouse_sensitivity.value,
		"eye_height": _eye_height.value,
		"step_height": _step_height.value,
		"fog_enabled": _fog_enabled.button_pressed,
	})
	closed.emit()
