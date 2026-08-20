extends SceneTree

## MeshBuilderTest
##
## Headless harness for SectorMeshBuilder: concave triangulation, real
## holes for inner loops, graceful skip of flagged sectors, portal riser
## quads and collision, open passages for same-height portals.
## Run: godot --path <repo> --headless -s Tests/MeshBuilderTest.gd

const LOG := "res://Tests/mesh_builder.log"
const STEP := 24.0

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_test_concave_sector()
	_test_inner_loop_hole()
	_test_corrupt_degrades()
	_test_portal_riser_and_collision()
	_test_same_height_portal_open()
	_finish()


func _test_concave_sector() -> void:
	var data := LevelData.create_empty()
	# L-shape: 256x256 square minus the top-right 128x128 quadrant.
	GeometryOps.close_loop_from_positions(data, [
		Vector2(0, 0), Vector2(128, 0), Vector2(128, 128), Vector2(256, 128),
		Vector2(256, 256), Vector2(0, 256),
	])
	var stats := _build(data)
	_check(stats["sectors_built"] == 1, "concave L-sector builds")
	_check(stats["sectors_skipped"] == 0, "concave L-sector not skipped")
	var expected := 256.0 * 256.0 - 128.0 * 128.0
	_check(absf(stats["floor_area"] - expected) < 1.0,
		"concave floor area matches (%f vs %f)" % [stats["floor_area"], expected])


func _test_inner_loop_hole() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 128))
	var stats := _build(data)
	_check(stats["sectors_built"] == 2, "donut: both sectors build")
	var expected := 256.0 * 256.0  # outer floor minus hole + inner floor = outer
	# Tolerance 4.0: the keyhole bridge channel (0.05 units wide) costs ~2.
	_check(absf(stats["floor_area"] - expected) < 4.0,
		"donut floor area: hole is real, inner floor fills it (%f vs %f)" % [stats["floor_area"], expected])
	# The outer sector alone must NOT cover the hole: rebuild with only it.
	var data2 := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data2, _square(0, 0, 256))
	var inner_id := GeometryOps.close_loop_from_positions(data2, _square(64, 64, 128))
	data2.sectors.remove_at(inner_id)  # leave the hole uncovered
	GeometryOps.validate(data2)
	var stats2 := _build(data2)
	var outer_expected := 256.0 * 256.0 - 128.0 * 128.0
	_check(absf(stats2["floor_area"] - outer_expected) < 4.0,
		"outer floor excludes the hole (%f vs %f)" % [stats2["floor_area"], outer_expected])


func _test_corrupt_degrades() -> void:
	var serializer := LevelSerializer.new()
	var text := FileAccess.get_file_as_string("res://Tests/Fixtures/level_corrupt_v0.json")
	var data := serializer.load_from_json(text)
	_check(data != null, "corrupt fixture loads")
	if data == null:
		return
	var stats := _build(data)
	_check(stats["sectors_skipped"] >= 1, "flagged sector skipped, no crash")
	_check(stats["collision_faces"] > 0, "collision still built from valid walls")


func _test_portal_riser_and_collision() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	GeometryOps.close_loop_from_positions(data, _square(128, 0, 128))
	data.sectors[1]["floor_height"] = 128.0
	GeometryOps.validate(data)
	var stats := _build(data)
	_check(stats["wall_quads"] == 7, "riser quad added (6 solid + 1), got %d" % stats["wall_quads"])
	_check(stats["collision_faces"] == 28, "collision: (6 solid + riser) x 2 windings = 28 tris, got %d" % stats["collision_faces"])


func _test_same_height_portal_open() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	GeometryOps.close_loop_from_positions(data, _square(128, 0, 128))
	var stats := _build(data)
	_check(stats["wall_quads"] == 6, "same-height portal is an open passage (no riser/lintel)")
	_check(stats["collision_faces"] == 24, "no riser collision on open passage")


func _build(data: LevelData) -> Dictionary:
	var root := Node3D.new()
	var stats := SectorMeshBuilder.build_level(root, data, STEP)
	root.free()
	return stats


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
