class_name PlatformDrawTool
extends DrawSectorTool

## PlatformDrawTool (2D "Platform Draw" mode)
##
## Draws a platform overlay: a closed polygon loop, identical interaction
## to sector drawing (click vertices, close on first vertex or Enter,
## Escape cancels). The loop never becomes a sector — it defines no walls
## and may overlap anything. The commit (default heights, texture) lives
## in ToolSystem.commit_platform; transient loop state is inherited from
## DrawSectorTool and dies with deactivation.


## _try_close() -> bool
##
## The only difference from sector drawing: the closed loop commits as a
## PlatformData overlay, not as sector geometry.
func _try_close() -> bool:
	if _verts.size() < 3:
		return false
	_system.commit_platform(_verts.duplicate())
	_verts.clear()
	finished.emit()
	return true
