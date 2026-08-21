class_name GameplayRuntime
extends Node

## GameplayRuntime (M7)
##
## The side-effecting half of play-test gameplay, owned by Viewport3DView
## (like Objects3D). Feeds player state into the pure TriggerEngine and
## executes the returned actions: messages and warps signal up to the
## EditorController, sounds go to the AudioManager autoload, remove_object
## hides the instance in Objects3D. Read-only consumer of LevelData — the
## runtime NEVER mutates it (a removed object reappears on rebuild).
##
## Lifecycle: revalidate() on every level change (cheap; also yields the
## debug-panel notes), start_playtest()/stop_playtest() on 3D mode
## enter/exit. Register state resets on every entry; gameplay edits made
## mid-play-test apply on the next entry.

signal message_shown(text: String)
signal warp_requested(link: Dictionary)
signal event_logged(text: String)
signal registers_changed

var _level_data: LevelData
var _player: Node3D
var _objects_3d: Objects3D
var _engine := TriggerEngine.new()
var _values: Dictionary = {}
var _object_positions: Array[Vector2] = []
var _active := false
var _last_sector := -2


func set_level_data(data: LevelData) -> void:
	_level_data = data


func set_player(player: Node3D) -> void:
	_player = player


func set_objects_3d(objects_3d: Objects3D) -> void:
	_objects_3d = objects_3d


## revalidate() -> Array[String]
##
## Recomputes the validated gameplay view; returns the tolerate+flag notes
## for the debug panel. Does not disturb a running play-test.
func revalidate() -> Array[String]:
	if _level_data == null:
		_values = {}
		return []
	var result := GameplayOps.settings(_level_data)
	_values = result["values"]
	return result["notes"]


## start_playtest()
##
## Resets the engine (registers back to `initial`), snapshots object
## positions, starts the level music, fires level_start.
func start_playtest() -> void:
	if _level_data == null:
		return
	if _values.is_empty():
		revalidate()
	_engine.setup(_values)
	_object_positions.clear()
	for obj in _level_data.objects:
		if obj is Dictionary:
			_object_positions.append(ObjectOps.get_pos(obj))
		else:
			_object_positions.append(Vector2.ZERO)
	_last_sector = -2
	_active = true
	var music: Dictionary = _values.get("music", {})
	var track := str(music.get("track", ""))
	if bool(music.get("enabled", false)) and not track.is_empty():
		var audio := get_node_or_null("/root/AudioManager")
		if audio == null or not audio.play_music(track):
			event_logged.emit("music unavailable: %s.wav" % track)
	registers_changed.emit()
	_execute(_engine.event_level_start())


func stop_playtest() -> void:
	_active = false
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.stop_music()


func is_active() -> bool:
	return _active


## get_watch() -> String
##
## Nonzero registers as "5=100  123=98" (named registers show their label)
## for the debug panel's register watch.
func get_watch() -> String:
	if not _active:
		return ""
	var regs := _engine.get_registers()
	var names: Dictionary = _values.get("registers", {}).get("names", {})
	var parts: Array[String] = []
	for reg in range(regs.size()):
		if regs[reg] == 0:
			continue
		var label := str(reg)
		if names.has(reg):
			label = "%d:%s" % [reg, str(names[reg])]
		parts.append("%s=%d" % [label, regs[reg]])
	return "  ".join(parts)


func _physics_process(delta: float) -> void:
	if not _active or _level_data == null or _player == null:
		return
	var pos := Vector2(_player.global_position.x, _player.global_position.z)
	var sector := GeometryOps.sector_at(_level_data, pos)
	if sector != _last_sector:
		_last_sector = sector
		if sector != -1:
			_execute(_engine.event_sector_changed(sector))
	_execute(_engine.tick(delta, pos, _object_positions))


func _execute(actions: Array) -> void:
	if actions.is_empty():
		return
	for action in actions:
		_execute_action(action)
	registers_changed.emit()


func _execute_action(action: Dictionary) -> void:
	match str(action.get("do", "")):
		"set_register", "add_register":
			var reg := int(action["reg"])
			var result := _engine.apply_register_action(action)
			if bool(result["ignored"]):
				event_logged.emit("write to read-only register %d ignored" % reg)
			else:
				event_logged.emit("register %d = %d" % [reg, _engine.get_registers()[reg]])
			if bool(result["game_over"]):
				_game_over("register %d set" % reg)
		"message":
			var text := str(action.get("text", ""))
			message_shown.emit(text)
			event_logged.emit("message: %s" % text)
		"play_sound":
			var art := str(action.get("art", ""))
			var audio := get_node_or_null("/root/AudioManager")
			if audio == null or not audio.play_sound(art):
				event_logged.emit("sound unavailable: %s.wav" % art)
			else:
				event_logged.emit("sound: %s" % art)
		"damage_player":
			var amount := int(action.get("amount", 0))
			var result := _engine.damage_player(amount)
			event_logged.emit("player takes %d damage (health %d)" % [
				amount, _engine.get_registers()[GameplayOps.REG_HEALTH],
			])
			if bool(result["died"]):
				_game_over("player died")
		"remove_object":
			var object := int(action.get("object", -1))
			if _objects_3d != null and object >= 0:
				_objects_3d.hide_object(object)
				event_logged.emit("object %d removed" % object)
		"warp":
			var link_id := str(action.get("link", ""))
			var links: Dictionary = _values.get("links", {})
			if links.has(link_id):
				event_logged.emit("warp: %s" % link_id)
				warp_requested.emit(links[link_id])
		"run_script":
			var steps := _engine.run_script(str(action.get("script", "")))
			for note in _engine.last_notes:
				event_logged.emit(note)
			_engine.last_notes.clear()
			_execute(steps)


func _game_over(reason: String) -> void:
	event_logged.emit("GAME OVER (%s)" % reason)
	message_shown.emit("GAME OVER — %s" % reason)
