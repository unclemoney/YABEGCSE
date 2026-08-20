class_name WalkController
extends CharacterBody3D

## WalkController
##
## Minimalist kinematic play-test walker. Horizontal: WASD +
## move_and_slide against the level collision body. Vertical:
## point-in-sector floor query with smooth stepping (no gravity, no jump
## in M2). Reads LevelData; never writes it. Feel knobs live in
## GameSettings (walk_speed, eye_height, step_height, mouse_sensitivity).

@export var camera_path: NodePath = ^"Camera3D"

var _level_data: LevelData
var _pitch := 0.0

@onready var _camera: Camera3D = get_node_or_null(camera_path)


func set_level_data(data: LevelData) -> void:
	_level_data = data


## spawn(data)
##
## Feet at the centroid of the first valid sector; origin fallback (void).
func spawn(data: LevelData) -> void:
	for si in range(data.sectors.size()):
		if data.flagged_sectors.has(si):
			continue
		var poly := GeometryOps.loop_to_polygon(data, data.sectors[si]["walls"])
		if poly.size() < 3:
			continue
		var centroid := Vector2.ZERO
		for p in poly:
			centroid += p
		centroid /= float(poly.size())
		var floor_y := float(data.sectors[si].get("floor_height", 0.0))
		global_position = Vector3(centroid.x, floor_y, centroid.y)
		return
	global_position = Vector3.ZERO


## look(relative)
##
## Yaw on the body, clamped pitch on the camera. Called down by the view.
func look(relative: Vector2) -> void:
	var sensitivity := 0.0025
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		sensitivity = settings.mouse_sensitivity
	rotation.y -= relative.x * sensitivity
	if _camera != null:
		_pitch = clampf(_pitch - relative.y * sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		_camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if _level_data == null:
		return
	var speed := 500.0
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		speed = settings.walk_speed
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0
	move_and_slide()
	# Floor-height steps: the point-in-sector query decides how high we
	# stand; risers taller than step_height are collision, not steps.
	var sector_id := GeometryOps.sector_at(_level_data, Vector2(global_position.x, global_position.z))
	if sector_id == -1:
		return  # the void: hold height, degrade gracefully
	var target := float(_level_data.sectors[sector_id].get("floor_height", 0.0))
	global_position.y = lerpf(global_position.y, target, minf(1.0, delta * 12.0))
