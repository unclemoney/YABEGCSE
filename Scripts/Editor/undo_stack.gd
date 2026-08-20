class_name UndoStack
extends Node

## UndoStack
##
## 3-deep undo of LevelData diffs. Imports and batch deletes are confirmed
## destructive operations and stay outside this stack.
## Scaffold scope: container and capacity only; snapshots land with M1 tools.

const CAPACITY := 3

var _snapshots: Array = []


func push(snapshot: Variant) -> void:
	_snapshots.push_back(snapshot)
	while _snapshots.size() > CAPACITY:
		_snapshots.pop_front()


func pop_undo() -> Variant:
	if _snapshots.is_empty():
		return null
	return _snapshots.pop_back()


func clear() -> void:
	_snapshots.clear()
