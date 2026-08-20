extends SceneTree

## ObjectTest
##
## Headless harness for M4: object commits (place/move/rotate/delete),
## undo snapshot coverage, serializer round-trip, 8-way view resolution
## with mirroring, view probing, fluid frames, ray picking, tolerate+flag
## on malformed entries, Objects3D smoke test.
## Run: godot --path <repo> --headless -s Tests/ObjectTest.gd

const LOG := "res://Tests/objects.log"

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_begin.call_deferred()


func _begin() -> void:
	_test_commits()
	_test_undo_snapshot()
	_test_serializer_round_trip()
	_test_view_resolution()
	_test_probe_and_frames()
	_test_malformed_flagged()
	_test_ray_pick()
	_test_objects_3d_smoke()
	_finish()


func _make_system() -> ToolSystem:
	var system := ToolSystem.new()
	root.add_child(system)
	return system


func _test_commits() -> void:
	var data := LevelData.create_empty()
	var system := _make_system()
	system.set_level_data(data)
	system.set_brush_type("billboard")
	system.set_brush_art("SOBJ_LIB/BARSTOOL.png")
	system.commit_object_place(Vector2(64, 32))
	_check(data.objects.size() == 1, "place: one object")
	var o: Dictionary = data.objects[0]
	_check(o["type"] == "billboard" and o["art"] == "SOBJ_LIB/BARSTOOL",
		"place: type + extension stripped (%s)" % o["art"])
	_check(o["pos"] == [64.0, 32.0], "place: position")
	system.commit_object_move(0, Vector2(100, 100), 16.0)
	_check(o["pos"] == [100.0, 100.0] and float(o["z"]) == 16.0, "move: pos + z")
	system.commit_object_rotate(0, 15.0)
	_check(float(o["angle"]) == 15.0, "rotate: 15 degrees")
	system.commit_object_z(0, -8.0)
	_check(float(o["z"]) == 8.0, "z nudge")
	system.commit_object_delete(0)
	_check(data.objects.is_empty(), "delete: empty")
	system.queue_free()


func _test_undo_snapshot() -> void:
	var data := LevelData.create_empty()
	var system := _make_system()
	system.set_level_data(data)
	var snapshots: Array = []
	system.mutation_committed.connect(
		func() -> void: snapshots.append({"objects": data.objects.duplicate(true)})
	)
	system.set_brush_type("fluid")
	system.set_brush_art("ANIM_LIB/BURN")
	system.commit_object_place(Vector2(0, 0))
	_check(snapshots.size() == 1, "undo snapshot captured before place")
	data.objects = snapshots[0]["objects"].duplicate(true)
	GeometryOps.validate(data)
	_check(data.objects.is_empty(), "undo restore removes the object")
	system.queue_free()


func _test_serializer_round_trip() -> void:
	var data := LevelData.create_empty()
	for type in ObjectOps.TYPES:
		var obj := ObjectOps.defaults(type)
		obj["pos"] = [16.0, 32.0]
		obj["art"] = "ANIM_LIB/BARREL"
		obj["angle"] = 45.0
		obj["z"] = 8.0
		data.objects.append(obj)
	data.objects[2]["params"]["views"] = {"1": "BUG_ENEM/BUG1BS", "5": "BUG_ENEM/BUG5BS"}
	var serializer := LevelSerializer.new()
	var text := serializer.save_to_json(data)
	var back := serializer.load_from_json(text)
	_check(back != null, "round-trip parses")
	if back == null:
		return
	_check(back.objects.size() == 5, "all five objects survive")
	_check(str(back.objects[0]["type"]) == "billboard", "type survives")
	_check(back.objects[0]["pos"] == [16.0, 32.0], "pos survives typed")
	_check(str(back.objects[2]["params"]["views"]["1"]) == "BUG_ENEM/BUG1BS", "views map survives")
	_check(back.flagged_objects.is_empty(), "no flags on clean round-trip")


func _test_view_resolution() -> void:
	var obj := ObjectOps.defaults("sprite_8way")
	var views := {}
	for v in range(1, 9):
		views[str(v)] = "BUG_ENEM/BUG%dBS" % v
	obj["params"]["views"] = views
	_check(ObjectOps.view_for_angle(obj, 0.0)["name"] == "BUG_ENEM/BUG1BS", "front view for 0 deg")
	_check(ObjectOps.view_for_angle(obj, 45.0)["name"] == "BUG_ENEM/BUG2BS", "view 2 for 45 deg")
	_check(ObjectOps.view_for_angle(obj, 180.0)["name"] == "BUG_ENEM/BUG5BS", "back view for 180 deg")
	_check(ObjectOps.view_for_angle(obj, 350.0)["name"] == "BUG_ENEM/BUG1BS", "wraps near 360")
	# Missing view 2 -> mirror partner 8.
	views.erase("2")
	var fallback := ObjectOps.view_for_angle(obj, 45.0)
	_check(fallback["name"] == "BUG_ENEM/BUG8BS" and fallback["mirrored"],
		"missing view falls back to mirrored partner")
	# Both missing -> nearest available, unmirrored.
	views.erase("8")
	var nearest := ObjectOps.view_for_angle(obj, 45.0)
	_check(not str(nearest["name"]).is_empty() and not nearest["mirrored"],
		"nearest view when partner absent")
	_check(ObjectOps.view_for_angle(ObjectOps.defaults("sprite_8way"), 0.0)["name"] == "",
		"no views -> empty name")


func _test_probe_and_frames() -> void:
	var views := ObjectOps.probe_views("BUG_ENEM/BUG1BS")
	_check(views.size() == 8, "BUG 8-view set probed (%d found)" % views.size())
	_check(str(views.get("3", "")) == "BUG_ENEM/BUG3BS", "digit substituted mid-name")
	var fluid := ObjectOps.defaults("fluid")
	fluid["art"] = "ANIM_LIB/BURN"
	var frames := ArtCache.resolve_object_frames(fluid)
	_check(frames.size() >= 2, "fluid frames discovered (%d)" % frames.size())
	var still := ObjectOps.defaults("billboard")
	still["art"] = "SOBJ_LIB/BARSTOOL"
	_check(ArtCache.resolve_object_frames(still).size() == 1, "static billboard: one frame")
	_check(ArtCache.resolve_object_frames(ObjectOps.defaults("billboard")).is_empty(),
		"empty art: no frames, no crash")


func _test_malformed_flagged() -> void:
	var data := LevelData.create_empty()
	data.objects.append({"type": "nope", "pos": "bad", "art": ""})
	data.objects.append("not even a dict")
	data.objects.append(ObjectOps.defaults("billboard"))
	GeometryOps.validate(data)
	_check(data.flagged_objects.has(0), "unknown type + bad pos flagged")
	_check(data.flagged_objects.has(1), "non-dict flagged")
	_check(data.flagged_objects.has(2), "empty art flagged")
	_check(data.flagged_objects.size() == 3, "exactly three flags")


func _test_ray_pick() -> void:
	var billboard := ObjectOps.defaults("billboard")
	billboard["pos"] = [0.0, 0.0]
	billboard["z"] = 0.0
	var hit := ObjectOps.ray_pick([billboard], Vector3(0, 50, -200), Vector3(0, 0, 1))
	_check(int(hit.get("object_id", -1)) == 0, "billboard hit face-on")
	_check(absf(float(hit.get("distance", 0.0)) - 200.0) < 1.0, "hit distance sane")
	var miss := ObjectOps.ray_pick([billboard], Vector3(0, 500, -200), Vector3(0, 0, 1))
	_check(miss.is_empty(), "ray above the quad misses")
	var platform := ObjectOps.defaults("platform")
	platform["pos"] = [0.0, 0.0]
	platform["z"] = 10.0
	var flat := ObjectOps.ray_pick([platform], Vector3(0, 100, 0), Vector3(0, -1, 0))
	_check(int(flat.get("object_id", -1)) == 0, "platform hit from above")
	var beside := ObjectOps.ray_pick([platform], Vector3(0, 100, 500), Vector3(0, -1, 0))
	_check(beside.is_empty(), "outside platform footprint misses")


func _test_objects_3d_smoke() -> void:
	var data := LevelData.create_empty()
	var specs := [
		{"type": "billboard", "art": "SOBJ_LIB/BARSTOOL"},
		{"type": "wall_object", "art": "ANIM_LIB/BARREL"},
		{"type": "sprite_8way", "art": "BUG_ENEM/BUG1BS"},
		{"type": "fluid", "art": "ANIM_LIB/BURN"},
		{"type": "platform", "art": "BASICLIB/BOX1"},
	]
	for spec in specs:
		var obj := ObjectOps.defaults(spec["type"])
		obj["art"] = spec["art"]
		if obj["type"] == "sprite_8way":
			obj["params"]["views"] = ObjectOps.probe_views(obj["art"])
		data.objects.append(obj)
	GeometryOps.validate(data)
	var objects_3d := Objects3D.new()
	root.add_child(objects_3d)
	objects_3d.set_level_data(data)
	objects_3d.rebuild()
	_check(objects_3d.get_child_count() == 5, "one sprite per object")
	var first := objects_3d.get_child(0) as Sprite3D
	_check(first != null and first.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "billboard mode set")
	_check(first.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD, "alpha-keyed discard set")
	var fluid_sprite := objects_3d.get_child(3) as Sprite3D
	_check(fluid_sprite != null and fluid_sprite.texture != null, "fluid textured")
	objects_3d.queue_free()


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
