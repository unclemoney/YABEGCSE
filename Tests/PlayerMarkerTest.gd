extends SceneTree

## PlayerMarkerTest
##
## Integration harness for the player position marker: the 3D view's
## player_moved drives the 2D marker through EditorController, and WASD
## in 2D mode drives the 3D player through the reverse path.
## Run: godot --path <repo> --headless -s Tests/PlayerMarkerTest.gd

const LOG := "res://Tests/player_marker.log"

var _failures := 0
var _lines: Array[String] = []
var _controller: EditorController
var _view: Canvas2DView
var _viewport3d: Viewport3DView


func _initialize() -> void:
	# Nodes added this early don't get _ready until the tree starts.
	_begin.call_deferred()


func _begin() -> void:
	var scene: PackedScene = load("res://Scenes/EditorShell.tscn")
	var shell := scene.instantiate()
	root.add_child(shell)
	_controller = shell as EditorController
	_view = shell.get_node("Canvas2D") as Canvas2DView
	_viewport3d = shell.get_node("Viewport3D") as Viewport3DView
	_check(_controller != null and _view != null and _viewport3d != null,
		"shell instantiates with both views")
	_test_3d_to_2d()
	await process_frame
	await process_frame
	_test_2d_to_3d()
	await _test_wasd_moves_marker()
	_finish()


## _test_3d_to_2d()
##
## Enter 3D (spawns the player), teleport the player, and let the view's
## _process report the motion: the marker must follow.
func _test_3d_to_2d() -> void:
	_controller.mode = EditorController.Mode.MODE_3D
	_controller._apply_mode()
	var player := _viewport3d.get_node("Player") as WalkController
	_check(player != null, "3D view has a player")
	if player == null:
		return
	player.global_position = Vector3(100.0, 0.0, 200.0)
	player.rotation.y = 0.0


func _test_2d_to_3d() -> void:
	# The deferred frames after _test_3d_to_2d delivered player_moved.
	_check(_controller.player_position.is_equal_approx(Vector3(100.0, 0.0, 200.0)),
		"controller stored the 3D player position")
	_check(_view._marker_pos.is_equal_approx(Vector2(100.0, 200.0)),
		"2D marker follows the 3D player")
	# Reverse path: 2D marker move -> 3D player.
	_controller._on_player_moved_2d(Vector2(50.0, 60.0), 0.5)
	var player := _viewport3d.get_node("Player") as WalkController
	_check(player.global_position.is_equal_approx(Vector3(50.0, 0.0, 60.0)),
		"3D player follows the 2D marker")
	_check(is_equal_approx(player.rotation.y, atan2(-cos(0.5), -sin(0.5))),
		"3D facing follows the 2D marker angle")
	_check(is_equal_approx(_controller.player_angle, 0.5),
		"controller stored the 2D facing angle")


func _test_wasd_moves_marker() -> void:
	_controller.mode = EditorController.Mode.MODE_2D
	_controller._apply_mode()
	var before: Vector2 = _view._marker_pos
	Input.action_press("move_forward")
	await process_frame
	await process_frame
	await process_frame
	Input.action_release("move_forward")
	_check(_view._marker_pos.y < before.y, "W (move_forward) moves the marker up-map")
	_check(is_equal_approx(_view._marker_angle, Vector2(0, -1).angle()),
		"marker facing follows the movement direction")
	var player := _viewport3d.get_node("Player") as WalkController
	_check(player.global_position.is_equal_approx(
			Vector3(_view._marker_pos.x, 0.0, _view._marker_pos.y)),
		"the 3D player mirrors the 2D WASD move")


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
