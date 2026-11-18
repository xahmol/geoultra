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
  of names on the right. The detailed and icon views and two panes
  come later, each its own step (the Classic style was dropped by the
  user on 2026-11-13: the icon view looks classic enough); the core is written so
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
  temporary banner is gone). `start=gush` still starts gush instead.
  Until 2026-11-11 it was opt-in (`desktop=geoultra`); from 2026-11-13
  `desktop=` is not read at all (the user: no choice of GEOS 2.0's
  deskTop; it only starts when GeoUltra's cannot).

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
  Ultimate a theme may carry a palette (firmware 3.15a on the Ultimate 64;
  not yet released for the C64 Ultimate, user 2026-11-11), which changes
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
   the REU, a failed write-back) in a dialog, nothing changed. Since disk images are gone into like folders
   (2026-11-13), mounting is the context menu's second item: on a disk
   image it reads "mount" instead of "open in new task" and opens the
   drive dialog (list.s TaskOrMount, ctxmenu.s; the user, 2026-11-16:
   no way to mount was left). A mount icon (8 x 8, a thin arrow into an open tray,
   own drawing, mount.s MountIcon) at the right end of each disk image's
   line in the list and detailed views (list.s ImgIcon, the list's last
   card) mounts with one click (listin.s IconHit sets openReq =
   OPEN_MOUNT, desktop.s OpenReq calls TaskOrMount: the drive dialog)
   and shows which files can be mounted; a click on the name still goes
   into the image (the user, 2026-11-18). Test tests/desktop/d6u64.py
   (U64: the icon, drive D, unmount; the user's files set aside and put
   back).
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
  2048 bytes (3072 until 2026-11-13), else not written), written as a `.TMP` file that then
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
- **Palettes, busy pointer, progress line (2026-11-11):** a theme
  file may carry `palette=` and 16 `RRGGBB` values (the C64 colours'
  order); the desktop sends it to the Ultimate 64 with `FE_UCI`
  (control target, `SET_PALETTE`; firmware 3.15a, not yet released
  for the C64 Ultimate; nothing on an Ultimate II+ or in VICE) when
  the theme is used, and `RESET_PALETTE` when the theme it leaves had
  one. The palette shows for every program, as the Ultimate's own
  setting does. GeoUltra keeps the C64's palette; the other five
  presets have their own (user, 2026-11-11: "optimise the colours of
  the other presets with full RGB freedom"), each colour keeping its
  character since programs see it too; Custom.ini has a note on the
  format. The pointer is an hourglass (own drawing, sprite 0's picture
  saved and put back, nested) while a folder is read, files are
  pasted or deleted, an image is mounted or unmounted; the arrow
  during a dialog. The status line shows "Copying 3 of 12: name, 40
  blocks" (or "Moving", "Deleting"); RUN/STOP stops a copy (the
  engine's FE_CANCELLED, the rest left). Memory: three 256-600 byte
  buffers now share side.s's INI text (never in use together).
  Tests: test-desktop (VICE); the progress line and pointer checked
  in VICE at a checkpoint in ProgressBlock; d7u64.py (U64: the files'
  palettes, Night's sent, the reset on leaving it).
- **Overlays (2026-11-11):** the desktop ran out of room, so it is now
  a VLIR file as DESKTOP.md "Structure" planned: record 0 the core at
  `$0400-$4FFF`, overlays at `$5000-$5FFF` (ovl.s; the loader and stubs
  shared with gush in `src/inc/ovlcore.inc`), kept in the application's
  REU bank 6: overlay 1 the theme files, overlay 2 the actions and
  mounting. The borders of the built-in themes match their desk's
  background (user, 2026-11-11).
- **Folders with everything in them (2026-11-11, user's request):**
  copy, cut and paste and delete work on folders recursively
  (tree.s, overlay 2; the walk follows gush's `cp -r`: each folder's
  listing read whole into REU bank 7 before anything in it is touched,
  8 levels deep). A move tries `FE_MOVE` first, else copies and
  deletes. A file that exists is replaced only after "Replace it?"
  answered **Yes** or **Yes to all** (for the rest of that paste);
  **No** leaves it. A folder that is not empty is deleted only after
  "Delete everything in it?" with the same three answers. A folder
  pasted into itself is refused. The progress line counts the files
  ("Copying 14: name, 40 blocks"); RUN/STOP stops. On the Ultimate's
  own file system a folder move is one rename and files copy with the
  Ultimate's own COPY (the engine's new modules 83 and 84,
  FILE_ENGINE.md). Mounting moved
  to overlay 3; the error dialog and `Append` to the core
  (errors.s). `OvlGo` keeps r0-r3 across a fetch now (`ThemeUse` takes
  r0; a theme chosen while another overlay was in place got a broken
  name). Tests: tests/desktop/d8.py (VICE: a tree copied, pasted again
  with Yes to all, deleted, moved), d8u64.py (U64: a tree copied on
  the Ultimate with its bytes checked, deleted, a folder moved).
- **Decisions (user, 2026-11-11):** the icon view shows the GEOS file
  headers' own 24 x 21 icons, read only for the entries on the screen
  and kept in an REU cache (Ultimate files and folders: the generic
  icons); a scrolling grid (about 6 x 4, the name under each icon, the
  same scroll strip, keys and selection as the list). Before it, the
  eighth code sweep, with three extras: one shared folder walk for
  gush's `cp -r` and the desktop (an include), one retry in `FE_NTP`
  after a lost reply, and copies within one Ultimate folder made
  possible (through a temporary folder; a new engine module).
- **Toolbar and right-click (user, 2026-11-11):** a separate toolbar
  row under the menu bar, the full screen width (over the sidebar too;
  the sidebar and the list start one row lower; the path line keeps its
  full width): 16 x 8 framed buttons (an 8 x 8 icon in a 2-card frame
  with a shadow, own drawings) in groups: navigation (back, forward,
  up, root, home), list position (top, end), view and refresh (the
  view toggle list / icons / detailed, refresh), actions (new folder,
  info, select all, copy, paste, delete). A theme element like the
  title bar: styles framed, flat, off (off gives the row back), ink on
  paper colours, a line in the theme files. Back and forward keep a
  short history of the folders visited. The right mouse button opens a
  context menu at the pointer with what fits the entry (open, copy,
  cut, paste, rename, delete, info, favourite, mount or eject); the
  1351 driver reports the right button in a GeoUltra variable (GEOS
  applications see nothing new); to be checked first on the U64 (its
  USB mouse as a 1351). Info: a dialog with the entry's size, type,
  date and GEOS class. Room: the desktop's core has about 150 bytes
  left, so the INI file handling (side.s) moves to an overlay first;
  the context menu and Info are an overlay.
- **Toolbar, after the mock-up (user, 2026-11-11; mock-up:
  https://claude.ai/artifact/ECimQq7UX37FcgWScJuR7u):** the height is a
  view option, not a theme style: view > toolbar > two-line (16 px,
  framed 16 x 14 buttons, the default), one-line (8 px, flat 8 x 8 icons
  12 px apart, dotted lines between the groups, one list row more) or
  off; saved as SETTINGS.INI `[desktop] toolbar=`. A theme gives the
  toolbar its colours only. The icons and their order as drawn there:
  back, forward, up, root ("/"), home | top, end | view, refresh | new
  folder, info, select all, copy, paste, delete.
- **Eighth sweep and the right button (2026-11-11):** done (DESIGN.md
  "Code sweeps"); the 1351 driver reports the right button in
  `guMouse2` (`$C0E6`, ARCHITECTURE.md "Menus and the pointer"), tested
  in VICE; the U64 check (its USB mouse) is on the user's list.
- **Toolbar, step T1 (2026-11-11):** `src/desktop/toolbar.s`. The row
  under the menu bar, the full width; view > toolbar > two lines (16
  px, framed buttons, the default), one line (8 px, the icons flat,
  dotted lines between the groups) or off; saved as SETTINGS.INI
  `[desktop] toolbar=16`, `8` or `off` (the height in pixels: the INI
  reader tells values apart by their first character, and "one" and
  "off" share theirs). The layout follows from `topY` (theme.s,
  Derive: 16 plus the toolbar's height): the sidebar, the title bar,
  the path line, the list and their colours start there. The buttons
  sit on cards (BitmapUp places bitmaps on cards): 16 px apart from x
  8, 8 px between the groups (the mock-up: x 4 and 6 px). Each button's
  bitmap is made when drawn (the frame template and the mock-up's icon
  shifted into it). Actions: up, root "/", home (FE_HOME; nothing
  without an Ultimate), top, end, view (list and detailed in turn; icons
  with the icon view), refresh, new folder, select all (all but ".."),
  copy, paste, delete; back and forward with T2 (below). Info (with
  the context menu) does nothing yet. Its colours: the theme's
  `toolbar=` line (below). Tests: d5.py (the buttons pressed, the three
  heights through the menu's routine).
  Found on the way: the boot ROM started each REU transfer by storing
  `RAM_ALL` (`$30`) at `$FF00`, inside the input driver once an earlier
  image had loaded it. Before, that hit the second byte of an
  instruction (the driver read a wrong address for its "moved" flag);
  with the right button's code an opcode sat there and the driver ran
  into garbage that wrote over the desktop's code. The boot ROM now
  writes back the byte it reads, as hibernation already did.
- **Room (2026-11-11):** the toolbar's drawing moved to overlay 5
  (tooldraw.s); the core ends at `$4EAF` of `$4FFF` with the history.
- **Toolbar, step T2 (2026-11-11):** back and forward (history.s, core:
  `Into` records each folder, and `Into` is also called from
  overlays). The last 16 places, a ring in the REU (bank 6 at `$8000`,
  256 bytes a path; the overlays use `$0000`-`$4FFF`); going somewhere
  new after going back drops the places ahead, as a web browser does;
  the same folder twice in a row is recorded once (a check value per
  slot: the path's length and byte sum). Tests: d5.py (back, forward,
  the end of the history, a new place after back, a full ring).
- **The toolbar's theme colour (2026-11-11):** a `toolbar=ink on
  paper` line in the theme files (after `status=`) and a colour byte in
  the theme record (22 bytes now). The built-in themes give it their
  menu bar's colours, as the mock-up has it; theme files written before
  lack the line and keep the built-in colour (a file needs only the
  lines it changes). Tests: d7u64.py (Custom.ini with `toolbar=white on
  red`: the record and the toolbar's row in the colour matrix).
- **Icon view (2026-11-11):** `src/desktop/iconview.s` (core:
  `ListDraw` draws it, and overlays call `ListDraw`). A grid of 40 x 32
  cells (5 columns beside the wide sidebar, 6 beside the narrow one, 4
  rows under the toolbar), each the entry's 24 x 21 icon with its name
  centred under it and cut at the cell's edge; selected cells inverted,
  the cursor's cell framed. GEOS files show their header's own icon
  (`FE_STAT`; kept in the REU, bank 6 from `$9000`, for the first 448
  entries, read once per folder); folders, "..", drives, the
  Ultimate's roots, plain files and disk images get generic 24 x 21
  drawings (`tools/mkbigicons.py`, text art; put into the REU at the
  start from overlay 5, bank 6 at `$7000`); anything else the list's
  8 x 8 icon three times as big. The list's code does the rest: in this
  view `rows` is the cells on a page and `step` a row of cells, so
  paging, the cursor keys, the scroll strip, selection and double
  clicks work as in the list. The toolbar's view button goes list ->
  icons -> detailed. Room: the built-in themes moved to overlay 1, the
  INI and theme files' scratch into their overlays, three buffers into
  side.s's shared `text`; the core ends at `$4F3E`. Tests: d9.py.
- **Files on the Ultimate (the user, 2026-11-11):** a GEOS file pasted
  onto the Ultimate is now named as gush's `cp` names it (`name.cvt`:
  the engine gets the target folder, not a full path); opening a file
  there that is no disk image shows "Not opened here: GEOS files open
  from drives A-E: copy it to one of them first." (the user kept this
  wording); the detailed view leaves an Ultimate file's size empty
  (the Ultimate's listings give none; it showed 0), the Info dialog will
  show the real size. A user manual, docs/DESKTOP_MANUAL.md, gets a
  section on what works on which kind of drive.
- **Drive C for testing (the user, 2026-11-11):** the user's own GEOS
  software sorted into folders, `private/geoultra-apps.dnp` from
  `private/apps.toml` (tools/mkappsdnp.py; private, never committed or
  published), as a native REU drive for tests, screenshots and videos
  (MOUNTS.INI `C=`, a copy in the test folder, rebuilt and uploaded by
  `make deploy`); tests that mount use D.
- **Recent documents and disk images (the user, 2026-11-18):** a
  document on a drive with a mounted image goes into the recent list by
  the image's Ultimate path (side.s RecentAdd, imgpath.s ImgPath), so
  the entry outlives an unmount. Opening a document in a folder through
  a disk image (a recent entry, or a double-click inside an image gone
  into) goes to the drive it is mounted on, or asks "Not mounted. Mount
  it?" and then shows the drive dialog; after the mount the document
  opens from that drive (side.s OpenAt, imgpath.s ImgLocal and
  AfterMount; the image's name and the rest of the path wait in side.s's
  shared text, as an overlay keeps no bytes of its own). Test
  tests/desktop/d29u64.py (U64: the document opens from D).
- **A document on C or D (the user, 2026-11-18):** geoWrite 2.1 finds a
  document it is started with only on drive A (equal disk names) or
  else on drive B (its findDocDevice, mist64/geowrite): one on C or D
  gave "opening file". When the desktop starts a program with a document
  on C or D, it swaps drive B and that drive first (appfind.s SwapDoc,
  FE_DRVSWAP; the kernal's drvswap.s, module 118, swaps everything that
  makes a drive: the driver's tables, the folders, the disk names, the
  BAM working copy's owner, the mount table entries, image paths and
  dirty maps); EnterDeskTop swaps them back after the write-back. A task
  switched to meanwhile sees the letters swapped. Test
  tests/desktop/d30.py (VICE: a document on C, swapped, opened, swapped
  back).
- **The newest version opens a document (the user, 2026-11-18):** a
  double-clicked document starts the newest version of its application
  found in the document's folder, or on any drive A-D in the root or a
  folder right below it (appfind.s, overlay 6: FindFTypes with the
  class, the version from the permanent name's last 4 characters; the
  document's folder first among equals). GEOS 2.0's deskTop takes the
  first one, on the document's disk first: an old geoWrite 1.x work disk
  opened its documents in its own 1.x instead of geoWrite 2.1 in
  /c/Writing, which converts them. Afterwards the document's drive and
  folder are made current again (FE_SELECT), then the winner's (AppGo).
  Test tests/desktop/d28.py (VICE: a 1.x work disk on A, geoWrite 2.1 in
  /b/Writing; the user's disks, never committed).
- **Sorting (the user, 2026-11-11):** the list sorted, folders first,
  each group by name (case-insensitive), ".." on top; replaces the
  directory order of the 2026-11-06 decision (a "disk order" choice for
  hand-ordered disks may follow). The sort runs in an overlay, from
  MainLoop right after a folder is read (reading only marks the list),
  so the list is drawn once, sorted.
- **The order turned round, columns (the user, 2026-11-13 and
  2026-11-14; done 2026-11-14):** `sort=` takes a "-" in front for the
  reversed order (`sort=-date`; sortMode's bit 7, SORT_REV), folders
  and ".." still first (sort.s inverts a key's bytes after its group).
  An arrow at the right end of the path line (one list; with two panes
  the first of the letters) points down for the order as named and up
  when reversed; a click turns it round. In the detailed view a click
  on the Size or Date heading on the path line sorts by it, a second
  click reverses, a third goes back to names; the column sorted by is
  bold. Each change writes `sort=` (inifile.s SortSave) and sorts the
  list again (ClockTick, sortDue: the sort and the settings are other
  overlays than the click; two panes are both read again). Settings'
  Desktop page shows `-date` as date (choice.s leaves the "-" out); a
  choice made there is the plain order. Test tests/desktop/d18.py.
- **Done 2026-11-12 (night):** copy, paste, move and delete onto drive
  C tested on the U64 (tests/desktop/d10u64.py); sorting (sort.s,
  overlay 6; tests/desktop/d11.py); docs/DESKTOP_MANUAL.md. The core ends
  at `$4FDC`: the context menu needs room made first.
- **Context menu and Info (2026-11-12):** `src/desktop/ctxmenu.s`,
  overlay 7. The right button (guMouse2's press bit, read in ClockTick
  from MainLoop) selects the entry under the pointer unless it is
  selected, then a menu at the pointer: open, copy, cut, paste, rename,
  delete, info, favourite, new folder, drawn on the foreground only in
  the menu bar's colours (closing it recovers the background and the
  shadow colours); the item under the pointer inverted; a left click
  picks the item where the pointer is at that moment; outside, RUN/STOP,
  ESC or the right button close it. The overlay returns the item and the
  core does it (list.s RightPress; most actions are overlay 2's). Info
  (the menu and the toolbar's info button): name, kind (the GEOS type's
  name), size (blocks; on the Ultimate bytes or KB from FE_STAT), date,
  class, in a dialog. Room: the clock's drawing moved to overlay 5;
  seven overlays fill bank 6 up to the generic icons at `$7000` (an
  assert in ovl.s). Tests: d12.py (VICE, the right button through the
  joyport simulation), d12u64.py (Info's size of an Ultimate file).
- **Menus and the gush button (the user, 2026-11-12):** every toolbar
  action also in the menus: geos (GeoUltra info, settings, gush, print
  queue (2026-11-15), the desk accessories; the name "geos" kept: the user's decision, applications
  draw their own menus anyway), file (open C=O, info C=I, copy C=C, cut
  C=X, paste C=V, delete DEL, rename C=R, new folder C=N, select all C=A,
  favourite C=F), view (theme, view, clock, toolbar, refresh), go (new:
  back C=cursor left, forward C=cursor right, up, root, home, top, end),
  disk (refresh). A gush button as a fifth toolbar group.
- **Two panes (the user, 2026-11-12):** side by side, 160 pixels each,
  the sidebar hidden while two panes are on; each pane its own path
  line and title, the active one highlighted; copy, cut and paste as
  now in the active pane, plus copy and move to the other pane (file
  menu, context menu, C=T and C=M); drag and drop as well: a press on a
  selected entry and a move drags it (a sprite with its icon), a
  release over the other pane or a sidebar folder or drive copies (other
  drive) or moves (same drive), C= held the other way. Drag and drop
  works on folders (with everything in them) and on selections of
  several files and folders (the user, 2026-11-12), through the same
  copy and move code as paste.
- **Settings tool (the user, 2026-11-12):** its own application
  "GeoUltra Settings" on drive E in assembler, started from the geos
  menu, a toolbar button (the user, 2026-11-12: both; the button takes
  home's place, next to gush; home stays in the go menu) and gush
  (structure and steps: docs/SETTINGS.md); first version: the theme editor (each line, the
  desktop's look as preview, saved as a theme file), desktop (default
  desktop, view, toolbar, clock), system (turbo and the slow list,
  hibernation delay, NTP server and time zone), mouse pointer designs.
  Also the system's own settings (the user, 2026-11-12): the REU (the
  size GEOS applications see) and the drives (which images on A-D,
  their sizes, long names).
- **Two panes, the steps (2026-11-12):** the core has 89 bytes left and
  the list code assumes one list (its edges and the scroll strip's
  place are constants; one path, cursor, selection and entry table).
  P1, room: the list's mouse and key handling (ListPress, ListKey,
  PathPress, Double, Range: about 700 bytes) into an overlay, "open"
  handed back to the core (Open can mount: overlay 3). P2, the list's
  geometry in variables (left, right, the strip) for the full width, the
  list beside the sidebar, or a pane. P3, a pane's state (path, count,
  top, cursor, selection, history position) kept for the other pane in
  the REU and swapped when the active pane changes; the entry tables
  1024 entries each (pane 1 banks 1-2, pane 2 banks 3-4). P4, drawing
  two panes (the sidebar hidden, view > two panes, SETTINGS.INI), a
  click activating a pane. P5, copy and move to the other pane (file
  and context menus, C=T, C=M). P6, drag and drop (a sprite with the
  icon; folders and selections through the paste code).
  **P1 done (2026-11-12):** listin.s, overlay 8 (ListPress, ListKey,
  PathPress, Double, Range, the strip's line and page steps); "open"
  goes back to the core through openReq (desktop.s OpenReq after Press
  and Key); REU bank 6 rearranged for an eighth overlay (overlays
  `$0000-$7FFF`, history `$8000`, icon cache `$9000-$FDFF` for 440
  icons, generic icons `$FE00`). The core ends at `$4CDE` (801 bytes
  free). **P2's places:** LIST_RIGHT (17 uses) and STRIP_LEFT (18) in
  list.s, listin.s and iconview.s become variables set by Derive; the
  scroll strip's drawing (list.s around Strip) assumes x >= 256
  (`STRIP_LEFT + 1 - 256` and the like) and needs rewriting for a strip
  at x 152; the detailed view's columns (COL_SIZE, COL_DATE,
  COL_NAME_END) are fixed x positions (in a 160-pixel pane: the list
  view, to be decided in P4).
  **P2 done (2026-11-12):** the list's edges are variables (theme.s:
  stripL, listR, paneR; their start values the full list beside the
  sidebar): the clear, the path line's underline, the title's centring
  and span, the selection bar, the name clip, the strip (rewritten for
  any x: its card, line and thumb from stripL), the strip's hit test
  (listin.s), InList, the icon grid's width. P4 sets them per pane.
  **P3 done (2026-11-12):** a pane's state (path, count, top, cur, its
  entry table's bank, the selection) is exchanged with the other
  pane's in the REU by SwapPane (SwapRAM; bank 5 from `$FC00`, after the
  clipboard, now 1008 names); PaneInit at the start gives the other pane
  "/" and an empty table in banks 3-4. A pane holds up to 1024 entries
  (was 2048 for the single list); the selection is 128 bytes (ClearSel
  and SelCount bounded to it). Still to handle in P4: the icon cache
  belongs to one pane's entries (forget it on a swap), the file
  engine's current folder (FE_CD to the pane's path when it becomes
  active), the history (one for both panes for now).
  **P4 done (2026-11-12):** panes.s (core): view > two panes, C=P and a
  toolbar button (view group) switch them; Draw reads and draws the
  other pane first (sorted on the spot), then the active one; a click in
  the other pane or C=SPACE makes it active (the file engine's folder
  and the free space follow). No title bars in two panes (the user,
  2026-11-12): the path lines name the folders, the active pane's
  inverted. The list view in panes (the detailed view refused; the
  icon view works, 3 columns); the view and the title bar come back when
  two panes go off. (Kept in SETTINGS.INI since: below.)
  **P5 done (2026-11-12):** copy to other (C=T) and move to other (C=M)
  in the file menu and the context menu: copied or cut to the clipboard,
  pasted with the other pane active, back, this pane read again.
  **The status line per pane (the user, 2026-11-12):** with two panes
  each pane's half shows its entries (or the number selected) and its
  drive's free space ("B: 98 KB"); a gap at x 159-160 continues the
  divider (the user). The free space is part of a pane's state
  (SwapPane's fourth part, bank 5 `$FF00`). The core has 50 bytes left:
  P6 (drag and drop) needs room made first.
  **P6 done (2026-11-12), without the sidebar:** room first: ListEnd and
  SelAll moved into overlay 8 (stubs in ovl.s). listin.s Drag: a press
  on a selected entry followed by a move of 5 pixels with the button
  held drags the selection, the entry's 8 x 8 icon as sprite 2 beside
  the pointer; the release asks the core for the drop (dropReq,
  desktop.s DropDo): on the other pane, CopyOther or MoveOther (the
  same drive, by the paths' first parts: a move; another drive: a
  copy); on a folder entry of the same list that is not selected, the
  selection cut (or copied) and pasted into it (path extended by its
  name, then back). C= held at the release: the other way. A press
  that does not move stays a click (and a double click). After a paste
  into the other pane, that pane is sorted on the spot (it is drawn as
  the inactive one, and SortNow only sorts the active pane); the
  progress text keeps to the active pane's half of the status line.
  The VICE test drags gush into the other pane (moved) and F1 onto a
  new folder (moved into it); the sprite itself and C= are hand tests.
  **Sidebar drops (2026-11-12):** with one list, a drop on a drive line
  (A-E, usb0, usb1, sd) or a favourite goes into that folder (recent
  documents are no target). listin.s builds every target's path in
  dropPath (`text + 1024`: Paste uses only text's first 256 bytes); the
  core's DropDo exchanges path and dropPath around the paste, which
  took the path building out of the core. **The drop target marked
  (2026-11-12):** while dragging, the folder row or sidebar line under
  the pointer is inverted (listin.s Hover, MarkTo); the icon view gets
  no mark yet.
  **Two panes kept (2026-11-12):** SETTINGS.INI `[desktop] panes=1` or
  `2`, written when two panes are switched on or off (inifile.s
  PanesSave), read at the start (DeskRead: wantPanes; side.s SideLoad
  calls panes.s PanesOn before the first drawing). The other pane starts
  at "/"; its folder is not kept. Test: d14u64.py on the U64 (the
  user's SETTINGS.INI set aside and restored).
- **Design answers (the user, 2026-11-12, second round):**
  - *Two panes:* the list view in each pane (the detailed columns do not
    fit 160 pixels; the chosen view returns when two panes go off; the
    icon view in a pane: 3 columns). On and off: view > two panes (a
    mark), C=P, and a toolbar button in the view group (the later
    groups move along; gush at x 296-311). A click in a pane, or
    C=SPACE, makes it the active one.
  - *Drag and drop:* a drop on a folder entry (in the same list), on a
    sidebar folder or drive line, or on the other pane puts the dragged
    entries into it: same drive moves, other drive copies, C= held the
    other way.
  - *The settings application:* pages with a side list (Theme, Desktop,
    System, Drives, REU, Pointer), the page's settings on the right as
    GEOS icons and fields, OK, Cancel and save at the bottom, in the
    theme's look.
  - *Theme editor:* colours from 16 swatches (in the theme's palette)
    for ink and paper, plus a colour's RGB value for themes with a
    palette (Ultimate 64); a small desktop mock on the page's right half
    as preview, redrawn at each change.
  - *System:* the slow list edited by picking applications from the
    GEOS drives (their permanent names; up to 6), remove; time: the NTP
    server with a "now" button, the time zone and summer time
    (automatic EU rule or off), date and time by hand.
  - *Drives:* the images at the start (MOUNTS.INI, chosen from the
    Ultimate's folders), a DNP's size in tracks (with the REU room
    left), long names on or off per drive, a new empty image
    (D64/D71/D81/DNP).
  - *REU:* the legacy REU size applications see, a map of the 16 MB
    (system, drives, tasks, applications, free), the number of task
    slots (once tasks exist).
  - *Pointer:* 4 own designs: a classic arrow, a large arrow, a hand, a
    crosshair; applied at boot.
- **The print queue (2026-11-15; docs/DESIGN.md "Print spooler",
  the user's decisions):** `src/desktop/spool.s`. The menu bar shows
  "printing 2/5, 45%" (job 2 of the 5 since the queue was last empty,
  45% of it printed: `FE_SPOOL` 0's r1H, from its pages and rows played;
  without the percentage before its first page starts; the user's
  request of 2026-11-16) or "print paused" right of the menus and left
  of the date (the status line has no room with two panes); where that
  does not fit (a 12-hour clock) "print 45%" (or "print 2/5") or
  "paused"; nothing when the queue is empty. The
  core asks `FE_SPOOL` once a second (SpoolTick, from ClockTick) and
  keeps the state; overlay 5 (with the clock, whose clearing covers the
  indicator) draws it. A click on it, or geos > print queue, opens the
  queue window (x 48-271, y 24-167): the title (with "paused" or
  "printer error"), a line per job (5 at most) with its cancel button,
  its place, the program, its pages and its state (the percentage
  printed, or "printing" before the first page; paused, waiting,
  cancelled), then pause or resume and close. The window is opened
  again after each button and when the queue changes while it is open
  (its own appMain, QTick; the percentage in steps of 8, so it is not
  drawn anew for every row), so it follows the queue; the indicator
  with it. Test: d26.py (VICE, 10 checks).
- **Choosing the printer (2026-11-16; docs/DESIGN.md "Printing", the
  user's decisions):** at its start the desktop puts SETTINGS.INI's
  `[desktop] printer=` into PrntFilename ($8465, the name applications
  load the driver by), or GU Epson FX-80 (drive E) when none was ever
  chosen. Opening a printer driver (a double click, RETURN) makes it the
  printer, as GEOS 2.0's deskTop did: PrntFilename and `printer=` set,
  a note "<name> is the printer now." (inifile.s UsePrinter, overlay
  4); the context menu's first item reads "use as printer" for a
  printer driver (it runs the same Open). Settings' Printing page sets
  it too. Applications find the driver on their own drive or on drive
  E (GetFile falls back to E). Test: d27.py (VICE, 6 checks).
- **Next, in this order:** two
  panes (the user, 2026-11-11: after the context menu, as both are about
  moving files between places); the settings tool (the theme editor,
  pointer designs, turbo and slow list, NTP and clock, the default
  desktop); the Classic style (dropped 2026-11-13).

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
