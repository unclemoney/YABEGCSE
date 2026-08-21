extends SceneTree

## Edit3DTest
##
## Headless harness for M3: slope plane math + flag degradation, aim
## raycast picking, ToolSystem 3D commits (raise/lower, corner drags, wall
## offsets, textures), slope-aware mesh building, serializer round-trip.
## Run: godot --path <repo> --headless -s Tests/Edit3DTest.gd

const LOG := "res://Tests/edit_3d.log"
const STEP := 24.0

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_begin.call_deferred()


func _begin() -> void:
	_test_fixture_loads_and_flags()
	_test_slope_plane_math()
	_test_flat_fallbacks()
	_test_aim_raycast()
	_test_raise_lower_and_flag()
	_test_corner_drag_sequence()
	_test_corner_drag_interaction()
	_test_wall_offsets()
	_test_textures_and_missing()
	_test_serializer_round_trip()
	_finish()


func _test_fixture_loads_and_flags() -> void:
	var data := _load_fixture()
	_check(data != null, "slope fixture loads")
	if data == null:
		return
	_check(not data.flagged_sectors.has(0), "valid sloped sector not flagged")
	_check(data.flagged_sectors.has(1) and data.flagged_sectors[1].contains("incomplete"),
		"incomplete slope flagged (%s)" % data.flagged_sectors.get(1, "-"))
	_check(data.flagged_sectors.has(2) and data.flagged_sectors[2].contains("collinear"),
		"collinear slope flagged (%s)" % data.flagged_sectors.get(2, "-"))


func _test_slope_plane_math() -> void:
	var data := LevelData.create_empty()
	var si := GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	var sector: Dictionary = data.sectors[si]
	# Corners (0,0)->0, (256,0)->32, (0,256)->64: h = x/8 + y/4.
	var pids := _corner_ids(data, si)
	GeometryOps.set_slope_corner(sector, &"floor_slope", pids[0], 0.0)  # (0,0)
	GeometryOps.set_slope_corner(sector, &"floor_slope", pids[1], 32.0)  # (256,0)
	GeometryOps.set_slope_corner(sector, &"floor_slope", pids[3], 64.0)  # (0,256)
	GeometryOps.validate(data)
	_check(not data.flagged_sectors.has(si), "valid 3-corner slope not flagged")
	_check(absf(GeometryOps.floor_height_at(data, si, Vector2(256, 256)) - 96.0) < 0.5,
		"plane height at far corner (%f)" % GeometryOps.floor_height_at(data, si, Vector2(256, 256)))
	_check(absf(GeometryOps.floor_height_at(data, si, Vector2(128, 128)) - 48.0) < 0.5,
		"plane height at center (%f)" % GeometryOps.floor_height_at(data, si, Vector2(128, 128)))


func _test_flat_fallbacks() -> void:
	var data := LevelData.create_empty()
	var si := GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	data.sectors[si]["floor_height"] = 40.0
	_check(GeometryOps.floor_height_at(data, si, Vector2(10, 10)) == 40.0, "no slope: flat height")
	# Incomplete slope: flat + flagged.
	GeometryOps.set_slope_corner(data.sectors[si], &"floor_slope", 0, 16.0)
	GeometryOps.set_slope_corner(data.sectors[si], &"floor_slope", 1, 24.0)
	GeometryOps.validate(data)
	_check(GeometryOps.floor_height_at(data, si, Vector2(10, 10)) == 40.0, "incomplete slope: flat")
	_check(data.flagged_sectors.has(si), "incomplete slope flagged")


func _test_aim_raycast() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var down := GeometryOps.aim_from_ray(data, Vector3(64, 200, 64), Vector3(0, -1, 0))
	_check(down.get("kind") == &"floor", "ray down hits floor")
	_check(int(down.get("sector_id", -1)) == 0, "floor hit sector 0")
	_check(absf((down.get("point", Vector3.ZERO) as Vector3).y) < 0.01, "floor hit at y=0")
	var up := GeometryOps.aim_from_ray(data, Vector3(64, 100, 64), Vector3(0, 1, 0))
	_check(up.get("kind") == &"ceiling", "ray up hits ceiling")
	var east := GeometryOps.aim_from_ray(data, Vector3(64, 100, 64), Vector3(1, 0, 0))
	_check(east.get("kind") == &"wall", "ray sideways hits wall")
	_check(int(east.get("wall_id", -1)) >= 0, "wall id resolved")
	var miss := GeometryOps.aim_from_ray(data, Vector3(-500, 100, -500), Vector3(-1, 0, 0))
	_check(miss.get("kind") == &"none", "ray into the void hits nothing")


func _test_raise_lower_and_flag() -> void:
	var data := LevelData.create_empty()
	var si := GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var system := ToolSystem.new()
	root.add_child(system)
	system.set_level_data(data)
	system.commit_height(si, &"floor", 8.0)
	_check(float(data.sectors[si]["floor_height"]) == 8.0, "floor raised by one tick")
	system.commit_height(si, &"floor", -8.0)
	_check(float(data.sectors[si]["floor_height"]) == 0.0, "floor lowered back")
	system.commit_height(si, &"ceiling", -256.0)
	_check(data.flagged_sectors.has(si) and data.flagged_sectors[si].contains("floor at or above ceiling"),
		"floor >= ceiling flagged")
	system.queue_free()


func _test_corner_drag_sequence() -> void:
	var data := LevelData.create_empty()
	var si := GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	var system := ToolSystem.new()
	root.add_child(system)
	system.set_level_data(data)
	var pids := _corner_ids(data, si)
	system.begin_corner_drag()
	system.update_corner_drag(si, &"floor_slope", pids[0], 0.0)
	system.update_corner_drag(si, &"floor_slope", pids[1], 32.0)
	system.end_corner_drag()
	_check(data.flagged_sectors.has(si), "2 corners: still flagged incomplete")
	system.begin_corner_drag()
	system.update_corner_drag(si, &"floor_slope", pids[3], 64.0)
	system.end_corner_drag()
	_check(not data.flagged_sectors.has(si), "3 corners: slope valid")
	# Mesh reflects the slope: floor vertex heights differ across the room.
	var mesh_root := Node3D.new()
	SectorMeshBuilder.build_level(mesh_root, data, STEP)
	var floor_mesh := mesh_root.get_node_or_null("FloorMesh") as MeshInstance3D
	_check(floor_mesh != null, "sloped sector still builds (not skipped)")
	if floor_mesh != null:
		var verts: PackedVector3Array = floor_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lo := INF
		var hi := -INF
		for v in verts:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		_check(hi - lo > 32.0, "floor heights vary with slope (%.1f..%.1f)" % [lo, hi])
	mesh_root.free()
	system.queue_free()


## _test_corner_drag_interaction()
##
## The interaction-layer regression: drives the Edit3DTool through
## ToolSystem with a synthetic crosshair aim (the same path Viewport3DView
## -> EditorController takes). The old fixed 32-unit grab range made the
## drag unreachable from a standing camera; now the corner nearest the
## aim point is grabbed, and nothing is written until the drag moves.
## The first motion seeds a complete 3-corner plane (grabbed corner +
## two farthest anchors at the flat base), so ONE drag already tilts the
## face; later drags on other corners adjust the plane without growing
## past 3 entries.
func _test_corner_drag_interaction() -> void:
	var data := LevelData.create_empty()
	var si := GeometryOps.close_loop_from_positions(data, _square(0, 0, 512))
	var system := ToolSystem.new()
	root.add_child(system)
	system.set_level_data(data)
	system.set_mode_3d(true)
	var aim := {
		"kind": &"floor", "sector_id": si, "wall_id": -1,
		"point": Vector3(256, 0, 256), "distance": 380.0,
	}
	# A bare click (press + release, no motion) must not pollute the slope.
	system.handle_3d_input(_action(&"grab_corner", true), aim)
	system.handle_3d_input(_action(&"grab_corner", false), aim)
	_check((data.sectors[si]["floor_slope"] as Array).is_empty(),
		"bare click on a floor leaves the slope empty")
	# LMB drag aimed at the middle of the room: the nearest corner is
	# ~362 units away — far beyond the old 32-unit snap.
	system.handle_3d_input(_action(&"grab_corner", true), aim)
	_check(system.handle_3d_motion(Vector2(0, -20), aim), "drag motion consumed")
	system.handle_3d_input(_action(&"grab_corner", false), aim)
	var slope: Array = data.sectors[si]["floor_slope"]
	_check(slope.size() == 3, "one drag seeds a complete 3-corner plane (got %d)" % slope.size())
	_check(not data.flagged_sectors.has(si), "seeded plane validates clean")
	var raised: Array = []
	for entry in slope:
		if float(entry[1]) != 0.0:
			raised.append(entry)
	_check(raised.size() == 1, "exactly one corner raised by the drag (got %d)" % raised.size())
	if raised.size() == 1:
		_check(absf(float(raised[0][1]) - 40.0) < 0.01,
			"corner raised by 20px * DRAG_SCALE = 40 (got %f)" % float(raised[0][1]))
		var corner := GeometryOps.get_point(data, int(raised[0][0]))
		_check(corner.distance_to(Vector2(256, 256)) > 300.0,
			"grabbed the nearest corner (%.0f, %.0f)" % [corner.x, corner.y])
	# A second drag aimed at another corner adjusts the plane: still
	# exactly 3 entries (the grabbed corner joins, the nearest seeded
	# anchor swaps out), still clean.
	var corner_aim := aim.duplicate()
	corner_aim["point"] = Vector3(512, 0, 0)
	system.handle_3d_input(_action(&"grab_corner", true), corner_aim)
	system.handle_3d_motion(Vector2(0, -30), corner_aim)
	system.handle_3d_input(_action(&"grab_corner", false), corner_aim)
	slope = data.sectors[si]["floor_slope"]
	_check(slope.size() == 3, "second drag keeps the plane at 3 corners (got %d)" % slope.size())
	_check(not data.flagged_sectors.has(si), "adjusted slope validates clean")
	# The mesh reflects it: floor vertex heights vary across the room.
	var mesh_root := Node3D.new()
	SectorMeshBuilder.build_level(mesh_root, data, STEP)
	var floor_mesh := mesh_root.get_node_or_null("FloorMesh") as MeshInstance3D
	_check(floor_mesh != null, "interaction-sloped sector builds")
	if floor_mesh != null:
		var verts: PackedVector3Array = floor_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lo := INF
		var hi := -INF
		for v in verts:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		_check(hi - lo > 30.0, "mesh is a tilted plane, not flat (%.1f..%.1f)" % [lo, hi])
	mesh_root.free()
	system.queue_free()


func _action(action: StringName, pressed: bool) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	return ev


func _test_wall_offsets() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 128))
	var system := ToolSystem.new()
	root.add_child(system)
	system.set_level_data(data)
	system.commit_wall_offset(0, 16.0, 8.0)
	_check(float(data.walls[0]["offset_u"]) == 16.0, "offset_u applied")
	_check(float(data.walls[0]["offset_v"]) == 8.0, "offset_v applied")
	var mesh_root := Node3D.new()
	SectorMeshBuilder.build_level(mesh_root, data, STEP)
	var wall_mesh := mesh_root.get_node_or_null("WallMesh") as MeshInstance3D
	if wall_mesh != null:
		var uvs: PackedVector2Array = wall_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		# UVs are scaled by 1/64 for the untextured group: u = (dist+16)/64.
		_check(absf(uvs[0].x - 0.25) < 0.001, "wall UV u includes offset (%f)" % uvs[0].x)
	else:
		_check(false, "wall mesh exists")
	mesh_root.free()
	system.queue_free()


func _test_textures_and_missing() -> void:
	_check(ArtCache.exists("BASICLIB/BLACK.png"), "known texture resolves")
	_check(not ArtCache.exists("NOPE/MISSING.png"), "bogus texture rejected")
	var data := _load_fixture()
	if data == null:
		return
	var mesh_root := Node3D.new()
	var stats := SectorMeshBuilder.build_level(mesh_root, data, STEP)
	_check(stats["missing_textures"].has("NOPE/MISSING.png"), "missing texture reported")
	_check(mesh_root.get_node_or_null("FloorMesh_BASICLIB_BLACK_png") != null,
		"textured floor group committed")
	_check(stats["sectors_built"] >= 2, "slope-flagged sectors still build (flat)")
	mesh_root.free()


func _test_serializer_round_trip() -> void:
	var data := _load_fixture()
	if data == null:
		return
	var serializer := LevelSerializer.new()
	var text := serializer.save_to_json(data)
	var back := serializer.load_from_json(text)
	_check(back != null, "round-trip parses")
	if back == null:
		return
	var slope: Array = back.sectors[0]["floor_slope"]
	_check(slope.size() == 3, "slope survives round-trip")
	_check(slope[1][0] == 1 and absf(slope[1][1] - 32.0) < 0.001, "slope entries typed (int, float)")
	_check(float(back.walls[4]["offset_u"]) == 16.0, "wall offsets survive")
	_check(str(back.sectors[0]["floor_texture"]) == "BASICLIB/BLACK.png", "texture names survive")


func _load_fixture() -> LevelData:
	var serializer := LevelSerializer.new()
	var text := FileAccess.get_file_as_string("res://Tests/Fixtures/level_slopes_v0.json")
	return serializer.load_from_json(text)


func _square(x: float, y: float, size: float) -> Array:
	return [
		Vector2(x, y),
		Vector2(x + size, y),
		Vector2(x + size, y + size),
		Vector2(x, y + size),
	]


## _corner_ids(data, sector_id) -> Array[int]
##
## Outer-loop corner point ids in polygon order (a-endpoint per wall).
func _corner_ids(data: LevelData, sector_id: int) -> Array[int]:
	var ids: Array[int] = []
	for wid in data.sectors[sector_id]["walls"]:
		ids.append(data.walls[wid]["a"])
	return ids


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
