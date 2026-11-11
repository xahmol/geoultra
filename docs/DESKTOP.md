# GeoUltra Desktop (design and plan, milestone 1)

GeoUltra's own desktop: a GEOS application that replaces GEOS 2.0's
deskTop as the place `EnterDeskTop` leads to. Own design (DESIGN.md,
"Desktop": decisions 2026-10-29 and 2026-11-06; mock-ups:
https://claude.ai/artifact/2yrZuKGyDceuaFJ2Do4gsq, direction C "modern
minimal"). Clean-room: no deskTop, TopDesk or MegaPatch code, icons or
layouts copied; GEOS's own conventions (menu bar, geos menu with desk
accessories, dialogs) are kept because applications and users expect
them.

## What milestone 1 is (user, 2026-11-06)

- The **Modern** view with the **list** only: one full-screen view, a
  menu bar on top, a sidebar on the left, the current folder as a list
  of names on the right. The detailed and icon views, two panes and the
  Classic style come later, each its own step; the core is written so
  that they are only other ways of drawing the same list.
- **Sidebar:** drives A-D, drive E (the system drive), the Ultimate's
  roots (usb0, usb1, sd), favourite folders (kept in `SETTINGS.INI`) and
  recent documents.
- **Actions:** open (an application started, a document with its
  application, a folder entered, a disk image mounted after asking for
  the drive), copy or cut then paste in the destination, delete
  (asking), rename, new folder; all through the file engine (FILE_ENGINE.md),
  so the Ultimate's file system is a full peer of the drives (CVT as in
  gush).
- **Keys:** cursor up and down move the selection, SHIFT extends it,
  RETURN opens, cursor left goes up a folder, DEL deletes (asking);
  menu items with C= shortcuts (C=C copy, C=X cut, C=V paste, C=R
  rename, C=N new folder, C=Q quit).
- **Text:** GeoUltra's own system font, columns at fixed pixel
  positions (name, type, size, date in later views), long names
  clipped at their column.
- **No task bar yet:** room kept at the bottom; it comes with the task
  switcher.
- **The default since 2026-11-11 (user):** `EnterDeskTop` starts it
  from drive E, and the cold start ends in `EnterDeskTop` (the kernal's
  temporary banner is gone). `SETTINGS.INI` `[system] desktop=geos`
  brings back GEOS 2.0's deskTop (searched on the drives as before);
  `start=gush` still starts gush instead. Until 2026-11-11 it was
  opt-in (`desktop=geoultra`, still accepted).

## Screen (320 x 200)

```
+--------------------------------------------------------------+  0
| geos  file  view  disk                         date  time     |  menu bar (GEOS menu)
+-------------+------------------------------------------------+ 14
| DRIVES      | /b/Letters                  12 files   6 MB    |  path line
|  A GEOS 64  +------------------------------------------------+ 26
|  B Work     | Letter to Sue                                  |
|  E System   | Invoice 0412           (selected: inverted)    |
| ULTIMATE    | Notes                                          |
|  usb0       | Recipes /                                      |  list, 9 px rows
|  sd         |   ...                                          |
| FAVOURITES  |                                                |
| RECENT      |                                                | 
+-------------+------------------------------------------------+ 186
| (task bar, later)                                            |
+--------------------------------------------------------------+ 199
```

Sidebar 80 pixels wide; list from x 82; rows of 9 pixels (the system
font's height plus a gap): about 17 visible names; a scroll position
moves the window over the folder's entries.

## Look and themes (user, 2026-11-06)

The desktop's look is a **theme built from design elements**, not from
palette numbers (mock-up with all choices:
https://claude.ai/artifact/5Jv2FtLekd6o343SYpRhJJ, approved
2026-11-06). Each element is one drawing routine with a few styles;
colour is a property of an element, by name:

| Element | Styles | Colours |
| --- | --- | --- |
| screen | - | border; desk ink on paper |
| menubar | plain, clock | ink on paper |
| sidebar | wide (80 px), narrow (64 px) | ink on paper |
| headings | inverted, band, underlined, plain (bold) | ink on paper |
| titlebar | stripes, solid, line, none | ink on paper |
| rows | 9 (system font and a gap), 8 (on the cell grid) | - |
| columns | name, detailed (name, size, date) | - |
| icons | on, off (8 x 8, own drawings) | ink |
| selection | invert, bar (needs 8-pixel rows), frame | ink on paper |
| cursor | dotted, mark, underline | accent ink |
| scrollbar | arrows (with a thumb), thin | - |
| status | on, off (entries, selection, free space) | ink on paper |

- A theme is a file `THEMES/<name>.ini` in GEOULTRA, in words
  (`selection=invert, white on purple`; "X on Y": X text on a Y
  background); `SETTINGS.INI` `[desktop] theme=` names the one in use.
  All themes are files, the built-in ones included (made at the first
  start), plus Custom to edit (user, 2026-11-11). Colour names map to the 16 colours; on an Ultimate 64 or C64
  Ultimate a theme may carry a palette (firmware 3.15), which changes
  what a name looks like, not which element uses it.
- In memory a theme record: a style byte per element, a colour byte
  per colour. Combinations the cell grid cannot draw are corrected
  when loading (a colour bar forces 8-pixel rows).
- Built-in themes: **GeoUltra (the default)**, GEOS classic, Flat,
  Detailed, Night, Mono. GeoUltra: clock, wide sidebar, inverted
  headings (white on light blue), striped title bar, 9-pixel rows,
  icons (blue), inverted selection, dotted cursor, scroll strip with
  arrows, status line (white on grey), dark grey on light grey,
  border light blue.
- Applications and dialogs keep GEOS's own look; a theme dresses the
  desktop only.
- The theme editor (settings tool, phase 3) edits this record, one
  line per element, the desktop as preview.

## Structure

- Assembler (ca65/ld65), a VLIR application like gush (gush's overlay
  mechanism and VLIR CVT build reused): `src/desktop/`. Record 0 the
  core (main loop hooks, drawing the list and sidebar, the selection,
  the entry table); overlays for the actions (copy/paste, delete,
  rename and new folder dialogs, mounting, starting programs), the
  sidebar's favourites and recent list, and later the other views.
- **Entries:** a folder's listing is read through `FE_OPENDIR` /
  `FE_READDIR` into an entry table in the application's REU (no limit
  of a page or a screen: thousands of entries on a native drive), a
  record per entry (kind, GEOS type, size, date, short and long name);
  the screen shows a window of it. In directory order, as GEOS 2.0's
  deskTop shows it; sorting (name, type, size, date) comes with the
  detailed view, where DESIGN.md's decision of 2026-10-29 puts it
  ("detailed: sortable").
- **Programs:** started as gush starts them (prog.s: `FE_SELECT` and
  `GetFile`, a document passed as the deskTop passes one, programs on
  drive E through `FE_RUNSYS`); shared code moves into an include when
  both need it.
- **Name on drive E:** `GeoUltra Desktop` (16 characters), in E's root.

## Plan (sub-steps, each tested, committed and pushed)

1. **D1 frame:** the application on drive E; `desktop=geoultra` in
   `SETTINGS.INI`; menu bar (geos with the desk accessories, file,
   view, disk), sidebar with the drives that are there and E, the list
   area with the current folder's names (first window), quit.
2. **D2 list:** the entry table in the REU, scrolling (mouse
   on a scroll strip, keys), selection by click and keys (SHIFT
   extends), the path line.
3. **D3 open:** folders entered and left (cursor left, a ".." row),
   sidebar clicks change drive or root, applications and documents
   started, desk accessories run.
4. **D4 actions:** copy/cut and paste, delete (asking), rename and new
   folder (dialogs), with a progress line for long copies.
5. **D5 sidebar:** the Ultimate's roots, favourites (add from the
   current folder; `SETTINGS.INI`), recent documents.
6. **D6 images:** opening a disk image on the Ultimate (`.d64`,
   `.d71`, `.d81`, `.dnp`) mounts it (`FE_MOUNT`) after asking for the
   drive: a dialog with A-D, each with the image mounted there now, and
   free letters offered too (user, 2026-11-06); the old image written
   back first, `MOUNTS.INI` updated, the list then at that drive's root
   and the sidebar's disk name new. **Unmount** (user, 2026-11-06): an
   eject icon (8 x 8, own drawing) at the right end of each sidebar
   drive line A-D that has an image (not drive E); a click asks
   "Unmount drive B (work.d81)?", then `FE_UMOUNT`. Errors (no room in
   the REU, a failed write-back) in a dialog, nothing changed.
7. **D7 look:** the element routines with their styles, the theme
   record (built-in themes, the default GeoUltra; a theme file read when
   named in `SETTINGS.INI`), icons, the clock and the status line, the
   busy pointer and the copy progress line. D5b and D6 are drawn
   through the same routines from the start.
8. **Sweep** and the switch of the default (user's decision).

## State of the work

- **D1 (2026-11-06):** `src/desktop/desktop.s`, a sequential application
  (5 blocks) in drive E's root as `GeoUltra Desktop`. The menu bar (geos
  with "GeoUltra info" and the desk accessories, from `FindFTypes`, so
  drive E's geoFolder is among them; file > gush; view > list; disk >
  refresh), the sidebar with each drive that is there and its disk name
  (`OpenDisk`, as GEOS 2.0's deskTop names its drives; the current
  drive opened again after), then E, and the list area with the path
  (`FE_PWD`) and the current folder's first 17 entries (`FE_OPENDIR`;
  folders and drives with "/"). Drawn on both screens and
  `RecoverVector` = `RecoverRectangle`, so menus and desk accessories
  give back what was under them (GEOS's default 0 erases with white).
  The kernal (then; the default since 2026-11-11): `SETTINGS.INI` `[system] desktop=geoultra` (mount.s) sets
  `ownDesk`; `EnterDeskTop` then starts the desktop through `FE_RUNSYS`
  and falls back to GEOS 2.0's deskTop when that fails. Found on the
  way: the name passed to the engine must not be in the calling overlay
  module (the engine's modules overwrite the slot): copied to `$0400`
  first. Tests: tests/desktop/d1.py (VICE, `make test-desktop`),
  tests/desktop/du64.py (U64, `make test-desktop-u64`).
- **D2 (2026-11-06):** the list (list.s). A folder's entries are read
  once into an entry table in the application's REU (128 bytes each:
  the engine's info block and the long name; banks 1-4, up to 2048
  entries), in directory order; 17 rows show from `top`, with a scroll
  strip on the right (its thumb at the window's place; a click above
  or below it pages). The selection is a bit per entry, the cursor
  the entry the keys move. Mouse: a click selects the entry alone,
  SHIFT+click the range from the cursor, C=+click toggles it. Keys:
  cursor up and down move the cursor, the window follows; **C= +
  cursor extends the selection** (a deviation from the plan's "SHIFT
  extends": on the C64 cursor up is SHIFT + CRSR DOWN, so SHIFT cannot
  be told apart); HOME to the first entry. SHIFT and C= are read from
  the keyboard matrix at a click, with I/O switched in (applications
  run with RAM over `$D000`: without it the matrix read RAM and every
  click looked like C=+SHIFT). Test tests/desktop/d2.py (VICE: 40
  files on drive B; reading, keys, C= extending, a click, a page).
- **D3a (2026-11-06):** opening (open.s). RETURN or a double click
  (GEOS's `dblClickCount`, the same entry clicked again in time) opens
  the cursor's entry: a folder or drive is entered (`FE_CD`), an
  application or auto-exec file started in the desktop's place, a desk
  accessory run (the screen drawn again when it comes back); programs
  start as gush starts them (`FE_SELECT`, `GetFile`; on drive E an
  application through `FE_RUNSYS`, a desk accessory through `GetFile`
  by its name). Cursor left goes to the parent folder; a click on a
  sidebar line to that drive's root. Test tests/desktop/d3.py (VICE).
- **D3b (2026-11-06):** documents (open.s, `Document`). Any other GEOS
  file opens with its application: the parent's permanent name from
  its header (`$75`; the class is its first 12 characters) is looked
  for among the applications of the document's folder (`FE_SELECT`
  makes it current, then `FindFTypes` with the class), then in the
  root of each other drive A-D; the application starts with
  `ST_LD_DATA`, `r2` the document disk's name and `r3` the document's
  name, as the deskTop passes one. Test tests/desktop/d3doc.py (VICE,
  the user's GEOS64.D81: "ReadMe 1581" opens in geoWrite 2.1).
- **D4 (2026-11-06):** the actions (actions.s), in the file menu and
  as keys: open C=O, copy C=C, cut C=X, paste C=V, delete DEL, rename
  C=R, new folder C=N. Copy and cut keep the source folder and the
  names of the selection (or the cursor's entry) in the application's
  REU (bank 5); paste copies (`FE_COPY`) or moves (`FE_MOVE`) them into
  the current folder, asking before a file of the same name is
  replaced; after cut and paste the clipboard is empty. Delete asks
  once, then removes files and empty folders. Rename and new folder
  ask for the name (an input line; RETURN ends the dialog as OK does:
  GEOS returns `DBGETSTRING` then). Errors in a dialog (the name and
  the engine's error number) end the action. Not yet: a progress line
  for long copies, recursive delete. Test tests/desktop/d4.py (VICE).
- **D5a (2026-11-06):** the sidebar's Ultimate roots: "ULTIMATE" and a
  line for each of usb0, usb1 and sd that is there (the root listing's
  Ultimate folders; none without a Command Interface, so none in
  VICE); a click goes there. Every sidebar line keeps its code and its
  top row, so clicks find their line across headings. Test
  tests/desktop/du64.py (U64: usb0 listed, a click goes to /usb0).
- **D5b (2026-11-06):** favourites and recent documents (side.s; the
  user's choices of 2026-11-06). Favourite folders are kept in
  `SETTINGS.INI` `[favourites]`, recent documents in `RECENT.INI`
  `[recent]` in the home folder, one path a line, at most four of each
  and paths of at most 62 characters. The desktop reads them at its
  start (applications reuse its memory). file > favourite (C=F) adds
  the selected folder under the cursor, else the current folder, at
  the end (not twice; the first dropped when there are four); C=+click
  on a favourite asks, then removes it; a click goes there. Opening a
  document puts it at the top of the recent ones (moved there when it
  is in the list); a click on one shows its folder and opens it with
  its application. The sidebar shows the headings only when there are
  entries, a path's last part (a one-part path such as `/a` whole), and
  leaves out lines below the screen. Writing keeps the file's other
  lines (its section moves to the end): the file is read whole (at most
  3072 bytes, else not written), written as a `.TMP` file that then
  takes its place, so a failed write leaves the old file. Without a
  home folder (VICE: no Ultimate) nothing is read or written and the
  lists live until the desktop starts again. Tests: tests/desktop/d5.py
  (VICE: adding, not twice, the selected folder, the fifth drops the
  first, the sidebar's lines, a click), du64.py (U64: both files read,
  C=F rewrites `SETTINGS.INI` with its other lines kept, a recent
  "ReadMe 1581" opens in geoWrite and goes to the top of `RECENT.INI`;
  both files deleted again). C=+click removal is for the hand test
  (the harness cannot hold C=).
- **D6 (2026-11-11):** disk images (mount.s). Opening a file on the
  Ultimate whose name ends in `.d64`, `.d71`, `.d81` or `.dnp` (any
  case) asks for the drive: "Mount on drive:" with a button per letter
  A-D (drawn by tools/mkicons.py like the system icons) and next to
  each the name of the image mounted there now (its path's last part,
  cut at 11 characters, clear of CANCEL) or "free". A button mounts it
  (`FE_MOUNT`: the old image written back first, `MOUNTS.INI` anew),
  the sidebar is drawn again and the list goes to the drive's root.
  Each sidebar line A-D with an image (`FE_MOUNTINFO`) has an eject
  icon (8 x 8, x 64-71; the disk names are clipped before it); a click
  on it asks "Unmount drive C?" with the image's name, YES unmounts
  (`FE_UMOUNT`) and redraws the sidebar; a list on that drive goes to
  "/". Errors in the dialog of actions.s (the image's name, the code).
  Found on the way: with no drive mounted at all the desktop could not
  start from E (the REU driver refused every block of an empty drive,
  E's tracks too); now an empty drive serves E's tracks. Tests:
  tests/desktop/d6u64.py (U64: a favourite to the test folder,
  geopub.d64 opened, drive C chosen, `/c` and `FE_MOUNTINFO`, the
  eject icon and YES, C gone; `MOUNTS.INI` put back). In VICE (no
  Ultimate files) the eject question is checked by hand.

- **D7a (2026-11-11):** the look (theme.s, icons.s; the drawing in
  desktop.s and list.s). The theme record (a style byte per element, a
  colour byte per colour) and the six built-in themes of the mock-up;
  the layout derived from it (sidebar 80 or 64 pixels, title bar,
  9- or 8-pixel rows, list top, rows, status line, scroll track). The
  elements: menu bar with the clock, sidebar headings (inverted, band,
  underlined, plain), items with icons and the open drive's arrow,
  the title bar (stripes, solid, line, none) with the folder's name,
  the rows with 8 x 8 icons (BitmapUp: on a card, one in from the
  list's edge), the selection (inverted, colour bar, frame), the
  cursor (dotted, mark, underline), the scroll strip (arrows with a
  grey thumb, or thin; arrows a line, the track a page), the status
  line (entries, selection, free space). Colours: every cell the
  desktop paints also goes to a shadow copy; dialogs (Dialog), the
  desktop's menus (all DYN_SUB_MENU: MenuNeutral) and programs and
  desk accessories (Neutral) get GEOS's own colours, RecoverVector
  (Recover) gives back bitmap and colours. Changed with the user
  while it was built (2026-11-11): the clock "Wed 11 Nov 2026  21:42",
  12- or 24-hour or off (24 the default); the view menu with
  submenus theme, view (list, icons, detailed; icons is a later step
  and draws the list for now) and clock; the detailed view (size in KB
  or MB, the date of GEOS files: "6 Nov 26"); **all UI text in
  sentence case** ("Drives", "21 entries, 2 selected", "1 entry",
  "B: 766 KB free"), not the mock-up's capitals. Settings in
  SETTINGS.INI `[desktop]`: `theme=` a theme's name, `view=` list,
  icons or detailed, `clock=` 24, 12 or off (side.s keeps the
  section's other lines). Tests: test-desktop (VICE) with the layout
  read from the desktop's memory; d6u64.py on the U64; the themes
  checked by screenshots in VICE and on the U64.
- **D7 theme files (2026-11-11, user's request):** every theme is a
  file `GEOULTRA/THEMES/<name>.ini` in words (themefile.s), the
  mock-up's format: `[theme]`, `name=`, then `border=`, `desk=`,
  `menubar=`, `sidebar=`, `headings=`, `titlebar=`, `rows=`,
  `columns=`, `icons=`, `selection=`, `cursor=`, `scrollbar=`,
  `status=` (a style word, then `ink on paper`, or one colour). The
  desktop makes THEMES at its start when it holds no theme: the six
  built-in themes and **Custom** (a copy of GeoUltra, to edit; the
  theme editor will start it from any theme). The view menu's theme
  submenu lists the files (up to 8); a theme in use is its built-in
  record with its file read on top (lines left out keep the built-in
  values), so the built-in themes are editable too; without an
  Ultimate (VICE) the built-in table alone. **"X on Y" means X text on
  a Y background** (user, 2026-11-11): elements drawn inverted (heading
  boxes and bands, the solid title bar, the status line) get their
  colours swapped when painted. Test: tests/desktop/d7u64.py (U64: the
  files there, Night.ini in words, an edited Custom.ini in use;
  Custom.ini and SETTINGS.INI put back).
- **Next:** the busy pointer and the copy progress line; the icon
  view; the theme editor (settings tool, phase 3).

## Open bugs

- **geoFolder garbled when opened from the desktop (2026-11-06, the
  user's hand test on the U64). Cause found 2026-11-11, not the
  desktop:** drive A's test copy (`/USB0/GEOULTRA/test/GEOS64.D81`)
  held its own geoFolder (put there by `tests/gush/gu64.py`), and
  GetFile takes the current drive's copy before drive E's. That copy
  was damaged: 2 data blocks allocated, but the first block's link
  was 0/$FF (last block), so only 254 of 508 bytes loaded; the
  dialog table loaded, the gush icon and the texts did not. The
  second block had been freed and reused. Removed from the test copy
  (directory entry and BAM; the damaged image kept outside the
  repository); on the U64 the desktop's geoFolder from `/e` then
  showed correctly. In VICE the dialog was correct from the list and
  the geos menu, with 1541 and 1581 drives A. What damaged the file is
  not known: gush's `cp` and the desktop's paste (`/e/geoFolder` to
  drive B, VICE) both write a correct 2-block chain; c1541's
  `-geoswrite` too. Watch for it in later write tests.
- Fixed (036c457): after a desk accessory started from the list, the
  menu bar was gone (Redraw clears it; open.s calls ReDoMenu after it).

## Tests

VICE (the conformance harness's application runner; screens rendered
and checked by the desktop's own state in memory: the current path,
the entry table, the selection) for everything that needs no Ultimate;
the U64 for the Ultimate's file system and mounting, as gush's gu64.py.
