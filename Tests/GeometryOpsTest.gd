extends SceneTree

## GeometryOpsTest
##
## Headless harness for the M1 geometry layer: loop drawing, auto-split,
## portals, inner loops, validity flags, delete, undo capacity, and
## round-trip with populated geometry.
## Run: godot --path <repo> --headless -s Tests/GeometryOpsTest.gd

const LOG := "res://Tests/geometry_ops.log"

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_test_draw_square()
	_test_auto_split_crossing()
	_test_t_junction_partial_overlap()
	_test_portal_on_shared_edge()
	_test_inner_loop()
	_test_corrupt_load_flags()
	_test_delete_sector()
	_test_undo_capacity()
	_test_roundtrip_with_geometry()
	_finish()


func _test_draw_square() -> void:
	var data := LevelData.create_empty()
	var id := GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	_check(id == 0, "square loop returns sector 0")
	_check(data.sectors.size() == 1, "one sector created")
	_check(data.walls.size() == 4, "four walls created")
	_check(data.points.size() == 4, "four points created")
	var all_solid := true
	for w in data.walls:
		if w["front"] != 0 or w["back"] != -1:
			all_solid = false
	_check(all_solid, "all walls solid, front = sector 0")
	GeometryOps.validate(data)
	_check(data.flagged_sectors.is_empty() and data.flagged_walls.is_empty(),
		"clean square validates without flags")


func _test_auto_split_crossing() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	# Second square overlaps the first one's corner: its edges cross two walls.
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 128))
	_check(GeometryOps.find_point_at(data, Vector2(64, 128), 0.01) != -1,
		"crossing vertex inserted at (64, 128)")
	_check(GeometryOps.find_point_at(data, Vector2(128, 64), 0.01) != -1,
		"crossing vertex inserted at (128, 64)")
	_check(data.points.size() == 10, "10 points after splits (4 + 4 + 2)")
	_check(data.walls.size() == 12, "12 walls after splits (4 + 2 splits + 6 ring edges)")
	GeometryOps.validate(data)
	_check(data.flagged_sectors.has(0) and data.flagged_sectors.has(1),
		"partial 2D overlap flags both sectors")


func _test_t_junction_partial_overlap() -> void:
	var data := LevelData.create_empty()
	# Wide room, then a room attached to the right half of its bottom edge.
	GeometryOps.close_loop_from_positions(data, [
		Vector2(0, 0), Vector2(256, 0), Vector2(256, 128), Vector2(0, 128),
	])
	GeometryOps.close_loop_from_positions(data, [
		Vector2(128, 128), Vector2(256, 128), Vector2(256, 256), Vector2(128, 256),
	])
	var wall_count := data.walls.size()
	var portal_count := 0
	for w in data.walls:
		if w["back"] != -1:
			portal_count += 1
	_check(portal_count == 1, "exactly one portal wall (shared half-edge)")
	_check(wall_count == 8, "T-junction split: 4 + 1 split + 3 new = 8 walls, got %d" % wall_count)
	GeometryOps.validate(data)
	_check(data.flagged_sectors.is_empty() and data.flagged_walls.is_empty(),
		"T-junction attachment validates clean")


func _test_portal_on_shared_edge() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	GeometryOps.close_loop_from_positions(data, _square(128, 0, 128))
	_check(data.sectors.size() == 2, "two sectors")
	_check(data.walls.size() == 7, "shared edge reuses one wall (4 + 3)")
	var portal := -1
	for wi in range(data.walls.size()):
		if data.walls[wi]["back"] != -1:
			portal = wi
	_check(portal != -1, "portal wall exists")
	if portal != -1:
		var w: Dictionary = data.walls[portal]
		_check(w["front"] == 0 and w["back"] == 1, "portal joins sectors 0 and 1")
	GeometryOps.validate(data)
	_check(data.flagged_sectors.is_empty(), "adjacent rooms validate clean")


func _test_inner_loop() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	var inner := GeometryOps.close_loop_from_positions(data, _square(64, 64, 128))
	_check(inner == 1, "inner loop becomes sector 1")
	_check(data.sectors[0]["inner"].size() == 1, "outer sector records the inner loop")
	var all_portals := true
	for wid in data.sectors[1]["walls"]:
		var w: Dictionary = data.walls[wid]
		if w["front"] != 1 or w["back"] != 0:
			all_portals = false
	_check(all_portals, "inner loop walls are two-sided (front 1, back 0)")
	GeometryOps.validate(data)
	_check(data.flagged_sectors.is_empty() and data.flagged_walls.is_empty(),
		"inner loop (sector-within-sector) validates clean")


func _test_corrupt_load_flags() -> void:
	var serializer := LevelSerializer.new()
	var text := FileAccess.get_file_as_string("res://Tests/Fixtures/level_corrupt_v0.json")
	var data := serializer.load_from_json(text)
	_check(data != null, "corrupt fixture loads without crashing")
	if data == null:
		return
	_check(not data.flagged_walls.is_empty(), "walls flagged at load")
	_check(data.flagged_sectors.has(0), "sector 0 flagged at load")
	var crossing_found := false
	var zero_found := false
	var range_found := false
	for wi in data.flagged_walls:
		var reason: String = data.flagged_walls[wi]
		if reason.contains("crossing"):
			crossing_found = true
		if reason.contains("zero-length"):
			zero_found = true
		if reason.contains("out of range"):
			range_found = true
	_check(crossing_found, "crossing-without-split detected")
	_check(zero_found, "zero-length wall detected")
	_check(range_found, "out-of-range point reference detected")
	# Splitting at the crossing clears that flag on re-validation.
	GeometryOps.add_segment(data, Vector2(64, -64), Vector2(64, 192))
	GeometryOps.validate(data)
	var still_crossing := false
	for wi in data.flagged_walls:
		if String(data.flagged_walls[wi]).contains("crossing"):
			still_crossing = true
	_check(not still_crossing, "splitting at the crossing clears the flag")


func _test_delete_sector() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	GeometryOps.close_loop_from_positions(data, _square(128, 0, 128))
	GeometryOps.delete_sector(data, 1)
	_check(data.sectors.size() == 1, "sector removed")
	_check(data.walls.size() == 4, "exclusive walls removed, shared wall kept")
	_check(data.points.size() == 4, "orphaned points removed")
	var all_solid := true
	for w in data.walls:
		if w["back"] != -1:
			all_solid = false
	_check(all_solid, "shared portal reverted to solid")
	GeometryOps.validate(data)
	_check(data.flagged_walls.is_empty() and data.flagged_sectors.is_empty(),
		"delete leaves a clean level")


func _test_undo_capacity() -> void:
	var stack := UndoStack.new()
	stack.push([1])
	stack.push([2])
	stack.push([3])
	stack.push([4])
	_check(stack.pop_undo() == [4], "undo pops latest")
	_check(stack.pop_undo() == [3], "undo pops second")
	_check(stack.pop_undo() == [2], "undo pops third")
	_check(stack.pop_undo() == null, "3-deep: fourth pop is empty")
	stack.free()


func _test_roundtrip_with_geometry() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(256, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 128))
	var serializer := LevelSerializer.new()
	var save1 := serializer.save_to_json(data)
	_check(not save1.contains("flagged"), "validity annotations are never serialized")
	var data2 := serializer.load_from_json(save1)
	_check(data2 != null, "populated geometry reloads")
	if data2 == null:
		return
	_check(data2.sectors.size() == 3, "three sectors survive the round-trip")
	_check(data2.sectors[0]["inner"].size() == 1, "inner loop survives the round-trip")
	var save2 := serializer.save_to_json(data2)
	_check(save1 == save2, "geometry round-trip is idempotent")
	# The hand-written two-room fixture validates clean.
	var fixture := FileAccess.get_file_as_string("res://Tests/Fixtures/level_geometry_v0.json")
	var data3 := serializer.load_from_json(fixture)
	_check(data3 != null and data3.sectors.size() == 2, "two-room fixture loads")
	if data3 != null:
		_check(data3.flagged_sectors.is_empty() and data3.flagged_walls.is_empty(),
			"two-room fixture validates clean")


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
