class_name GCSImporter

## GCSImporter (M5)
##
## DOS 1.3 univ??.txt + objdef??.txt -> v0 LevelData. Pure text-in /
## data-out: never touches the filesystem (EditorController owns file
## access and include expansion). The level imports as object-walls in
## the void: geometry stays empty, all content lands in the objects
## section, and the import report (skipped/unreconstructable elements)
## rides meta.import_report so it round-trips through save/load.
##
## Line grammar (confirmed against retail DOS 1.3 UNIV0.TXT/OBJDEF0.TXT):
##   objdef: "<species> <handle> <file> <hsize_cm> <vsize_cm>"
##           file may be a DOS path (its basename is the art) or a bare
##           integer = alias of that handle's art (used for 45-degree
##           walls, which are longer). Species 6/11 lines carry no size.
##           "setpath"/"include" lines are directives; include expansion
##           is the controller's job (filesystem), they are ignored here.
##   univ:   "<species> <handle> <x> <y> <z> <theta> <attr> <op1..op4>"
##           (11 columns; op1..op4 = the editor's red boxes 1-4).
##           "s <x> <y> <z> <theta>" = test spawn point (meta.spawn).
##
## Units: GCS centimetres -> units via CM_TO_UNITS (1 unit = 6 mm).
## theta is a signed 16-bit-style angle: 32768 = 180 degrees. Wall
## placement: univ pos is the wall's ANCHOR (one end); the segment runs
## along (sin theta, cos theta) for hsize. The emitted wall_object is
## centred: pos = anchor + run * width/2, angle = 90 - theta_deg.
##
## Attribute bits: bitdontbump (64) -> params.collide = false (species
## 0/1 default true). Doors (bitdoor 4096), inventory (bit 2), lighting
## bytes and all opvals are NOT reconstructed in v1 — preserved in
## params.gcs and noted in the report. Unknown handles/species and
## malformed lines are skipped and listed in the report (tolerate+flag).

const CM_TO_UNITS := 5.0 / 3.0
const THETA_TO_DEG := 180.0 / 32768.0
const WALL_ANGLE_OFFSET := 90.0
const BIT_DONT_BUMP := 64
const BIT_DOOR := 4096

const SPECIES_TO_TYPE := {
	0: "wall_object",
	1: "wall_object",
	2: "billboard",
	6: "fluid",
	7: "sprite_8way",
	11: "platform",
}

static var _token_re := RegEx.create_from_string("\\S+")


## import_level(univ_text, objdef_text, source_name, extra_notes) ->
##   {"level": LevelData,
##    "report": {"imported": int, "skipped": Array[String], "notes": Array[String]}}
##
## source_name is the univ filename (report provenance). extra_notes are
## the controller's filesystem-side notes (include expansion results).
static func import_level(univ_text: String, objdef_text: String, source_name: String, extra_notes: Array = []) -> Dictionary:
	var report := {"imported": 0, "skipped": [], "notes": []}
	for note in extra_notes:
		report["notes"].append(str(note))
	var defs := _parse_objdef(objdef_text, report)
	var level := LevelData.create_empty()
	level.meta["name"] = "GCS import: " + source_name
	_parse_univ(univ_text, defs, level, report)
	level.meta["import_report"] = {
		"source": source_name,
		"imported": report["imported"],
		"skipped": report["skipped"].duplicate(),
		"notes": report["notes"].duplicate(),
	}
	GeometryOps.validate(level)
	return {"level": level, "report": report}


## _parse_objdef(text, report) -> Dictionary
##
## handle (int) -> {"species": int, "art": String (bare basename),
## "size_cm": Vector2}. Malformed lines and bad aliases are skipped and
## reported; parsing continues.
static func _parse_objdef(text: String, report: Dictionary) -> Dictionary:
	var defs := {}
	var line_no := 0
	for raw in text.split("\n"):
		line_no += 1
		var cols := _tokenize(raw)
		if cols.is_empty():
			continue
		var keyword: String = str(cols[0]).to_lower()
		if keyword == "setpath" or keyword == "include":
			continue  # directives; include expansion is the controller's job
		if cols.size() < 2 or not cols[0].is_valid_int() or not cols[1].is_valid_int():
			_skip(report, "objdef line %d: malformed (need <species> <handle> ...)" % line_no)
			continue
		var species := int(cols[0])
		var handle := int(cols[1])
		if defs.has(handle):
			_note(report, {}, "objdef line %d: duplicate handle %d (last wins)" % [line_no, handle])
		var art := ""
		var size_cm := Vector2.ZERO
		if cols.size() >= 3:
			var file: String = str(cols[2])
			if file.is_valid_int():
				# Art alias: this handle reuses another handle's art at a
				# different size (the 45-degree wall trick).
				var alias := int(file)
				if defs.has(alias):
					art = str(defs[alias]["art"])
				else:
					_skip(report, "objdef line %d: handle %d aliases unknown handle %d" % [line_no, handle, alias])
			else:
				art = file.replace("\\", "/").get_file().get_basename()
		if cols.size() >= 5 and cols[3].is_valid_float() and cols[4].is_valid_float():
			size_cm = Vector2(float(cols[3]), float(cols[4]))
		defs[handle] = {"species": species, "art": art, "size_cm": size_cm}
	return defs


## _parse_univ(text, defs, level, report)
##
## One placed object per line -> level.objects. Unknown handles are
## grouped per handle in the report (include files are often missing);
## malformed lines are reported individually.
static func _parse_univ(text: String, defs: Dictionary, level: LevelData, report: Dictionary) -> void:
	var unknown_handles := {}  # handle -> count
	var noted := {}  # dedup set for one-shot notes
	var line_no := 0
	for raw in text.split("\n"):
		line_no += 1
		var cols := _tokenize(raw)
		if cols.is_empty():
			continue
		if cols[0].to_lower() == "s":
			_parse_spawn(cols, level, report, line_no)
			continue
		if cols.size() < 7 or not cols[0].is_valid_int() or not cols[1].is_valid_int():
			_skip(report, "univ line %d: malformed (need <species> <handle> <x> <y> <z> <theta> <attr> ...)" % line_no)
			continue
		var numbers := []
		var bad := false
		for i in range(2, mini(cols.size(), 11)):
			if not cols[i].is_valid_float():
				bad = true
				break
			numbers.append(float(cols[i]))
		if bad:
			_skip(report, "univ line %d: non-numeric column" % line_no)
			continue
		while numbers.size() < 9:
			numbers.append(0.0)
		var univ_species := int(cols[0])
		var handle := int(cols[1])
		if not defs.has(handle):
			unknown_handles[handle] = int(unknown_handles.get(handle, 0)) + 1
			continue
		var def: Dictionary = defs[handle]
		var species := int(def["species"])
		if species != univ_species:
			_note(report, noted, "handle %d: univ species %d != objdef species %d (using objdef)" % [handle, univ_species, species])
		if not SPECIES_TO_TYPE.has(species):
			_note(report, noted, "species %d (handle %d): not importable in v1, placement(s) skipped" % [species, handle])
			continue
		var opvals := [int(numbers[5]), int(numbers[6]), int(numbers[7]), int(numbers[8])]
		var obj := _map_object(handle, def, Vector2(numbers[0], numbers[1]), numbers[2], numbers[3], int(numbers[4]), opvals, report, noted)
		level.objects.append(obj)
		report["imported"] = int(report["imported"]) + 1
	var handles := unknown_handles.keys()
	handles.sort()
	for handle in handles:
		_skip(report, "handle %d: %d placement(s) skipped (not defined in objdef/includes)" % [handle, unknown_handles[handle]])


## _parse_spawn(cols, level, report, line_no)
##
## "s <x> <y> <z> <theta>" — the editor's test start point. Stored as a
## meta hint (units, degrees); WalkController prefers it when present.
static func _parse_spawn(cols: Array, level: LevelData, report: Dictionary, line_no: int) -> void:
	if cols.size() < 5:
		_skip(report, "univ line %d: malformed spawn line" % line_no)
		return
	for i in range(1, 5):
		if not str(cols[i]).is_valid_float():
			_skip(report, "univ line %d: malformed spawn line" % line_no)
			return
	level.meta["spawn"] = [
		float(cols[1]) * CM_TO_UNITS,
		float(cols[2]) * CM_TO_UNITS,
		float(cols[3]) * CM_TO_UNITS,
		float(cols[4]) * THETA_TO_DEG,
	]


static func _map_object(handle: int, def: Dictionary, pos_cm: Vector2, z_cm: float, theta_raw: float, attr: int, opvals: Array, report: Dictionary, noted: Dictionary) -> Dictionary:
	var species := int(def["species"])
	var type: String = SPECIES_TO_TYPE[species]
	var obj := ObjectOps.defaults(type)
	var pos := pos_cm * CM_TO_UNITS
	var theta_deg := theta_raw * THETA_TO_DEG
	var size_units := (def["size_cm"] as Vector2) * CM_TO_UNITS
	obj["z"] = z_cm * CM_TO_UNITS
	obj["art"] = _resolve_art(str(def["art"]), handle, report, noted)
	obj["params"]["gcs"] = {
		"handle": handle,
		"species": species,
		"attr": attr,
		"opvals": opvals,
	}
	match type:
		"wall_object":
			# Anchor -> centre: the segment runs along (sin, cos) of theta.
			if size_units.x <= 0.0:
				size_units = Vector2(ObjectOps.DEFAULT_SIZE, ObjectOps.DEFAULT_SIZE)
			if size_units.y <= 0.0:
				size_units.y = size_units.x
			var run := Vector2(sin(deg_to_rad(theta_deg)), cos(deg_to_rad(theta_deg)))
			pos += run * size_units.x * 0.5
			obj["angle"] = WALL_ANGLE_OFFSET - theta_deg
			obj["params"]["scale"] = 1.0
			obj["params"]["size"] = [size_units.x, size_units.y]
			obj["params"]["collide"] = (attr & BIT_DONT_BUMP) == 0
			if attr & BIT_DOOR:
				_note(report, noted, "handle %d: door imported as a static wall_object; door semantics not reconstructed" % handle)
		"billboard":
			obj["angle"] = theta_deg
			if size_units.x > 0.0:
				if size_units.y <= 0.0:
					size_units.y = size_units.x
				obj["params"]["scale"] = 1.0
				obj["params"]["size"] = [size_units.x, size_units.y]
			if attr & 2:
				_note(report, noted, "handle %d: inventory pickup semantics preserved in params.gcs only" % handle)
		"sprite_8way":
			obj["angle"] = theta_deg
			if size_units.x > 0.0:
				obj["params"]["scale"] = _scale_for_width(str(obj["art"]), size_units.x)
			obj["params"]["views"] = ObjectOps.probe_views(str(obj["art"]))
			if (obj["params"]["views"] as Dictionary).is_empty():
				_note(report, noted, "handle %d: no 8-way views found for art '%s'" % [handle, obj["art"]])
		"fluid":
			obj["angle"] = theta_deg
			_note(report, noted, "handle %d: fluid command table not parsed in v1; frames probed from art name" % handle)
		"platform":
			if opvals[0] > 0 and opvals[1] > 0:
				obj["params"]["size"] = [float(opvals[0]) * CM_TO_UNITS, float(opvals[1]) * CM_TO_UNITS]
			if attr != 0 or int(opvals[2]) != 0:
				_note(report, noted, "handle %d: platform register/trigger semantics preserved in params.gcs only" % handle)
	obj["pos"] = [pos.x, pos.y]
	return obj


## _resolve_art(bare, handle, report, noted) -> String
##
## Bare GCS name -> library-relative base via ArtCache. Unresolved names
## are kept as the bare guess: they render as the placeholder and land on
## the missing-texture list (tolerate + flag), plus a report note.
static func _resolve_art(bare: String, handle: int, report: Dictionary, noted: Dictionary) -> String:
	if bare.is_empty():
		return ""
	var resolved := ArtCache.find_base(bare)
	if resolved.is_empty():
		_note(report, noted, "art not found in library: %s (handle %d) — placeholder" % [bare, handle])
		return bare
	return resolved


## _scale_for_width(art, width_units) -> float
##
## pixel_size factor so the art spans width_units at 1 texel = 1 unit.
static func _scale_for_width(art: String, width_units: float) -> float:
	if art.is_empty():
		return 1.0
	var tex := ArtCache.resolve_base(art)
	var w := float(tex.get_size().x)
	if w <= 0.0:
		return 1.0
	return width_units / w


static func _tokenize(line: String) -> Array:
	var semi := line.find(";")
	if semi >= 0:
		line = line.substr(0, semi)
	var out := []
	for m in _token_re.search_all(line):
		out.append(m.get_string())
	return out


static func _skip(report: Dictionary, message: String) -> void:
	(report["skipped"] as Array).append(message)


## _note(report, noted, message)
##
## One-shot report note: repeats of the same message are dropped so a
## level full of doors/enemies doesn't flood the report.
static func _note(report: Dictionary, noted: Dictionary, message: String) -> void:
	if noted.has(message):
		return
	noted[message] = true
	(report["notes"] as Array).append(message)
