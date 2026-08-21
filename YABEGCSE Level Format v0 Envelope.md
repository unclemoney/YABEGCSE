# YABEGCSE — Level Format v0 Envelope

Draft 1 — high-level schema sections and semantics. **No field-level detail
yet** — that lands when Milestone 1 enters plan mode.

---

## 0. Ground rules

- One file per level. JSON, UTF-8, human-diffable.
- **Editor-owned.** Users never hand-edit; the editor reads and writes
  everything. Hand-editability is a debugging convenience, not a feature.
- Every file carries a format identifier and an integer version.
- Forward compatibility rule: loaders **ignore unknown sections and fields**
  without error. Writers never emit sections above their own version.
- Validity annotations (red-flagged sectors etc.) are **computed at load**,
  never stored.
- Units are fixed forever: **1 unit = 6 mm.** Grid snap sizes are editor
  behavior, not file data.

## 1. Section inventory

### `header`
Format identifier (`"yabegcse-level"`), version integer, generator
(editor version). Gate for all loading decisions.

### `meta`
Level name, author, timestamps, free-text description. Editor defaults
(grid preference etc.) live here as *hints*, clearly marked non-semantic.

### `environment`
The GCS-identity block. Per-level, all fields optional with defaults:
- Fog: enabled, color, near/far distances. (In the spirit of `.tbl` fade;
  this is the only distance-shading mechanism.)
- Sky: mode = flat color | horizon strip (art-library reference, in the
  spirit of `backg??.vga` / `strip??.vga`).
- Ambient light level.
- Void behavior: how unenclosed space renders (fog color default).

### `geometry`
The Build-native sector model:
- **Points** — the 2D vertex table.
- **Walls** — segments over points; per-wall texture, alignment offsets;
  a wall is solid or a **portal** (two-sided, joining adjacent sectors).
- **Sectors** — closed loops of walls; per-sector floor height + texture +
  optional slope plane; ceiling likewise; sector flags (reserved).
- Inner loops express sector-within-sector (rooms, pillars with ceilings).

**Invariants (enforced by editor, verified at load):**
- Sectors never overlap in 2D at differing heights → **no room-over-room**,
  ever.
- Wall segments never cross without a split vertex (editor auto-splits on
  draw; load-time verification only).

### `objects`
The GCS-native layer. Objects may clip anything — geometry validity rules
do not apply to them. Object taxonomy (from the GCS species table):

| YABEGCSE object type | GCS ancestor | Essence |
|---|---|---|
| `billboard` | species 2 (shaped symmetrical) | always faces player |
| `wall_object` | species 0/1 (deadwall, shapedwall) | oriented quad/box, may clip, optional alpha-holes |
| `sprite_8way` | species 7 (solid) | 8-view sprite, mirrored views |
| `fluid` | species 6 | animated sequence object |
| `platform` | species 11 | trigger / stand-on / teleport region |

Each object: type, transform (position, angle; z free), art reference,
per-type parameter bag. Scale is part of the parameter bag, not schema.

### `art`
Art references are **library-relative names only** (never embedded, never
absolute paths). Palette identity tag for the level. The art library ships
with the editor and runtime; unresolved references render as an obvious
placeholder and log to the debug panel.

### `gameplay` — **defined at Milestone 7**
All five slots optional; malformed entries are skipped with a debug-panel note
(tolerate + flag). The full semantics live in `Scripts/Data/gameplay_ops.gd`.
- `registers` — the universe-register model: 256 registers, 0–255.
  `{"initial": {"5": 100}, "names": {"5": "label"}}` — initial values apply on
  every play-test entry; 0 and 122–127 are reserved (122–126 read-only live
  stats: fps, health, …; 127 game-over), `names` are non-semantic editor hints.
- `triggers` — fluid command equivalents:
  `[{"id", "event": level_start|enter_sector|near_object|timer, "sector" |
  "object"+"radius" | "every", "once", "condition": {"reg", "op": eq|ne|lt|gt,
  "value"}, "actions": [...]}]`. Action verbs: `set_register`, `add_register`,
  `message`, `play_sound`, `damage_player`, `remove_object` (runtime-only hide),
  `warp`, `run_script`.
- `scripts` — `[{"id", "steps": [action dicts]}]`: named reusable action lists
  invoked by `run_script` (depth-capped). Redesigned in spirit — no Forth.
- `music` — `{"enabled": bool, "track": "LIB/NAME"}`: library-relative WAV base
  name, looped during play-test.
- `links` — `[{"id", "file", "entry": [x, y, z, theta_deg] (optional)}]`:
  level-to-level connections (the theaters.txt descendant). `warp` loads the
  linked level in play-test, spawning at `entry` when present.

Editors before Milestone 7 preserve this section verbatim on load/save
round-trips; writers keep unknown sub-fields the same way.

## 2. What is explicitly NOT in v0

- Room-over-room constructs of any kind.
- True freeform (unsnapped) authoring aids — snapping is the way.
- Lighting rigs beyond fog + ambient (evaluated at Milestone 6).
- Any scripting or gameplay semantics (Milestone 7).

## 3. Converter relationship

The GCS importer (Milestone 5) emits v0 files: geometry section nearly
empty (a bounding void context), all imported content as `wall_object` /
`billboard` / `sprite_8way` entries, plus an import report listing
unreconstructable elements. Sector reconstruction from GCS object clouds
is importer v2 and may write the `geometry` section; the format already
supports it, so no version bump is required for that day.
