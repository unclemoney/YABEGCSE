extends SceneTree

## EnvironmentTest
##
## Headless harness for M6: environment defaults, EnvironmentOps
## validation (fallback + note per malformed field), serializer
## round-trip of the environment section (unknown fields survive, notes
## never stored), sky-strip art resolution, and GameSettings persistence.
## Run: godot --path <repo> --headless -s Tests/EnvironmentTest.gd

const LOG := "res://Tests/environment.log"
const ENV_FIXTURE := "res://Tests/Fixtures/level_environment_v0.json"

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_begin.call_deferred()


func _begin() -> void:
	_test_defaults()
	_test_malformed()
	_test_valid_custom()
	_test_fixture_round_trip()
	_test_strip_art()
	_test_preferences_persistence()
	_finish()


func _test_defaults() -> void:
	var data := LevelData.create_empty()
	_check(data.environment.has("sky") and data.environment.has("void"),
		"create_empty carries sky + void blocks")
	var result := EnvironmentOps.settings(data)
	_check((result["notes"] as Array).is_empty(), "defaults validate with zero notes")
	var values: Dictionary = result["values"]
	_check(values["sky"]["mode"] == "flat" and values["void"]["mode"] == "fog_color",
		"default sky/void modes")
	_check(_approx(values["fog"]["near"], 128.0) and _approx(values["fog"]["far"], 1536.0),
		"default fog range")


func _test_malformed() -> void:
	var data := LevelData.create_empty()
	data.environment = {
		"fog": {"enabled": "yes", "color": "blurple", "near": 500.0, "far": 100.0},
		"ambient": "high",
		"sky": {"mode": "weird", "color": "#112233", "strip": ""},
		"void": {"mode": "black"},
	}
	var result := EnvironmentOps.settings(data)
	var values: Dictionary = result["values"]
	var notes: Array = result["notes"]
	_check(values["fog"]["enabled"] == true, "malformed fog.enabled -> default")
	_check(values["fog"]["color"] == "#202830", "malformed fog.color -> default")
	_check(_approx(values["fog"]["near"], 128.0) and _approx(values["fog"]["far"], 1536.0),
		"near >= far -> both reset to defaults")
	_check(_approx(values["ambient"], 1.0), "string ambient -> default")
	_check(values["sky"]["mode"] == "flat", "unknown sky mode -> flat")
	_check(values["void"]["mode"] == "fog_color", "unknown void mode -> default")
	_check(notes.size() >= 6, "one note per malformed field (got %d)" % notes.size())

	# Horizon strip with empty / missing art degrades to flat + note.
	data.environment = {"sky": {"mode": "horizon_strip", "color": "#112233", "strip": ""}}
	result = EnvironmentOps.settings(data)
	_check(result["values"]["sky"]["mode"] == "flat", "empty strip -> flat fallback")
	_check((result["notes"] as Array).size() == 1, "empty strip noted")
	data.environment = {"sky": {"mode": "horizon_strip", "color": "#112233", "strip": "NOPE404"}}
	result = EnvironmentOps.settings(data)
	_check(result["values"]["sky"]["mode"] == "flat", "missing strip art -> flat fallback")
	_check((result["notes"] as Array).size() == 1, "missing strip art noted")


func _test_valid_custom() -> void:
	var data := LevelData.create_empty()
	data.environment = {
		"fog": {"enabled": false, "color": "#3a4a5a", "near": 200.0, "far": 2048.0},
		"ambient": 0.7,
		"sky": {"mode": "horizon_strip", "color": "#3a4a5a", "strip": "SOBJ_LIB/SKYSIDE"},
		"void": {"mode": "sky_color"},
	}
	var result := EnvironmentOps.settings(data)
	var values: Dictionary = result["values"]
	_check((result["notes"] as Array).is_empty(), "valid custom environment: zero notes")
	_check(values["fog"]["enabled"] == false, "custom fog.enabled passes through")
	_check(values["sky"]["mode"] == "horizon_strip", "strip mode kept when art resolves")
	_check(_approx(values["ambient"], 0.7), "custom ambient passes through")
	_check(values["void"]["mode"] == "sky_color", "custom void mode passes through")


func _test_fixture_round_trip() -> void:
	var serializer := LevelSerializer.new()
	var text := FileAccess.get_file_as_string(ENV_FIXTURE)
	var data := serializer.load_from_json(text)
	_check(data != null, "environment fixture loads")
	if data == null:
		return
	# The malformed field is stored verbatim (validation is computed).
	_check(str(data.environment["fog"]["color"]) == "blurple",
		"malformed value stored verbatim in LevelData")
	var result := EnvironmentOps.settings(data)
	_check((result["notes"] as Array).size() == 1, "fixture yields exactly one note")
	_check(result["values"]["sky"]["mode"] == "horizon_strip", "fixture strip sky survives")
	# Round-trip: environment + an unknown field inside it survive.
	data.environment["future_field"] = {"x": 1}
	var saved := serializer.save_to_json(data)
	var back := serializer.load_from_json(saved)
	_check(back != null, "round-trip: re-parses")
	if back == null:
		return
	_check(back.environment.has("sky") and back.environment.has("future_field"),
		"round-trip: environment + unknown field survive")
	_check(not back.environment.has("notes"), "round-trip: notes never stored")


func _test_strip_art() -> void:
	_check(ArtCache.exists("SOBJ_LIB/SKYSIDE.png"), "SKYSIDE strip art in library")
	_check(ArtCache.find_base("SKYSIDE") == "SOBJ_LIB/SKYSIDE", "strip resolves via find_base")


func _test_preferences_persistence() -> void:
	var settings := root.get_node_or_null("/root/GameSettings")
	_check(settings != null, "GameSettings autoload present")
	if settings == null:
		return
	var path: String = settings.SETTINGS_PATH
	var existed := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_string(path) if existed else ""
	settings.walk_speed = 640.0
	settings.mouse_sensitivity = 0.004
	settings.eye_height = 150.0
	settings.step_height = 32.0
	settings.fog_enabled = false
	settings.save_settings()
	var cfg := ConfigFile.new()
	_check(cfg.load(path) == OK, "settings file written")
	_check(_approx(float(cfg.get_value("preferences", "walk_speed", 0.0)), 640.0),
		"walk_speed persisted")
	_check(_approx(float(cfg.get_value("preferences", "mouse_sensitivity", 0.0)), 0.004, 0.0001),
		"mouse_sensitivity persisted")
	_check(cfg.get_value("preferences", "fog_enabled", true) == false, "fog_enabled persisted")
	settings.walk_speed = 500.0
	settings.mouse_sensitivity = 0.0025
	settings.eye_height = 140.0
	settings.step_height = 24.0
	settings.fog_enabled = true
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(backup)
			file.close()
		settings.load_settings()
	else:
		DirAccess.remove_absolute(path)
		settings.load_settings()
	_check(_approx(settings.walk_speed, 500.0), "settings restored after test")


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
