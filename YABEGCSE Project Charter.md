# YABEGCSE — Project Charter

**YABEGCSE** — *Yet Another Build Engine / Game Creation Studio Editor*

Version: draft 1 — pre-handoff, awaiting project lead sign-off
Status: design locked after three grilling rounds; no code exists yet

---

## 1. Identity

YABEGCSE is a GCS-content-compatible retro FPS **editor and engine**, built in
Godot 4.4.1, GDScript only, as a standalone desktop application.

The editor is the product. The runtime is its play-test mode.

Lineage:

- **From GCS (Pie in the Sky, 3D Game Creation System, DOS 1.3):** the object
  taxonomy, the original art and palette, the level content (via converter),
  the fog-and-void aesthetic, the data-driven "game creation system"
  philosophy.
- **From Build (Ken Silverman):** the sector data model, the 2D top-down
  editing paradigm, the instant in-game 3D editing, the grid discipline.
- **From Godot:** all rendering, all platform plumbing, export/sharing.

This is **not a port and not a faithful recreation.** It is a new tool that
can read the old worlds.

## 2. Goals

1. A joyful, standalone, 2D-first level editor with zero-lag 3D play-test.
2. Sector-based levels with per-sector floor/ceiling heights and slopes,
   rendered by Godot's 3D pipeline at a deliberate retro presentation.
3. GCS content compatibility: original art ships with the editor; original
   levels import as editable content.
4. Shareable level files and exportable packaged executables.

## 3. Non-goals

- No software renderer, no raycaster, no portal renderer of our own.
- No faithful recreation of Power 3D behavior, palette engine, or quirks.
- No PYGMY Forth interpreter. AI/gameplay redesigned "in the spirit of."
- No `.ENG`/`.BIN` binary compilation path.
- **No room-over-room. Ever. By design.**
- No transliterated Build/Duke code (see §7).

## 4. Design constitution (locked decisions)

### Data model
- Sectors are closed wall loops. Per-sector floor/ceiling height, texture,
  and slope plane. Two-sided portal walls join adjacent sectors. Inner loops
  (sector within sector) are allowed.
- An object layer sits on top of sectors: billboards, non-billboard
  wall-objects, 8-view sprites, animated fluids, trigger platforms.
  **Objects may clip anything.**
- Unenclosed space is "the void": rendered as fog, objects allowed. Imported
  GCS levels live here as object-walls.
- Grid-snapped editing, zoom-dependent grid sizes. 1 unit = 6 mm.

### Editor
- 2D top-down canvas; Build-style loop drawing; drawing a line across an
  existing wall auto-splits it with a new vertex.
- Instant, zero-lag toggle between 2D and 3D modes.
- 3D mode edits: sector floor/ceiling heights, corner-drag slopes, texture
  pick/align, object placement. Build's firstwall slope UX is rejected.
- Validity: **tolerate + flag.** Invalid sectors paint red in 2D, appear in
  a debug panel, play-test degrades gracefully. Nothing crashes.
- Undo 3-deep. Imports and batch deletes are confirmed destructive
  operations outside the undo stack.

### Format
- One JSON file per level, versioned, editor-owned (users never hand-edit).
- Envelope defined in *YABEGCSE Level Format v0 Envelope*.

### Art & audio
- The art library ships with the editor/runtime: the ~2,700 PNGs converted
  from the GCS Mega Pack and DOS 1.3 assets.
- One defined transparent color; a final vga2png alpha-keying rerun is a
  pre-handoff task (the last art tool this project builds).
- $RP9A palette remains the canonical palette identity for new art.
- Music: original MIDIs rendered to WAV, dropped in.

### Presentation & feel
- 640×400 internal viewport, nearest-neighbor upscale.
- Distance fog: toggleable, "in the spirit of" the GCS `.tbl` fade tables.
- WASD + mouse-look. Movement feel is a minimalist player preference
  (a small set of knobs), tuned between two measured reference poles:
  DOSBox captures of GCS 1.3 and the Build engine's published constants.

### Sharing
- Levels are shareable files.
- Finished games export as packaged executables via Godot export templates.

### Converter
- In-editor GDScript importer (offline, one-way).
- v1: `univ??.txt` / `objdef??.txt` → object-walls in the void.
- v2: sector reconstruction with a debug list for unreconstructable elements.

## 5. Milestones (locked order)

1. 2D canvas + sector drawing + save/load.
2. Sector→mesh generator + 3D walk mode (this *is* the walking demo).
3. 3D-mode editing (heights, corner-drag slopes, textures).
4. Objects / billboards.
5. Converter importer.
6. Environment, fog, feel tuning.
7. Triggers / gameplay (activates the reserved schema).

Full acceptance criteria and CLI session prompts: *YABEGCSE Milestones and
CLI Prompts*.

## 6. Risk register

| Risk | Mitigation |
|---|---|
| Editor scope creep (the #1 risk) | Locked milestone order; each milestone has checkable acceptance criteria; nothing enters the plan without a milestone slot |
| Concave/looped sector triangulation in GDScript | Ear-clipping via Godot `Geometry2D.triangulate_polygon`; red-flag invalid sectors instead of crashing |
| Floor-height + step movement on slopes/stairs | Standard kinematic controller with point-in-sector floor query and step height; tune against DOSBox captures |
| Converter sector reconstruction is genuinely hard | v1 imports objects only (immediately useful); v2 deferred until editor is proven |
| Editor UX complexity ("Blender disease") | 2D-first paradigm, refusal to expose 3D modeling concepts, minimalist preference surface |

## 7. License & rights stance

- **GCS media:** Kevin Stokes gave explicit permission (Feb 2021, to
  Graham L. Wilson) to reuse Pie in the Sky media. Covers art assets.
- **Build / Duke3D source:** architectural reference **only**. The Build
  engine is under Ken Silverman's BUILDLIC (not a conventional open-source
  license); Duke3D game source is GPL. We read, we learn, we do not copy or
  transliterate code. All implementation is original GDScript.
- **GCS file-format research** (the prior project's knowledge base:
  `.VGA`/`.VGR`, palette facts, `univ`/`objdef` semantics) is ours and
  carries forward as the converter's specification appendix.

## 8. Process

- All plans, harnesses, documents, and project code live in the CLI project.
- The three session documents (this charter, the format envelope, the
  milestone plan + prompts) are signed by the project lead before any
  plan-mode handoff.
- The legacy *3DGCS Project Knowledge* document is demoted to appendix
  status: its format research feeds the converter; its "faithful recreation"
  charter is superseded by this document.
