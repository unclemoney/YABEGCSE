class_name Canvas2DView
extends Node2D

## Canvas2DView
##
## Top-down 2D editing view. Read-only consumer of LevelData.
## Scaffold scope: grid backdrop and axes. Drawing tools land in M1.

var _level_data: LevelData


## set_level_data(data)
##
## Called down by EditorController whenever the level is (re)bound.
func set_level_data(data: LevelData) -> void:
	_level_data = data
	queue_redraw()


func redraw_level() -> void:
	queue_redraw()


func _draw() -> void:
	var grid := 32
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		grid = maxi(1, settings.grid_size)
	var extent := 64 * grid
	var minor := Color(0.25, 0.25, 0.28, 0.6)
	var x := -extent
	while x <= extent:
		draw_line(Vector2(x, -extent), Vector2(x, extent), minor)
		x += grid
	var y := -extent
	while y <= extent:
		draw_line(Vector2(-extent, y), Vector2(extent, y), minor)
		y += grid
	draw_line(Vector2(-extent, 0), Vector2(extent, 0), Color(0.5, 0.3, 0.3), 2.0)
	draw_line(Vector2(0, -extent), Vector2(0, extent), Color(0.3, 0.5, 0.3), 2.0)
	# TODO M1: draw sectors from _level_data (red when flagged).
