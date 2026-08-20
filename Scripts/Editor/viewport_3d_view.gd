class_name Viewport3DView
extends Node3D

## Viewport3DView
##
## 3D walk view. Read-only consumer of LevelData.
## Scaffold scope: placeholder ground plane. SectorMeshBuilder lands in M2.

var _level_data: LevelData


## set_level_data(data)
##
## Called down by EditorController whenever the level is (re)bound.
func set_level_data(data: LevelData) -> void:
	_level_data = data


## rebuild()
##
## TODO M2: SectorMeshBuilder reads LevelData and rebuilds meshes here.
func rebuild() -> void:
	pass
