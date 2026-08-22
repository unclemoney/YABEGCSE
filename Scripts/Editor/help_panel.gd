class_name HelpPanel
extends Control

## HelpPanel
##
## Read-only viewer for docs/EDITOR_CONTROLS.md — the editor key binding
## reference. Opened with F1 or the "?" button (top-right). Follows the
## Panel Construction Standards: full-rect overlay, centered PanelContainer
## clamped to the viewport minus a 20 px margin (600x360 at the 640x400
## internal viewport), fixed header row (title + X close) over a
## ScrollContainer, Escape closes, open/close tweens animate position and
## modulate only (never scale). The file is re-read on every open so
## edits to the doc show up without a restart; a missing file degrades to
## an inline note, never a crash.

## Emitted on every close path so the controller can re-capture the mouse.
signal closed

const VIEWPORT_MARGIN := 20.0
const MAX_PANEL_SIZE := Vector2(600, 360)  # desired size; clamped to the viewport
const ANIM_OFFSET := 20.0  # px slide for open/close tweens (keeps the panel on-screen)
const CONTROLS_PATH := "res://docs/EDITOR_CONTROLS.md"

var _overlay: ColorRect
var _panel: PanelContainer
var _text: RichTextLabel
var _tween: Tween
var _closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_ui()


## open()
##
## Reloads the controls document and shows the panel. Called down by
## UIPanels (F1 / "?" button).
func open() -> void:
	_reload_text()
	_show_animated()


## toggle()
##
## F1 / "?" button behavior: opens when hidden, closes when shown.
func toggle() -> void:
	if visible:
		_request_close()
	else:
		open()


## _unhandled_input(event)
##
## Escape closes the panel from anywhere.
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
	title.text = "Editor Controls (docs/EDITOR_CONTROLS.md)"
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
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false  # the doc is markdown; show it verbatim
	_text.fit_content = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_text)


## _reload_text()
##
## Reads the controls document from disk. A missing or unreadable file
## degrades to an inline note (tolerate + flag), never a crash.
func _reload_text() -> void:
	var content := FileAccess.get_file_as_string(CONTROLS_PATH)
	if content.is_empty() and FileAccess.get_open_error() != OK:
		_text.text = "Controls document not found: " + CONTROLS_PATH
	else:
		_text.text = content


## _layout_panel()
##
## Clamps the panel to the viewport minus VIEWPORT_MARGIN on every side
## (600x360 at the 640x400 internal viewport) and re-centers it. Called
## at build time and on every open, so window resizes can never push the
## panel — or its close button — off-screen.
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
## The single close path (X button, F1 toggle, Escape): exit tween
## downward + fade on panel and overlay, then hide and emit closed so the
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
