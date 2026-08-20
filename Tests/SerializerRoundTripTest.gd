extends SceneTree

## SerializerRoundTripTest
##
## Headless round-trip harness for the v0 envelope.
## Run: godot --path <repo> --headless -s Tests/SerializerRoundTripTest.gd
## Results print to stdout and are mirrored to Tests/last_run.log (the
## non-console Windows build does not attach stdout to a shell).

const FIXTURE := "res://Tests/Fixtures/roundtrip_v0.json"
const LOG := "res://Tests/last_run.log"

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	var bad_format := LevelSerializer.new()
	var result: LevelData = bad_format.load_from_json(
		'{"header": {"format": "other", "version": 0}}'
	)
	_check(result == null and not bad_format.last_error.is_empty(),
		"rejects wrong format id")

	var bad_version := LevelSerializer.new()
	result = bad_version.load_from_json(
		'{"header": {"format": "yabegcse-level", "version": 99}}'
	)
	_check(result == null and not bad_version.last_error.is_empty(),
		"rejects unsupported version")

	var text := FileAccess.get_file_as_string(FIXTURE)
	_check(not text.is_empty(), "fixture readable")

	var serializer := LevelSerializer.new()
	var data := serializer.load_from_json(text)
	_check(data != null, "fixture loads (%s)" % serializer.last_error)
	if data == null:
		_finish()
		return

	var save1 := serializer.save_to_json(data)
	var data2 := serializer.load_from_json(save1)
	_check(data2 != null, "own output reloads")
	var save2 := serializer.save_to_json(data2)
	_check(save1 == save2, "round-trip is idempotent")

	var parsed: Dictionary = JSON.parse_string(save2)
	var fixture: Dictionary = JSON.parse_string(text)
	_check(parsed.has("future_section"), "unknown top-level section survives")
	_check(parsed["meta"].has("future_meta_field"), "unknown meta field survives")
	_check(parsed["geometry"].has("future_geometry_field"),
		"unknown geometry field survives")
	_check(parsed["gameplay"] == fixture["gameplay"],
		"gameplay section survives verbatim")
	_check(parsed["future_section"] == fixture["future_section"],
		"unknown section content verbatim")

	_finish()


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
