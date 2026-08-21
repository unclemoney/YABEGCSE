class_name GameplayOps

## GameplayOps (M7)
##
## Validated view of a level's v0 `gameplay` section: triggers (fluid
## command equivalents), registers (the universe-register variable model),
## scripts (named action lists — redesigned in spirit, never a Forth
## interpreter), music (library-relative WAV), links (level-to-level
## connections, the theaters.txt descendant). Static and pure — settings()
## reads LevelData and NEVER writes to it: annotations are computed, not
## stored (format envelope §0). Every malformed entry is skipped (or falls
## back to its default) with one human-readable note; the notes land in
## the debug panel (tolerate + flag). Nothing here ever errors on bad
## data.
##
## Schema (v0):
##   registers: {"initial": {"5": 100}, "names": {"5": "label"}}
##   triggers:  [{"id", "event": level_start|enter_sector|near_object|timer,
##                "sector"|"object"+"radius"|"every" (per event),
##                "once": bool, "condition": {"reg", "op": eq|ne|lt|gt, "value"},
##                "actions": [{"do": verb, ...}]}]
##   scripts:   [{"id", "steps": [action dicts]}]
##   music:     {"enabled": bool, "track": "LIB/NAME" (WAV base name)}
##   links:     [{"id", "file", "entry": [x, y, z, theta_deg] (optional)}]
##
## Action verbs: set_register / add_register {reg, value}, message {text},
## play_sound {art}, damage_player {amount}, remove_object {object},
## warp {link}, run_script {script}.
##
## The validated view converts register keys to ints and links/scripts to
## id-keyed Dictionaries for lookup. It is a VIEW: LevelData.gameplay keeps
## the raw JSON shape so unknown fields round-trip verbatim.

const DEFAULTS := {
	"registers": {"initial": {}, "names": {}},
	"triggers": [],
	"scripts": [],
	"music": {"enabled": false, "track": ""},
	"links": [],
}

const EVENTS: Array[String] = ["level_start", "enter_sector", "near_object", "timer"]
const OPS: Array[String] = ["eq", "ne", "lt", "gt"]
const VERBS: Array[String] = [
	"set_register", "add_register", "message", "play_sound",
	"damage_player", "remove_object", "warp", "run_script",
]

## Universe registers (mining doc §5): 256 registers, 0-255. 122-126 are
## read-only live stats (fps, health, ...), 127 is the game-over register.
const REGISTER_COUNT := 256
const FIRST_READ_ONLY := 122
const LAST_READ_ONLY := 126
const REG_FPS := 122
const REG_HEALTH := 123
const REG_GAME_OVER := 127
const DEFAULT_HEALTH := 100
const MAX_SCRIPT_DEPTH := 8


## settings(data) -> {"values": Dictionary, "notes": Array[String]}
##
## values mirrors the DEFAULTS shape with the level's valid entries
## applied. Safe to call with a null/empty gameplay section.
static func settings(data: LevelData) -> Dictionary:
	var notes: Array[String] = []
	var gp: Dictionary = {}
	if data != null and data.gameplay is Dictionary:
		gp = data.gameplay
	var sector_count := 0
	var object_count := 0
	if data != null:
		sector_count = data.sectors.size()
		object_count = data.objects.size()
	var registers := _validate_registers(gp.get("registers"), notes)
	var music := _validate_music(gp.get("music"), notes)
	var links := _validate_links(gp.get("links"), notes)
	var script_ids := _collect_script_ids(gp.get("scripts"), notes)
	var scripts := _validate_scripts(gp.get("scripts"), links, script_ids, object_count, notes)
	var triggers := _validate_triggers(
		gp.get("triggers"), sector_count, object_count, links, script_ids, notes
	)
	return {
		"values": {
			"registers": registers,
			"triggers": triggers,
			"scripts": scripts,
			"music": music,
			"links": links,
		},
		"notes": notes,
	}


static func _validate_registers(raw: Variant, notes: Array[String]) -> Dictionary:
	var initial := {}
	var names := {}
	if raw == null:
		return {"initial": initial, "names": names}
	if not raw is Dictionary:
		notes.append("registers is not an object; reset to defaults")
		return {"initial": initial, "names": names}
	var raw_initial: Variant = raw.get("initial")
	if raw_initial is Dictionary:
		for key in raw_initial:
			var reg := _parse_reg_key(key)
			if reg == -1:
				notes.append("registers.initial key '%s' is not a register number 0-255; dropped" % str(key))
				continue
			if reg == 0 or (reg >= FIRST_READ_ONLY and reg <= REG_GAME_OVER):
				notes.append("registers.initial[%d] targets a reserved/read-only register; dropped" % reg)
				continue
			var value: Variant = raw_initial[key]
			if not (value is float or value is int):
				notes.append("registers.initial[%d] is not a number; dropped" % reg)
				continue
			initial[reg] = clampi(int(value), 0, 255)
	elif raw_initial != null:
		notes.append("registers.initial is not an object; reset to default")
	var raw_names: Variant = raw.get("names")
	if raw_names is Dictionary:
		for key in raw_names:
			var reg := _parse_reg_key(key)
			if reg == -1:
				notes.append("registers.names key '%s' is not a register number 0-255; dropped" % str(key))
				continue
			names[reg] = str(raw_names[key])
	elif raw_names != null:
		notes.append("registers.names is not an object; reset to default")
	return {"initial": initial, "names": names}


static func _validate_music(raw: Variant, notes: Array[String]) -> Dictionary:
	var music: Dictionary = (DEFAULTS["music"] as Dictionary).duplicate()
	if raw == null:
		return music
	if not raw is Dictionary:
		notes.append("music is not an object; reset to defaults")
		return music
	if raw.has("enabled"):
		if raw["enabled"] is bool:
			music["enabled"] = raw["enabled"]
		else:
			notes.append("music.enabled is not a bool; reset to default")
	music["track"] = str(raw.get("track", "")).trim_suffix(".wav").trim_suffix(".WAV")
	var track: String = music["track"]
	if not track.is_empty() and not ResourceLoader.exists(ArtCache.LIBRARY_ROOT + track + ".wav"):
		notes.append("music track not in library: %s.wav; playback skipped" % track)
	return music


static func _validate_links(raw: Variant, notes: Array[String]) -> Dictionary:
	var links := {}
	if raw == null:
		return links
	if not raw is Array:
		notes.append("links is not an array; reset to defaults")
		return links
	for i in range(raw.size()):
		var entry: Variant = raw[i]
		if not entry is Dictionary:
			notes.append("links[%d] is not an object; skipped" % i)
			continue
		var id := str(entry.get("id", ""))
		var file := str(entry.get("file", ""))
		if id.is_empty() or file.is_empty():
			notes.append("links[%d] needs a non-empty id and file; skipped" % i)
			continue
		if links.has(id):
			notes.append("links[%d] duplicates link id '%s'; skipped" % [i, id])
			continue
		var link := {"file": file, "entry": []}
		var raw_entry: Variant = entry.get("entry")
		if raw_entry is Array and not (raw_entry as Array).is_empty():
			var valid: bool = raw_entry.size() >= 4
			if valid:
				for k in range(4):
					if not (raw_entry[k] is float or raw_entry[k] is int):
						valid = false
			if valid:
				link["entry"] = [
					float(raw_entry[0]), float(raw_entry[1]),
					float(raw_entry[2]), float(raw_entry[3]),
				]
			else:
				notes.append("links[%d] entry must be 4 numbers [x, y, z, theta]; ignored" % i)
		links[id] = link
	return links


## _collect_script_ids(raw, notes) -> Dictionary
##
## First pass over the scripts array: the id set, so run_script references
## resolve regardless of definition order (cycles are capped at runtime).
static func _collect_script_ids(raw: Variant, notes: Array[String]) -> Dictionary:
	var ids := {}
	if raw == null:
		return ids
	if not raw is Array:
		return ids  # _validate_scripts reports the type error
	for i in range(raw.size()):
		var entry: Variant = raw[i]
		if not entry is Dictionary:
			continue
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		if ids.has(id):
			notes.append("scripts[%d] duplicates script id '%s'; first definition wins" % [i, id])
			continue
		ids[id] = true
	return ids


static func _validate_scripts(raw: Variant, links: Dictionary, script_ids: Dictionary, object_count: int, notes: Array[String]) -> Dictionary:
	var scripts := {}
	if raw == null:
		return scripts
	if not raw is Array:
		notes.append("scripts is not an array; reset to defaults")
		return scripts
	for i in range(raw.size()):
		var entry: Variant = raw[i]
		var path := "scripts[%d]" % i
		if not entry is Dictionary:
			notes.append("%s is not an object; skipped" % path)
			continue
		var id := str(entry.get("id", ""))
		if id.is_empty():
			notes.append("%s has no id; skipped" % path)
			continue
		if scripts.has(id):
			continue  # duplicate already noted by _collect_script_ids
		var raw_steps: Variant = entry.get("steps")
		if not raw_steps is Array:
			notes.append("%s steps is not an array; skipped" % path)
			continue
		var steps := _validate_actions(raw_steps, links, script_ids, object_count, path, notes)
		if steps.is_empty():
			notes.append("%s has no valid actions; skipped" % path)
			continue
		scripts[id] = steps
	return scripts


static func _validate_triggers(raw: Variant, sector_count: int, object_count: int, links: Dictionary, script_ids: Dictionary, notes: Array[String]) -> Array:
	var triggers: Array = []
	if raw == null:
		return triggers
	if not raw is Array:
		notes.append("triggers is not an array; reset to defaults")
		return triggers
	for i in range(raw.size()):
		var entry: Variant = raw[i]
		var path := "triggers[%d]" % i
		if not entry is Dictionary:
			notes.append("%s is not an object; skipped" % path)
			continue
		var event := str(entry.get("event", ""))
		if not EVENTS.has(event):
			notes.append("%s has unknown event '%s'; skipped" % [path, event])
			continue
		var trigger := {
			"id": str(entry.get("id", "")),
			"event": event,
			"sector": -1,
			"object": -1,
			"radius": 600.0,
			"every": 0.0,
			"once": true,
			"condition": {},
			"actions": [],
		}
		var subject_ok := true
		match event:
			"enter_sector":
				var sector := _int_field(entry, "sector", -1)
				if sector < 0 or sector >= sector_count:
					notes.append("%s sector %d out of range; skipped" % [path, sector])
					subject_ok = false
				else:
					trigger["sector"] = sector
			"near_object":
				var object := _int_field(entry, "object", -1)
				if object < 0 or object >= object_count:
					notes.append("%s object %d out of range; skipped" % [path, object])
					subject_ok = false
				else:
					trigger["object"] = object
					trigger["radius"] = _float_field(entry, "radius", 600.0)
					if float(trigger["radius"]) <= 0.0:
						notes.append("%s radius must be > 0; reset to 600" % path)
						trigger["radius"] = 600.0
			"timer":
				var every := _float_field(entry, "every", 0.0)
				if every <= 0.0:
					notes.append("%s timer needs every > 0 seconds; skipped" % path)
					subject_ok = false
				else:
					trigger["every"] = every
		if not subject_ok:
			continue
		if entry.has("once"):
			if entry["once"] is bool:
				trigger["once"] = entry["once"]
			else:
				notes.append("%s once is not a bool; reset to true" % path)
		if entry.has("condition"):
			trigger["condition"] = _validate_condition(entry["condition"], path, notes)
		var raw_actions: Variant = entry.get("actions")
		if not raw_actions is Array:
			notes.append("%s actions is not an array; skipped" % path)
			continue
		var actions := _validate_actions(raw_actions, links, script_ids, object_count, path, notes)
		if actions.is_empty():
			notes.append("%s has no valid actions; skipped" % path)
			continue
		trigger["actions"] = actions
		triggers.append(trigger)
	return triggers


static func _validate_condition(raw: Variant, path: String, notes: Array[String]) -> Dictionary:
	if not raw is Dictionary:
		notes.append("%s condition is not an object; ignored" % path)
		return {}
	var reg := _int_field(raw, "reg", -1)
	var op := str(raw.get("op", ""))
	var value: Variant = raw.get("value")
	if reg < 0 or reg >= REGISTER_COUNT or not OPS.has(op) or not (value is float or value is int):
		notes.append("%s condition needs reg (0-255), op (eq|ne|lt|gt) and value; ignored" % path)
		return {}
	return {"reg": reg, "op": op, "value": int(value)}


static func _validate_actions(raw: Array, links: Dictionary, script_ids: Dictionary, object_count: int, path: String, notes: Array[String]) -> Array:
	var actions: Array = []
	for j in range(raw.size()):
		var action: Variant = raw[j]
		var apath := "%s actions[%d]" % [path, j]
		if not action is Dictionary:
			notes.append("%s is not an object; dropped" % apath)
			continue
		var verb := str(action.get("do", ""))
		if not VERBS.has(verb):
			notes.append("%s has unknown action '%s'; dropped" % [apath, verb])
			continue
		var clean := {"do": verb}
		var valid := true
		match verb:
			"set_register", "add_register":
				var reg := _int_field(action, "reg", -1)
				var value: Variant = action.get("value")
				if reg < 0 or reg >= REGISTER_COUNT or not (value is float or value is int):
					notes.append("%s %s needs reg (0-255) and a numeric value; dropped" % [apath, verb])
					valid = false
				else:
					clean["reg"] = reg
					clean["value"] = int(value)
			"message":
				clean["text"] = str(action.get("text", ""))
			"play_sound":
				var art := str(action.get("art", "")).trim_suffix(".wav").trim_suffix(".WAV")
				if art.is_empty():
					notes.append("%s play_sound needs an art reference; dropped" % apath)
					valid = false
				else:
					clean["art"] = art
					if not ResourceLoader.exists(ArtCache.LIBRARY_ROOT + art + ".wav"):
						notes.append("%s sound not in library: %s.wav; playback skipped" % [apath, art])
			"damage_player":
				var amount: Variant = action.get("amount")
				if not (amount is float or amount is int):
					notes.append("%s damage_player needs a numeric amount; dropped" % apath)
					valid = false
				else:
					clean["amount"] = int(amount)
			"remove_object":
				var object := _int_field(action, "object", -1)
				if object < 0 or object >= object_count:
					notes.append("%s remove_object target %d out of range; dropped" % [apath, object])
					valid = false
				else:
					clean["object"] = object
			"warp":
				var link := str(action.get("link", ""))
				if link.is_empty() or not links.has(link):
					notes.append("%s warp references unknown link '%s'; dropped" % [apath, link])
					valid = false
				else:
					clean["link"] = link
			"run_script":
				var script := str(action.get("script", ""))
				if script.is_empty() or not script_ids.has(script):
					notes.append("%s run_script references unknown script '%s'; dropped" % [apath, script])
					valid = false
				else:
					clean["script"] = script
		if valid:
			actions.append(clean)
	return actions


static func _parse_reg_key(key: Variant) -> int:
	var text := str(key)
	if not text.is_valid_int():
		return -1
	var reg := text.to_int()
	if reg < 0 or reg >= REGISTER_COUNT:
		return -1
	return reg


static func _int_field(src: Dictionary, key: String, default: int) -> int:
	var value: Variant = src.get(key, default)
	if value is float or value is int:
		return int(value)
	return default


static func _float_field(src: Dictionary, key: String, default: float) -> float:
	var value: Variant = src.get(key, default)
	if value is float or value is int:
		return float(value)
	return default
