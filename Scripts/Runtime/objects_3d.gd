class_name Objects3D
extends Node3D

## Objects3D (M4)
##
## Renders the level's object layer as Sprite3D instances. Rebuilt from
## Viewport3DView.rebuild(); per-frame updates animate fluids and re-aim
## 8-way sprites at the player. Read-only consumer of LevelData. Objects
## clip geometry freely by design; alpha-keyed transparency via
## ALPHA_CUT_DISCARD. Unresolved art renders as the ArtCache placeholder
## and lands on the debug panel's missing-texture list.

var _level_data: LevelData
var _player: Node3D
var _fluids: Array = []  # {"sprite": Sprite3D, "frames": Array[String], "fps": float}
var _eight_way: Array = []  # {"sprite": Sprite3D, "obj": Dictionary}
var _time := 0.0


func set_level_data(data: LevelData) -> void:
	_level_data = data


func set_player(player: Node3D) -> void:
	_player = player


## rebuild()
##
## One Sprite3D per well-formed object. Malformed entries (flagged) are
## skipped; they show in the debug panel instead.
func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_fluids.clear()
	_eight_way.clear()
	if _level_data == null:
		return
	for i in range(_level_data.objects.size()):
		if _level_data.flagged_objects.has(i):
			continue
		_spawn(_level_data.objects[i])


func _process(delta: float) -> void:
	_time += delta
	for f in _fluids:
		var frames: Array = f["frames"]
		if frames.size() < 2:
			continue
		var idx := int(_time * float(f["fps"])) % frames.size()
		f["sprite"].texture = ArtCache.resolve(frames[idx])
	if _player != null:
		for e in _eight_way:
			_update_view(e["sprite"], e["obj"])


func _spawn(obj: Dictionary) -> void:
	var type := str(obj.get("type", ""))
	var frames := ArtCache.resolve_object_frames(obj)
	var pos := ObjectOps.get_pos(obj)
	var z := float(obj.get("z", 0.0))
	var obj_scale := float(obj.get("params", {}).get("scale", 1.0))
	var sprite := Sprite3D.new()
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.pixel_size = obj_scale  # 1 texel = 1 world unit at scale 1
	match type:
		"billboard", "fluid":
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.position = Vector3(pos.x, z + _tex_height(frames) * obj_scale * 0.5, pos.y)
		"wall_object", "sprite_8way":
			sprite.rotation.y = -deg_to_rad(float(obj.get("angle", 0.0)))
			sprite.position = Vector3(pos.x, z + _tex_height(frames) * obj_scale * 0.5, pos.y)
		"platform":
			sprite.rotation.x = deg_to_rad(-90.0)
			sprite.position = Vector3(pos.x, z + 1.0, pos.y)
			sprite.modulate = Color(1.0, 1.0, 1.0, 0.7)
	if not frames.is_empty():
		sprite.texture = ArtCache.resolve(frames[0])
	else:
		sprite.texture = ArtCache.placeholder()
	if type == "platform":
		var size := ObjectOps.get_extent(obj)
		var tex_size := sprite.texture.get_size()
		sprite.scale = Vector3(size.x / tex_size.x, size.y / tex_size.y, 1.0)
	add_child(sprite)
	if type == "fluid" and frames.size() > 1:
		_fluids.append({"sprite": sprite, "frames": frames, "fps": float(obj["params"].get("fps", 8.0))})
	elif type == "sprite_8way":
		_eight_way.append({"sprite": sprite, "obj": obj})


## _update_view(sprite, obj)
##
## 8-way logic: pick the view for the object->player direction; mirror
## the partner view when the exact one is absent.
func _update_view(sprite: Sprite3D, obj: Dictionary) -> void:
	var pos := ObjectOps.get_pos(obj)
	var to_player := Vector2(_player.global_position.x, _player.global_position.z) - pos
	if to_player.length_squared() < 0.000001:
		return
	var deg := rad_to_deg(to_player.angle()) - 90.0
	var view := ObjectOps.view_for_angle(obj, deg)
	var view_name := str(view["name"])
	if view_name.is_empty():
		return
	sprite.texture = ArtCache.resolve_base(view_name)
	sprite.flip_h = view["mirrored"]


func _tex_height(frames: Array) -> float:
	if frames.is_empty():
		return ObjectOps.DEFAULT_SIZE
	return float(ArtCache.resolve(frames[0]).get_size().y)
