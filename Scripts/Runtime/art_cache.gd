class_name ArtCache

## ArtCache
##
## Resolves library-relative texture names ("BASICLIB/BLACK.png") against
## ArtLibrary/ and hands out cached materials. Unresolved names get a
## magenta checker placeholder and are recorded in the missing list for
## the debug panel. Static cache, editor-session lifetime; never errors.

const LIBRARY_ROOT := "res://ArtLibrary/"
const PLACEHOLDER_CELL := 4  # pixels per checker cell
const PLACEHOLDER_SIZE := 64  # assumed texel size for missing textures

static var _materials: Dictionary = {}  # name -> StandardMaterial3D
static var _sizes: Dictionary = {}  # name -> Vector2i
static var _missing: Dictionary = {}  # name -> true (dedup set)
static var _scan_cache: Array[String] = []
static var _scanned := false
static var _placeholder: ImageTexture


## exists(name) -> bool
static func exists(name: String) -> bool:
	if name.is_empty():
		return false
	return ResourceLoader.exists(LIBRARY_ROOT + name)


## material_for(name, fallback_color) -> StandardMaterial3D
##
## Empty name = untextured: flat fallback color. Unknown name = placeholder
## checker plus a missing-textures entry. Everything unshaded + nearest,
## per the retro rendering rules.
static func material_for(name: String, fallback_color: Color) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if name.is_empty():
		mat.albedo_color = fallback_color
		_sizes[name] = Vector2i(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	elif exists(name):
		var tex: Texture2D = ResourceLoader.load(LIBRARY_ROOT + name)
		if tex != null:
			mat.albedo_texture = tex
			_sizes[name] = tex.get_size()
		else:
			_mark_missing(name)
			mat.albedo_texture = placeholder()
			_sizes[name] = Vector2i(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	else:
		_mark_missing(name)
		mat.albedo_texture = placeholder()
		_sizes[name] = Vector2i(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	_materials[name] = mat
	return mat


## texture_size(name) -> Vector2
##
## Pixel size of the resolved texture (64x64 for placeholder/untextured).
## UVs are emitted in world units and scaled by 1/size at commit time, so
## 1 texel = 1 world unit (6 mm).
static func texture_size(name: String) -> Vector2:
	if _sizes.has(name):
		return Vector2(_sizes[name])
	return Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)


## take_missing() -> Array[String]
##
## Drains the missing-names set. Called by the editor after a mesh rebuild
## to feed the debug panel.
static func take_missing() -> Array[String]:
	var out: Array[String] = []
	for name in _missing:
		out.append(name)
	_missing.clear()
	out.sort()
	return out


## scan() -> Array[String]
##
## All library-relative .png names under ArtLibrary/, sorted. Cached after
## the first call (the library does not change during a session).
static func scan() -> Array[String]:
	if _scanned:
		return _scan_cache.duplicate()
	_scan_dir(LIBRARY_ROOT, "")
	_scan_cache.sort()
	_scanned = true
	return _scan_cache.duplicate()


## resolve(tex_name) -> Texture2D
##
## Full library-relative name (with extension) to texture; placeholder on
## a miss (recorded for the debug panel).
static func resolve(tex_name: String) -> Texture2D:
	if tex_name.is_empty():
		return placeholder()
	if exists(tex_name):
		var tex: Texture2D = ResourceLoader.load(LIBRARY_ROOT + tex_name)
		if tex != null:
			return tex
	_mark_missing(tex_name)
	return placeholder()


## resolve_base(base_name) -> Texture2D
##
## M4 object art: base names carry no extension (frame/view suffixes are
## resolved by the caller). Falls back to the placeholder on a miss.
static func resolve_base(base_name: String) -> Texture2D:
	if base_name.is_empty():
		return placeholder()
	return resolve(base_name + ".png")


## resolve_object_frames(obj) -> Array[String]
##
## Frame names (with extension) for an object dict:
## - fluid: base + trailing digits, 1..MAX while they exist;
## - sprite_8way: the params.views values (explicit map wins);
## - others: base.png, falling back to base1.png.
static func resolve_object_frames(obj: Dictionary) -> Array[String]:
	var frames: Array[String] = []
	var art := str(obj.get("art", ""))
	if art.is_empty():
		return frames
	var type := str(obj.get("type", ""))
	if type == "fluid":
		for i in range(1, 17):
			var candidate := "%s%d.png" % [art, i]
			if not exists(candidate):
				break
			frames.append(candidate)
	elif type == "sprite_8way":
		for key in obj.get("params", {}).get("views", {}):
			frames.append(str(obj["params"]["views"][key]) + ".png")
	else:
		if exists(art + ".png"):
			frames.append(art + ".png")
		elif exists(art + "1.png"):
			frames.append(art + "1.png")
	return frames


static func placeholder() -> ImageTexture:
	if _placeholder != null:
		return _placeholder
	var img := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGB8)
	for y in range(PLACEHOLDER_SIZE):
		for x in range(PLACEHOLDER_SIZE):
			var on := (x / PLACEHOLDER_CELL + y / PLACEHOLDER_CELL) % 2 == 0
			img.set_pixel(x, y, Color(1.0, 0.0, 1.0) if on else Color(0.0, 0.0, 0.0))
	_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


static func _mark_missing(name: String) -> void:
	_missing[name] = true


static func _scan_dir(abs_path: String, prefix: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var rel := prefix + entry
		if dir.current_is_dir():
			_scan_dir(abs_path + "/" + entry, rel + "/")
		elif entry.to_lower().ends_with(".png"):
			_scan_cache.append(rel)
		entry = dir.get_next()
	dir.list_dir_end()
