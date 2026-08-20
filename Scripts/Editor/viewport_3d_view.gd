class_name Viewport3DView
extends Node3D

## Viewport3DView
##
## 3D walk view. Read-only consumer of LevelData. Owns the Level3DRoot
## (SectorMeshBuilder output), the WorldEnvironment (fog/void) and the
## player WalkController. Meshes rebuild eagerly on every geometry change
## so the 2D<->3D toggle stays zero-lag.

@export var world_env_path: NodePath = ^"WorldEnvironment"
@export var level_root_path: NodePath = ^"Level3DRoot"
@export var player_path: NodePath = ^"Player"

var _level_data: LevelData
var _spawned := false

@onready var _world_env: WorldEnvironment = get_node_or_null(world_env_path)
@onready var _level_root: Node3D = get_node_or_null(level_root_path)
@onready var _player: WalkController = get_node_or_null(player_path)


## set_level_data(data)
##
## Called down by EditorController whenever the level is (re)bound.
func set_level_data(data: LevelData) -> void:
	_level_data = data
	_spawned = false
	if _player != null:
		_player.set_level_data(data)


## rebuild()
##
## Called down by EditorController on level changes. Cheap enough to run
## eagerly at editor scale; the 3D view is always ready when toggled to.
func rebuild() -> void:
	if _level_root == null or _level_data == null:
		return
	SectorMeshBuilder.build_level(_level_root, _level_data, _step_height())
	_apply_environment()


## enter_3d() / exit_3d()
##
## Called down by EditorController on mode switch. Mouse capture follows
## the mode; the player spawns once per level binding.
func enter_3d() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _spawned and _player != null and _level_data != null:
		_player.spawn(_level_data)
		_spawned = true


func exit_3d() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _player != null:
			_player.look((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_fog"):
		var settings := get_node_or_null("/root/GameSettings")
		if settings != null:
			settings.fog_enabled = not settings.fog_enabled
			_apply_environment()
			get_viewport().set_input_as_handled()


## _apply_environment()
##
## Fog (color/near/far) comes from the level's environment section; the
## toggle is a GameSettings preference. The void renders as fog color.
func _apply_environment() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	var fog := {}
	if _level_data != null:
		fog = _level_data.environment.get("fog", {})
	var fog_color := Color.html(str(fog.get("color", "#202830")))
	var enabled := true
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		enabled = settings.fog_enabled
	env.fog_enabled = enabled
	env.fog_light_color = fog_color
	# World units are large (1 unit = 6 mm) and Godot's depth fog is
	# exponential: 1 - exp(-density * depth). Anchor the curve to the
	# level's near/far range: density 3/far reaches ~95% fog at far.
	env.fog_depth_begin = float(fog.get("near", 128.0))
	env.fog_depth_end = float(fog.get("far", 1536.0))
	env.fog_density = 3.0 / env.fog_depth_end
	env.background_mode = Environment.BG_COLOR
	env.background_color = fog_color


func _step_height() -> float:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		return settings.step_height
	return 24.0
