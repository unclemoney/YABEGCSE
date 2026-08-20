class_name ToolSystem
extends Node

## ToolSystem
##
## Owns the active tool and routes input to it. Tools are classes, not
## nodes; they mutate LevelData through ToolSystem and never touch views.
## Scaffold scope: no tools exist yet (M1 adds sector drawing).

signal level_data_changed(change_type: LevelData.ChangeType)

var _level_data: LevelData
var _active_tool: Object  # TODO M1: Tool base class with activate/deactivate/handle_input/get_cursor


func set_level_data(data: LevelData) -> void:
	_level_data = data


func get_active_tool() -> Object:
	return _active_tool


## handle_input(event) -> bool
##
## Returns true when the active tool consumed the event.
func handle_input(_event: InputEvent) -> bool:
	if _active_tool == null:
		return false
	return false  # TODO M1: route to _active_tool.handle_input(event)
