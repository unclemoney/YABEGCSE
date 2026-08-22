extends SceneTree

## VertexMergeTest
##
## Headless harness for the 2D tool modes: vertex-move validity
## (wall-crossing rejection + snap-back), portal-merge geometry and its
## rejections, object preservation across a merge, the ToolSystem Tab
## cycle, and the one-undo-step drag/merge commit paths.
## Run: godot --path <repo> --headless -s Tests/VertexMergeTest.gd

const LOG := "res://Tests/vertex_merge.log"

var _failures := 0
var _lines: Array[String] = []


func _initialize() -> void:
	# ToolSystem is a Node: defer so add_child runs its _ready (tool set).
	_begin.call_deferred()


func _begin() -> void:
	_test_vertex_move_valid()
	_test_vertex_move_crossing()
	_test_vertex_drag_commit_path()
	_test_merge_two_rooms()
	_test_merge_inherits_larger_sector()
	_test_merge_preserves_objects()
	_test_merge_rejects_boundary()
	_test_merge_rejects_multi_wall()
	_test_merge_rejects_inner_loop()
	_test_tool_cycle()
	_finish()


func _test_vertex_move_valid() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var pid := GeometryOps.find_point_at(data, Vector2(0, 0), 0.01)
	_check(pid != -1, "corner point found")
	_check(not GeometryOps.move_causes_crossing(data, pid, Vector2(-32, -32)),
		"outward corner move is valid")
	GeometryOps.move_point(data, pid, Vector2(-32, -32))
	GeometryOps.validate(data)
	_check(data.flagged_walls.is_empty() and data.flagged_sectors.is_empty(),
		"moved square validates clean")


func _test_vertex_move_crossing() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var pid := GeometryOps.find_point_at(data, Vector2(0, 0), 0.01)
	# Dragging (0,0) past the right edge crosses the (128,0)-(128,128) wall.
	_check(GeometryOps.move_causes_crossing(data, pid, Vector2(200, 64)),
		"crossing corner move is detected")
	# Touching the opposite corner is not a crossing (loops join at vertices).
	var pid2 := GeometryOps.find_point_at(data, Vector2(128, 0), 0.01)
	_check(not GeometryOps.move_causes_crossing(data, pid, Vector2(32, 32)),
		"interior move without crossing stays valid")
	_check(GeometryOps.move_causes_crossing(data, pid2, GeometryOps.get_point(data, pid)),
		"collapsing a wall to zero length is invalid")


func _test_vertex_drag_commit_path() -> void:
	var ts := ToolSystem.new()
	root.add_child(ts)
	var data := LevelData.create_empty()
	ts.set_level_data(data)
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var pid := GeometryOps.find_point_at(data, Vector2(0, 0), 0.01)
	var start := GeometryOps.get_point(data, pid)
	var emissions := [0]
	ts.mutation_committed.connect(func() -> void: emissions[0] += 1)
	# Rejected drag: live preview moves, release snaps back.
	ts.begin_vertex_drag()
	ts.update_vertex_drag(pid, Vector2(200, 64))
	_check(GeometryOps.get_point(data, pid) == Vector2(200, 64),
		"drag preview moves the vertex live")
	var accepted := ts.finish_vertex_drag(pid, start)
	_check(not accepted, "crossing move rejected at release")
	_check(GeometryOps.get_point(data, pid) == start, "vertex snaps back to drag start")
	_check(emissions[0] == 1, "rejected drag took exactly one undo snapshot")
	# Accepted drag stands.
	ts.begin_vertex_drag()
	ts.update_vertex_drag(pid, Vector2(-32, -32))
	accepted = ts.finish_vertex_drag(pid, start)
	_check(accepted, "valid move accepted at release")
	_check(GeometryOps.get_point(data, pid) == Vector2(-32, -32), "valid move stands")
	_check(emissions[0] == 2, "accepted drag adds exactly one more snapshot")
	root.remove_child(ts)
	ts.free()


func _test_merge_two_rooms() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	GeometryOps.close_loop_from_positions(data, _square(128, 0, 128))
	var portal := _portal_wall(data)
	_check(portal != -1, "two-room fixture has a portal wall")
	var plan := GeometryOps.check_portal_merge(data, portal)
	_check(plan["ok"], "two-room portal passes the merge gate")
	var result := GeometryOps.merge_sectors_at_portal(data, portal)
	_check(result["ok"], "merge applies")
	_check(data.sectors.size() == 1, "one sector remains")
	_check(data.walls.size() == 6, "portal wall removed, 6 walls remain (got %d)" % data.walls.size())
	var poly := GeometryOps.loop_to_polygon(data, data.sectors[0]["walls"])
	_check(poly.size() == 6, "merged loop chains into 6 corners (got %d)" % poly.size())
	_check(absf(absf(GeometryOps.polygon_area(poly)) - 256.0 * 128.0) < 0.01,
		"merged area equals both rooms")
	GeometryOps.validate(data)
	_check(data.flagged_sectors.is_empty() and data.flagged_walls.is_empty(),
		"merged level validates clean")


func _test_merge_inherits_larger_sector() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(256, 0, 128))
	data.sectors[0]["floor_height"] = 32.0
	data.sectors[0]["floor_texture"] = "BASICLIB/BIGFLOOR"
	data.sectors[1]["floor_height"] = -16.0
	GeometryOps.merge_sectors_at_portal(data, _portal_wall(data))
	_check(data.sectors.size() == 1, "one sector remains")
	_check(float(data.sectors[0]["floor_height"]) == 32.0,
		"merged sector keeps the larger sector's floor height")
	_check(str(data.sectors[0]["floor_texture"]) == "BASICLIB/BIGFLOOR",
		"merged sector keeps the larger sector's textures")


func _test_merge_preserves_objects() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	GeometryOps.close_loop_from_positions(data, _square(128, 0, 128))
	data.objects.append({
		"type": "billboard", "pos": [192.0, 64.0], "z": 0.0, "angle": 0.0,
		"art": "SOBJ_LIB/BARSTOOL", "params": {},
	})
	GeometryOps.merge_sectors_at_portal(data, _portal_wall(data))
	_check(data.objects.size() == 1, "object survives the merge")
	_check(ObjectOps.get_pos(data.objects[0]) == Vector2(192.0, 64.0),
		"object keeps its world position (deleted sector's room)")


func _test_merge_rejects_boundary() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var plan := GeometryOps.check_portal_merge(data, 0)
	_check(not plan["ok"], "boundary wall rejected")
	_check(str(plan["reason"]) == "boundary wall", "reason names the boundary case")
	var result := GeometryOps.merge_sectors_at_portal(data, 0)
	_check(not result["ok"], "merge_sectors_at_portal refuses the boundary wall")
	_check(data.walls.size() == 4 and data.sectors.size() == 1,
		"rejected merge leaves the level untouched")


func _test_merge_rejects_multi_wall() -> void:
	# Hand-built: sector 1 is an L wrapping sector 0's right AND bottom
	# edges, so the two sectors share two portal walls.
	var data := LevelData.create_empty()
	data.points = [
		[0, 0], [128, 0], [128, 128], [0, 128], [256, 0], [256, 256], [0, 256],
	]
	data.walls = [
		_wall(0, 1, 0, -1),
		_wall(1, 2, 0, 1),
		_wall(2, 3, 0, 1),
		_wall(3, 0, 0, -1),
		_wall(1, 4, 1, -1),
		_wall(4, 5, 1, -1),
		_wall(5, 6, 1, -1),
		_wall(6, 3, 1, -1),
	]
	data.sectors = [_sector([0, 1, 2, 3]), _sector([4, 5, 6, 7, 2, 1])]
	var plan := GeometryOps.check_portal_merge(data, 1)
	_check(not plan["ok"], "multi-wall portal rejected")
	_check(str(plan["reason"]).contains("share"), "reason names the multi-wall case")
	plan = GeometryOps.check_portal_merge(data, 2)
	_check(not plan["ok"], "the second shared wall is rejected too")


func _test_merge_rejects_inner_loop() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 128))
	var plan := GeometryOps.check_portal_merge(data, _portal_wall(data))
	_check(not plan["ok"], "inner-loop portal rejected")
	_check(str(plan["reason"]).contains("inner loops"), "reason names the inner-loop case")


func _test_tool_cycle() -> void:
	var ts := ToolSystem.new()
	root.add_child(ts)
	_check(ts.get_tool_mode_name() == "SECTOR DRAW", "cycle starts at Sector Draw")
	ts.cycle_tool(1)
	_check(ts.get_tool_mode_name() == "VERTEX EDIT", "Tab forward -> Vertex Edit")
	ts.cycle_tool(1)
	_check(ts.get_tool_mode_name() == "WALL SELECT", "Tab forward -> Wall Select")
	ts.cycle_tool(1)
	_check(ts.get_tool_mode_name() == "PLATFORM DRAW", "Tab forward -> Platform Draw")
	ts.cycle_tool(1)
	_check(ts.get_tool_mode_name() == "SECTOR DRAW", "cycle wraps to Sector Draw")
	ts.cycle_tool(-1)
	_check(ts.get_tool_mode_name() == "PLATFORM DRAW", "Shift+Tab cycles backward")
	# The key-event path (the same one real canvas input takes).
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	_check(ts.handle_input(tab, Vector2.ZERO, Vector2.ZERO), "Tab key is consumed")
	_check(ts.get_tool_mode_name() == "SECTOR DRAW", "Tab key advances the cycle")
	var shift_tab := InputEventKey.new()
	shift_tab.keycode = KEY_TAB
	shift_tab.pressed = true
	shift_tab.shift_pressed = true
	ts.handle_input(shift_tab, Vector2.ZERO, Vector2.ZERO)
	_check(ts.get_tool_mode_name() == "PLATFORM DRAW", "Shift+Tab key goes backward")
	# The object tool sits outside the cycle: O overlays, Tab returns to
	# the cycle.
	ts.cycle_tool(1)  # -> SECTOR DRAW
	ts.set_object_mode(true)
	_check(ts.get_tool_mode_name() == "OBJECT PLACE", "O overlays the object tool")
	ts.handle_input(tab, Vector2.ZERO, Vector2.ZERO)
	_check(ts.get_tool_mode_name() == "VERTEX EDIT", "Tab leaves object mode into the cycle")
	root.remove_child(ts)
	ts.free()


func _square(x: float, y: float, size: float) -> Array:
	return [
		Vector2(x, y),
		Vector2(x + size, y),
		Vector2(x + size, y + size),
		Vector2(x, y + size),
	]


func _portal_wall(data: LevelData) -> int:
	for wi in range(data.walls.size()):
		if data.walls[wi]["back"] != -1:
			return wi
	return -1


func _wall(a: int, b: int, front: int, back: int) -> Dictionary:
	return {
		"a": a, "b": b, "front": front, "back": back,
		"texture": "", "offset_u": 0.0, "offset_v": 0.0,
	}


func _sector(walls: Array) -> Dictionary:
	return {
		"walls": walls,
		"inner": [],
		"floor_height": 0.0,
		"ceiling_height": 256.0,
		"floor_texture": "",
		"ceiling_texture": "",
		"floor_slope": [],
		"ceiling_slope": [],
		"flags": 0,
	}


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
