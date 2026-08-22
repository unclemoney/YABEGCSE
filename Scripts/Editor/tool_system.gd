class_name ToolSystem
extends Node

## ToolSystem
##
## Owns the active tool and routes input to it. Tools are classes, not
## nodes; they mutate LevelData through the commit_* methods here and
## never touch views. mutation_committed fires BEFORE the mutation so
## EditorController can push an undo snapshot; level_data_changed fires
## after re-validation so views redraw.

signal level_data_changed(change_type: LevelData.ChangeType)
signal mutation_committed
signal texture_pick_requested(aim: Dictionary)
## Tool feedback routed to the status line / debug panel (tools never
## touch UI themselves; EditorController wires these to UIPanels).
signal status_requested(text: String)
signal debug_log_requested(text: String)

var _level_data: LevelData
var _draw_tool: DrawSectorTool
var _edit_3d_tool: Edit3DTool
var _object_tool: ObjectTool
var _vertex_tool: VertexEditTool
var _wall_tool: WallSelectTool
var _platform_tool: PlatformDrawTool
var _platform_edit_tool: PlatformEditTool
var _active_tool: RefCounted
## Position in the 2D tool cycle (Sector Draw -> Vertex Edit -> Wall
## Select -> Platform Draw -> Platform Edit); survives object-mode detours
## and 3D toggles.
var _cycle_index := 0
## World units per screen pixel (1 / 2D zoom), set down by
## EditorController each frame so tool pick radii stay in screen px.
var _pick_scale := 1.0
var _pending_texture_aim := {}
var _last_aim := {}
## M4 brush: what the ObjectTool places on click.
var _brush := {"type": "billboard", "art": ""}
## Platform Edit selection (index into LevelData.platforms, -1 = none).
## Shared by the 2D PlatformEditTool, the 3D Edit3DTool and the texture
## picker; single selection only.
var _selected_platform := -1


## _ready()
##
## Side-effects: creates the tool set (the 2D cycle: draw + vertex +
## wall + platform draw + platform edit, plus 2D objects and 3D edit)
## and activates the draw tool.
func _ready() -> void:
	_draw_tool = DrawSectorTool.new(self)
	_edit_3d_tool = Edit3DTool.new(self)
	_object_tool = ObjectTool.new(self)
	_vertex_tool = VertexEditTool.new(self)
	_wall_tool = WallSelectTool.new(self)
	_platform_tool = PlatformDrawTool.new(self)
	_platform_edit_tool = PlatformEditTool.new(self)
	_active_tool = _draw_tool


func set_level_data(data: LevelData) -> void:
	_level_data = data
	_selected_platform = -1
	if _active_tool != null:
		_active_tool.deactivate()


func get_level_data() -> LevelData:
	return _level_data


func get_active_tool() -> Object:
	return _active_tool


## _cycle_tools() -> Array
##
## The 2D tool cycle, in Tab order. The object tool is deliberately not
## part of the cycle (O key toggles it on top of the current cycle slot).
func _cycle_tools() -> Array:
	return [_draw_tool, _vertex_tool, _wall_tool, _platform_tool, _platform_edit_tool]


## cycle_tool(direction)
##
## Tab / Shift+Tab: instant switch, the active tool is deactivated before
## the next is activated. No-op in 3D mode (the Edit3DTool owns 3D).
func cycle_tool(direction: int) -> void:
	if _active_tool == _edit_3d_tool or _active_tool == null:
		return
	_active_tool.deactivate()
	_cycle_index = posmod(_cycle_index + direction, _cycle_tools().size())
	_active_tool = _cycle_tools()[_cycle_index]
	_active_tool.activate()


## get_tool_mode_name() -> String
##
## Display name for the 2D canvas mode label.
func get_tool_mode_name() -> String:
	if _active_tool == _vertex_tool:
		return "VERTEX EDIT"
	if _active_tool == _wall_tool:
		return "WALL SELECT"
	if _active_tool == _object_tool:
		return "OBJECT PLACE"
	if _active_tool == _platform_tool:
		return "PLATFORM DRAW"
	if _active_tool == _platform_edit_tool:
		return "PLATFORM EDIT"
	if _active_tool == _edit_3d_tool:
		return "3D EDIT"
	return "SECTOR DRAW"


## set_mode_3d(is_3d)
##
## Called down by EditorController on mode switch. The current 2D cycle
## tool and the 3D edit tool are swapped; tool state dies on deactivation.
func set_mode_3d(is_3d: bool) -> void:
	if _active_tool != null:
		_active_tool.deactivate()
	if is_3d:
		_active_tool = _edit_3d_tool
	else:
		_active_tool = _cycle_tools()[_cycle_index]
	_active_tool.activate()


## set_object_mode(on)
##
## 2D tool switching (O key): the object tool overlays the current cycle
## slot; turning it off returns to that slot. 3D mode always uses the
## Edit3DTool; set_mode_3d wins over this.
func set_object_mode(on: bool) -> void:
	if _active_tool == _edit_3d_tool:
		return
	_active_tool.deactivate()
	if on:
		_active_tool = _object_tool
	else:
		_active_tool = _cycle_tools()[_cycle_index]
	_active_tool.activate()


func get_brush() -> Dictionary:
	return _brush


## set_pick_scale(scale) / get_pick_scale() -> float
##
## World units per screen pixel, fed down by EditorController every frame
## (2D mode). Tools multiply their screen-px pick radii by it.
func set_pick_scale(scale: float) -> void:
	_pick_scale = maxf(scale, 0.0001)


func get_pick_scale() -> float:
	return _pick_scale


## request_status(text) / report_debug(text)
##
## Tool feedback helpers: signals up to EditorController, which calls the
## status line / debug panel down. Tools never touch UI themselves.
func request_status(text: String) -> void:
	status_requested.emit(text)


func report_debug(text: String) -> void:
	debug_log_requested.emit(text)


func set_brush_type(type: String) -> void:
	_brush["type"] = type


## set_brush_art(tex_name)
##
## Object art is stored as a library-relative BASE name (no extension) so
## frame/view expansion rules apply.
func set_brush_art(tex_name: String) -> void:
	_brush["art"] = tex_name.trim_suffix(".png")


func get_preview() -> Dictionary:
	if _active_tool == null:
		return {}
	return _active_tool.get_preview()


## handle_input(event, world_pos, snapped_pos) -> bool
##
## 2D canvas route. Returns true when consumed. Tab / Shift+Tab cycle the
## 2D tool modes (forward / backward) before any tool sees the event.
func handle_input(event: InputEvent, world_pos: Vector2, snapped_pos: Vector2) -> bool:
	if _active_tool == null or _active_tool == _edit_3d_tool:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_TAB:
			cycle_tool(-1 if key.shift_pressed else 1)
			return true
		if key.keycode == KEY_O:
			set_object_mode(_active_tool != _object_tool)
			return true
	return _active_tool.handle_input(event, world_pos, snapped_pos)


## handle_3d_input(event, aim) -> bool
## handle_3d_motion(relative, aim) -> bool
##
## 3D route: the Viewport3DView computes the crosshair AimInfo and signals
## upward; EditorController calls these down in 3D mode.
func handle_3d_input(event: InputEvent, aim: Dictionary) -> bool:
	if _active_tool != _edit_3d_tool:
		return false
	if not aim.is_empty():
		_last_aim = aim
	return _edit_3d_tool.handle_input(event, aim)


func handle_3d_motion(relative: Vector2, aim: Dictionary) -> bool:
	if _active_tool != _edit_3d_tool:
		return false
	if not aim.is_empty():
		_last_aim = aim
	return _edit_3d_tool.handle_motion(relative, aim)


func is_3d_dragging() -> bool:
	if _active_tool != _edit_3d_tool:
		return false
	return _edit_3d_tool.is_dragging()


func describe_aim(aim: Dictionary) -> String:
	if _active_tool != _edit_3d_tool:
		return ""
	return _edit_3d_tool.describe_aim(aim)


## pick_sector(world_pos) -> int
##
## Picking helper exposed to tools (smallest containing sector).
func pick_sector(world_pos: Vector2) -> int:
	if _level_data == null:
		return -1
	return GeometryOps.sector_at(_level_data, world_pos)


## pick_platform(world_pos) -> int
##
## Picking helper exposed to tools (smallest containing platform).
func pick_platform(world_pos: Vector2) -> int:
	if _level_data == null:
		return -1
	return GeometryOps.platform_at(_level_data, world_pos)


## select_platform(idx) / get_selected_platform() -> int
##
## Platform Edit selection, shared by the 2D PlatformEditTool and the 3D
## Edit3DTool. Out-of-range and -1 both clear the selection.
func select_platform(idx: int) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.platforms.size():
		_selected_platform = -1
	else:
		_selected_platform = idx


func get_selected_platform() -> int:
	return _selected_platform


## commit_loop(verts)
##
## Closes a drawn loop into a sector. One mutation = one undo step.
func commit_loop(verts: Array) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	GeometryOps.close_loop_from_positions(_level_data, verts)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_platform(verts)
##
## Platform Draw mode: closes a drawn loop into a PlatformData overlay
## (NOT a sector — no walls, no containment rules). floor_height defaults
## to the sector floor height at the polygon centroid (0 in the void),
## ceiling_height to floor + 16 (thin platform), texture to the current
## UI brush art. One mutation = one undo step.
func commit_platform(verts: Array) -> void:
	if _level_data == null or verts.size() < 3:
		return
	var platform := PlatformData.new()
	for v in verts:
		platform.vertices.append(v)
	var centroid := platform.centroid()
	var sector_id := GeometryOps.sector_at(_level_data, centroid)
	if sector_id != -1:
		platform.floor_height = GeometryOps.floor_height_at(_level_data, sector_id, centroid)
	platform.ceiling_height = platform.floor_height + 16.0
	platform.texture = str(_brush["art"])
	mutation_committed.emit()
	_level_data.platforms.append(platform)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


## commit_platform_delete(idx)
##
## Platform Edit (Delete key): removes one drawn platform overlay. One
## mutation = one undo step (undo snapshots carry platforms).
func commit_platform_delete(idx: int) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.platforms.size():
		return
	mutation_committed.emit()
	_level_data.platforms.remove_at(idx)
	if _selected_platform == idx:
		_selected_platform = -1
	elif _selected_platform > idx:
		_selected_platform -= 1
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


## commit_platform_toggle_visible(idx) -> bool
##
## Platform Edit (V key): flips is_visible. Invisible platforms skip 3D
## mesh generation and draw as a dashed outline only in 2D. Returns the
## new visibility. One mutation = one undo step.
func commit_platform_toggle_visible(idx: int) -> bool:
	if _level_data == null or idx < 0 or idx >= _level_data.platforms.size():
		return false
	mutation_committed.emit()
	var platform: PlatformData = _level_data.platforms[idx]
	platform.is_visible = not platform.is_visible
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)
	return platform.is_visible


## request_delete(sector_id)
##
## Single-sector delete: an ordinary undoable edit. Batch deletes (Clear
## Level) are confirmed destructive ops handled by EditorController.
func request_delete(sector_id: int) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	GeometryOps.delete_sector(_level_data, sector_id)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_height(sector_id, kind, delta)
##
## M3: raise/lower a sector's floor or ceiling by delta (one wheel tick =
## one undo step). kind is &"floor" or &"ceiling".
func commit_height(sector_id: int, kind: StringName, delta: float) -> void:
	if _level_data == null:
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		return
	mutation_committed.emit()
	var sector: Dictionary = _level_data.sectors[sector_id]
	var key := &"floor_height" if kind == &"floor" else &"ceiling_height"
	sector[key] = float(sector.get(key, 0.0)) + delta
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_match_surrounding(sector_id, kind) -> Dictionary
##
## Inner sector height shortcut (3D mode, Shift+H / Shift+L): matches the
## selected sector's ceiling (kind &"ceiling") or floor (&"floor") height
## to its surrounding sector's — the smallest-area sector whose polygon
## contains all of the selected sector's vertices (GeometryOps.
## surrounding_sector). Intended for pillars: an inner sector becomes a
## solid column. The face's slope is cleared so the match is what the
## player sees. One mutation = one undo step; a rejected shortcut never
## touches the undo stack. Returns {"ok", "surrounding"|"reason"}.
func commit_match_surrounding(sector_id: int, kind: StringName) -> Dictionary:
	if _level_data == null:
		return {"ok": false, "reason": "no level"}
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		return {"ok": false, "reason": "no sector"}
	var outer := GeometryOps.surrounding_sector(_level_data, sector_id)
	if outer == -1:
		return {"ok": false, "reason": "no_surrounding"}
	mutation_committed.emit()
	var sector: Dictionary = _level_data.sectors[sector_id]
	var surrounding: Dictionary = _level_data.sectors[outer]
	if kind == &"ceiling":
		sector["ceiling_height"] = float(surrounding.get("ceiling_height", 256.0))
		sector["ceiling_slope"] = []
	else:
		sector["floor_height"] = float(surrounding.get("floor_height", 0.0))
		sector["floor_slope"] = []
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)
	return {"ok": true, "surrounding": outer}


## commit_wall_offset(wall_id, du, dv)
##
## M3: nudge a wall's texture alignment (offset_u/offset_v, in texels).
func commit_wall_offset(wall_id: int, du: float, dv: float) -> void:
	if _level_data == null:
		return
	if wall_id < 0 or wall_id >= _level_data.walls.size():
		return
	mutation_committed.emit()
	var w: Dictionary = _level_data.walls[wall_id]
	w["offset_u"] = float(w.get("offset_u", 0.0)) + du
	w["offset_v"] = float(w.get("offset_v", 0.0)) + dv
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## request_texture_pick(aim)
##
## The Edit3DTool asks for the texture picker (T key). The aim is kept so
## commit_texture knows what to apply the picked name to.
func request_texture_pick(aim: Dictionary) -> void:
	_pending_texture_aim = aim.duplicate()
	texture_pick_requested.emit(aim)


## commit_texture(tex_name)
##
## Applies a library-relative texture name to the face/wall/object/
## platform remembered by request_texture_pick (platform aims carry
## {"kind": &"platform", "platform_id": int} — this is the shared path
## for Platform Edit texturing in both 2D and 3D). One mutation = one
## undo step.
func commit_texture(tex_name: String) -> void:
	if _level_data == null:
		return
	var aim := _pending_texture_aim
	if aim.is_empty():
		aim = _last_aim
	if aim.is_empty():
		return
	var kind: StringName = aim.get("kind", &"none")
	mutation_committed.emit()
	if kind == &"object":
		var object_id := int(aim.get("object_id", -1))
		if object_id >= 0 and object_id < _level_data.objects.size():
			var o: Dictionary = _level_data.objects[object_id]
			o["art"] = tex_name.trim_suffix(".png")
			if o.get("type") == "sprite_8way":
				o["params"]["views"] = ObjectOps.probe_views(o["art"])
	elif kind == &"wall":
		var wall_id := int(aim.get("wall_id", -1))
		if wall_id >= 0 and wall_id < _level_data.walls.size():
			_level_data.walls[wall_id]["texture"] = tex_name
	elif kind == &"platform":
		var platform_id := int(aim.get("platform_id", -1))
		if platform_id >= 0 and platform_id < _level_data.platforms.size():
			_level_data.platforms[platform_id].texture = tex_name
	else:
		var sector_id := int(aim.get("sector_id", -1))
		if sector_id >= 0 and sector_id < _level_data.sectors.size():
			var key := &"floor_texture" if kind == &"floor" else &"ceiling_texture"
			_level_data.sectors[sector_id][key] = tex_name
	_pending_texture_aim = {}
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## commit_reset_slope(sector_id, slope_key)
##
## M3: clears a face's slope corners (X key). Undoable, no confirm dialog.
func commit_reset_slope(sector_id: int, slope_key: StringName) -> void:
	if _level_data == null:
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		return
	mutation_committed.emit()
	_level_data.sectors[sector_id][slope_key] = []
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## Corner-drag slope editing: begin takes the undo snapshot once (the drag
## is ONE undo step), update mutates + revalidates for live preview, end
## closes the gesture.
func begin_corner_drag() -> void:
	GeometryOps.slope_log("system: begin_corner_drag (undo snapshot)")
	mutation_committed.emit()


func update_corner_drag(sector_id: int, slope_key: StringName, point_id: int, height: float) -> void:
	if _level_data == null:
		GeometryOps.slope_log("system: update_corner_drag dropped — no LevelData")
		return
	if sector_id < 0 or sector_id >= _level_data.sectors.size():
		GeometryOps.slope_log("system: update_corner_drag dropped — bad sector %d" % sector_id)
		return
	GeometryOps.set_slope_corner(_level_data.sectors[sector_id], slope_key, point_id, height)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


func end_corner_drag() -> void:
	GeometryOps.slope_log("system: end_corner_drag")


## --- M4 object commits -------------------------------------------------
## Same discipline as geometry: mutation_committed (undo snapshot) ->
## mutate -> validate -> level_data_changed. Drags take the snapshot once
## at begin and preview through update.

## commit_object_place(pos)
##
## Places the current brush at pos. 8-way sprites get their rotation views
## probed from the library at placement time.
func commit_object_place(pos: Vector2) -> void:
	if _level_data == null:
		return
	var obj := ObjectOps.defaults(str(_brush["type"]))
	if obj.is_empty():
		return
	obj["pos"] = [pos.x, pos.y]
	obj["art"] = str(_brush["art"])
	if obj["type"] == "sprite_8way":
		obj["params"]["views"] = ObjectOps.probe_views(obj["art"])
	mutation_committed.emit()
	_level_data.objects.append(obj)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func commit_object_move(idx: int, pos: Vector2, z: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	_level_data.objects[idx]["pos"] = [pos.x, pos.y]
	_level_data.objects[idx]["z"] = z
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func commit_object_rotate(idx: int, delta_deg: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	var o: Dictionary = _level_data.objects[idx]
	o["angle"] = fmod(float(o.get("angle", 0.0)) + delta_deg, 360.0)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func commit_object_delete(idx: int) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	_level_data.objects.remove_at(idx)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


## commit_object_z(idx, delta)
##
## Ctrl+wheel z nudge in 3D. One tick = one undo step.
func commit_object_z(idx: int, delta: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	mutation_committed.emit()
	var o: Dictionary = _level_data.objects[idx]
	o["z"] = float(o.get("z", 0.0)) + delta
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func begin_object_drag() -> void:
	mutation_committed.emit()


func update_object_drag(idx: int, pos: Vector2) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	_level_data.objects[idx]["pos"] = [pos.x, pos.y]
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func update_object_drag_z(idx: int, z: float) -> void:
	if _level_data == null or idx < 0 or idx >= _level_data.objects.size():
		return
	_level_data.objects[idx]["z"] = z
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)


func end_object_drag() -> void:
	pass


## --- Vertex edit commits (2D Vertex mode) ------------------------------
## Same discipline as corner drags: begin takes the undo snapshot once
## (the drag is ONE undo step), update mutates + revalidates for live
## preview, finish validates the final position and snaps back on a
## crossing move.

func begin_vertex_drag() -> void:
	mutation_committed.emit()


func update_vertex_drag(point_id: int, pos: Vector2) -> void:
	if _level_data == null:
		return
	GeometryOps.move_point(_level_data, point_id, pos)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)


## finish_vertex_drag(point_id, start_pos) -> bool
##
## Release of a vertex drag. The drag previewed live; the final position
## is validated now: a move that crosses any wall snaps the vertex back
## to start_pos and returns false (the tool flashes + logs). Returns
## true when the move stands.
func finish_vertex_drag(point_id: int, start_pos: Vector2) -> bool:
	if _level_data == null:
		return false
	if point_id < 0 or point_id >= _level_data.points.size():
		return false
	var current := GeometryOps.get_point(_level_data, point_id)
	if GeometryOps.move_causes_crossing(_level_data, point_id, current):
		GeometryOps.move_point(_level_data, point_id, start_pos)
		GeometryOps.validate(_level_data)
		level_data_changed.emit(LevelData.ChangeType.GEOMETRY)
		return false
	return true


## commit_merge_portal(wall_id) -> Dictionary
##
## Wall-select merge (Delete in Wall mode). The pure GeometryOps gate
## runs first so a rejected merge never touches the undo stack; a
## passing merge is one undo step. Returns the check/merge result
## ({"ok", "reason", ...}).
func commit_merge_portal(wall_id: int) -> Dictionary:
	if _level_data == null:
		return {"ok": false, "reason": "no level"}
	var plan := GeometryOps.check_portal_merge(_level_data, wall_id)
	if not plan["ok"]:
		return plan
	mutation_committed.emit()
	var result := GeometryOps.merge_sectors_at_portal(_level_data, wall_id)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.GEOMETRY)
	return result


## commit_environment(env)
##
## M6: replaces the level's environment section (Environment panel
## Apply). One mutation = one undo step. The panel passes raw field
## values; malformed entries are tolerated and flagged by
## EnvironmentOps at consumption time.
func commit_environment(env: Dictionary) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	_level_data.environment = env.duplicate(true)
	level_data_changed.emit(LevelData.ChangeType.ENVIRONMENT)


## commit_gameplay(gameplay)
##
## M7: replaces the level's gameplay section (Gameplay panel Apply). One
## mutation = one undo step. The panel passes raw field values; malformed
## entries are tolerated and flagged by GameplayOps at consumption time.
func commit_gameplay(gameplay: Dictionary) -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	_level_data.gameplay = gameplay.duplicate(true)
	level_data_changed.emit(LevelData.ChangeType.GAMEPLAY)


## debug_place_test_set()
##
## Debug-panel command: one object of each type near the origin, using
## real ArtLibrary art (BUG_ENEM 8-view set, ANIM_LIB fluid).
func debug_place_test_set() -> void:
	if _level_data == null:
		return
	mutation_committed.emit()
	var specs := [
		{"type": "billboard", "pos": [0.0, -192.0], "art": "SOBJ_LIB/BARSTOOL"},
		{"type": "wall_object", "pos": [128.0, -192.0], "art": "ANIM_LIB/BARREL"},
		{"type": "sprite_8way", "pos": [256.0, -192.0], "art": "BUG_ENEM/BUG1BS"},
		{"type": "fluid", "pos": [384.0, -192.0], "art": "ANIM_LIB/BURN"},
		{"type": "platform", "pos": [512.0, -192.0], "art": "BASICLIB/BOX1"},
	]
	for spec in specs:
		var obj := ObjectOps.defaults(spec["type"])
		obj["pos"] = spec["pos"]
		obj["art"] = spec["art"]
		if obj["type"] == "sprite_8way":
			obj["params"]["views"] = ObjectOps.probe_views(obj["art"])
		_level_data.objects.append(obj)
	GeometryOps.validate(_level_data)
	level_data_changed.emit(LevelData.ChangeType.OBJECTS)
