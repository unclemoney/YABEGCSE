extends SceneTree

## GCSImportTest
##
## Headless harness for M5: objdef/univ parsing against the real DOS 1.3
## fixture pair (Tests/Fixtures/UNIV0.TXT + OBJDEF0.TXT), species mapping,
## unit/angle conversion, art aliasing, attribute bits, spawn hint,
## serializer round-trip with meta.import_report, object-wall collision,
## and tolerate+flag on malformed/unknown input (synthetic mini-pair).
## Run: godot --path <repo> --headless -s Tests/GCSImportTest.gd

const LOG := "res://Tests/gcs_import.log"
const UNIV := "res://Tests/Fixtures/UNIV0.TXT"
const OBJDEF := "res://Tests/Fixtures/OBJDEF0.TXT"
const CM := 5.0 / 3.0  # GCS cm -> v0 units

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_begin.call_deferred()


func _begin() -> void:
	_test_find_base()
	var result := _test_real_fixture()
	_test_synthetic_pair()
	_test_out_of_bounds_object()
	_test_round_trip(result["level"])
	_test_collision(result["level"])
	_finish()


## _import_real() -> Dictionary
func _import_real() -> Dictionary:
	var univ := FileAccess.get_file_as_string(UNIV)
	var objdef := FileAccess.get_file_as_string(OBJDEF)
	_check(not univ.is_empty() and not objdef.is_empty(), "fixtures readable")
	return GCSImporter.import_level(univ, objdef, "UNIV0.TXT", [])


func _test_find_base() -> void:
	_check(ArtCache.find_base("BRKWL1") == "BASICLIB/BRKWL1", "find_base: bare name")
	_check(ArtCache.find_base("..\\..\\$RP9A\\BASICLIB\\BRKWL1.VGR") == "BASICLIB/BRKWL1",
		"find_base: DOS path + extension")
	_check(ArtCache.find_base("brkwl1.vgr") == "BASICLIB/BRKWL1", "find_base: case-insensitive")
	_check(ArtCache.find_base("NOPE404") == "", "find_base: miss returns empty")


func _test_real_fixture() -> Dictionary:
	var result := _import_real()
	var level: LevelData = result["level"]
	var report: Dictionary = result["report"]
	_check(int(report["imported"]) == 174, "real fixture: 174 objects imported (got %d)" % int(report["imported"]))
	_check(level.objects.size() == 174, "real fixture: objects array size")
	var skipped: Array = report["skipped"]
	_check(skipped.size() == 4, "real fixture: 4 unknown-handle groups (got %d)" % skipped.size())
	var joined := "\n".join(skipped)
	_check("3700" in joined and "2193" in joined and "2159" in joined and "2191" in joined,
		"real fixture: skipped handles listed")
	var notes := "\n".join(report["notes"])
	_check("METL026" in notes, "real fixture: missing art noted")
	_check("door" in notes, "real fixture: door semantics noted")

	# univ line 2 -> objects[0]: species-0 wall, handle 3, anchor
	# (7800,8800) theta 16384 (=90 deg), 400x400 cm, art BRKWL1.
	var w: Dictionary = level.objects[0]
	_check(w["type"] == "wall_object", "wall: type")
	_check(w["art"] == "BASICLIB/BRKWL1", "wall: art resolved (%s)" % w["art"])
	_check(_approx(w["pos"][0], 7800.0 * CM + 200.0 * CM) and _approx(w["pos"][1], 8800.0 * CM),
		"wall: anchor shifted to centre along run direction")
	_check(_approx(w["angle"], 0.0), "wall: theta 16384 -> angle 0 (got %s)" % w["angle"])
	_check(_approx(w["params"]["size"][0], 400.0 * CM) and _approx(w["params"]["size"][1], 400.0 * CM),
		"wall: size in units")
	_check(bool(w["params"]["collide"]), "wall: collides by default")
	var gcs: Dictionary = w["params"]["gcs"]
	_check(int(gcs["handle"]) == 3 and int(gcs["species"]) == 0, "wall: provenance bag")

	# Handle 4 aliases handle 3's art at 565 cm (the 45-degree wall def).
	var diag: Dictionary = level.objects[6]  # univ line 8
	_check(int(diag["params"]["gcs"]["handle"]) == 4, "alias: handle 4 located")
	_check(diag["art"] == "BASICLIB/BRKWL1", "alias: art inherited from handle 3")
	_check(_approx(diag["params"]["size"][0], 565.0 * CM), "alias: wider diagonal size")
	_check(_approx(diag["angle"], 225.0), "alias: theta -24576 (-135 deg) -> angle 225")

	# Platform: univ line 122 (handle 4095, size from opval1/opval2).
	# 32 skipped lines before it shift the object index to 88.
	var platform: Dictionary = level.objects[88]
	_check(platform["type"] == "platform", "platform: type")
	_check(int(platform["params"]["gcs"]["handle"]) == 4095, "platform: handle")
	_check(_approx(platform["pos"][0], -1005.0 * CM) and _approx(platform["pos"][1], 3775.0 * CM),
		"platform: position")
	_check(_approx(platform["z"], 200.0 * CM), "platform: z")
	_check(_approx(platform["params"]["size"][0], 194.0 * CM) and _approx(platform["params"]["size"][1], 174.0 * CM),
		"platform: size from opvals")

	# Fluid: univ line 129 (handle 27, TRAP_1A.0 — table not parsed in v1).
	# 37 skipped lines before it shift the object index to 90.
	var fluid: Dictionary = level.objects[90]
	_check(fluid["type"] == "fluid", "fluid: type")
	_check(fluid["art"] == "TRAP_1A", "fluid: unresolved art kept as bare guess")
	_check(_approx(fluid["params"]["fps"], 8.0), "fluid: default fps")

	# Spawn hint from the "s" line.
	var spawn: Array = level.meta["spawn"]
	_check(_approx(spawn[0], 8018.0 * CM) and _approx(spawn[1], 8548.0 * CM), "spawn: position hint")

	# Tolerate + flag: nothing malformed in the real fixture.
	_check(level.flagged_objects.is_empty(), "real fixture: no flagged objects")
	return result


func _test_synthetic_pair() -> void:
	var objdef := "; comment\n" + \
		"setpath .\\lib\\\n" + \
		"0 100 WALLA.VGR 400 400\n" + \
		"2 101 PICK1.VGA 100 100\n" + \
		"9 102 MYSTERY.VGA 64 64\n" + \
		"0 104 100 565 400\n" + \
		"bogus line here\n"
	var univ := "s 100 200 0 0\n" + \
		"0 100 0 0 0 16384 64 0 0 0 0\n" + \
		"2 101 150 150 168 0 2 5 9 0 0\n" + \
		"7 999 0 0 0 0 0 0 0 0 0\n" + \
		"9 102 100 100 0 0 0 0 0 0 0\n" + \
		"0 104 400 0 0 -8192 0 0 0 0 0\n" + \
		"0 100 400\n"
	var result := GCSImporter.import_level(univ, objdef, "synthetic", [])
	var level: LevelData = result["level"]
	var report: Dictionary = result["report"]
	_check(int(report["imported"]) == 3, "synthetic: 3 imported (got %d)" % int(report["imported"]))
	_check((report["skipped"] as Array).size() == 3,
		"synthetic: malformed objdef + malformed univ + unknown handle skipped (got %d)" % (report["skipped"] as Array).size())
	var notes := "\n".join(report["notes"])
	_check("species 9" in notes, "synthetic: unsupported species noted")
	_check("999" in "\n".join(report["skipped"]), "synthetic: unknown handle reported")

	var wall: Dictionary = level.objects[0]
	_check(not bool(wall["params"]["collide"]), "synthetic: bitdontbump (64) clears collide")
	var pickup: Dictionary = level.objects[1]
	_check(pickup["type"] == "billboard", "synthetic: species 2 -> billboard")
	_check(_approx(pickup["z"], 168.0 * CM), "synthetic: z converts cm -> units")
	var opvals: Array = pickup["params"]["gcs"]["opvals"]
	_check(int(opvals[0]) == 5 and int(opvals[1]) == 9, "synthetic: red-box opvals preserved")
	var alias: Dictionary = level.objects[2]
	_check(alias["art"] == "WALLA" and _approx(alias["angle"], 135.0),
		"synthetic: alias art + theta -8192 (-45 deg) -> angle 135")
	var spawn: Array = level.meta["spawn"]
	_check(_approx(spawn[0], 100.0 * CM) and _approx(spawn[1], 200.0 * CM), "synthetic: spawn hint")


## _test_out_of_bounds_object()
##
## Objects past the ±10200 cm GCS world limit are kept — imported with
## their exact position, never dropped or clamped — so they still render
## on the 2D map (the 2D canvas draws the full object list uncapped).
func _test_out_of_bounds_object() -> void:
	var objdef := "0 200 WALLA.VGR 400 400\n"
	var univ := "0 200 15000 15000 0 16384 0 0 0 0 0\n"
	var result := GCSImporter.import_level(univ, objdef, "out-of-limit", [])
	var level: LevelData = result["level"]
	_check(level.objects.size() == 1, "out-of-limit object imports (not dropped)")
	if level.objects.size() == 1:
		var o: Dictionary = level.objects[0]
		# theta 16384 = 90 deg: run (1, 0), so the centre shifts +200 cm in x.
		_check(_approx(float(o["pos"][0]), 15200.0 * CM) and _approx(float(o["pos"][1]), 15000.0 * CM),
			"out-of-limit position preserved in units (got %s, %s)" % [str(o["pos"][0]), str(o["pos"][1])])
		_check(not level.flagged_objects.has(0), "out-of-limit object not hidden by a flag")


func _test_round_trip(level: LevelData) -> void:
	var serializer := LevelSerializer.new()
	var text := serializer.save_to_json(level)
	var back := serializer.load_from_json(text)
	_check(back != null, "round-trip: imported level re-parses as valid v0 JSON")
	if back == null:
		return
	_check(back.objects.size() == level.objects.size(), "round-trip: object count")
	_check(back.points.is_empty() and back.walls.is_empty() and back.sectors.is_empty(),
		"round-trip: geometry section stays empty")
	var report: Dictionary = back.meta.get("import_report", {})
	_check(int(report.get("imported", -1)) == 174, "round-trip: import report survives")
	var w: Dictionary = back.objects[0]
	_check(_approx(w["pos"][0], 7800.0 * CM + 200.0 * CM), "round-trip: object position survives")
	_check(int(w["params"]["gcs"]["handle"]) == 3, "round-trip: params.gcs survives")
	_check(back.header.get("format") == LevelData.FORMAT_ID, "round-trip: format id")
	var respawn: Array = back.meta.get("spawn", [])
	_check(respawn.size() >= 2 and _approx(respawn[0], 8018.0 * CM), "round-trip: spawn survives")


func _test_collision(level: LevelData) -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var stats := SectorMeshBuilder.build_level(root3d, level, 24.0)
	_check(int(stats["object_collision_quads"]) == 127,
		"collision: 127 object-wall quads (got %d)" % int(stats["object_collision_quads"]))
	var body := root3d.get_node_or_null("CollisionBody")
	_check(body != null, "collision: body exists for a geometry-less import")
	root3d.queue_free()


func _approx(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) < eps


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
