extends SceneTree

## WalkTest
##
## Headless walk-mode harness: instantiates the real EditorShell scene,
## builds three rooms in a row (floor 0 -> portal -> floor 16 -> portal ->
## floor 200), switches to 3D, and drives the WalkController with injected
## actions through real physics frames.
## Run: godot --path <repo> --headless -s Tests/WalkTest.gd

const LOG := "res://Tests/walk.log"

var _failures := 0
var _lines: Array[String] = []
var _controller: EditorController
var _player: CharacterBody3D


func _initialize() -> void:
	# Nodes added this early don't get _ready until the tree starts.
	_begin.call_deferred()


func _begin() -> void:
	var scene: PackedScene = load("res://Scenes/EditorShell.tscn")
	var shell := scene.instantiate()
	root.add_child(shell)
	_controller = shell as EditorController
	var view3d := shell.get_node("Viewport3D") as Viewport3DView
	_player = view3d.get_node("Player") as CharacterBody3D

	# Build the level through GeometryOps, then notify (as ToolSystem would).
	var data := _controller.level_data
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(256, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(512, 0, 256))
	data.sectors[1]["floor_height"] = 16.0
	data.sectors[2]["floor_height"] = 200.0
	GeometryOps.validate(data)
	data.notify_changed(LevelData.ChangeType.GEOMETRY)
	_check(data.flagged_sectors.is_empty(), "test level validates clean")
	_check(data.sectors.size() == 3, "three rooms built")

	# Switch to 3D mode (spawns the player in sector 0).
	var toggle := InputEventAction.new()
	toggle.action = "toggle_mode"
	toggle.pressed = true
	_controller._unhandled_input(toggle)
	await physics_frame
	await physics_frame
	_check(Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(128, 128)) < 1.0,
		"player spawns at sector 0 centroid")

	await _test_forward_and_wall()
	await _test_step_up()
	await _test_blocked_riser()
	await _test_void()
	_finish()


func _test_forward_and_wall() -> void:
	_player.rotation.y = 0.0  # face -z
	_player.global_position = Vector3(128, 0, 128)
	Input.action_press("move_forward")
	await _frames(30)
	_check(_player.global_position.z < 100.0, "WASD: player advances")
	await _frames(60)
	Input.action_release("move_forward")
	var z := _player.global_position.z
	_check(z > 5.0 and z < 60.0, "wall collision stops the player (z=%.1f)" % z)


func _test_step_up() -> void:
	_player.rotation.y = -PI / 2.0  # face +x
	_player.global_position = Vector3(128, 0, 128)
	Input.action_press("move_forward")
	var frames := 0
	while _player.global_position.x < 300.0 and frames < 120:
		await physics_frame
		frames += 1
	_check(_player.global_position.x > 300.0, "crossed the portal into room B")
	await _frames(30)  # let the step lerp settle
	var y := _player.global_position.y
	_check(absf(y - 16.0) < 3.0, "floor step up to 16 units (y=%.2f)" % y)


func _test_blocked_riser() -> void:
	# Still facing +x; room C's floor is 200 — 184 above us, over step height.
	await _frames(120)
	Input.action_release("move_forward")
	var x := _player.global_position.x
	_check(x < 500.0, "tall riser blocks movement (x=%.1f)" % x)
	_check(absf(_player.global_position.y - 16.0) < 3.0, "stayed on room B floor")


func _test_void() -> void:
	_player.rotation.y = PI  # face +z
	# Teleport past the south wall — the void is unenclosed space, but the
	# room's solid walls rightly block walking straight out of a room.
	_player.global_position = Vector3(384, 16, 400)
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	_check(_player.global_position.z > 500.0, "walked off into the void without crashing (z=%.1f)" % _player.global_position.z)
	_check(absf(_player.global_position.y - 16.0) < 3.0, "void holds last floor height")


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame


func _square(x: float, y: float, size: float) -> Array:
	return [
		Vector2(x, y),
		Vector2(x + size, y),
		Vector2(x + size, y + size),
		Vector2(x, y + size),
	]


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
	# Mirror incrementally: a hung physics await would otherwise hide
	# how far the run got.
	var file := FileAccess.open(LOG, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
