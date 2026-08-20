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
## Computed validity annotations (tolerate + flag). Recomputed by
## GeometryOps.validate() after every load and mutation. NEVER serialized.
var flagged_sectors: Dictionary = {}  # sector id -> reason String
var flagged_walls: Dictionary = {}  # wall id -> reason String

## Geometry schema (v0, locked in the M1 plan):
##   points:  [[x, y], ...]            world units, 1 unit = 6 mm
##   walls:   {"a": int, "b": int,     directed segment over point ids
##             "front": int,           sector left of a->b
##             "back": int,            sector right of a->b; -1 = solid.
##                                     back != -1 IS a portal wall.
##             "texture": String, "offset_u": float, "offset_v": float}
##   sectors: {"walls": [wall ids],    ordered closed outer loop
##             "inner": [[wall ids]],  inner loops (sector-within-sector)
##             "floor_height": float, "ceiling_height": float,
##             "floor_texture": String, "ceiling_texture": String,
##             "floor_slope": [[point_id, height] x3],   optional; empty or
##             "ceiling_slope": [[point_id, height] x3], incomplete = flat
##             "flags": int}           reserved, 0


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
		"fog": {"enabled": true, "color": "#202830", "near": 128.0, "far": 1536.0},
		"ambient": 1.0,
	}
	return data


## notify_changed(change_type)
##
## Called by writers (tools, controller) after mutating.
func notify_changed(change_type: ChangeType) -> void:
	level_changed.emit(change_type)
