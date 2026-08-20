class_name DebugPanel
extends Control

## DebugPanel (F12)
##
## Tolerate + flag: invalid sectors and unresolved art references surface
## here, plus debug commands (fixture loading) per the skill's rule that
## new features ship with debug-panel access.

signal fixture_load_requested(path: String)

var _panel: PanelContainer
var _list: Label


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


## set_flags(flagged_sectors, flagged_walls)
##
## One line per flagged sector/wall with its reason. Annotations are
## computed by GeometryOps.validate() — this panel only displays them.
func set_flags(flagged_sectors: Dictionary, flagged_walls: Dictionary) -> void:
	if _list == null:
		return
	var lines: Array[String] = []
	for id in flagged_sectors:
		lines.append("Sector %d: %s" % [id, flagged_sectors[id]])
	for id in flagged_walls:
		lines.append("Wall %d: %s" % [id, flagged_walls[id]])
	if lines.is_empty():
		_list.text = "Debug — no flagged sectors or walls."
	else:
		_list.text = "\n".join(lines)


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
