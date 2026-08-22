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
	_test_zero_height_sector_aim()
	_test_angled_aim_inner_sector()
	_test_platform_edit_tool()
	_test_platform_visibility()
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


## Root-cause regression for the live flush-pillar failure: a STANDING
## camera aims at an angle, so the crosshair ray crosses the inner sector's
## portal-wall plane before it reaches the top face. A wall hit only counts
## where the wall has a rendered face at the hit height
## (GeometryOps._wall_has_face_at): a flush inner sector renders no wall
## (its floors and ceilings match the room's), so the ray must pass through
## to the floor hit that the innermost-sector remap needs.
func _test_angled_aim_inner_sector() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))  # room
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 64))  # inner
	var origin := Vector3(32, 140, 32)  # eye height, standing in the room
	var dir := (Vector3(96, 0, 96) - origin).normalized()  # at the inner top face
	# Freshly drawn inner sector: same heights as the room, no wall face
	# anywhere on its boundary.
	var aim := GeometryOps.aim_from_ray(data, origin, dir)
	_check(aim.get("kind", &"none") == &"floor",
		"angled aim at a flush inner sector is a floor hit, not a phantom wall")
	_check(int(aim.get("sector_id", -1)) == 1, "angled aim selects the inner sector")
	var ts := _make_tool_system(data)
	var tool := Edit3DTool.new(ts)
	# The wheel now edits the inner sector's floor (not a wall offset).
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	tool.handle_input(wheel, aim)
	_check(float(data.sectors[1]["floor_height"]) == 8.0,
		"wheel raised the flush inner sector's floor")
	_check(float(data.walls[4]["offset_u"]) == 0.0, "wheel did not touch wall offsets")
	# Shift+L brings it back down to the room floor.
	var shift_l := InputEventKey.new()
	shift_l.keycode = KEY_L
	shift_l.pressed = true
	shift_l.shift_pressed = true
	tool.handle_input(shift_l, aim)
	_check(float(data.sectors[1]["floor_height"]) == 0.0, "Shift+L matched the inner floor")
	# A literal zero-height pillar (floor == ceiling == room floor) DOES
	# render a wall (room-side lintel spans floor..ceiling), so the wall hit
	# is on a real face and stands.
	data.sectors[1]["floor_height"] = 0.0
	data.sectors[1]["ceiling_height"] = 0.0
	GeometryOps.validate(data)
	var column := GeometryOps.aim_from_ray(data, origin, dir)
	_check(column.get("kind", &"none") == &"wall",
		"zero-height pillar's rendered column wall is still aimable")
	_check(int(column.get("sector_id", -1)) == 1, "column wall belongs to the inner sector")
	var shift_h := InputEventKey.new()
	shift_h.keycode = KEY_H
	shift_h.pressed = true
	shift_h.shift_pressed = true
	tool.handle_input(shift_h, column)
	_check(float(data.sectors[1]["ceiling_height"]) == 256.0,
		"Shift+H works through the column wall aim")
	_release(ts)
	# A doorway passage is phantom too: aiming through a flat portal (equal
	# floors, equal ceilings) at the next room's floor must not stop on the
	# portal wall plane.
	var halls := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(halls, _square(0, 0, 256))
	GeometryOps.close_loop_from_positions(halls, _square(256, 64, 128))  # shares the x=256 wall
	var through := GeometryOps.aim_from_ray(halls,
		Vector3(192, 140, 128), (Vector3(320, 0, 128) - Vector3(192, 140, 128)).normalized())
	_check(through.get("kind", &"none") == &"floor",
		"aim through a flat portal passes the phantom wall plane")
	_check(int(through.get("sector_id", -1)) == 1, "aim through the portal selects the far room")


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


## Issue 1: a zero-height inner sector (flush pillar) has no geometry for
## the pure raycast to hit — the ray lands on the surrounding sector's
## floor. aim_from_ray must remap the hit to the innermost sector at the
## hit point (2D point-in-polygon), and Shift+H/L must then work on it.
func _test_zero_height_sector_aim() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))  # room
	GeometryOps.close_loop_from_positions(data, _square(64, 64, 64))  # pillar
	data.sectors[1]["ceiling_height"] = 0.0  # flush: floor == ceiling == room floor
	var aim := GeometryOps.aim_from_ray(data, Vector3(96, 200, 96), Vector3(0, -1, 0))
	_check(aim.get("kind", &"none") == &"floor", "flush pillar aim kind is floor")
	_check(int(aim.get("sector_id", -1)) == 1,
		"flush pillar selected via point-in-polygon, not the surrounding sector")
	# Outside every sector: the raw raycast fallback (none here — the void
	# has no planes).
	var miss := GeometryOps.aim_from_ray(data, Vector3(-500, 200, -500), Vector3(0, -1, 0))
	_check(miss.get("kind", &"none") == &"none", "void aim falls back to no hit")
	# Shift+H on the remapped aim raises the pillar ceiling to the room's.
	var ts := _make_tool_system(data)
	var tool := Edit3DTool.new(ts)
	var shift_h := InputEventKey.new()
	shift_h.keycode = KEY_H
	shift_h.pressed = true
	shift_h.shift_pressed = true
	_check(tool.handle_input(shift_h, aim), "Shift+H consumed on the remapped aim")
	_check(float(data.sectors[1]["ceiling_height"]) == 256.0,
		"Shift+H raised the flush pillar's ceiling to the room's")
	_release(ts)


## Issue 4: Platform Edit mode — cycle reaches it, click selects, V
## toggles visibility, T textures via the shared commit_texture path,
## Delete removes. All mutations take exactly one undo snapshot.
func _test_platform_edit_tool() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	var ts := _make_tool_system(data)
	ts.commit_platform(_square(32, 32, 64))
	ts.commit_platform(_square(320, 320, 64))
	for i in range(4):
		ts.cycle_tool(1)
	_check(ts.get_tool_mode_name() == "PLATFORM EDIT", "cycle reaches Platform Edit")
	var emissions := [0]
	ts.mutation_committed.connect(func() -> void: emissions[0] += 1)
	# Hover then click selects the smallest platform under the cursor.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(48, 48)
	ts.handle_input(motion, Vector2(48, 48), Vector2(48, 48))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_check(ts.handle_input(click, Vector2(48, 48), Vector2(48, 48)), "select click consumed")
	_check(ts.get_selected_platform() == 0, "platform 0 selected")
	# V toggles visibility.
	var vkey := InputEventKey.new()
	vkey.keycode = KEY_V
	vkey.pressed = true
	_check(ts.handle_input(vkey, Vector2.ZERO, Vector2.ZERO), "V consumed")
	_check(not data.platforms[0].is_visible, "V hid the platform")
	ts.handle_input(vkey, Vector2.ZERO, Vector2.ZERO)
	_check(data.platforms[0].is_visible, "V showed it again")
	# T opens the texture picker for the selection; commit_texture applies.
	var tkey := InputEventKey.new()
	tkey.keycode = KEY_T
	tkey.pressed = true
	_check(ts.handle_input(tkey, Vector2.ZERO, Vector2.ZERO), "T consumed")
	ts.commit_texture("BASICLIB/BOX1.png")
	_check(data.platforms[0].texture == "BASICLIB/BOX1.png", "texture applied to platform")
	# Delete removes the selected platform.
	var del := InputEventKey.new()
	del.keycode = KEY_DELETE
	del.pressed = true
	_check(ts.handle_input(del, Vector2.ZERO, Vector2.ZERO), "Delete consumed")
	_check(data.platforms.size() == 1, "selected platform deleted")
	_check(ts.get_selected_platform() == -1, "selection cleared after delete")
	_check(emissions[0] == 4, "V x2 + texture + delete = four undo snapshots")
	_release(ts)


## Issue 4: invisible platforms skip 3D mesh generation, are not aimable
## in 3D, and the visibility flag round-trips through the serializer.
func _test_platform_visibility() -> void:
	var data := LevelData.create_empty()
	GeometryOps.close_loop_from_positions(data, _square(0, 0, 256))
	var p := PlatformData.new()
	p.vertices = [Vector2(32, 32), Vector2(96, 32), Vector2(96, 96), Vector2(32, 96)]
	p.floor_height = 64.0
	p.ceiling_height = 48.0
	data.platforms.append(p)
	GeometryOps.validate(data)
	# Visible platform: meshed and aimable in 3D.
	var node := Node3D.new()
	root.add_child(node)
	var stats := SectorMeshBuilder.build_level(node, data, 24.0)
	_check(int(stats["platforms_built"]) == 1, "visible platform meshed")
	var aim := GeometryOps.aim_from_ray(data, Vector3(64, 200, 64), Vector3(0, -1, 0))
	_check(aim.get("kind", &"none") == &"platform", "visible platform aimed in 3D")
	_check(int(aim.get("platform_id", -1)) == 0, "platform aim carries the platform id")
	# Invisible: skipped by the mesh builder and the 3D aim, still
	# selectable in 2D.
	p.is_visible = false
	stats = SectorMeshBuilder.build_level(node, data, 24.0)
	_check(int(stats["platforms_built"]) == 0, "invisible platform skips mesh generation")
	aim = GeometryOps.aim_from_ray(data, Vector3(64, 200, 64), Vector3(0, -1, 0))
	_check(aim.get("kind", &"none") != &"platform", "invisible platform not aimable in 3D")
	_check(GeometryOps.platform_at(data, Vector2(64, 64)) == 0,
		"invisible platform still selectable in 2D")
	# Serializer round-trip preserves the flag.
	var serializer := LevelSerializer.new()
	var reloaded := serializer.load_from_json(serializer.save_to_json(data))
	_check(reloaded != null and reloaded.platforms.size() == 1, "platform round-trips")
	if reloaded != null and reloaded.platforms.size() == 1:
		_check(not reloaded.platforms[0].is_visible, "is_visible preserved by save/load")
	# Default: a platform entry without is_visible loads as visible.
	var bare := serializer.load_from_json("""
	{
		"header": {"format": "yabegcse-level", "version": 0},
		"objects": [{"type": "platform", "vertices": [[0, 0], [8, 0], [8, 8]]}]
	}
	""")
	_check(bare != null and bare.platforms.size() == 1
		and bare.platforms[0].is_visible, "is_visible defaults to true on load")
	root.remove_child(node)
	node.free()


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
