# YABEGCSE — Editor Controls

Every key binding and mouse action. Keep this file current: update it
whenever a control is added or changed. The in-editor help panel (F1 or
the "?" button, top-right) displays this file verbatim.

## Global

| Key | Action | Mode | Notes |
|---|---|---|---|
| ` (backquote) | Toggle 2D / 3D mode | Both | `toggle_mode` action |
| Ctrl+Z | Undo | Both | 3-deep undo stack |
| F1 | Open/close this help panel | Both | Also the "?" button, top-right |
| F12 | Toggle debug panel | Both | |
| Escape | Cancel in-progress loop / close panel | Both | |

## 2D canvas

| Key | Action | Mode | Notes |
|---|---|---|---|
| Middle mouse drag | Pan | 2D | |
| Mouse wheel | Zoom at cursor | 2D | Zoom-dependent grid snapping |
| WASD | Move player marker | 2D | Synced to the 3D spawn position |
| Tab / Shift+Tab | Cycle tool mode forward/back | 2D | Sector Draw → Vertex Edit → Wall Select → Platform Draw → Platform Edit |
| O | Toggle Object Place mode | 2D | Overlays the current cycle slot |

### Sector Draw

| Key | Action | Mode | Notes |
|---|---|---|---|
| LMB | Add loop vertex | Sector Draw | Grid-snapped; crossing a wall auto-splits it |
| LMB on first vertex / Enter | Close loop | Sector Draw | Inner loops become sector-within-sector |
| Escape | Cancel the in-progress loop | Sector Draw | |
| Delete | Delete hovered sector | Sector Draw | Undoable |

### Vertex Edit

| Key | Action | Mode | Notes |
|---|---|---|---|
| LMB drag | Move vertex | Vertex Edit | Grid-snapped; wall-crossing moves snap back + flash red |

### Wall Select

| Key | Action | Mode | Notes |
|---|---|---|---|
| LMB | Select portal wall | Wall Select | Boundary walls cannot be selected |
| Delete | Merge sectors across selected portal | Wall Select | Undoable; larger sector keeps heights/textures |

### Platform Draw

| Key | Action | Mode | Notes |
|---|---|---|---|
| LMB | Add platform vertex | Platform Draw | Same loop interaction as Sector Draw |
| LMB on first vertex / Enter | Close platform | Platform Draw | Height = sector floor at centroid, thickness 16 |
| Escape | Cancel the in-progress loop | Platform Draw | |

### Platform Edit

| Key | Action | Mode | Notes |
|---|---|---|---|
| LMB | Select platform (click empty space to deselect) | Platform Edit | Smallest platform under the cursor |
| Delete | Delete selected platform | Platform Edit | Undoable |
| V | Toggle selected platform visible/invisible | Platform Edit | Hidden platforms skip 3D meshes, draw dashed in 2D |
| T | Texture picker for the selected platform | Platform Edit | Undoable |

## 3D view (walk mode)

| Key | Action | Mode | Notes |
|---|---|---|---|
| WASD | Move | 3D | Kinematic walk, wall collision, step-up |
| Mouse | Look | 3D | Captured mouse; suppressed during drags |
| F | Toggle fog | 3D | GameSettings preference |
| Mouse wheel | Raise/lower aimed floor or ceiling | 3D | Shift+wheel edits the opposite face |
| Shift+wheel | Wall texture offset (when aiming a wall) | 3D | offset_u; Ctrl not used here |
| LMB drag | Corner-drag slope on aimed face | 3D | First motion seeds a 3-corner plane |
| LMB click | Select platform (when aiming one) | 3D | Shared Platform Edit selection |
| LMB drag | Move aimed object | 3D | Objects beat geometry when nearer |
| Mouse wheel | Rotate aimed object | 3D | Ctrl+wheel nudges object z |
| T | Texture picker for the aimed face/wall/object/platform | 3D | |
| X | Clear slope on aimed face / delete aimed object | 3D | |
| Delete | Delete aimed object or platform | 3D | |
| V | Toggle aimed platform visibility | 3D | |
| Shift+H | Match aimed inner sector's ceiling to surrounding sector | 3D | Clears the ceiling slope; pillar UX |
| Shift+L | Match aimed inner sector's floor to surrounding sector | 3D | Clears the floor slope |

## UI panels

| Key | Action | Mode | Notes |
|---|---|---|---|
| File menu | New / Open / Save As / Import GCS Level | Both | Import is destructive-confirmed |
| Edit menu | Clear Level / Environment / Preferences / Gameplay | Both | Clear is destructive-confirmed |
| Object menu | Brush type + brush art | Both | Arms Object Place mode |
| T (via picker) | Apply picked texture | Both | Face/wall/object/platform under aim or selection |
| Escape | Close any modal panel | Both | Picker, environment, preferences, gameplay, help |

## Debug panel (F12)

| Key | Action | Mode | Notes |
|---|---|---|---|
| F9 | Load two-room fixture | Both | `debug_load_fixture` |
| F10 | Import GCS fixture pair | Both | `debug_import_fixture` |
| F11 | Cycle sky mode (flat / horizon strip) | Both | `debug_cycle_sky` |
| F13 | Load gameplay fixture | Both | `debug_gameplay_fixture` |
