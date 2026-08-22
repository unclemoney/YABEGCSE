extends SceneTree

## PlatformTest
##
## Headless harness for platform drawing (PlatformData, PlatformDrawTool,
## commit_platform defaults, validation, mesh generation, serializer
## round-trip through the objects section) and the inner sector height
## shortcut (GeometryOps.surrounding_sector, ToolSystem.
## commit_match_surrounding, undo-snapshot discipline).
## Run: godot --path <repo> --headless -s Tests/PlatformTest.gd

const LOG := "res://Tests/platform_test.log"

var _failures := 0
var _lines: Array[String] = []


func _initialize() -> void:
	# ToolSystem is a Node: defer so add_child runs its _ready (tool set).
	_begin.call_deferred()


func _begin() -> void:
	_test_commit_platform_defaults()
	_test_commit_platform_in_void()
	_test_platform_validation()
	_test_platform_mesh()
	_test_highlight_mesh()
	_test_serializer_round_trip()
	_test_surrounding_sector()
	_test_match_surrounding()
	_test_platform_draw_tool_input()
	_test_shift_h_l_key_route()
	_test_platform_duplicate_independence()
	_finish()


func _make_tool_system(data: LevelData) -> ToolSystem:
	var ts := ToolSystem.new()
	root.add_child(ts)
	ts.set_level_data(data)
	return ts


func _release(ts: ToolSystem) -> void:
	root.remove_child(ts)
	ts.free()


func _test_commit_platform_defaults() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	data.sectors[0]["floor_height"] = 32.0
	var ts := _make_tool_system(data)
	ts.set_brush_art("BASICLIB/BOX1")
	var emissions := [0]
	ts.mutation_committed.connect(func() -> void: emissions[0] += 1)
	ts.commit_platform(_square(32, 32, 64))
	_check(data.platforms.size() == 1, "platform appended to LevelData")
	var p: PlatformData = data.platforms[0]
	_check(p.floor_height == 32.0, "floor height defaults to sector floor at centroid")
	_check(p.ceiling_height == 48.0, "ceiling height defaults to floor + 16 (thin platform)")
	_check(p.texture == "BASICLIB/BOX1", "texture defaults to the current UI brush art")
	_check(p.is_trigger == false and p.trigger_params.is_empty(), "trigger fields default off/empty")
	_check(emissions[0] == 1, "one platform commit = one undo snapshot")
	_check(data.flagged_platforms.is_empty(), "valid platform is not flagged")
	_release(ts)


func _test_commit_platform_in_void() -> void:
	var data := LevelData.create_empty()
	var ts := _make_tool_system(data)
	ts.commit_platform(_square(512, 512, 64))
	_check(data.platforms.size() == 1, "void platform appended")
	_check(data.platforms[0].floor_height == 0.0, "void platform floor defaults to 0")
	_check(data.platforms[0].ceiling_height == 16.0, "void platform ceiling defaults to 16")
	_release(ts)


func _test_platform_validation() -> void:
	var data := LevelData.create_empty()
	var few := PlatformData.new()
	few.vertices = [Vector2(0, 0), Vector2(64, 0)]
	data.platforms.append(few)
	var bowtie := PlatformData.new()
	bowtie.vertices = [
		Vector2(0, 0), Vector2(128, 128), Vector2(128, 0), Vector2(0, 128)]
	data.platforms.append(bowtie)
	var flat := PlatformData.new()
	flat.vertices = [Vector2(0, 0), Vector2(64, 0), Vector2(128, 0)]
	data.platforms.append(flat)
	var ok := PlatformData.new()
	ok.vertices = [Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)]
	data.platforms.append(ok)
	GeometryOps.validate(data)
	_check(str(data.flagged_platforms.get(0, "")).contains("fewer than 3"),
		"sub-3-point platform flagged")
	_check(str(data.flagged_platforms.get(1, "")).contains("self-intersecting"),
		"bowtie platform flagged self-intersecting")
	_check(str(data.flagged_platforms.get(2, "")).contains("degenerate"),
		"collinear platform flagged degenerate")
	_check(not data.flagged_platforms.has(3), "valid triangle platform not flagged")


func _test_platform_mesh() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	var ok := PlatformData.new()
	ok.vertices = [Vector2(32, 32), Vector2(96, 32), Vector2(96, 96), Vector2(32, 96)]
	ok.floor_height = 64.0
	ok.ceiling_height = 48.0
	ok.texture = "BASICLIB/BOX1.png"
	data.platforms.append(ok)
	var bad := PlatformData.new()
	bad.vertices = [Vector2(0, 0), Vector2(128, 128), Vector2(128, 0), Vector2(0, 128)]
	data.platforms.append(bad)
	GeometryOps.validate(data)
	var node := Node3D.new()
	root.add_child(node)
	var stats := SectorMeshBuilder.build_level(node, data, 24.0)
	_check(int(stats["platforms_built"]) == 1, "valid platform meshed")
	_check(int(stats["platforms_skipped"]) == 1, "flagged platform skipped in mesh generation")
	var mesh_instance := node.get_node_or_null("PlatformMesh_BASICLIB_BOX1_png")
	_check(mesh_instance != null, "textured platform mesh node exists")
	if mesh_instance != null:
		var arrays: Array = (mesh_instance as MeshInstance3D).mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# A quad = 2 triangles x 2 faces (top + underside) = 12 vertices.
		_check(verts.size() == 12, "platform emits top + bottom faces (got %d verts)" % verts.size())
		var tops := 0
		var bottoms := 0
		for v in verts:
			if is_equal_approx(v.y, 64.0):
				tops += 1
			elif is_equal_approx(v.y, 48.0):
				bottoms += 1
		_check(tops == 6 and bottoms == 6, "top face at floor_height, underside at ceiling_height")
	root.remove_child(node)
	node.free()


func _test_highlight_mesh() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 64))  # pillar inner loop
	var mesh := SectorMeshBuilder.build_sector_highlight(data, 0, 0.5)
	_check(mesh != null, "highlight mesh builds for a sector with an inner loop")
	if mesh != null:
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(not verts.is_empty(), "highlight mesh has triangles")
		var flat := true
		for v in verts:
			if not is_equal_approx(v.y, 0.5):
				flat = false
		_check(flat, "highlight floats at floor + offset")
	_check(SectorMeshBuilder.build_sector_highlight(data, 99, 0.5) == null,
		"highlight mesh is null for an invalid sector id")


func _test_serializer_round_trip() -> void:
	var text := """
	{
		"header": {"format": "yabegcse-level", "version": 0},
		"meta": {"name": "platforms"},
		"objects": [
			{
				"type": "platform",
				"vertices": [[16.0, 16.0], [80.0, 16.0], [80.0, 80.0]],
				"floor_height": 40.0,
				"ceiling_height": 56.0,
				"texture": "BASICLIB/BOX1.png",
				"is_trigger": true,
				"trigger_params": {"tag": "lift"},
				"future_field": 7
			},
			{
				"type": "platform",
				"pos": [5.0, 6.0], "z": 1.0, "angle": 0.0,
				"art": "", "params": {"size": [64.0, 64.0]}
			},
			{
				"type": "billboard",
				"pos": [1.0, 2.0], "z": 0.0, "angle": 0.0,
				"art": "SOBJ_LIB/BARSTOOL", "params": {"scale": 1.0}
			}
		],
		"unknown_future_section": {"keep": "me"}
	}
	"""
	var serializer := LevelSerializer.new()
	var data := serializer.load_from_json(text)
	_check(data != null, "fixture loads: %s" % serializer.last_error)
	if data == null:
		return
	_check(data.platforms.size() == 1, "polygon platform reconstructed into LevelData.platforms")
	_check(data.objects.size() == 2, "pos-based platform and billboard stay in objects")
	var p: PlatformData = data.platforms[0]
	_check(p.vertices.size() == 3 and p.vertices[1] == Vector2(80, 16), "vertices preserved")
	_check(p.floor_height == 40.0 and p.ceiling_height == 56.0, "heights preserved")
	_check(p.texture == "BASICLIB/BOX1.png", "texture preserved")
	_check(p.is_trigger and str(p.trigger_params.get("tag", "")) == "lift",
		"trigger fields preserved")
	var out := serializer.save_to_json(data)
	var json := JSON.new()
	_check(json.parse(out) == OK, "saved JSON parses")
	var objects: Array = json.data["objects"]
	_check(objects.size() == 3, "objects section carries 2 objects + 1 platform")
	var saved_platform: Dictionary = objects[2]
	_check(str(saved_platform.get("type", "")) == "platform", "platform saved with type platform")
	_check(int(saved_platform.get("future_field", -1)) == 7, "unknown platform field round-trips")
	_check((saved_platform["vertices"] as Array).size() == 3, "vertices saved")
	_check(json.data.has("unknown_future_section"), "unknown top-level section survives")
	var reloaded := serializer.load_from_json(out)
	_check(reloaded != null and reloaded.platforms.size() == 1 and reloaded.objects.size() == 2,
		"re-save round-trip is stable")
	if reloaded != null and reloaded.platforms.size() == 1:
		var rp: PlatformData = reloaded.platforms[0]
		_check(rp.floor_height == 40.0 and rp.is_trigger
			and str(rp.trigger_params.get("tag", "")) == "lift",
			"reloaded platform keeps all fields")


func _test_surrounding_sector() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))  # room
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 64))  # pillar
	GeometryOps.close_loop_from_positions(data, _square(512, 512, 64))  # detached
	_check(GeometryOps.surrounding_sector(data, 1) == 0, "pillar's surrounding sector is the room")
	_check(GeometryOps.surrounding_sector(data, 0) == -1, "the room has no surrounding sector")
	_check(GeometryOps.surrounding_sector(data, 2) == -1, "detached sector has none either")
	_check(GeometryOps.surrounding_sector(data, 99) == -1, "out-of-range id tolerated")


func _test_match_surrounding() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 64))
	data.sectors[0]["floor_height"] = 16.0
	data.sectors[0]["ceiling_height"] = 192.0
	data.sectors[1]["ceiling_slope"] = [[4, 64.0], [5, 64.0], [6, 64.0]]
	var ts := _make_tool_system(data)
	var emissions := [0]
	ts.mutation_committed.connect(func() -> void: emissions[0] += 1)
	var result := ts.commit_match_surrounding(1, &"ceiling")
	_check(bool(result["ok"]) and int(result["surrounding"]) == 0, "ceiling match succeeds")
	_check(float(data.sectors[1]["ceiling_height"]) == 192.0,
		"inner ceiling raised to the surrounding ceiling")
	_check((data.sectors[1]["ceiling_slope"] as Array).is_empty(),
		"matched face slope cleared so the change is visible")
	result = ts.commit_match_surrounding(1, &"floor")
	_check(bool(result["ok"]), "floor match succeeds")
	_check(float(data.sectors[1]["floor_height"]) == 16.0,
		"inner floor lowered to the surrounding floor")
	_check(emissions[0] == 2, "two matches = two undo snapshots")
	result = ts.commit_match_surrounding(0, &"ceiling")
	_check(not bool(result["ok"]) and str(result["reason"]) == "no_surrounding",
		"outer sector rejected: no surrounding sector")
	_check(emissions[0] == 2, "rejected shortcut never touches the undo stack")
	_release(ts)


func _test_platform_draw_tool_input() -> void:
	var data := LevelData.create_empty()
	var ts := _make_tool_system(data)
	ts.cycle_tool(1)
	ts.cycle_tool(1)
	ts.cycle_tool(1)
	_check(ts.get_tool_mode_name() == "PLATFORM DRAW", "cycle reaches Platform Draw")
	for pos in [Vector2(0, 0), Vector2(64, 0), Vector2(64, 64)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		_check(ts.handle_input(click, pos, pos), "vertex click consumed")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_check(ts.handle_input(enter, Vector2.ZERO, Vector2.ZERO), "Enter closes the loop")
	_check(data.platforms.size() == 1, "drawn platform committed")
	_check(data.sectors.is_empty(), "platform drawing creates no sector")
	_release(ts)


## Drives Edit3DTool.handle_input with the real key events (Shift+H /
## Shift+L) against fabricated crosshair aims — the same route 3D-mode
## input takes through Viewport3DView -> EditorController -> ToolSystem.
func _test_shift_h_l_key_route() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 64))
	data.sectors[0]["ceiling_height"] = 192.0
	var ts := _make_tool_system(data)
	var tool := Edit3DTool.new(ts)
	var statuses: Array[String] = []
	ts.status_requested.connect(func(t: String) -> void: statuses.append(t))
	var aim_inner := {"kind": &"floor", "sector_id": 1}
	var shift_h := InputEventKey.new()
	shift_h.keycode = KEY_H
	shift_h.pressed = true
	shift_h.shift_pressed = true
	_check(tool.handle_input(shift_h, aim_inner), "Shift+H consumed by the edit tool")
	_check(float(data.sectors[1]["ceiling_height"]) == 192.0,
		"Shift+H raised the inner ceiling to the room's")
	var shift_l := InputEventKey.new()
	shift_l.keycode = KEY_L
	shift_l.pressed = true
	shift_l.shift_pressed = true
	_check(tool.handle_input(shift_l, aim_inner), "Shift+L consumed")
	_check(float(data.sectors[1]["floor_height"]) == 0.0,
		"Shift+L lowered the inner floor to the room's")
	# Plain H (no Shift) must not fire the shortcut.
	var plain_h := InputEventKey.new()
	plain_h.keycode = KEY_H
	plain_h.pressed = true
	data.sectors[1]["ceiling_height"] = 64.0
	tool.handle_input(plain_h, aim_inner)
	_check(float(data.sectors[1]["ceiling_height"]) == 64.0, "plain H does not fire the shortcut")
	# A sector with no surrounding sector reports to the status line.
	tool.handle_input(shift_h, {"kind": &"floor", "sector_id": 0})
	_check(statuses.size() > 0 and statuses[statuses.size() - 1].contains("No surrounding sector")
		or statuses[statuses.size() - 1].contains("no surrounding sector"),
		"rejected shortcut reports to the status line")
	# Void crosshair: no sector aimed.
	tool.handle_input(shift_h, {"kind": &"none"})
	_check(statuses[statuses.size() - 1].contains("No sector under crosshair"),
		"void aim reports no sector under crosshair")
	_release(ts)


func _test_platform_duplicate_independence() -> void:
	var p := PlatformData.new()
	p.vertices = [Vector2(0, 0), Vector2(8, 0), Vector2(8, 8)]
	p.floor_height = 24.0
	p.trigger_params = {"tag": "a"}
	var copy: PlatformData = p.clone()
	copy.floor_height = 99.0
	copy.vertices[0] = Vector2(-1, -1)
	copy.trigger_params["tag"] = "b"
	_check(p.floor_height == 24.0, "clone does not share scalar state")
	_check(p.vertices[0] == Vector2(0, 0), "clone does not share the vertex array")
	_check(str(p.trigger_params["tag"]) == "a", "clone does not share trigger_params")


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
