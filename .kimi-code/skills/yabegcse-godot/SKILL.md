---
name: yabegcse-godot
description: YABEGCSE project conventions, Godot 4.4 GDScript standards, and architectural patterns for the 3D GCS retro editor
type: prompt
whenToUse: When writing, reviewing, or debugging GDScript code in the YABEGCSE Godot project
disableModelInvocation: false
---

# Agent Instructions — YABEGCSE (3DGCS)

YABEGCSE is a retro 3D level editor built in Godot 4.4.1, GDScript only. It is a Build-style sector editor with GCS content compatibility. The editor is the product. The runtime is its play-test mode. 2D top-down canvas and 3D walk mode live in the same scene. No scene reload on toggle.

---

## Architecture Rules (Debt Prevention)

These rules are not suggestions. Violating them creates coupling that will force a refactor later.

### Autoload Discipline

- **Maximum 6 autoloads.** If you need a seventh, delete or merge one first.
- An autoload is only for data that must survive the entire application lifetime. Preferences. Audio. Nothing else.
- Never use an autoload as a dumping ground for helper methods. Extract a static utility class or a local node.
- Never store editor state, tool state, level data, or viewport state in an autoload.
- Current autoloads (locked): `GameSettings` (preferences), `AudioManager` (sound). Four slots remain. Justify each addition in the commit message.

### Signal Up, Call Down (Strict)

- A child node emits signals upward. It never calls methods on its parent.
- A parent node calls methods downward on its children. It never reaches into grandchildren.
- Sibling nodes do not talk to each other. They emit signals to their common parent, which calls the sibling.
- No `get_parent()` calls. No `owner` references from children. No `get_node()` across branches.
- If a child needs something from above, it signals. If a parent needs something from below, it calls a method.
- Cross-domain communication goes up to the common ancestor, then down. No shortcuts.

### State Ownership

- **LevelData** is a single `Resource` class owned by `EditorController`. It is the only source of truth for the current level.
- All views (2D canvas, 3D viewport, UI panels) read from `LevelData`. None write to it directly.
- Only the **tool system** writes to `LevelData`. Tools receive input events and mutate `LevelData`. The tool system then emits `level_data_changed`.
- Views listen to `level_data_changed` and redraw. No view calls another view.
- Editor preferences (grid size, snap mode, theme) live in `GameSettings` autoload. Everything else is scene-local.
- Undo snapshots are `LevelData` diffs. The undo stack lives in a node under `EditorController`, not an autoload.

### Scene Tree Architecture

- The editor is a **single persistent scene**. `EditorController` is the root.
- `EditorController` owns: `Canvas2D` (drawing view), `Viewport3D` (walk view), `ToolSystem`, `UIPanels`, `UndoStack`.
- 2D/3D toggle changes visibility and input processing. No scene change. No reload.
- Each major domain is a child scene under `EditorController`. No domain knows about another domain.
- `EditorController` is the only node that knows all domains exist. It wires signals.

### Tool System Architecture

- Tools are classes, not nodes. Each tool implements `activate()`, `deactivate()`, `handle_input(event)`-style input handlers, and `get_preview()`.
- `ToolSystem` owns the active tool. It instantiates tools and routes input to the active one.
- A tool mutates `LevelData` through `ToolSystem` methods. It never touches the 2D canvas or 3D viewport directly.
- A tool emits `finished` or `cancelled` signals upward to `ToolSystem`. No tool reaches into UI.
- Tool state (mouse position, drag start, preview geometry) lives in the tool instance. It dies with deactivation.

### 2D/3D View Synchronization

- Both views are read-only consumers of `LevelData`.
- `LevelData` emits `changed` with a change type enum. Views subscribe to relevant change types and redraw.
- 2D camera position and 3D camera position are independent. No view syncs cameras.
- The mesh generator reads `LevelData` geometry and produces Godot meshes. It is a separate system, not a tool.
- `Geometry2D.triangulate_polygon` is used in the mesh builder only. Never in a tool.

### JSON Serialization

- `LevelSerializer` is a class, not an autoload. `EditorController` instantiates it for load/save operations.
- Load: JSON → `LevelData` Resource. Unknown sections are preserved verbatim.
- Save: `LevelData` → JSON. Round-trip must be lossless.
- Validation happens at load time, not at draw time. Invalid sectors are flagged, not crashed.
- The serializer never touches the file system directly. `EditorController` handles file dialogs.

### Refactoring Triggers

Split when any of these are true:
- A script exceeds 300 lines.
- A node has more than 12 direct children. Group into sub-scenes.
- A scene references more than 3 domains (UI, logic, rendering, data). Split it.
- A method has more than 3 levels of indentation. Extract a method.
- You add a second `if` checking the same condition in two different nodes. Extract shared state or a signal.
- An autoload grows beyond 200 lines. It is doing too much. Move logic into the scene tree.

---

## Coding Standards

- Target **Godot 4.4 GDScript** syntax exclusively.
- **Tabs** for indentation. Never spaces.
- Prefix every script with `extends` and `class_name`.
- `snake_case` for methods/variables, `PascalCase` for classes and node names.
- Wrap exported properties in `@export var` and onready lookups in `@onready var`.
- Never emit inline parsing hacks — break declarations into separate `var` + assignment.
- Godot does **not** support `?:` ternary syntax. Use `if/else`.
- GDScript does **not** support multi-line boolean expressions with `and`/`or` split across lines. Use single-line `if` or nested `if` blocks.
- Do **not** add `class_name` to autoload scripts.
- Review the existing codebase for naming consistency before introducing new variables, methods, or classes.
- Godot executable path (for reference): `C:\Users\danie\OneDrive\Documents\GODOT\Godot_v4.4.1-stable_win64.exe`

---

## API Verification Guardrail

Before calling any method, connecting any signal, or accessing any property from another script, **always verify its exact signature** (name, argument count, argument types, return type) by reading the source file. Common mistakes this prevents:

- Calling a method with the wrong number of arguments.
- Connecting to a signal that does not exist or has the wrong argument signature.
- Using a property name that does not exist or has the wrong type.

**class_name scope errors in editors:** When the GDScript Language Server reports "Could not find type X in current scope" for class_name types that are correctly declared, this is typically an LSP indexing issue — not a code error. Godot's own `global_script_class_cache.cfg` (in `.godot/`) is the source of truth for registered class_names. To resolve: restart the GDScript language server, or close and reopen the Godot editor to force a re-import. Do not refactor code to work around IDE-only scope errors when the class_name declarations are valid.

---

## Documentation Standards

- Use Godot doc comments `##` for any function header or documentation you want editors/IDE to surface.
- Keep the top line the function signature (as a doc title): e.g. `## _on_game_start()` then `##` blank line, then description lines.
- Put parameter descriptions only when the function's behavior depends on non-obvious args. Use `_arg` for unused signal params to avoid lint warnings.
- Use short "Notes" or "Side-effects" sections when the function interacts with other systems (UI, signals, scene tree).
- Keep single responsibility per function; if a function needs long doc blocks (>8 lines), consider splitting it.
- For lifecycle functions (`_ready`, `_process`, `_on_tree_exiting`) state side-effects clearly (what they connect, what they start).
- For public API functions (used by other scripts), document the contract: inputs, outputs, error modes, and expected object types.
- Keep dev TODOs as `# TODO:` or `## TODO:` lines so they're searchable; prefer issue links for long tasks.

---

## Scene & Node Organization

- **Single responsibility**: each scene owns exactly one domain (UI, 2D view, 3D view, tool logic).
- Design scenes to have no dependencies where possible.
- Reusable scenes should be self-contained and not rely on external nodes.
- **Root Logic Node**: `EditorController` at the scene root. It owns `LevelData` and wires cross-domain signals.
- **Typed Paths**: export `NodePath` for everything you need from another scene, assign them in the inspector, and guard with `get_node_or_null()` in `_ready()`.
- Avoid global state when possible; use node trees and signals.

---

## Tool Usage

This agent has file system, shell, search, and documentation tools. Prefer them over manual inspection:

- **File read/write**: `ReadFile`, `WriteFile`, `StrReplaceFile` — use these for all code changes.
- **Search**: `Grep` and `Glob` — use instead of `Select-String` or manual directory traversal.
- **Shell**: `Shell` — use PowerShell for running tests, launching Godot scenes, or project-wide operations.
- **Godot docs**: `Context7` (`resolve-library-id` + `query-docs`) — use for Godot 4.4 API verification before calling unfamiliar engine methods.
- **Subagents**: `Agent` with `subagent_type="explore"` — use for codebase research when more than 3 search queries are needed.

### Running Tests
- Manual test via Godot CLI:
  ```powershell
  & "C:\Users\danie\OneDrive\Documents\GODOT\Godot_v4.4.1-stable_win64.exe" --path "c:\Users\danie\Documents\YABEGCSE" Tests/SectorDrawTest.tscn
  ```
- **Never** run `taskkill` commands to close Godot. This can corrupt project files.

---

## Response Mode
- Keep sentences short and simple.
- No filler, no hype, no soft asks, no emojis, no conversational transitions, no sign-off appendixes. End when the content ends. If there's nothing left to say, stop.
- Speak to the top of technical ability, not to current energy or phrasing. Do not tone-match. Do not soften. Do not pad for engagement, sentiment, or continuation.
- Ask a question only when ambiguity would degrade the answer. Never ask to fill silence or extend the conversation.
- Default to the highest technical depth the topic supports. Simplify only when asked or when the deliverable has a non-technical audience.
- Thinking partner, not a mirror. Tackle wrong premises first. If something false is stated, correct it with evidence before engaging further. Do not build on a false foundation.
- Catch loaded questions. If a question assumes a false conclusion, name the assumption, reject the frame, then answer the question that should be asked.
- Isolate logical breaks. If logic is valid but the conclusion doesn't follow, name the exact step where reasoning fails. Identify the fallacy, the unsupported leap, or the missing variable.
- Call out pattern-matching. If a conclusion is reached because it fits a narrative rather than the evidence, say so.
- Distinguish opinion from fact. If an opinion is presented as settled, separate what's defensible from what's projection.
- Steelman the other side. When a position is taken, present the strongest opposing argument, not a strawman.
- Track contradictions. If something contradicts an earlier statement in the conversation, point it out.
- Agree when agreement is warranted. Do not manufacture a counterpoint to perform balance.
- No flattery. Never say "That's a great point" or any variant. If it's a great point, build on it. If it isn't, say why.

---

## Project Context

- **Main Scene**: `Scenes/EditorShell.tscn` (single persistent scene, 2D/3D toggle)
- **Project Root = Repo Root**: `c:\Users\danie\Documents\YABEGCSE` (the `project.godot` at repo root IS the editor project; no `editor/` subfolder)
- **Layout**: `Scenes/` (scenes), `Scripts/Editor/` (controller, views, tools, UI), `Scripts/Data/` (LevelData, LevelSerializer), `Scripts/Runtime/` (play-test/walk mode), `ArtLibrary/` (~2,550 PNGs, library-relative references only), `Tests/` (headless harnesses + fixtures)
- **Key Autoloads**: `GameSettings` (preferences, `Scripts/Editor/game_settings.gd`), `AudioManager` (sound, `Scripts/Runtime/audio_manager.gd`). Four slots reserved.
- **Key Controllers**: `EditorController` (root coordinator), `ToolSystem`, `Canvas2DView` (node `Canvas2D`), `Viewport3DView` (node `Viewport3D`)
- **Level Data**: `LevelData` Resource class (`Scripts/Data/level_data.gd`), owned by `EditorController`
- **Serializer**: `LevelSerializer` class (`Scripts/Data/level_serializer.gd`), instantiated by `EditorController`; strings in/out, never touches the filesystem; unknown sections round-trip via `LevelData.unknown_sections`
- **Mesh Builder**: `SectorMeshBuilder` (`Scripts/Runtime/sector_mesh_builder.gd`) — reads `LevelData`, produces floor/ceiling/wall meshes (one MeshInstance per distinct texture name; untextured groups keep the plain FloorMesh/CeilingMesh/WallMesh names) + `CollisionBody` (ConcavePolygonShape3D). Concave loops via `Geometry2D.triangulate_polygon`; inner loops via keyhole bridging (0.05-wide epsilon channel — Godot's ear clipping rejects coincident points, and `clip_polygons` does NOT cut rings, it returns holes as separate negative rings). **GodotPhysics concave trimeshes collide only from the backface side** — collision quads are always emitted double-wound. Sloped faces: per-vertex heights from `GeometryOps.floor_height_at`/`ceiling_height_at` (invalid slopes fall back to flat); walls/risers/lintels are per-endpoint sheared quads. UVs are world units scaled by 1/texture_size at commit (1 texel = 1 world unit); wall `offset_u`/`offset_v` shift UVs in texels. Sectors flagged with structural markers (`unclosed`, `crossing`, `overlap` — see `GeometryOps.STRUCTURAL_FLAG_MARKERS`) are skipped; cosmetic flags (slopes, floor>=ceiling) still build.
- **Art Cache**: `ArtCache` (`Scripts/Runtime/art_cache.gd`) — static; resolves library-relative names against `res://ArtLibrary/`, hands out cached unshaded+nearest materials, magenta-checker placeholder for misses (recorded for the debug panel via `take_missing()`), `scan()` feeds the TexturePicker.
- **3D Editing (M3)**: crosshair-driven against the walk camera (mouse stays captured). `GeometryOps.aim_from_ray` (pure math, no physics — floors/ceilings have no collision) produces the AimInfo; `Viewport3DView` signals `edit_input`/`edit_motion` upward; `EditorController` routes to `ToolSystem.handle_3d_input/handle_3d_motion` → `Edit3DTool`. Wheel = raise/lower face (Shift = opposite face) or wall offset_u/v; LMB drag = corner-drag slope (`floor_slope`/`ceiling_slope`: 3× [point_id, height]); X clears a slope; T opens the TexturePicker. A drag is ONE undo step: snapshot at `begin_corner_drag`, live `update_corner_drag` previews without pushing undo. Look is suppressed during drags via `Viewport3DView.set_look_suppressed` (synchronous signal chain).
- **Walk Mode**: `WalkController` (`Scripts/Runtime/walk_controller.gd`, node `Viewport3D/Player`) — WASD + mouse-look, `move_and_slide` vs the collision body, point-in-sector floor query with smooth step-up; void holds last floor height. Fog: `Viewport3DView._apply_environment` from `level.environment.fog`, F toggles (`toggle_fog` action).
- **Milestones**: M1 done (2D canvas, sector loop drawing, auto-split, portals, inner loops, tolerate+flag, 3-deep undo, save/load), M2 done (mesh generator, walk mode, fog toggle), M3 done (3D editing: heights, corner-drag slopes, texture pick, wall alignment), M4 done (objects: 5 types, 2D+3D placement, 8-way views, fluids), M5 done (GCS importer), M6 (environment), M7 (gameplay).
- **Objects (M4)**: schema in `ObjectOps` (`Scripts/Data/object_ops.gd`, static, pure) — `objects: [{type, pos, z, angle, art, params}]`, art is a library-relative BASE name (no `.png`; fluids append digits, 8-way sprites use `params.views`). `ObjectOps` owns defaults, picking (2D `pick` + 3D `ray_pick`), 8-way view resolution (views 1..8 clockwise from front; mirror partners 2↔8, 3↔7, 4↔6) and `validate` → `LevelData.flagged_objects` (platforms are exempt from the art requirement — imported GCS platforms are artless). Rendering: `Objects3D` (`Scripts/Runtime/objects_3d.gd`, Sprite3D per object, `ALPHA_CUT_DISCARD`, `pixel_size = params.scale` so 1 texel = 1 world unit; objects with `params.size` — M5 imports — stretch per-axis instead). Editing: 2D `ObjectTool` (O key toggles with DrawSectorTool; brush lives in `ToolSystem._brush`, set from the "Object" menu), 3D via `Edit3DTool` (object aim beats geometry when nearer; LMB drag moves, wheel rotates, Ctrl+wheel = z, T re-picks art, X/Delete deletes). Undo snapshots include `objects`. **Gotcha**: Sprite3D's `pixel_size` is world-units-per-texel — set it to the desired scale directly, NOT 0.01.
- **GCS Importer (M5)**: `GCSImporter` (`Scripts/Data/gcs_importer.gd`, static, pure text-in/data-out) converts DOS 1.3 `univ??.txt` + `objdef??.txt` into a v0 level: geometry empty, all content as objects, report in `meta.import_report` (round-trips via the serializer's meta deep-copy). Grammar: univ = `species handle x y z theta attr op1..op4` + `s x y z theta` spawn line (→ `meta.spawn`, preferred by `WalkController.spawn`); objdef = `species handle file hsize vsize` where file may be a DOS path (basename = art, resolved via `ArtCache.find_base`) or an integer alias of another handle's art (the 45°-wall trick). Units cm → units × 5/3; theta is fixed-point (32768 = 180°); wall pos is the segment ANCHOR — centre = anchor + (sin θ, cos θ) × width/2, angle = 90 − θ_deg. Species map: 0/1→wall_object (params.collide unless attr bit 64; collision quads built by `SectorMeshBuilder._build_object_collision`), 2→billboard, 6→fluid, 7→sprite_8way, 11→platform (size from opvals 1/2). Doors/inventory/fluid tables/opvals are NOT reconstructed — preserved in `params.gcs` + report note. UI: File → "Import GCS Level..." (destructive-confirmed, outside undo), `EditorController._expand_includes` inlines objdef `include` files one level deep; debug panel shows the report + has an "Import GCS fixture" button (also F10 = `debug_import_fixture` action). Real fixtures: `Tests/Fixtures/UNIV0.TXT` + `OBJDEF0.TXT`.
- **GDScript/Godot gotchas (M3)**: GDScript has no `Array * int` repetition (`[n] * 3` is a parse error — append in a loop). `Plane` constructors are `(normal, point)` / `(normal, d)` / `(p1, p2, p3)` — there is no `(point, normal)` order. Three slope corners with different heights always define SOME 3D plane; the degenerate case is a *vertical* plane, so collinearity must be checked on the 2D projection (`_corners_form_plane`). `Plane.intersects_ray` returns null for parallel or behind-the-origin rays — no t<0 filtering needed.
- **GDScript/Godot gotchas (M5)**: `var x := array[i]` fails to compile when the Array is untyped ("cannot infer type" — Variant element); annotate explicitly or wrap in `str()`/`int()`. `Node` already has a native `_import_path` member — never declare your own `var _import_path` on a Node-derived class. `ProjectSettings.load_from_file()` does not exist; to register an InputMap action for the MCP `simulate_input` validator, use `ProjectSettings.set_setting("input/<action>", {...})` + `ProjectSettings.save()`.
- **Geometry Layer**: `GeometryOps` (`Scripts/Data/geometry_ops.gd`) — static, pure functions over LevelData; all mutation/validation lives here. Schema v0 documented in `level_data.gd`.
- **Tools**: `DrawSectorTool` (`Scripts/Editor/tools/draw_sector_tool.gd`) — RefCounted, active by default; commit_loop / request_delete go through `ToolSystem` (one loop = one undo step).
- **Tests**: eight headless suites — `Tests/SerializerRoundTripTest.gd`, `Tests/GeometryOpsTest.gd`, `Tests/EditorShellTest.gd` (integration: drives EditorShell with synthetic input events), `Tests/MeshBuilderTest.gd`, `Tests/WalkTest.gd` (physics frames), `Tests/Edit3DTest.gd` (M3: slopes, aim raycast, 3D commits, textures), `Tests/ObjectTest.gd` (M4: object commits, views, picking, renderer smoke), `Tests/GCSImportTest.gd` (M5: real DOS 1.3 fixture pair import, mapping, round-trip, collision). Run each with `--headless -s`; redirect stdout to a file (`> Tests/x.log`), never a pipe to `head` (deadlocks Godot's stdout). **Run a filesystem rescan in the editor after adding new `class_name` scripts** or headless runs fail with "not declared in the current scope" (stale `global_script_class_cache.cfg`). The `GDAIMCPRuntime` autoload starts a server on port 3572 in EVERY run including headless tests — a zombie test process holding 3572 takes the editor's MCP server down.
- **Debug Panel**: Press `F12` in editor (`Scripts/Editor/debug_panel.gd`). All new features need debug commands there.

---

## Panel Construction Standards

All new full-screen popup/panel overlays must follow the pattern established by the editor's modal system:

### Root Node
- Use `extends Control` (not `CanvasLayer`).
- Set `mouse_filter = MOUSE_FILTER_STOP` to block input behind the panel.
- Set a high `z_index` (e.g., 100) to render above gameplay.

### Overlay
- Create a `ColorRect` child named `Overlay`.
- Use `PRESET_FULL_RECT` (with `keep_offsets=true`, see gotcha below) and `mouse_filter = MOUSE_FILTER_STOP`.
- Typical color: `Color(0, 0, 0, 0.6)`.

### Panel Container
- Create a `PanelContainer` child named `Panel`.
- Center with `set_anchors_preset(Control.PRESET_CENTER, true)`.
- Set `custom_minimum_size` explicitly (e.g., `Vector2(460, 340)`).
- Position with offsets: `offset_left = -230`, `offset_top = -170`, `offset_right = 230`, `offset_bottom = 170`.
- **Gotcha**: always pass `keep_offsets=true` to `set_anchors_preset`. The default (`false`) rewrites the offsets to preserve the control's *current* rect — for a freshly created 0×0 control that means offsets like `-640`/`-400` and a permanently collapsed panel. (Verified on 4.4.1, Session 0.)

### Theme & Styling
- Apply a custom `StyleBoxFlat` override on the `"panel"` style for background and border:
  ```gdscript
  var style = StyleBoxFlat.new()
  style.bg_color = Color(0.12, 0.10, 0.14, 0.98)
  style.border_color = Color(0.3, 0.25, 0.35, 1.0)
  style.set_border_width_all(4)
  style.set_corner_radius_all(20)
  style.corner_detail = 8
  _panel.add_theme_stylebox_override("panel", style)
  ```

### Animation
- **Never** apply scale tweens directly to a `PanelContainer` — scale distortion will stretch child content.
- Animate `position` and `modulate:a` on the `PanelContainer` instead:
  ```gdscript
  _panel.position = _original_pos - Vector2(0, 300)
  _panel.modulate.a = 0.0
  var tween = create_tween()
  tween.tween_property(_panel, "position", _original_pos, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
  tween.parallel().tween_property(_panel, "modulate:a", 1.0, 0.4)
  ```
- For exit, tween `position` downward and fade out both overlay and panel.

### Buttons
- Connect hover, unhover, and press tweens to all interactive buttons via a shared tween helper.

### Dynamic Building
- Build UI dynamically in `_build_ui()` or similar.
- Call `queue_free()` on existing children before rebuilding to support re-showing.
- One panel scene per distinct domain. Reuse instances. Do not copy-paste panel logic.
