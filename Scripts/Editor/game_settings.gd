extends Node

## GameSettings (autoload)
##
## Editor preferences only — the data that lives for the whole application
## lifetime. No editor state, no level data, no helper methods.
## Persisted to user://game_settings.cfg (M6): the preferences panel's
## Apply writes and saves; load is tolerant (missing/malformed entries
## keep the compiled-in defaults).

const SETTINGS_PATH := "user://game_settings.cfg"
const SECTION := "preferences"

## World units per grid cell at base zoom. 1 unit = 6 mm.
var grid_size: int = 32
## Zoom-dependent grid ladder (world units). The canvas picks the smallest
## step whose on-screen size stays readable.
var grid_sizes: Array[int] = [4, 8, 16, 32, 64, 128, 256]
var snap_enabled: bool = true
var fog_enabled: bool = true

## Movement feel knobs (minimalist preference surface; tune between the
## DOSBox GCS capture and Build-constants reference poles).
var walk_speed := 500.0
var eye_height := 140.0
var step_height := 24.0
var mouse_sensitivity := 0.0025


func _ready() -> void:
	load_settings()


## load_settings()
##
## Reads persisted preferences. Every entry is optional and type-checked;
## bad values keep the defaults (tolerate, don't crash).
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	walk_speed = _num(cfg, "walk_speed", walk_speed)
	mouse_sensitivity = _num(cfg, "mouse_sensitivity", mouse_sensitivity)
	eye_height = _num(cfg, "eye_height", eye_height)
	step_height = _num(cfg, "step_height", step_height)
	grid_size = int(_num(cfg, "grid_size", grid_size))
	var fog: Variant = cfg.get_value(SECTION, "fog_enabled", fog_enabled)
	if fog is bool:
		fog_enabled = fog


## save_settings()
##
## Writes the current preferences. Called by EditorController when the
## preferences panel applies.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "walk_speed", walk_speed)
	cfg.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value(SECTION, "eye_height", eye_height)
	cfg.set_value(SECTION, "step_height", step_height)
	cfg.set_value(SECTION, "grid_size", grid_size)
	cfg.set_value(SECTION, "fog_enabled", fog_enabled)
	cfg.save(SETTINGS_PATH)


func _num(cfg: ConfigFile, key: String, default: float) -> float:
	var value: Variant = cfg.get_value(SECTION, key, default)
	if value is float or value is int:
		return float(value)
	return default
