class_name Viewport3DView
extends Node3D

## Viewport3DView
##
## 3D walk view. Read-only consumer of LevelData. Owns the Level3DRoot
## (SectorMeshBuilder output), the WorldEnvironment (fog/void) and the
## player WalkController. Meshes rebuild eagerly on every geometry change
## so the 2D<->3D toggle stays zero-lag.
##
## M3: computes the crosshair AimInfo (GeometryOps.aim_from_ray) every
## frame and signals edit input upward; EditorController routes it to the
## ToolSystem. Mouse-look is suppressed while a corner drag is active
## (set_look_suppressed, called down by the controller).

signal edit_input(event: InputEvent, aim: Dictionary)
signal edit_motion(relative: Vector2, aim: Dictionary)

@export var world_env_path: NodePath = ^"WorldEnvironment"
@export var level_root_path: NodePath = ^"Level3DRoot"
@export var player_path: NodePath = ^"Player"

var _level_data: LevelData
var _spawned := false
var _look_suppressed := false
var _aim := {"kind": &"none"}

@onready var _world_env: WorldEnvironment = get_node_or_null(world_env_path)
@onready var _level_root: Node3D = get_node_or_null(level_root_path)
@onready var _player: WalkController = get_node_or_null(player_path)

var _objects_3d: Objects3D


func _ready() -> void:
	_objects_3d = Objects3D.new()
	_objects_3d.name = "Objects3D"
	add_child(_objects_3d)
	if _player != null:
		_objects_3d.set_player(_player)


## set_level_data(data)
##
## Called down by EditorController whenever the level is (re)bound.
func set_level_data(data: LevelData) -> void:
	_level_data = data
	_spawned = false
	if _player != null:
		_player.set_level_data(data)
	if _objects_3d != null:
		_objects_3d.set_level_data(data)


## rebuild() -> Dictionary
##
## Called down by EditorController on level changes. Cheap enough to run
## eagerly at editor scale; the 3D view is always ready when toggled to.
## Returns the SectorMeshBuilder stats (missing_textures feeds the debug
## panel).
func rebuild() -> Dictionary:
	if _level_root == null or _level_data == null:
		return {}
	var stats := SectorMeshBuilder.build_level(_level_root, _level_data, _step_height())
	if _objects_3d != null:
		_objects_3d.rebuild()
	_apply_environment()
	return stats


## get_aim() -> Dictionary
##
## The current crosshair AimInfo (read-only query from the controller).
func get_aim() -> Dictionary:
	return _aim


## set_look_suppressed(suppressed)
##
## Called down by EditorController: while a corner drag is active, mouse
## motion drives the drag instead of the camera.
func set_look_suppressed(suppressed: bool) -> void:
	_look_suppressed = suppressed


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


func _process(_delta: float) -> void:
	_update_aim()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var relative := (event as InputEventMouseMotion).relative
		# Edit route first: the controller/tool may claim the motion for a
		# corner drag and suppress look synchronously.
		edit_motion.emit(relative, _aim)
		if not _look_suppressed and _player != null:
			_player.look(relative)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_fog"):
		var settings := get_node_or_null("/root/GameSettings")
		if settings != null:
			settings.fog_enabled = not settings.fog_enabled
			_apply_environment()
			get_viewport().set_input_as_handled()
		return
	# M3 edit input: wheel, grab/release, T, X. The controller decides
	# whether the tool consumes it.
	edit_input.emit(event, _aim)


## _update_aim()
##
## Crosshair ray: camera through screen center, resolved against the level
## geometry (pure math, no physics query — floors/ceilings have no
## collision shapes).
func _update_aim() -> void:
	if _level_data == null or _player == null:
		_aim = {"kind": &"none"}
		return
	var camera := _player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		_aim = {"kind": &"none"}
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var dir := camera.project_ray_normal(center)
	_aim = GeometryOps.aim_from_ray(_level_data, origin, dir)
	# M4: an object nearer than the geometry hit wins the crosshair.
	var obj_hit := ObjectOps.ray_pick(_level_data.objects, origin, dir)
	if not obj_hit.is_empty():
		var geo_dist := float(_aim.get("distance", GeometryOps.MAX_AIM_DIST))
		if float(obj_hit["distance"]) < geo_dist:
			var idx := int(obj_hit["object_id"])
			var obj: Dictionary = _level_data.objects[idx]
			var ground: Variant = Plane(Vector3.UP, float(obj.get("z", 0.0))).intersects_ray(origin, dir)
			_aim = {
				"kind": &"object",
				"object_id": idx,
				"sector_id": -1,
				"wall_id": -1,
				"point": obj_hit["point"],
				"distance": obj_hit["distance"],
				"ground_point": ground if ground != null else obj_hit["point"],
			}


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
