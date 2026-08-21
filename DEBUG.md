Read: YABEGCSE Project Charter.md, YABEGCSE Level Format v0 Envelope.md, YABEGCSE Milestones and CLI Prompts.md, and the current yabegcse-godot SKILL.md.

This is a post-Session 7 bug-fix pass. Three issues. Fix all three. Do not add features. Do not refactor unrelated systems.

---

## Issue 1: Slopes do not work

**Symptom:** Corner-drag slopes in 3D mode do not produce visible sloped ceilings or floors. Either the interaction is not triggering, or the mesh generator is not producing sloped geometry.

**Acceptance:**
- Verify that 3D-mode corner-drag on a sector sets the three corner heights correctly in LevelData.
- Verify that SectorMeshBuilder reads those three heights and produces a sloped plane (not flat).
- The slope must render correctly in the 3D viewport: one corner high, opposite low, plane tilted.
- If the interaction requires a specific modifier key or drag pattern, document it in a one-line tooltip or status-bar message.
- Tolerate + flag: if a sector has invalid slope data (e.g. three collinear points), paint it red in 2D and log to the debug panel. Do not crash.

---

## Issue 2: Imported GCS objects do not appear on the 2D map

**Symptom:** GCS levels import (M5 converter). Objects are visible in 3D view. They do not render on the 2D canvas.

**Acceptance:**
- The 2D canvas must draw all object types (billboard, wall_object, sprite_8way, fluid, platform) as icons or bounding boxes at their X/Y position.
- Objects must use the same position data that the 3D view uses. If the 3D view sees them, the 2D view must too.
- Verify the converter writes object positions into LevelData in the same coordinate space as the 2D canvas. Fix any mismatch.
- Size tweaking: imported wall-objects should render at their original GCS world size (1 unit = 6 mm), not at arbitrary scale. Verify the converter applies the correct scale factor from GCS cm to YABEGCSE units.
- Objects that clip outside the ±10200 GCS world limit should still render on the 2D map (flagged, not hidden).

---

## Issue 3: Gameplay panel overflows viewport and cannot be closed

**Symptom:** The gameplay/trigger panel (reserved schema UI) is larger than the 640×400 internal viewport. It extends beyond screen edges. No close button is reachable.

**Acceptance:**
- Clamp the panel's `custom_minimum_size` and actual size to fit within the viewport with 20 px margin on all sides. Never exceed viewport bounds.
- Make the panel content scrollable: wrap the inner content in a ScrollContainer. The panel frame stays fixed; the content scrolls.
- Add an `Escape` key handler to close the panel and return focus to the editor. This must work even if the close button is off-screen.
- Add a visible close button (X) in the panel header, top-right, always within the clamped bounds.
- Panel z_index must stay above gameplay but below modal dialogs.
- Follow the Panel Construction Standards in the SKILL.md: animate position and modulate, never scale the PanelContainer directly.

---

## Standing rules

- Godot 4.4.1, GDScript only. No plugins.
- Signal up, call down. No cross-branch get_node().
- Maximum 6 autoloads. Do not add new ones.
- All changes must preserve existing save/load round-trips. Unknown JSON sections survive untouched.
- Validity = tolerate + flag. The editor never crashes on bad data.
- Document any new public methods with Godot doc comments `##`.
- Keep dev TODOs as `# TODO:` lines.