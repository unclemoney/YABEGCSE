extends Node

## GameSettings (autoload)
##
## Editor preferences only — the data that lives for the whole application
## lifetime. No editor state, no level data, no helper methods.

## World units per grid cell at base zoom. 1 unit = 6 mm.
var grid_size: int = 32
## Zoom-dependent grid ladder (world units). The canvas picks the smallest
## step whose on-screen size stays readable.
var grid_sizes: Array[int] = [4, 8, 16, 32, 64, 128, 256]
var snap_enabled: bool = true
var fog_enabled: bool = true
