class_name PlatformData
extends Resource

## PlatformData
##
## One drawn platform: a closed 2D polygon overlay (not a sector — it
## defines no walls and clips/overlaps anything). Lives in
## LevelData.platforms; serializes into the v0 "objects" section as a
## {"type": "platform", "vertices": ...} entry, which is what
## distinguishes it from the M4/M5 pos-based "platform" objects.
## trigger fields are reserved for M7 gameplay.

## Polygon points in world coordinates (1 unit = 6 mm).
var vertices: Array[Vector2] = []
## Height of the platform surface (top face).
var floor_height: float = 0.0
## Height of the platform underside (bottom face). Thin platform default:
## floor_height + 16.
var ceiling_height: float = 16.0
## Art library reference (library-relative name, with extension — the
## same convention as sector face textures).
var texture: String = ""
## V key (Platform Edit): invisible platforms skip 3D mesh generation and
## draw as a dashed outline only in 2D. Serialized; default true.
var is_visible: bool = true
## Reserved for M7 gameplay.
var is_trigger: bool = false
## Reserved for M7 gameplay.
var trigger_params: Dictionary = {}
## Unknown JSON fields from a loaded platform entry, written back verbatim
## on save (forward compatibility, same rule as unknown sections).
var _extra: Dictionary = {}

const KNOWN_FIELDS: Array[String] = [
	"type", "vertices", "floor_height", "ceiling_height", "texture",
	"is_visible", "is_trigger", "trigger_params",
]


## to_dict() -> Dictionary
##
## The v0 objects-section form. Unknown loaded fields round-trip via
## _extra; known fields win on key collisions.
func to_dict() -> Dictionary:
	var out := _extra.duplicate(true)
	var verts: Array = []
	for v in vertices:
		verts.append([v.x, v.y])
	out["type"] = "platform"
	out["vertices"] = verts
	out["floor_height"] = floor_height
	out["ceiling_height"] = ceiling_height
	out["texture"] = texture
	out["is_visible"] = is_visible
	out["is_trigger"] = is_trigger
	out["trigger_params"] = trigger_params.duplicate(true)
	return out


## from_dict(d) -> PlatformData
##
## Tolerant reconstruction from a JSON objects entry. Missing heights fall
## back to the thin-platform default (ceiling = floor + 16).
static func from_dict(d: Dictionary) -> PlatformData:
	var p := PlatformData.new()
	var verts: Variant = d.get("vertices", [])
	if verts is Array:
		for v in verts:
			if v is Array and (v as Array).size() >= 2:
				p.vertices.append(Vector2(float(v[0]), float(v[1])))
	p.floor_height = float(d.get("floor_height", 0.0))
	p.ceiling_height = float(d.get("ceiling_height", p.floor_height + 16.0))
	p.texture = str(d.get("texture", ""))
	p.is_visible = bool(d.get("is_visible", true))
	p.is_trigger = bool(d.get("is_trigger", false))
	if d.get("trigger_params") is Dictionary:
		p.trigger_params = (d["trigger_params"] as Dictionary).duplicate(true)
	for key in d:
		if not KNOWN_FIELDS.has(str(key)):
			p._extra[key] = d[key]
	return p


## clone() -> PlatformData
##
## Explicit deep copy. Resource.duplicate() mishandles typed Array
## properties on script variables, so undo snapshots use this instead.
func clone() -> PlatformData:
	var p := PlatformData.new()
	p.vertices = vertices.duplicate()
	p.floor_height = floor_height
	p.ceiling_height = ceiling_height
	p.texture = texture
	p.is_visible = is_visible
	p.is_trigger = is_trigger
	p.trigger_params = trigger_params.duplicate(true)
	p._extra = _extra.duplicate(true)
	return p


## centroid() -> Vector2
##
## Vertex average; used for the default floor-height lookup at draw time.
func centroid() -> Vector2:
	var c := Vector2.ZERO
	if vertices.is_empty():
		return c
	for v in vertices:
		c += v
	return c / float(vertices.size())
