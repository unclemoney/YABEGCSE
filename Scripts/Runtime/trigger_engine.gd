class_name TriggerEngine
extends RefCounted

## TriggerEngine (M7)
##
## The pure play-test core: the 256-register universe bank plus trigger
## evaluation over GameplayOps' validated view. No nodes, no LevelData, no
## audio — events and ticks go in, action lists come out; the
## GameplayRuntime node executes the side effects. Fully headless-testable.
##
## Semantics:
## - `once` (default true) latches a trigger after its first fire; a failed
##   condition does NOT consume it (it can fire when the condition holds).
## - enter_sector is edge-triggered by the runtime; near_object is
##   edge-triggered on entering the radius (re-arms on leaving when
##   once=false); timer accumulates delta and fires each period.
## - Writes to the read-only live-stat registers 122-126 are ignored (GCS
##   semantics); register 127 nonzero means game over — the engine halts.
## - run_script steps are returned flattened; recursion is capped
##   (GameplayOps.MAX_SCRIPT_DEPTH) with a note in last_notes.

var last_notes: Array[String] = []

var _registers: Array[int] = []
var _triggers: Array = []
var _scripts: Dictionary = {}
var _fired: Array = []  # bool per trigger
var _inside: Array = []  # bool per near_object trigger (edge re-arm)
var _timer_accum: Array = []  # float per trigger
var _game_over := false


## setup(values)
##
## Arms the engine from a validated GameplayOps view: registers zeroed,
## `initial` applied, health (123) defaults to DEFAULT_HEALTH, all
## per-trigger state cleared. Called on every play-test entry — registers
## deliberately reset (editor play-test is single-level).
func setup(values: Dictionary) -> void:
	_registers.clear()
	_registers.resize(GameplayOps.REGISTER_COUNT)
	_registers.fill(0)
	var initial: Dictionary = values.get("registers", {}).get("initial", {})
	for reg in initial:
		_registers[int(reg)] = int(initial[reg])
	if not initial.has(GameplayOps.REG_HEALTH):
		_registers[GameplayOps.REG_HEALTH] = GameplayOps.DEFAULT_HEALTH
	_triggers = values.get("triggers", [])
	_scripts = values.get("scripts", {})
	_fired.clear()
	_inside.clear()
	_timer_accum.clear()
	for i in range(_triggers.size()):
		_fired.append(false)
		_inside.append(false)
		_timer_accum.append(0.0)
	_game_over = false
	last_notes.clear()


## event_level_start() / event_sector_changed(sector_id) -> Array
##
## Discrete events; each returns the fired actions (conditions gated,
## once applied). Empty during game over.
func event_level_start() -> Array:
	return _fire_matching("level_start", -1)


func event_sector_changed(sector_id: int) -> Array:
	return _fire_matching("enter_sector", sector_id)


## tick(delta, player_pos, object_positions) -> Array
##
## Continuous evaluation: timer accumulation, near_object radius edges,
## and the fps live stat (register 122). object_positions is the level's
## object layer as 2D positions, indexed like LevelData.objects.
func tick(delta: float, player_pos: Vector2, object_positions: Array) -> Array:
	var actions: Array = []
	if _game_over:
		return actions
	if delta > 0.0:
		_registers[GameplayOps.REG_FPS] = clampi(int(roundf(1.0 / delta)), 0, 255)
	for i in range(_triggers.size()):
		var trigger: Dictionary = _triggers[i]
		match str(trigger["event"]):
			"timer":
				_timer_accum[i] = float(_timer_accum[i]) + delta
				if float(_timer_accum[i]) >= float(trigger["every"]):
					_timer_accum[i] = 0.0
					actions.append_array(_fire(i))
			"near_object":
				var object := int(trigger["object"])
				if object >= object_positions.size():
					continue
				var dist: float = player_pos.distance_to(object_positions[object])
				# The edge is on (inside radius AND condition holds), so a
				# condition that becomes true while the player is already
				# close still fires (GCS branches re-check every frame).
				var active := dist <= float(trigger["radius"]) and _condition_met(trigger["condition"])
				if active and not bool(_inside[i]):
					actions.append_array(_fire(i))
				_inside[i] = active
	return actions


## apply_register_action(action) -> {"game_over": bool, "ignored": bool}
##
## set_register / add_register with clamping and the read-only range.
func apply_register_action(action: Dictionary) -> Dictionary:
	var result := {"game_over": false, "ignored": false}
	var reg := int(action.get("reg", -1))
	if reg < 0 or reg >= GameplayOps.REGISTER_COUNT:
		return result
	if reg >= GameplayOps.FIRST_READ_ONLY and reg <= GameplayOps.LAST_READ_ONLY:
		result["ignored"] = true
		return result
	var value := int(action.get("value", 0))
	if str(action.get("do", "")) == "add_register":
		value = _registers[reg] + value
	_registers[reg] = clampi(value, 0, 255)
	if reg == GameplayOps.REG_GAME_OVER and _registers[reg] != 0:
		_game_over = true
		result["game_over"] = true
	return result


## damage_player(amount) -> {"died": bool}
##
## Health lives in register 123; at zero the game-over register is set
## (player died = value < 128, per the GCS convention).
func damage_player(amount: int) -> Dictionary:
	var health: int = maxi(0, _registers[GameplayOps.REG_HEALTH] - amount)
	_registers[GameplayOps.REG_HEALTH] = health
	if health == 0:
		_registers[GameplayOps.REG_GAME_OVER] = 1
		_game_over = true
		return {"died": true}
	return {"died": false}


## run_script(script_id, depth) -> Array
##
## The script's steps with nested run_script actions flattened in
## definition order. Unknown ids and the depth cap land in last_notes.
func run_script(script_id: String, depth: int = 0) -> Array:
	if _game_over:
		return []
	if depth >= GameplayOps.MAX_SCRIPT_DEPTH:
		last_notes.append("run_script depth cap (%d) reached at '%s'; stopped" % [
			GameplayOps.MAX_SCRIPT_DEPTH, script_id,
		])
		return []
	if not _scripts.has(script_id):
		last_notes.append("run_script references unknown script '%s'" % script_id)
		return []
	var out: Array = []
	var steps: Array = _scripts[script_id]
	for step in steps:
		if str(step.get("do", "")) == "run_script":
			out.append_array(run_script(str(step.get("script", "")), depth + 1))
		else:
			out.append(step)
	return out


func get_registers() -> Array[int]:
	return _registers.duplicate()


func is_game_over() -> bool:
	return _game_over


func _fire_matching(event: String, subject: int) -> Array:
	var actions: Array = []
	if _game_over:
		return actions
	for i in range(_triggers.size()):
		var trigger: Dictionary = _triggers[i]
		if str(trigger["event"]) != event:
			continue
		if event == "enter_sector" and int(trigger["sector"]) != subject:
			continue
		actions.append_array(_fire(i))
	return actions


## _fire(index) -> Array
##
## Condition gate + once latch. A failed condition leaves the trigger
## armed so it can fire when the condition holds.
func _fire(index: int) -> Array:
	if _game_over or bool(_fired[index]):
		return []
	var trigger: Dictionary = _triggers[index]
	if not _condition_met(trigger["condition"]):
		return []
	if bool(trigger["once"]):
		_fired[index] = true
	return trigger["actions"]


func _condition_met(condition: Dictionary) -> bool:
	if condition.is_empty():
		return true
	var reg := int(condition["reg"])
	var value := int(condition["value"])
	var current: int = _registers[reg]
	var op := str(condition["op"])
	if op == "eq":
		return current == value
	if op == "ne":
		return current != value
	if op == "lt":
		return current < value
	if op == "gt":
		return current > value
	return true
