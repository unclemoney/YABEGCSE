# YABEGCSE — Milestone Plan + CLI Session Prompts

Draft 1 — locked milestone order with acceptance criteria, plus the literal
prompt text for plan-mode CLI sessions. Governing documents: *YABEGCSE
Project Charter*, *YABEGCSE Level Format v0 Envelope*.

---

## 0. Pre-handoff checklist (this project's side)

- [ ] Final vga2png rerun with alpha keying at the defined transparent color
      (the last art tool this project builds).
- [ ] Assemble the art library folder (~2,700 PNGs, Mega Pack + DOS 1.3
      stock), palette identity file included.
- [ ] Render the original MIDIs to WAV.
- [ ] Demote *3DGCS Project Knowledge* to appendix status (converter
      reference); supersede its charter with the YABEGCSE charter.
- [ ] Project lead signs all three session documents.

## 1. Milestones

### M1 — 2D canvas + sector drawing + save/load
Build-style loop drawing on a top-down grid canvas.
**Acceptance:**
- Draw closed sector loops; drawing a line across an existing wall
  auto-splits it with a new vertex.
- Zoom-dependent grid snapping; base scale 1 unit = 6 mm.
- Invalid sectors paint red and appear in a debug panel (tolerate + flag).
- JSON save/load round-trips losslessly; unknown sections ignored on load.
- Undo 3-deep; destructive ops confirm-dialoged.

### M2 — Sector→mesh generator + 3D walk mode
**This is the walking demo** — it lives inside the editor.
**Acceptance:**
- Instant, zero-lag toggle 2D ↔ 3D.
- Concave and inner-loop sectors triangulate correctly (no crash, ever;
  failures degrade to red flags).
- Walk a drawn level: collision against walls, floor-height steps,
  WASD + mouse-look.
- 640×400 nearest-neighbor viewport; fog toggle live.

### M3 — 3D-mode editing
**Acceptance:**
- Raise/lower sector floors and ceilings in 3D view.
- Corner-drag slopes (three corner heights define the plane).
- Texture pick from art library; wall texture alignment.

### M4 — Objects
**Acceptance:**
- Place/move/rotate billboards, wall-objects, 8-view sprites, fluids,
  platforms, in both 2D and 3D modes.
- Objects clip geometry freely; alpha-keyed transparency renders.
- Sprites render correct view for player angle (8-way logic).

### M5 — GCS converter (importer v1)
**Acceptance:**
- Load a DOS 1.3 `univ??.txt` + `objdef??.txt`; level appears as
  object-walls in the void, walkable in play-test.
- Import is destructive-confirmed; produces a debug list of skipped or
  unreconstructable elements.
- Round-trip: imported level saves as valid v0 JSON.

### M6 — Environment + feel
**Acceptance:**
- Fog (color/near/far), sky modes (flat / horizon strip), ambient — all
  editor-settable per level and stored in `environment`.
- Minimalist player-preference movement knobs; reference poles measured
  from DOSBox GCS captures and Build's published constants.

### M7 — Triggers / gameplay
Activates the reserved `gameplay` schema. Designed when M1–M6 are proven,
"in the spirit of" fluid commands / registers / theaters — never a Forth
interpreter.

## 2. CLI session prompts (plan mode)

### Session 0 — scaffolding
```
Read: YABEGCSE Project Charter.md, YABEGCSE Level Format v0 Envelope.md,
YABEGCSE Milestones and CLI Prompts.md. This is Milestone M1 prep.
Scaffold the standalone Godot 4.4.1 GDScript project: app shell, 2D/3D
mode toggle skeleton (same scene, shared state, zero reload), project
layout for editor/runtime/art-library, and the JSON level file
load/save/ignore-unknown harness per the format envelope. No drawing
tools yet. Plan mode: produce the implementation plan only.
```

### Session 1 — M1: 2D sector editor
```
Read the three YABEGCSE documents. Implement M1 per its acceptance
criteria: top-down grid canvas with zoom-dependent snapping
(1 unit = 6 mm), Build-style sector loop drawing with auto-split on
wall crossing, portal wall creation between adjacent sectors, inner
loops, tolerate+flag validity (red paint + debug panel), 3-deep undo,
confirmed destructive ops, JSON save/load round-trip. Plan mode:
produce the implementation plan only.
```

### Session 2 — M2: mesh generator + walk mode
```
Read the three YABEGCSE documents. Implement M2: sector→mesh generation
(concave + inner-loop triangulation, graceful degradation on invalid
data), instant 2D↔3D toggle, kinematic walk controller with wall
collision and floor-height steps, WASD + mouse-look, 640×400
nearest-neighbor viewport, fog toggle. Plan mode: produce the plan only.
```

### Sessions 3–7
Prompt to be written at the end of the prior milestone's session, using
that milestone's acceptance criteria verbatim, in the same shape as
Sessions 1–2. Do not pre-plan later milestones in detail — the format
envelope and charter constrain them enough.

## 3. Standing instructions for every CLI session

- Godot 4.4.1, GDScript only. No plugins, no native code.
- Charter non-goals are binding: no room-over-room, no software renderer,
  no firstwall slope UX, no Build/Duke code transliteration.
- The level format is editor-owned; unknown JSON sections must survive
  load/save round-trips.
- Validity = tolerate + flag. The editor never crashes on bad geometry.
