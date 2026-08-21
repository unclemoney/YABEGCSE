extends SceneTree

## EditorShellTest
##
## Headless integration test: instantiates the real EditorShell scene and
## drives it with synthetic input events through Canvas2DView — the same
## path real input takes (view -> canvas_input -> EditorController ->
## ToolSystem -> DrawSectorTool -> GeometryOps).
## Run: godot --path <repo> --headless -s Tests/EditorShellTest.gd

const LOG := "res://Tests/editor_shell.log"
const SAVE_PATH := "user://editor_shell_test.json"

var _failures := 0
var _lines: Array[String] = []
var _controller: EditorController
var _view: Canvas2DView
var _ui: UIPanels


func _initialize() -> void:
	# Nodes added this early don't get _ready until the tree starts;
	# defer the whole run so the shell is fully wired when tests execute.
	_begin.call_deferred()


func _begin() -> void:
	var scene: PackedScene = load("res://Scenes/EditorShell.tscn")
	var shell := scene.instantiate()
	root.add_child(shell)
	_controller = shell as EditorController
	_view = shell.get_node("Canvas2D") as Canvas2DView
	_ui = shell.get_node("UIPanels") as UIPanels
	_check(_controller != null and _view != null and _ui != null,
		"shell instantiates with all domains wired")
	_test_draw_via_input()
	_test_undo()
	_test_delete_via_input()
	_test_save_load_portal()
	_test_object_via_input()
	_test_clear_level()
	_test_environment_undo()
	_finish()


## _test_object_via_input()
##
## M4: the O key swaps to the ObjectTool; clicks place the brush, drags
## move, R rotates, Delete removes; Ctrl+Z restores. Drives the same
## view -> controller -> ToolSystem path as real input.
func _test_object_via_input() -> void:
	var tool_system := _controller.get_node("ToolSystem") as ToolSystem
	tool_system.set_brush_type("billboard")
	tool_system.set_brush_art("SOBJ_LIB/BARSTOOL.png")
	_key(KEY_O)
	_click(Vector2(300, 300))
	_check(_controller.level_data.objects.size() == 1, "O + click places an object")
	_move(Vector2(300, 300))
	_key(KEY_R)
	_check(float(_controller.level_data.objects[0]["angle"]) == 15.0, "R rotates hovered object")
	_key(KEY_DELETE)
	_check(_controller.level_data.objects.is_empty(), "Delete removes hovered object")
	_ctrl_z()
	_check(_controller.level_data.objects.size() == 1, "undo restores the object")
	_key(KEY_O)  # back to the draw tool
	_ctrl_z()


func _test_draw_via_input() -> void:
	for p in [Vector2(0, 0), Vector2(128, 0), Vector2(128, 128), Vector2(0, 128), Vector2(0, 0)]:
		_click(p)
	var data := _controller.level_data
	_check(data.sectors.size() == 1, "drawn loop closes into one sector")
	_check(data.walls.size() == 4, "four walls from clicks")
	_check(data.flagged_sectors.is_empty(), "drawn sector validates clean")


func _test_undo() -> void:
	_ctrl_z()
	_check(_controller.level_data.sectors.is_empty(), "undo removes the drawn sector")
	_check(_controller.level_data.points.is_empty(), "undo restores empty point table")
	_ctrl_z()
	_check(_controller.level_data.sectors.is_empty(), "second undo is a harmless no-op")


func _test_delete_via_input() -> void:
	for p in [Vector2(0, 0), Vector2(128, 0), Vector2(128, 128), Vector2(0, 128), Vector2(0, 0)]:
		_click(p)
	_move(Vector2(64, 64))
	_key(KEY_DELETE)
	var data := _controller.level_data
	_check(data.sectors.is_empty(), "hover + Delete removes the sector")
	_check(data.points.is_empty(), "delete removes orphaned points")


func _test_save_load_portal() -> void:
	for p in [Vector2(0, 0), Vector2(128, 0), Vector2(128, 128), Vector2(0, 128), Vector2(0, 0)]:
		_click(p)
	for p in [Vector2(128, 0), Vector2(256, 0), Vector2(256, 128), Vector2(128, 128), Vector2(128, 0)]:
		_click(p)
	_check(_controller.level_data.sectors.size() == 2, "two adjacent rooms drawn via input")
	var portal_found := false
	for w in _controller.level_data.walls:
		if w["back"] != -1:
			portal_found = true
	_check(portal_found, "shared edge became a portal wall")
	_controller.save_level(SAVE_PATH)
	_controller.new_level()
	_check(_controller.level_data.sectors.is_empty(), "new level resets state")
	_controller.open_level(SAVE_PATH)
	var data := _controller.level_data
	_check(data.sectors.size() == 2, "saved level reloads with both rooms")
	portal_found = false
	for w in data.walls:
		if w["back"] != -1:
			portal_found = true
	_check(portal_found, "portal survives save/load")
	_check(data.flagged_sectors.is_empty() and data.flagged_walls.is_empty(),
		"reloaded level validates clean")


func _test_clear_level() -> void:
	_ui.clear_confirmed.emit()
	_check(_controller.level_data.sectors.is_empty(), "clear level wipes geometry")
	_check(_controller.level_data.points.is_empty(), "clear level wipes points")


## _test_environment_undo()
##
## M6: commit_environment is an ordinary undoable edit (one snapshot,
## restored by Ctrl+Z).
func _test_environment_undo() -> void:
	var tool_system := _controller.get_node("ToolSystem") as ToolSystem
	var env := {
		"fog": {"enabled": false, "color": "#112233", "near": 64.0, "far": 512.0},
		"ambient": 2.0,
		"sky": {"mode": "flat", "color": "#112233", "strip": ""},
		"void": {"mode": "sky_color"},
	}
	tool_system.commit_environment(env)
	_check(float(_controller.level_data.environment.get("ambient", 0.0)) == 2.0,
		"commit_environment applies")
	_ctrl_z()
	_check(float(_controller.level_data.environment.get("ambient", 0.0)) == 1.0,
		"undo restores environment")


func _click(world: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _view.world_to_screen(world)
	_view._unhandled_input(ev)


func _move(world: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _view.world_to_screen(world)
	_view._unhandled_input(ev)


func _key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	_view._unhandled_input(ev)


func _ctrl_z() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.pressed = true
	ev.ctrl_pressed = true
	_controller._unhandled_input(ev)


func _check(condition: bool, label: String) -> void:
	if condition:
		_log("PASS: " + label)
	else:
		_failures += 1
		_log("FAIL: " + label)


func _finish() -> void:
	if _failures == 0:
		_log("ALL TESTS PASSED")
	else:
		_log("%d FAILURE(S)" % _failures)
	var file := FileAccess.open(LOG, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	for line in _lines:
		print(line)
	if _failures == 0:
		quit(0)
	else:
		quit(1)


func _log(line: String) -> void:
	_lines.append(line)
