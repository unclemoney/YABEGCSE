class_name LevelData
extends Resource

## LevelData
##
## The single source of truth for the current level. Owned by
## EditorController. Views read it; only tools write to it (via ToolSystem).
## Sections mirror the v0 format envelope. Unknown sections and unknown
## geometry fields are kept in unknown_sections so load/save round-trips
## stay lossless.

signal level_changed(change_type: ChangeType)

enum ChangeType { GEOMETRY, OBJECTS, ENVIRONMENT, META, FULL_RELOAD }

const FORMAT_ID := "yabegcse-level"
const FORMAT_VERSION := 0

var header: Dictionary = {}
var meta: Dictionary = {}
var environment: Dictionary = {}
var points: Array = []
var walls: Array = []
var sectors: Array = []
var objects: Array = []
var art: Dictionary = {}
## Reserved namespace (M7). Stored verbatim; never interpreted before then.
var gameplay: Dictionary = {}
## Unknown top-level sections, plus unknown geometry fields under
## the "geometry" key. Written back verbatim on save.
var unknown_sections: Dictionary = {}


## create_empty() -> LevelData
##
## A blank level with a valid v0 header and section defaults.
static func create_empty() -> LevelData:
	var data := LevelData.new()
	data.header = {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"generator": "YABEGCSE 0.1.0",
	}
	data.meta = {
		"name": "Untitled",
		"author": "",
		"description": "",
	}
	data.environment = {
		"fog": {"enabled": true, "color": "#202830", "near": 8.0, "far": 48.0},
		"ambient": 1.0,
	}
	return data


## notify_changed(change_type)
##
## Called by writers (tools, controller) after mutating.
func notify_changed(change_type: ChangeType) -> void:
	level_changed.emit(change_type)
