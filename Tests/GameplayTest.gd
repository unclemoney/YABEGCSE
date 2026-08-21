extends SceneTree

## GameplayTest
##
## Headless harness for M7: GameplayOps validation (fallback/skip + note
## per malformed entry), serializer round-trip of the gameplay section
## (unknown fields survive, notes never stored), TriggerEngine behavior
## (registers, conditions, once, events, timers, scripts, game over), and
## the gameplay fixture's working trigger chain.
## Run: godot --path <repo> --headless -s Tests/GameplayTest.gd

const LOG := "res://Tests/gameplay.log"
const GP_FIXTURE := "res://Tests/Fixtures/level_gameplay_v0.json"

var _failures := 0
var _lines: Array[String] = []


func _init() -> void:
	_begin.call_deferred()


func _begin() -> void:
	_test_defaults()
	_test_malformed()
	_test_valid_custom()
	_test_round_trip()
	_test_engine_registers()
	_test_engine_triggers()
	_test_engine_scripts()
	_test_fixture_chain()
	_finish()


func _test_defaults() -> void:
	var data := LevelData.create_empty()
	var result := GameplayOps.settings(data)
	_check((result["notes"] as Array).is_empty(), "defaults validate with zero notes")
	var values: Dictionary = result["values"]
	_check((values["triggers"] as Array).is_empty(), "default triggers empty")
	_check((values["links"] as Dictionary).is_empty(), "default links empty")
	_check(values["music"]["enabled"] == false, "default music disabled")
	_check((values["registers"]["initial"] as Dictionary).is_empty(), "default initial registers empty")


func _test_malformed() -> void:
	var data := LevelData.create_empty()
	data.gameplay = {
		"registers": {
			"initial": {"x": 1, "0": 5, "123": 1, "130": "a", "131": 300},
			"names": "nope",
		},
		"music": {"enabled": "yes", "track": "NOPE404"},
		"links": [{"id": "", "file": "x"}, {"id": "a"}, {"id": "b", "file": "b.json", "entry": [1, 2]}],
		"scripts": [{"steps": []}, {"id": "s", "steps": "nope"}],
		"triggers": [
			{"event": "explode", "actions": [{"do": "message", "text": "x"}]},
			{"event": "enter_sector", "sector": 99, "actions": [{"do": "message", "text": "x"}]},
			{"event": "near_object", "object": 4, "actions": [{"do": "message", "text": "x"}]},
			{"event": "timer", "every": 0.0, "actions": [{"do": "message", "text": "x"}]},
			{"event": "level_start", "once": "yes", "actions": [{"do": "nuke"}]},
			{"event": "level_start", "actions": [{"do": "set_register", "reg": 5}]},
			{"event": "level_start", "actions": [{"do": "warp", "link": "ghost"}]},
			{"event": "level_start", "actions": [{"do": "run_script", "script": "ghost"}]},
			{"event": "level_start", "condition": "nope", "actions": [{"do": "message", "text": "ok"}]},
		],
	}
	var result := GameplayOps.settings(data)
	var values: Dictionary = result["values"]
	var notes: Array = result["notes"]
	_check(_has_note(notes, "not a register number"), "bad register key noted")
	_check(_has_note(notes, "reserved/read-only"), "reserved initial register noted")
	_check(_has_note(notes, "not a number"), "non-numeric initial value noted")
	_check(_has_note(notes, "registers.names"), "non-object names noted")
	_check(int(values["registers"]["initial"][131]) == 255, "initial value clamps to 255")
	_check(_has_note(notes, "music.enabled"), "non-bool music.enabled noted")
	_check(_has_note(notes, "NOPE404"), "missing music track noted")
	_check((values["links"] as Dictionary).size() == 1, "only the recoverable link survives")
	_check((values["links"]["b"]["entry"] as Array).is_empty(), "bad link entry dropped, link kept")
	_check(_has_note(notes, "non-empty id and file"), "empty link id noted")
	_check(_has_note(notes, "entry must be 4 numbers"), "bad link entry noted")
	_check((values["scripts"] as Dictionary).is_empty(), "malformed scripts all skipped")
	_check(_has_note(notes, "unknown event 'explode'"), "unknown event noted")
	_check(_has_note(notes, "sector 99 out of range"), "sector subject noted")
	_check(_has_note(notes, "object 4 out of range"), "object subject noted")
	_check(_has_note(notes, "every > 0"), "bad timer noted")
	_check(_has_note(notes, "once is not a bool"), "bad once noted")
	_check(_has_note(notes, "unknown action 'nuke'"), "unknown verb noted")
	_check(_has_note(notes, "needs reg (0-255) and a numeric value"), "bad set_register noted")
	_check(_has_note(notes, "unknown link 'ghost'"), "unknown warp link noted")
	_check(_has_note(notes, "unknown script 'ghost'"), "unknown run_script noted")
	_check(_has_note(notes, "condition is not an object"), "bad condition noted")
	# Only the bad-condition trigger survives (its condition was dropped).
	_check((values["triggers"] as Array).size() == 1, "only the recoverable trigger survives")
	_check((values["triggers"][0]["condition"] as Dictionary).is_empty(), "dropped condition is empty")


func _test_valid_custom() -> void:
	var data := LevelData.create_empty()
	data.objects.append({"type": "platform", "pos": [0.0, 0.0], "z": 0.0, "angle": 0.0, "art": "", "params": {}})
	data.gameplay = {
		"registers": {"initial": {"5": 100}, "names": {"5": "key"}},
		"music": {"enabled": true, "track": "MUSIC/TEST_TONE"},
		"links": [{"id": "cave", "file": "cave.json", "entry": [1, 2, 3, 90]}],
		"scripts": [{"id": "s1", "steps": [{"do": "message", "text": "hi"}]}],
		"triggers": [
			{
				"id": "t1", "event": "near_object", "object": 0, "radius": 300.0, "once": false,
				"condition": {"reg": 5, "op": "gt", "value": 50},
				"actions": [
					{"do": "play_sound", "art": "MUSIC/TEST_TONE"},
					{"do": "remove_object", "object": 0},
					{"do": "warp", "link": "cave"},
					{"do": "run_script", "script": "s1"},
					{"do": "damage_player", "amount": 10},
				],
			},
		],
	}
	var result := GameplayOps.settings(data)
	var values: Dictionary = result["values"]
	_check((result["notes"] as Array).is_empty(), "valid custom gameplay: zero notes (got %d)" % (result["notes"] as Array).size())
	_check(int(values["registers"]["initial"][5]) == 100, "initial register keyed by int")
	_check(values["music"]["track"] == "MUSIC/TEST_TONE", "music track kept")
	_check(values["links"].has("cave"), "links keyed by id")
	_check((values["links"]["cave"]["entry"] as Array).size() == 4, "link entry kept")
	_check(values["scripts"].has("s1"), "script kept")
	var trigger: Dictionary = values["triggers"][0]
	_check(trigger["once"] == false, "once=false kept")
	_check((trigger["actions"] as Array).size() == 5, "all five actions kept")


func _test_round_trip() -> void:
	var serializer := LevelSerializer.new()
	var text := FileAccess.get_file_as_string(GP_FIXTURE)
	var data := serializer.load_from_json(text)
	_check(data != null, "gameplay fixture loads")
	if data == null:
		return
	# Raw storage keeps the JSON shape (string register keys).
	_check(data.gameplay["registers"]["initial"].has("5"), "raw gameplay keeps string register keys")
	data.gameplay["future_field"] = {"x": 1}
	var saved := serializer.save_to_json(data)
	var back := serializer.load_from_json(saved)
	_check(back != null, "round-trip: re-parses")
	if back == null:
		return
	_check(back.gameplay.has("triggers") and back.gameplay.has("future_field"),
		"round-trip: gameplay + unknown field survive")
	_check(back.gameplay["triggers"].size() == 8, "round-trip: all raw triggers kept (malformed included)")
	_check(not back.gameplay.has("notes"), "round-trip: notes never stored")


func _test_engine_registers() -> void:
	var engine := TriggerEngine.new()
	engine.setup(_engine_values({5: 10}, [], {}))
	_check(engine.get_registers()[5] == 10, "initial register applied")
	_check(engine.get_registers()[GameplayOps.REG_HEALTH] == GameplayOps.DEFAULT_HEALTH,
		"health defaults to 100")
	var r := engine.apply_register_action({"do": "set_register", "reg": 5, "value": 300})
	_check(engine.get_registers()[5] == 255, "set clamps to 255")
	r = engine.apply_register_action({"do": "add_register", "reg": 5, "value": -300})
	_check(engine.get_registers()[5] == 0, "add clamps to 0")
	r = engine.apply_register_action({"do": "set_register", "reg": 123, "value": 5})
	_check(bool(r["ignored"]) and engine.get_registers()[123] == 100, "read-only write ignored")
	r = engine.apply_register_action({"do": "set_register", "reg": 127, "value": 200})
	_check(bool(r["game_over"]) and engine.is_game_over(), "register 127 nonzero = game over")
	_check(engine.event_level_start().is_empty(), "game over halts events")

	# Fresh engine: damage path to death.
	engine = TriggerEngine.new()
	engine.setup(_engine_values({}, [], {}))
	var d := engine.damage_player(30)
	_check(not bool(d["died"]) and engine.get_registers()[123] == 70, "damage reduces health")
	d = engine.damage_player(100)
	_check(bool(d["died"]) and engine.get_registers()[127] == 1, "death sets game-over register 1")


func _test_engine_triggers() -> void:
	var triggers := [
		{"id": "start", "event": "level_start", "sector": -1, "object": -1, "radius": 600.0,
			"every": 0.0, "once": true, "condition": {},
			"actions": [{"do": "message", "text": "go"}]},
		{"id": "gated", "event": "enter_sector", "sector": 2, "object": -1, "radius": 600.0,
			"every": 0.0, "once": true, "condition": {"reg": 5, "op": "gt", "value": 3},
			"actions": [{"do": "message", "text": "gated"}]},
		{"id": "pad", "event": "near_object", "sector": -1, "object": 0, "radius": 100.0,
			"every": 0.0, "once": false, "condition": {},
			"actions": [{"do": "message", "text": "pad"}]},
		{"id": "beat", "event": "timer", "sector": -1, "object": -1, "radius": 600.0,
			"every": 2.0, "once": false, "condition": {},
			"actions": [{"do": "add_register", "reg": 9, "value": 1}]},
	]
	var engine := TriggerEngine.new()
	engine.setup(_engine_values({}, triggers, {}))
	_check(engine.event_level_start().size() == 1, "level_start fires")
	_check(engine.event_level_start().is_empty(), "level_start once: no refire")
	# Condition gate: reg 5 == 0, needs > 3 — the edge passes unconsumed.
	_check(engine.event_sector_changed(2).is_empty(), "failed condition does not fire")
	engine.apply_register_action({"do": "set_register", "reg": 5, "value": 7})
	_check(engine.event_sector_changed(2).size() == 1, "condition met later: fires")
	_check(engine.event_sector_changed(2).is_empty(), "once: latched after firing")
	_check(engine.event_sector_changed(1).is_empty(), "wrong sector does not fire")
	# near_object edge + re-arm (once=false).
	var objects := [Vector2(0.0, 0.0)]
	_check(engine.tick(0.1, Vector2(50.0, 0.0), objects).size() == 1, "near_object fires on entry")
	_check(engine.tick(0.1, Vector2(50.0, 0.0), objects).is_empty(), "near_object: no refire while inside")
	engine.tick(0.1, Vector2(500.0, 0.0), objects)
	_check(engine.tick(0.1, Vector2(50.0, 0.0), objects).size() == 1, "near_object re-arms after leaving")
	# Timer accumulation (the near_object entry also re-fires; filter by verb).
	var fired := engine.tick(1.5, Vector2(500.0, 0.0), objects)
	_check(fired.is_empty(), "timer not yet at period")
	fired = engine.tick(0.6, Vector2(500.0, 0.0), objects)
	_check(fired.size() == 1 and fired[0]["do"] == "add_register", "timer fires at period")
	fired = engine.tick(2.1, Vector2(500.0, 0.0), objects)
	_check(fired.size() == 1, "timer refires (once=false)")
	# fps live stat.
	engine.tick(0.5, Vector2(500.0, 0.0), objects)
	_check(engine.get_registers()[GameplayOps.REG_FPS] == 2, "fps written to register 122")
	# A condition that turns true while already inside the radius still fires.
	var cond_triggers := [
		{"id": "cpad", "event": "near_object", "sector": -1, "object": 0, "radius": 100.0,
			"every": 0.0, "once": true, "condition": {"reg": 7, "op": "eq", "value": 1},
			"actions": [{"do": "message", "text": "cpad"}]},
	]
	var engine2 := TriggerEngine.new()
	engine2.setup(_engine_values({}, cond_triggers, {}))
	_check(engine2.tick(0.1, Vector2(0.0, 0.0), objects).is_empty(),
		"conditioned pad: no fire while condition false")
	engine2.apply_register_action({"do": "set_register", "reg": 7, "value": 1})
	_check(engine2.tick(0.1, Vector2(0.0, 0.0), objects).size() == 1,
		"conditioned pad fires when condition turns true inside")
	_check(engine2.tick(0.1, Vector2(0.0, 0.0), objects).is_empty(),
		"conditioned pad once: latched")


func _test_engine_scripts() -> void:
	var scripts := {
		"outer": [{"do": "message", "text": "a"}, {"do": "run_script", "script": "inner"}],
		"inner": [{"do": "message", "text": "b"}],
		"loop_a": [{"do": "run_script", "script": "loop_b"}],
		"loop_b": [{"do": "run_script", "script": "loop_a"}],
	}
	var engine := TriggerEngine.new()
	engine.setup(_engine_values({}, [], scripts))
	var steps := engine.run_script("outer")
	_check(steps.size() == 2, "run_script flattens nested calls")
	_check(steps[1]["text"] == "b", "nested steps in order")
	engine.run_script("ghost")
	_check(_has_note(engine.last_notes, "unknown script 'ghost'"), "unknown script noted")
	engine.last_notes.clear()
	engine.run_script("loop_a")
	_check(_has_note(engine.last_notes, "depth cap"), "script cycle hits the depth cap")


func _test_fixture_chain() -> void:
	var serializer := LevelSerializer.new()
	var data := serializer.load_from_json(FileAccess.get_file_as_string(GP_FIXTURE))
	_check(data != null, "fixture loads")
	if data == null:
		return
	var result := GameplayOps.settings(data)
	var values: Dictionary = result["values"]
	var notes: Array = result["notes"]
	_check(notes.size() == 7, "fixture yields exactly 7 notes (got %d)" % notes.size())
	_check((values["triggers"] as Array).size() == 5, "5 of 8 fixture triggers survive")
	_check(values["links"].has("self") and values["links"].has("nowhere"), "both links kept")
	_check(values["music"]["enabled"] == true, "fixture music enabled (track in library)")
	var engine := TriggerEngine.new()
	engine.setup(values)
	_check(engine.get_registers()[5] == 1, "fixture initial register 5 = 1")
	_check(engine.get_registers()[123] == 100, "fixture reserved initial 123 ignored, health default")
	var actions := engine.event_level_start()
	_check(actions.size() == 1 and actions[0]["text"] == "Welcome to the gameplay fixture",
		"level_start welcome message")
	actions = engine.event_sector_changed(0)
	_check(actions.size() == 1, "bad_condition trigger recovered and fires")
	actions = engine.event_sector_changed(1)
	_check(actions.size() == 2, "second_room trigger fires (2 actions)")
	engine.apply_register_action(actions[0])
	_check(engine.get_registers()[5] == 2, "register 5 set to 2")
	# The pad chain: player near the platform with reg 5 == 2.
	var objects := [Vector2(384.0, 128.0)]
	actions = engine.tick(0.1, Vector2(384.0, 128.0), objects)
	_check(actions.size() == 3, "pad chain fires: sound + remove + run_script")
	_check(actions[2]["do"] == "run_script", "pad ends in run_script")
	var steps := engine.run_script(str(actions[2]["script"]))
	_check(steps.size() == 2 and steps[1]["do"] == "warp", "warp_home script resolves to the warp")
	_check(engine.tick(0.1, Vector2(384.0, 128.0), objects).is_empty(), "pad once: no refire")


func _engine_values(initial: Dictionary, triggers: Array, scripts: Dictionary) -> Dictionary:
	return {
		"registers": {"initial": initial, "names": {}},
		"triggers": triggers,
		"scripts": scripts,
		"music": {"enabled": false, "track": ""},
		"links": {},
	}


func _has_note(notes: Array, substr: String) -> bool:
	for note in notes:
		if str(note).contains(substr):
			return true
	return false


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
