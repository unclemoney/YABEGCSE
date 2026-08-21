class_name EnvironmentOps

## EnvironmentOps (M6)
##
## Validated view of a level's v0 `environment` section: fog (color,
## near/far), sky (flat color | horizon strip with a library-relative art
## reference), ambient light level, void behavior. Static and pure —
## settings() reads LevelData and NEVER writes to it: annotations are
## computed, not stored (format envelope §0). Every malformed field falls
## back to its default and appends one human-readable note; the notes land
## in the debug panel (tolerate + flag). Nothing here ever errors on bad
## data.

const DEFAULTS := {
	"fog": {"enabled": true, "color": "#202830", "near": 128.0, "far": 1536.0},
	"ambient": 1.0,
	"sky": {"mode": "flat", "color": "#202830", "strip": ""},
	"void": {"mode": "fog_color"},
}

const SKY_MODES: Array[String] = ["flat", "horizon_strip"]
const VOID_MODES: Array[String] = ["fog_color", "sky_color"]


## settings(data) -> {"values": Dictionary, "notes": Array[String]}
##
## values mirrors the DEFAULTS shape with the level's valid fields
## applied. Safe to call with a null/empty environment.
static func settings(data: LevelData) -> Dictionary:
	var notes: Array[String] = []
	var env: Dictionary = {}
	if data != null and data.environment is Dictionary:
		env = data.environment
	var fog_in: Dictionary = env.get("fog", {}) if env.get("fog", {}) is Dictionary else {}
	var sky_in: Dictionary = env.get("sky", {}) if env.get("sky", {}) is Dictionary else {}
	var void_in: Dictionary = env.get("void", {}) if env.get("void", {}) is Dictionary else {}
	var defaults_fog: Dictionary = DEFAULTS["fog"]

	var fog := {
		"enabled": _bool_field(fog_in, "enabled", defaults_fog["enabled"], "fog.enabled", notes),
		"color": _color_field(fog_in, "color", defaults_fog["color"], "fog.color", notes),
		"near": _float_field(fog_in, "near", defaults_fog["near"], "fog.near", notes),
		"far": _float_field(fog_in, "far", defaults_fog["far"], "fog.far", notes),
	}
	if fog["near"] <= 0.0 or fog["near"] >= fog["far"]:
		notes.append("fog.near/far out of range (need 0 < near < far); reset to defaults")
		fog["near"] = defaults_fog["near"]
		fog["far"] = defaults_fog["far"]

	var ambient := 0.0
	if env.has("ambient"):
		if env["ambient"] is float or env["ambient"] is int:
			ambient = maxf(0.0, float(env["ambient"]))
		else:
			notes.append("ambient is not a number; reset to default")
			ambient = DEFAULTS["ambient"]
	else:
		ambient = DEFAULTS["ambient"]

	var defaults_sky: Dictionary = DEFAULTS["sky"]
	var sky := {
		"mode": _enum_field(sky_in, "mode", SKY_MODES, defaults_sky["mode"], "sky.mode", notes),
		"color": _color_field(sky_in, "color", defaults_sky["color"], "sky.color", notes),
		"strip": str(sky_in.get("strip", defaults_sky["strip"])),
	}
	if sky["mode"] == "horizon_strip":
		if (sky["strip"] as String).is_empty():
			notes.append("sky.mode is horizon_strip but sky.strip is empty; rendering flat sky color")
			sky["mode"] = "flat"
		elif not ArtCache.exists(sky["strip"] + ".png"):
			notes.append("sky strip art not in library: %s; rendering flat sky color" % sky["strip"])
			sky["mode"] = "flat"

	var defaults_void: Dictionary = DEFAULTS["void"]
	var void_block := {
		"mode": _enum_field(void_in, "mode", VOID_MODES, defaults_void["mode"], "void.mode", notes),
	}

	return {"values": {"fog": fog, "ambient": ambient, "sky": sky, "void": void_block}, "notes": notes}


static func _bool_field(src: Dictionary, key: String, default: bool, path: String, notes: Array[String]) -> bool:
	if not src.has(key):
		return default
	if src[key] is bool:
		return src[key]
	notes.append("%s is not a bool; reset to default" % path)
	return default


static func _float_field(src: Dictionary, key: String, default: float, path: String, notes: Array[String]) -> float:
	if not src.has(key):
		return default
	if src[key] is float or src[key] is int:
		return float(src[key])
	notes.append("%s is not a number; reset to default" % path)
	return default


static func _color_field(src: Dictionary, key: String, default: String, path: String, notes: Array[String]) -> String:
	if not src.has(key):
		return default
	if src[key] is String and Color.html_is_valid(src[key]):
		return src[key]
	notes.append("%s is not a valid color; reset to default" % path)
	return default


static func _enum_field(src: Dictionary, key: String, allowed: Array[String], default: String, path: String, notes: Array[String]) -> String:
	if not src.has(key):
		return default
	var value := str(src[key])
	if allowed.has(value):
		return value
	notes.append("%s has unknown value '%s'; reset to default" % [path, value])
	return default
