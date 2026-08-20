class_name LevelSerializer
extends RefCounted

## LevelSerializer
##
## JSON <-> LevelData. Strings in, strings out — never touches the
## filesystem (EditorController owns file dialogs and FileAccess).
## Unknown sections and fields are preserved verbatim; a wrong format id
## or a newer version fails gracefully via last_error.

const KNOWN_SECTIONS: Array[String] = [
	"header", "meta", "environment", "geometry", "objects", "art", "gameplay",
]
const KNOWN_GEOMETRY_FIELDS: Array[String] = ["points", "walls", "sectors"]

var last_error := ""


## load_from_json(text) -> LevelData (null on error; see last_error)
##
## Gates on header.format and header.version. Unknown top-level sections
## and unknown geometry fields land in LevelData.unknown_sections.
func load_from_json(text: String) -> LevelData:
	last_error = ""
	var json := JSON.new()
	if json.parse(text) != OK:
		last_error = "Invalid JSON at line %d: %s" % [
			json.get_error_line(), json.get_error_message(),
		]
		return null
	if not json.data is Dictionary:
		last_error = "Level file root must be a JSON object."
		return null
	var root: Dictionary = json.data
	if not root.get("header") is Dictionary:
		last_error = "Missing or malformed 'header' section."
		return null
	var header: Dictionary = root["header"]
	if header.get("format", "") != LevelData.FORMAT_ID:
		last_error = "Not a %s file." % LevelData.FORMAT_ID
		return null
	if int(header.get("version", -1)) != LevelData.FORMAT_VERSION:
		last_error = "Unsupported format version: %s" % str(header.get("version"))
		return null

	var data := LevelData.new()
	data.header = header.duplicate(true)
	if root.get("meta") is Dictionary:
		data.meta = root["meta"].duplicate(true)
	if root.get("environment") is Dictionary:
		data.environment = root["environment"].duplicate(true)
	if root.get("art") is Dictionary:
		data.art = root["art"].duplicate(true)
	if root.get("gameplay") is Dictionary:
		data.gameplay = root["gameplay"].duplicate(true)
	if root.get("objects") is Array:
		data.objects = root["objects"].duplicate(true)
	if root.get("geometry") is Dictionary:
		var geometry: Dictionary = root["geometry"]
		if geometry.get("points") is Array:
			data.points = geometry["points"].duplicate(true)
		if geometry.get("walls") is Array:
			data.walls = geometry["walls"].duplicate(true)
		if geometry.get("sectors") is Array:
			data.sectors = geometry["sectors"].duplicate(true)
		var leftover := {}
		for key in geometry:
			if not KNOWN_GEOMETRY_FIELDS.has(key):
				leftover[key] = geometry[key]
		if not leftover.is_empty():
			data.unknown_sections["geometry"] = leftover
	for key in root:
		if not KNOWN_SECTIONS.has(key):
			data.unknown_sections[key] = root[key]
	# TODO M1: compute validity annotations (red-flag sectors) here at load.
	return data


## save_to_json(data) -> String
##
## Emits known sections at this writer's version plus every unknown
## section verbatim. Deterministic key order for stable diffs.
func save_to_json(data: LevelData) -> String:
	var root: Dictionary = {}
	var header := data.header.duplicate(true)
	header["format"] = LevelData.FORMAT_ID
	header["version"] = LevelData.FORMAT_VERSION
	root["header"] = header
	root["meta"] = data.meta.duplicate(true)
	root["environment"] = data.environment.duplicate(true)
	var geometry: Dictionary = {}
	if data.unknown_sections.has("geometry"):
		geometry = data.unknown_sections["geometry"].duplicate(true)
	geometry["points"] = data.points.duplicate(true)
	geometry["walls"] = data.walls.duplicate(true)
	geometry["sectors"] = data.sectors.duplicate(true)
	root["geometry"] = geometry
	root["objects"] = data.objects.duplicate(true)
	root["art"] = data.art.duplicate(true)
	root["gameplay"] = data.gameplay.duplicate(true)
	for key in data.unknown_sections:
		if key != "geometry":
			root[key] = data.unknown_sections[key]
	return JSON.stringify(root, "\t")
