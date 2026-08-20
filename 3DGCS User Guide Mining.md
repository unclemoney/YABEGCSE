# 3D GCS DOS User's Guide — Mining Report

Distilled from `Pie in the Sky Software - 3D Game Creation System for DOS - User's Guide.pdf`
(52-page retail manual scan, OCR text layer; a few two-column pages re-OCR'd manually).
Everything below is **new information** or **confirmation/correction** relative to the
existing Project Knowledge Base + ENGINE.TXT / LEVELS.TXT / FILEFMTS.TXT / BARFWRLD.C.
Page numbers refer to the printed manual.

---

## 1. What this manual is (version/dating clues)

- Retail **3D Game Creation System for DOS**, ~1995. Credits: GCS programming John Nagle
  & Kevin Stokes; 3D engine Kevin Stokes & **Mat McKenzie**; GCSPAINT by **David Johndrow**;
  art Colin Stokes & Terri Hamel; music John Davis. Built partly on **Fastgraph** (Ted Gruber
  Software) — explains the `fg_vport` / `fgfonts.h` / `palmatch` stuff in BARFWRLD.C.
- Written **before** GCS Professional: repeatedly teases "the upcoming GCS Professional
  Version" (handles 4–8 MB RAM for artwork, lifting the one-enemy-type-per-level limit).
- **GCSMENU** companion product ($34.95, in development at print time): menu/save-load
  system, .FLI animations, multiple game endings driven by a universe register (OCR reads
  "register 129" — probably 127; treat as uncertain).
- Default install: `c:\P3DGCS` (matches the hardcoded path in BARFWRLD.C).

## 2. Retail directory layout (confirmed)

```
c:\P3DGCS\                  main dir: GCS.EXE (editor), GCSPAINT.EXE, HELP_MEM.EXE, BOOTDISK.EXE
c:\P3DGCS\ENGINE\           ENGINE.EXE (a.k.a. P.EXE), PSTR.EXE, weapons support files
c:\P3DGCS\ENGINE\<PROJ>\    project directories (one per game)
c:\P3DGCS\<PALETTE>\        master palette dir, e.g. $RP9A\
    $RP9A\BASICLIB\         object library (demo walls); .mid music files live in library dirs
    $RP9A\DEF_ENEM\         default enemy artwork set
    $RP9A\STNDWEAP\ / DWEAPON\   weapon+inventory sets (art, fld*.txt, weapons.txt,
                                 weapdef.txt, pickups.txt)
```

- **$rp9a.pal is officially "the general purpose palette"** — direct confirmation that our
  recovered $RP9A.PAL is the standard GCS palette (validates the Mega Pack pipeline).
- Palette is chosen once at project creation and **can never be changed**; libraries can be
  switched freely. Custom palette = save .pal in GCSPAINT + mkdir of same name + a tiny
  description file (two 11-char lines).
- Custom enemy/weapon dirs are created from the editor's FILE menu ("Create Directory" →
  copies defaults and **palette-matches** them to the project palette).

## 3. Editor facts that matter for .WLD parsing

- **700 objects per level max** ("W" meter; BARFWRLD's `world_objects[701]` matches).
  **600 library types** (`pie_objects[600]`). **32 enemies max per level**, and only
  **one enemy species per level** (RAM; all 8-view frames of one guard set loaded).
- "M" meter = artwork RAM, ~300 KB available for wall/sprite bitmaps in the engine
  (≈75 unique 64×64 walls; realistically 10–20 with enemies/weapons/inventory loaded).
  Placing more instances of an already-loaded object costs zero RAM.
- Editor places walls as anchored segments; rotate tool works in **90° increments**;
  **diagonal (45°) walls exist** and "are longer than the right angle sections" when
  measured on screen — i.e. diagonals span a grid cell corner-to-corner.
- **Invert (Ctrl-I)** flips a wall 180° (front/back swap) — relevant to the
  bitdontdrawbacks semantics.
- Grid snap: 50/100/200/400 typical; default gsnapres=400 in BARFWRLD. Object snap
  snaps to existing walls. The white boundary rectangle on screen = the ±10200 world limit
  (CE 146 when violated).
- Platforms must protrude **≥150 cm** from a stair wall to trigger reliably.
- "Set player position" (LEVEL menu) is **test-only** and ignored by Make Final; the real
  start point is set in the Warp-To Point Manager ("Set Final Game Start Point", yellow
  dot vs red dots for normal warp-tos).

## 4. Editor attribute names → engine attribute bits

| Editor checkbox (Edit Attributes) | ENGINE.TXT bit | Value |
|---|---|---|
| Don't Draw Backsides | bitdontdrawbacks | 2 |
| — on a species-2 object this SAME bit makes it an **inventory item** | bitinventory | 2 |
| Don't Fade With Distance | bitdontfade | 4 |
| Set Wall Lighting By Angle (auto N/S vs E/W shading) | *(engine feature, per-object flag)* | — |
| Don't Draw If Far Away | bitdontdrawfar | 32 |
| Can't Bump Into Object | bitdontbump | 64 |
| Object Won't Show Up On Radar | bitnoradar | 256 |
| Set FTC On Solid Walls (Floor-To-Ceiling blocker) | bitftcblocker | 16 |

- "Edit Attributes" red boxes map to univ.txt columns 8–11 (opval1–4 in .WLD):
  **box 1** = pickup/inventory type number (on species 2 with bit 2); **box 2** = item value;
  **box 3** = lighting command byte (see §10); **box 4** = guard difficulty byte (high 8 bits,
  per ENGINE.TXT). Confirms opval semantics for the .WLD world_def records.
- Wall lighting by angle is applied per-wall and must be OFF for the lighting command byte
  to take effect.

### Doors (bitdoor 4096) — parameters revealed
- Resistance: 0 = bump opens; 1 = shooting/kicking; <8 = weakened by bump+fire; **31 =
  jump-kick only** (impossible where textured ceilings disable jumping); **>31 = player-proof**.
- Doors stay open until the player is **>800 cm** away; won't close on the player.
- Key value selects key by color; missing key shows the needed key's icon on the HUD.
- "Open upon Explosion" flag exists (grenades).
- **Sliding doors only** (N/E/S/W slide, independent of wall orientation — even diagonal
  sliders). Rotating/vertical doors must be built as animated objects.
- Doors wider than **600 cm may fail; ≥1200 cm always fail**. Door panels don't clip at
  frames — level design must hide the open panel (offset 200 cm into a door pocket).
- Door frames need bitdontbump + bitnoradar so players/enemies pass and enemies shoot
  through (matches ENGINE.TXT's grenade line-of-sight note).

## 5. Universe registers — refined picture

- 256 registers, values 0–255, persist across levels and save games (state.bin).
- **Don't use register 0** (some commands fail on it).
- **122–126 are read-only live stats** (writes ignored; reset during play):
  | reg | content |
  |---|---|
  | 122 | animation frames per second |
  | 123 | player health, **100 = perfect** |
  | 124 | hits scored on enemies/objects |
  | 125 | ammo rounds fired |
  | 126 | enemies killed |
- **127 = game-over register**: nonzero ends the game. <128 → player died (red fade);
  >128 → game ends and the value is handed to the menu program (multiple endings).
- **128–168 reserved** (enemy counts, per-level lighting status). NOTE: ENGINE.TXT says
  "128–255 reserved" — the guide's 128–168 is the more precise retail-era statement.
- Platform register-set (attr 64) and inventory runcode 8 both write registers; fluid
  commands 17/81/82/33 test & set them (already known).

## 6. Animated objects (fluids) — the editor's view

- **Up to 40 frames** per animation in the editor (cf. BARFWRLD `fld[40]`; ENGINE.TXT's
  `maxnfluid 32` is the older number — retail raised it; record both).
- **Delay must be ≤109** per frame (engine doc says the waitcount byte is 0–255 in 0.08 s
  units; editor caps at 109 — longer pauses = repeat frames).
- Delay 0 = CPU-speed-dependent (bad); 1 = fast; 2 = normal; 30–50 = multi-second.
- Saving an animation writes a **.FLD file** into the library directory — a new file format
  to watch for in asset dirs (text, presumably the fluid table).
- Editor command-menu names ↔ fluid command numbers (from ENGINE.TXT):
  Unconditional Branch=1, Branch if Shot=2, Xform=4, Invisible Blast=8, Remove=16,
  Add to Register=17, Branch if Player Close=18 (fixed ~600 cm), Warp to New Level=21,
  Damage Player=22, Play Sound=23, Palette Pulse=32, Skip if Reg≠Val=33, Branch if No
  Guards=69, Skip if Player Close=71 (configurable distance), Set Invincibility=80,
  Assign Register=81, Skip if Reg=Val=82, Display Text=83, Floor Texture=84,
  Modify Lighting Register=85, Change Universe Attribute=86.
- Invisible Blast: hurts player by proximity, **~700 cm radius**, also kills guards.
- Reference-point system: frame 0 position = default anchor; placements stamp the object
  at the clicked point. Moving animations must be re-authored from frame 0 if edited.
- "Branch if No Guards" counts **only** icon-placed enemies, not fluid-actor "fake" enemies.

## 7. Sound & music specs

`sounds.txt` (project dir), 3 columns per active line (`;` = comment):
```
<number>  <priority>  <filename.wav>
```
- WAV **must be 8-bit mono, 17,100 Hz** (guide misprints "17,100 kHz"), **< 65,535 bytes**
  (~3.5 s). Up to **4 simultaneous** effects; priority 0 = highest (5 is safe; 0 can
  supersede the player's own weapon sound).
- Keep custom sound numbers **>31** — low numbers reserved. Enemy alert barks ("HEY!")
  are **sounds 20–23**, chosen random/round-robin.
- MIDI music: files go in the **library directory**, picked per-level with the musical-note
  icon; **< 32,767 bytes** (guide claims oversized MIDI → CE 95). **All levels must have
  music if any does.** Can't have music without SFX: `s1 t` = both, `s1` = SFX only.
- Sounds attenuate with distance from the fluid object that plays them.

## 8. Weapons & inventory internals (biggest single payload)

### Weapon sets
- A weapon set dir = weapon .vgr frames + **`fld????.txt`** animation files +
  **`weapons.txt`** (range/power/accuracy/display name) + **`weapdef.txt`** +
  **`pickups.txt`** (+ `objweap.txt` for 3D sizes, per guide; ENGINE.TXT calls the fluid
  weapon files FLDSHTGN/FLUIDKCK/FLUIDGRN/FLUIDMG/FLDFEXT/FLDROCK).
- Weapon bitmaps live in **EMS/XMS** (the 'w' objdef flag) — **each .vgr ≤ 16,000 bytes**.
- **Every level in a project must use the same weapons directory** (inventory carries
  across levels) — mixing dirs = critical errors in the final game only, not in test mode.
- `*fat.vga` files = control-panel weapon labels (flat .vga, edit via DOS GCSPAINT).

### The pickup table system (two files, weapons dir)
`weapdef.txt` — object definitions, same grammar as objdef lines:
```
2 <handle> <file.vga> <hsize> <vsize>   ; species-2 always
```
`pickups.txt` — the inventory type table:
```
p <TYPE> <3D-handle> <ICON-handle> <RUNCODE>  ; comment
p 26 2130 2120 7     ; goo gun: drop-object 2130, icon 2120, weapon runcode
```
Rules: handles **≥2000**, unique across weapdef.txt **and gardef.txt** (enemy dir) —
collision = CE 87. Icon art **must be 16×16 px** or CE 167/168. Inventory TYPE numbers
<64, unique.

### Runcodes 0–15 (the full list, straight from the manual)
| # | name | behavior |
|---|---|---|
| 0 | nofunct | plain pickup/drop (keys) |
| 1 | bombinvfunct | explodes on 'b' key |
| 2 | mineinvfunct | explodes when a guard comes close |
| 3 | textinvfunct | displays pstr message # = value |
| 4 | bmapinvfunct | shows a .VGA full-screen; pstr string holds the filename. If value >255, top byte = univ register whose value is appended to the string |
| 5 | ammoinvfunct | ammo; auto-loads matching weapon else stays in inventory |
| 6 | foldinvfunct | heals; value 319 = max |
| 7 | weapinvfunct | weapon; value = ammo amount |
| 8 | reginvfunct | `ureg[value>>8] += value&0xff` on pickup; **decremented again on drop** |
| 9 | bigbombinvfunct | no longer used |
| 10, 11 | basinvfunct | no special function |
| 12 | radarinvfunct | enables radar |
| 13 | gasmaskinvfunct | gas immunity |
| 14 | jetpackinvfunct | "does nothing" but modifies a univ register on pickup |
| 15 | armorinvfunct | cuts hits by ~3× (see formula below) |

### Default inventory type numbers
hand grenade **1**, key **2**, machine gun **15**, shotgun **16**, rocket launcher **25**,
goo gun **26**, gas grenades **28**; memo 12, gold key 13, purple key 14, explosion 10,
"kick me down" 11 (from the sample pickups.txt).

### Item value encodings (editor red box 2)
- Health pack: heal amount, default 80; **perfect health = 320** (contrast: register 123
  reports 100 = perfect — different scales, note for the port).
- Armor: `new_damage = old_damage / (1 + armor_value)`.
- Generic ammo: **value = weapon_inventory_number × 256 + rounds** (e.g. 15×256+41 =
  3881 = 41 MG rounds). Grenades/rockets work the same way.
- Memo: value = pstr message number.
- Custom inventory item recipe: define object + 16×16 icon in weapdef.txt, add pickups.txt
  line, re-define the 3D object in a normal object library (same handle), place it, set
  "Don't Draw Backs" + type number in red box 1, value in red box 2.

## 9. Artwork & memory limits (engine-level, confirmed + new)

- Max image dimension **256** (hard), practical max **200×200** (GCSPAINT's ceiling);
  typical wall art **64×64**, tall walls 64×104, upscaled walls 96×96, max ever used 128×128.
- Wall world sizes: keep between **50–600 cm wide**; very short wide walls (800×50) can
  break the renderer ("numerical overflow" if stretch ratios get obscene).
- Why walls can't use EMS/XMS: scanline z-buffer draws walls in vertical strips —
  hundreds of fetches per frame, so wall art must stay in conventional RAM. Only WAVs and
  weapon bitmaps are swappable. (A crisp architectural fact for the port.)
- Shaped-wall hole analysis works on **vertical strips**: ≤23–24 holes per strip plus a
  whole-image total (CE 19/20/116). Venetian blinds = worst case; rotate the art 90° and a
  striped pattern becomes one hole. This confirms *why* .vgr is stored rotated: the engine
  consumes columns.
- Color 0 = transparent for species 1/2. All-black shaped/symmetrical art = CE 184
  (classic culprit: `invisble.vgr` going all-black after palette matching).
- GCS 640k reality: needs **~590–600 KB conventional free** (CE 199 writes a `memfail`
  file) and **~2.5 MB XMS or EMS** (prefers EMS if ≥2.5 MB, else XMS; none = CE 210/211).
- GCSPAINT: launched from the GCS icon → saves **.vgr only**, canvas max 192×150;
  from DOS prompt → saves **.vga**, up to 320×200. .vgr = .vga rotated 90° (confirmed
  again, official). Import formats: GIF/PCX/BMP, **256-color only**, ≤200×200.

## 10. Backgrounds, HUD & screens

- `backg??.vga` per level number: **top pixel row = sky**, repeated horizon-to-top; rest =
  ground texture, **jiggles** as the player moves (intentional motion cue); if a floor texture
  is set but no ceiling, backg is drawn **upside-down as the ceiling**. Never resize it.
  Make the top row solid or you get vertical bands.
- `htpt.vga` (project dir) = hit-point guy, **20 tiled damage frames**; do NOT resize, and
  **never save it with an attached palette** (causes an endless fade-in/out bug).
- `backdrop.vga` = 320×200 gameplay frame; `mask.vga` = viewport border with rounded
  corners (its middle is forced to a solid color — this is the goggle/periscope trick);
  `compass.vga` (already decoded: 256×5 tick strip), `numlist.vga` = LED digits,
  `help.vga`, `pause.vga` — all flat .vga, edit with DOS-mode GCSPAINT.
- `readouts.txt` (project dir) = score/number-readout system tied to universe register
  values (OCR here is rough — flag for re-verification against a real file).
- Radar: inert until a Radar Pack (runcode 12) is picked up.

## 11. Fading tables & lighting — defaults finally known

- The editor's fade-color icon runs **PALTABLE.EXE** after you pick a fade color and
  writes **two files per level**: `p??.tbl` (normal fade table) **and `palt??.tbl`**
  (table for objects with the "fade more" attribute — this second table is NEW to us).
  Swap .tbl files around for special effects.
- Lighting register **defaults** (new data):
  | # | reg | default | notes |
  |---|---|---|---|
  | 0 | lgtfstart | 400 | fade begin distance (0–8191) |
  | 1 | lgtfamount | 8 | fade power 6–9 (6 cave, 9 outdoors) |
  | 2 | lgtfmore | 450 | extra distance added for fade-more objects |
  | 3–5 | lgtrate1–3 | 4 | smooth-cycle speeds |
  | 6 | lgtflashrate | 64 | flicker rate |
  | 7 | lgtflashduty | 64 | duty cycle (0 off, 255 on) |
  | 8–9 | flrspeedx/y | 0 | scrolling floor |
- Lighting command byte (red box 3 = univ attr4 low byte): `command×32 + n`, n signed
  0–15 (negative as 31−k); 160+n = flash-to, 191 = full-range flicker. Requires
  "wall lighting by angle" OFF on that object.
- Fade color advice: fade only to colors with many shades in the palette (black/grey/white
  in $rp9a) — explains the Mega Pack's grayscale-heavy ramps.

## 12. Make Final pipeline & the final game

- Warp-to points stored in **WARP_TO.DAT + GAMESTRT.DAT** (confirms LEVELS.TXT;
  delete both to reset). theaters.txt is generated at test time; the guide confirms the
  column layout and that **floor/ceiling status is saved inside warp-to points** (attribute
  column) — stale warp-tos = floors missing in final game.
- Make Final requires: unique level numbers (dupes silently drop the older level),
  every level tested after last edit, a Final Game Start Point set, and every included level
  reachable by warp-to. Output: `<PROJ>` game dir with a `DATA\` subdir (CE 174 if
  missing); distribute with `pkzip -rP` / unzip `-d`.
- **GO.BAT option string** (retail launcher):
  `go` · `go s1` (SB sound) · `go s1 t` (+MIDI music) · `+ j` (joystick) · `+ m` (mouse) ·
  `+ g` (god mode). No dashes/slashes; `s1` not `sl`.
- New error code beyond ENGINE.TXT's 1–239 list: **CE 247** = "didn't test a level that
  has a warp-to point before Make Final". Proof the retail 1.3 engine has extended codes.
- Guide's CE 188 = "missing objdef??.txt — did you test before make final?" (ENGINE.TXT:
  objmfnf/objdef?.dat — same root cause, text-mode vs compiled view).
- Guide says oversized MIDI → CE 95 (ENGINE.TXT: aplfnf) — likely code re-use; record
  both, resolve later against real binary behavior.
- Level switching is inert in test mode — warps only fire in the compiled game.

## 13. Enemies & player detection (AI behavior constants)

- Enemy params at placement: quickness, step size, resistance, attack strength, attack
  accuracy, range. Behaviors: sentry-then-hunt / random patrol / stand-and-shoot.
  Alertness grades: "Einstein with an Attitude" → "What was the question?" (near-blind).
- The only alert trigger is **seeing the player**, modulated by view angle (behind = safer),
  walls block sight, corpse discovery raises alertness, and any hit alerts instantly.
- Player **profile** = single number raised by running, shooting (heavily), and being
  wounded — the stealth system's whole input.
- Combat rhythm: serpentine approach when out of range, stop at halfway for ≥1 shot,
  shoot repeatedly in range, melee continuously up close; damaged-enough enemies retreat
  and turn to fight when cornered.
- 8-view trick officially explained: negative handle = mirrored view; attack/tear-gas/
  immobilized frames are front-view-only by design; death sequence can be 1 or 8 views.
- Enemy definition files: `gardef.txt` in enemy dirs shares the handle namespace with
  weapdef.txt.

## 14. Player controls (for the port's input map)

- Space = fire; **1/2/4/7** = kick / goo gun / machine gun / shotgun (top-row number keys);
  **I** = pick up; **S** then arrows+Enter = drop item; **B** = detonate bomb; Esc = quit
  to editor. Arrow keys move (implied), mouse/joystick optional in final game.

## 15. Discrepancies & open questions flagged

1. Fluid frames: editor 40 vs ENGINE.TXT maxnfluid 32 — retail likely raised it
   (fld[40] in BARFWRLD sides with 40).
2. Reserved registers: 128–168 (guide) vs 128–255 (ENGINE.TXT).
3. CE 95 / CE 188 meanings differ slightly between guide and ENGINE.TXT (era drift).
4. GCSMENU ending register reads "129" in OCR — probably 127; unverified.
5. readouts.txt format only partially legible (score via universe registers).
6. The `.FLD` library animation file and `objweap.txt` / `gardef.txt` formats are named
   but not specified — grab real samples from the DOS 1.3 install when extracted.
7. "theaters.txt" printed column order confirmed: entry, objdef(+bg×256), univ, x, y, z,
   theta — matches LEVELS.TXT.

## 16. Net gains for the reverse-engineering effort

- Confirmed $RP9A.PAL as the canonical palette, straight from Pie in the Sky.
- Second fade table **palt??.tbl** discovered; lighting register defaults now known —
  enough to reproduce authentic distance shading without guessing.
- The inventory/pickup system (weapdef.txt + pickups.txt + 16 runcodes) is fully specified —
  previously only hinted at via ENGINE.TXT's 'p' lines.
- Door parameter semantics (resistance bands 0/1/8/31/32+, 800 cm close radius) decoded.
- Live universe registers 122–127 mapped (fps/health/kills/game-over) — the port's HUD and
  game-over logic can match the original behavior exactly.
- Retail engine has error codes past 239 (CE 247) — the error table in our knowledge base
  is the older GCSP-era list.
- Editor limits (700 objects / 600 types / 32 enemies / 40 fluid frames) corroborate the
  struct array sizes in BARFWRLD.C — our .WLD struct reading is right.
