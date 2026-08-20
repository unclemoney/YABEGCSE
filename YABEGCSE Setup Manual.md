# YABEGCSE — Setup Manual

Step-by-step manual setup: Godot project, repository directory harness, and
git via GitHub Desktop. Do these in order. Every step ends with a check —
don't move on until it passes.

Prerequisite reading: none. Prerequisite software decisions are made for you
below — deviate only if you know why.

---

## Part 1 — Software

1. **Godot 4.4.1, standard build** (NOT the .NET build — we are GDScript-only).
   - Download from godotengine.org/download → "Godot Engine — Standard".
   - It's a single portable executable. Put it somewhere permanent, e.g.
     `C:\Tools\Godot\Godot_v4.4.1-stable_win64.exe`.
   - ✅ Check: double-click it; the Project Manager window opens.

2. **GitHub Desktop** — desktop.github.com, install, sign in with your
   GitHub account (create one first if needed).
   - ✅ Check: GitHub Desktop opens, shows your username top-right.

No git CLI install is needed — GitHub Desktop bundles git.

---

## Part 2 — Repository directory harness

This layout is the agreed home for code, docs, art, music, and tools.
The **repo root is NOT the Godot project** — the Godot project lives one
level down in `editor\`, so docs and tools stay outside the game export.

3. Create this folder tree (Windows example root: `C:\Dev\YABEGCSE`):

```
YABEGCSE\                  ← git repository root
├── docs\                  ← the three signed session documents
│   └── appendix\          ← legacy 3DGCS research (converter reference)
├── editor\                ← the Godot project (created in Part 3)
├── art_source\            ← original .VGA/.VGR/.PAL files + Mega Pack tree
├── music\                 ← WAV renders of the original MIDIs
└── tools\                 ← vga2png.py, probe.py (final alpha rerun lives here)
```

4. Populate it:
   - `docs\` ← the three signed documents (*Project Charter*, *Level Format
     v0 Envelope*, *Milestones and CLI Prompts*).
   - `docs\appendix\` ← *3DGCS Project Knowledge.md*, `ENGINE.TXT`,
     `LEVELS.TXT`, `FILEFMTS.TXT`, `README.TXT`, `BARFWRLD.C`.
   - `art_source\` ← the original Mega Pack tree and DOS 1.3 assets,
     `$RP9A.PAL`, `$RP9A.TBL`.
   - `tools\` ← `vga2png.py` and `probe.py`.
   - `music\` ← the WAV renders (when made; empty folder is fine for now).

> Note: the **runtime art library** (the ~2,700 alpha-keyed PNGs that ship
> with the editor) will live *inside* the Godot project at
> `editor\art_library\` — created in Part 3 and populated by the final
> vga2png rerun. `art_source\` is the archive; `art_library\` is the
> shipping product. Don't conflate them.

✅ Check: tree matches the diagram; the three signed docs are in `docs\`.

---

## Part 3 — The Godot project

5. Open the Godot Project Manager → **New Project**.
   - Project name: `YABEGCSE`
   - Project path: browse to the repo root, then create/select the
     `editor` subfolder — Godot requires the target folder to be **empty**.
     Final path: `C:\Dev\YABEGCSE\editor`
   - Renderer: **Compatibility** (broadest hardware support, everything
     we need for retro 3D + fog, keeps web export open as an option).
   - Version control metadata: **Git** (Godot writes its own
     `.gitattributes`; harmless and helpful).
   - Click **Create & Edit**.

6. Inside the Godot editor, create the project-internal folder skeleton
   (right-click `res://` in the FileSystem dock → New Folder):

```
editor\  (res://)
├── scenes\        ← .tscn files (app shell, 2D canvas, 3D view)
├── scripts\       ← .gd files
├── levels\        ← YABEGCSE JSON level files (editor-owned)
├── art_library\   ← shipping art: alpha-keyed PNGs + palette identity
└── music\         ← WAV files that ship with games
```

7. Set the two project-wide render defaults now so no CLI session has to
   discover them:
   - **Project → Project Settings → Rendering → Textures → Canvas Textures →
     Default Texture Filter → Nearest.** (Also searchable as
     `default_texture_filter`.) This is the 1995 crunch — global, one switch.
   - Leave window size alone for now; the 640×400 internal viewport is a
     Milestone 2 implementation detail (a scaled SubViewport), not a
     project setting.

8. **Project → Project Settings → Application → Run → Main Scene:** leave
   unset for now (the M0/M1 scaffolding sessions will create and set the
   app shell scene).

✅ Check: press F5 — Godot asks for a main scene; cancel. Project opens
without errors; the five folders show in FileSystem. Close Godot.

---

## Part 4 — Git + GitHub (via GitHub Desktop)

9. **GitHub Desktop → File → New Repository:**
   - Name: `YABEGCSE`
   - Local path: `C:\Dev\YABEGCSE` (the **repo root**, NOT `editor\`).
   - **Git ignore: choose "Godot"** from the template dropdown. This
     correctly excludes `.godot\` (Godot 4's import/cache folder — never
     commit it).
   - License: None for now (see the rights note below before ever
     publishing).
   - Create Repository.

10. **First commit.** GitHub Desktop now shows all created files as
    changes. Summary: `Initial scaffold: docs, tools, Godot project shell`.
    Commit to `main`.

11. **Publish** (Publish repository button):
    - **Keep "Keep this code private" CHECKED.** The repo contains GCS art
      (reused under Kevin Stokes' permission to the preservation community)
      and Build-inspired design docs. Private until a deliberate decision
      is made — flipping private→public later is one click; the reverse
      is impossible.
    - Publish.
    - ✅ Check: github.com → your repos → YABEGCSE exists, private,
      folder tree intact, and `.godot\` is **absent** from `editor\`.

12. **Working rhythm for CLI sessions** (this is the harness discipline):
    - Each CLI coding session works on a **branch**:
      GitHub Desktop → Branch → New Branch → e.g. `m1-sector-editor`.
    - When a session's work is accepted: Branch → Create Pull Request on
      GitHub, review the diff, merge. `main` stays green and signed-off.
    - **Commit early within a session** — your 3-deep undo philosophy
      applies to the editor, not to git. Commits are free.
    - If a session goes wrong: GitHub Desktop → History → right-click the
      last good commit → Create branch from commit. You are never more
      than one click from a known-good state.

13. **Large files note (do nothing yet):** the ~2,700 converted PNGs are
    small and commit normally. WAV music may grow large; if the repo ever
    feels heavy, GitHub Desktop supports Git LFS for `*.wav` — revisit at
    Milestone 6, not before.

---

## Part 5 — Handoff readiness

You are ready for CLI Session 0 when ALL of these are true:

- [ ] Godot 4.4.1 standard opens `editor\` without errors
- [ ] Folder tree matches Part 2; three signed docs in `docs\`
- [ ] Repo on GitHub, **private**, `.godot\` excluded
- [ ] `main` branch has the initial scaffold commit
- [ ] The vga2png alpha rerun is still pending — it's a pre-M5 task,
      not a blocker for Session 0

The CLI Session 0 prompt (in *YABEGCSE Milestones and CLI Prompts.md*)
assumes exactly this layout: docs at `docs\`, Godot project at `editor\`,
art staging at `art_source\`. If you deviated anywhere above, either
re-conform or edit the Session 0 prompt before running it.
