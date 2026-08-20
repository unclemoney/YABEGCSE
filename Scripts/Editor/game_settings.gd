extends Node

## GameSettings (autoload)
##
## Editor preferences only — the data that lives for the whole application
## lifetime. No editor state, no level data, no helper methods.

## World units per grid cell at base zoom. 1 unit = 6 mm.
var grid_size: int = 32
var snap_enabled: bool = true
var fog_enabled: bool = true
