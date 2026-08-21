class_name Viewport3DView
extends Node3D

## Viewport3DView
##
## 3D walk view. Read-only consumer of LevelData. Owns the Level3DRoot
## (SectorMeshBuilder output), the WorldEnvironment (fog/sky/ambient/void
## via EnvironmentOps, M6), the horizon-strip sky band, and the player
## WalkController. Meshes rebuild eagerly on every geometry change so the
## 2D<->3D toggle stays zero-lag.
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
var _gameplay: GameplayRuntime
var _sky_band: MeshInstance3D
var _environment_notes: Array[String] = []


func _ready() -> void:
	_objects_3d = Objects3D.new()
	_objects_3d.name = "Objects3D"
	add_child(_objects_3d)
	if _player != null:
		_objects_3d.set_player(_player)
	# M7 gameplay runtime: triggers/registers/music during play-test.
	_gameplay = GameplayRuntime.new()
	_gameplay.name = "GameplayRuntime"
	add_child(_gameplay)
	_gameplay.set_player(_player)
	_gameplay.set_objects_3d(_objects_3d)
	# M6 horizon-strip sky: an open-ended fog-exempt cylinder around the
	# player. Hidden unless the level's sky.mode is horizon_strip.
	_sky_band = MeshInstance3D.new()
	_sky_band.name = "SkyBand"
	var cylinder := CylinderMesh.new()
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = 32
	_sky_band.mesh = cylinder
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sky_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sky_mat.disable_fog = true
	_sky_band.material_override = sky_mat
	_sky_band.visible = false
	add_child(_sky_band)


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
	if _gameplay != null:
		_gameplay.set_level_data(data)


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
	stats["environment_notes"] = _environment_notes.duplicate()
	if _gameplay != null:
		stats["gameplay_notes"] = _gameplay.revalidate()
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
	apply_preferences()
	if not _spawned and _player != null and _level_data != null:
		_player.spawn(_level_data)
		_spawned = true
	if _gameplay != null:
		_gameplay.start_playtest()


func exit_3d() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _gameplay != null:
		_gameplay.stop_playtest()


## get_gameplay() -> GameplayRuntime
##
## Read-only handle for the EditorController's signal wiring.
func get_gameplay() -> GameplayRuntime:
	return _gameplay


## restart_playtest()
##
## Called down by the controller after a warp loads the linked level:
## the new level's registers, triggers and music take over.
func restart_playtest() -> void:
	if _gameplay != null:
		_gameplay.start_playtest()


## spawn_player_at(entry)
##
## Warp arrival: entry is [x, y, z, theta_deg] in v0 units (the same
## convention as the meta.spawn hint in WalkController.spawn).
func spawn_player_at(entry: Array) -> void:
	if _player == null or entry.size() < 4:
		return
	_player.global_position = Vector3(float(entry[0]), float(entry[2]), float(entry[1]))
	_player.rotation.y = deg_to_rad(float(entry[3]) - 180.0)
	_spawned = true


## apply_preferences()
##
## Called down by EditorController when the preferences panel applies
## (and on enter_3d). Walk speed / mouse sensitivity are read per-frame
## by the WalkController; eye height needs an explicit nudge.
func apply_preferences() -> void:
	if _player == null:
		return
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	var camera := _player.get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.position.y = settings.eye_height


func _process(_delta: float) -> void:
	_update_aim()
	if _sky_band != null and _sky_band.visible:
		_follow_sky_band()


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
	if event.is_action_pressed("grab_corner") or event.is_action_released("grab_corner"):
		GeometryOps.slope_log("view: grab_corner %s — aim kind='%s' sector=%s hit=%s" % [
			"pressed" if event.is_action_pressed("grab_corner") else "released",
			_aim.get("kind", &"none"), str(_aim.get("sector_id", "-")),
			str(_aim.get("point", "-")),
		])
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
## Applies the level's validated environment (EnvironmentOps.settings):
## fog (level fog.enabled AND the GameSettings F-toggle), ambient light,
## background. The background color is the void color — fog color by
## default, sky color when void.mode is sky_color; horizon_strip adds the
## fog-exempt art band at the horizon. Notes (malformed fields that fell
## back to defaults) are collected for the debug panel.
##
## Caveat: the retro pipeline is unshaded, so ambient is semantically
## applied but has no visual effect on level meshes yet.
func _apply_environment() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	var result := EnvironmentOps.settings(_level_data)
	var values: Dictionary = result["values"]
	_environment_notes.clear()
	for note in result["notes"]:
		_environment_notes.append(note)
	var fog: Dictionary = values["fog"]
	var sky: Dictionary = values["sky"]
	var fog_color := Color.html(fog["color"])
	var sky_color := Color.html(sky["color"])
	var enabled := bool(fog["enabled"])
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		enabled = enabled and settings.fog_enabled
	env.fog_enabled = enabled
	env.fog_light_color = fog_color
	# World units are large (1 unit = 6 mm) and Godot's depth fog is
	# exponential: 1 - exp(-density * depth). Anchor the curve to the
	# level's near/far range: density 3/far reaches ~95% fog at far.
	env.fog_depth_begin = fog["near"]
	env.fog_depth_end = fog["far"]
	env.fog_density = 3.0 / env.fog_depth_end
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = values["ambient"]
	var background := fog_color
	if values["void"]["mode"] == "sky_color":
		background = sky_color
	env.background_mode = Environment.BG_COLOR
	env.background_color = background
	if sky["mode"] == "horizon_strip":
		_update_sky_band(sky, fog)
	elif _sky_band != null:
		_sky_band.visible = false


## _update_sky_band(sky, fog)
##
## (Re)builds the horizon strip: radius just inside fog far, height from
## the strip texture (mildly stretched), texture repeated around the
## circumference at 1 texel = 1 world unit.
func _update_sky_band(sky: Dictionary, fog: Dictionary) -> void:
	if _sky_band == null:
		return
	var radius := 0.8 * float(fog["far"])
	var tex := ArtCache.resolve(str(sky["strip"]) + ".png")
	var tex_size := Vector2(tex.get_size())
	var cylinder := _sky_band.mesh as CylinderMesh
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = maxf(64.0, tex_size.y * 4.0)
	var mat := _sky_band.material_override as StandardMaterial3D
	mat.albedo_texture = tex
	var repeats := maxf(1.0, roundf(TAU * radius / maxf(1.0, tex_size.x)))
	mat.uv1_scale = Vector3(repeats, 1.0, 1.0)
	_sky_band.visible = true
	_follow_sky_band()


## _follow_sky_band()
##
## The band is centered on the player at eye height; yaw-locked so the
## texture scrolls with the world (GCS-style).
func _follow_sky_band() -> void:
	if _sky_band == null or _player == null:
		return
	var eye := 140.0
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		eye = settings.eye_height
	_sky_band.position = Vector3(_player.global_position.x, eye, _player.global_position.z)


func _step_height() -> float:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		return settings.step_height
	return 24.0
