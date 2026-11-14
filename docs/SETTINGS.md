# GeoUltra Settings: design

GeoUltra Settings is the application for GeoUltra's own settings: the
theme editor, the desktop, the system, the drives, the REU and the mouse
pointer. It writes the files the system and the desktop already read
(`GEOULTRA/SETTINGS.INI`, `GEOULTRA/MOUNTS.INI`, the theme files in
`GEOULTRA/THEMES`), so nothing it sets depends on the application being
there. The user's decisions are in docs/DESKTOP.md ("Settings tool",
"Design answers"); this document holds the structure and the steps.

## Decisions (the user, 2026-11-12)

- Its own GEOS application, "GeoUltra Settings" (class `GU Settings`),
  on drive E in assembler (ca65/ld65), like the desktop and gush.
- Started from the desktop's geos menu ("settings"), a toolbar button
  (it takes the home button's place, next to gush; home stays in the go
  menu) and from gush.
- Layout: a side list of pages on the left (Theme, Desktop, System,
  Drives, REU, Pointer), the page's settings on the right as GEOS icons
  and fields, OK, Cancel and Save at the bottom; in the theme in use
  (since 2026-11-14, src/settings/chrome.s): a frame round the screen,
  the title bar in the theme's title bar style and colours (stripes
  with a gap for "GeoUltra Settings", solid, line, none), the side list
  in the side bar's colours with the current page marked as the
  theme's selection (invert, bar, frame), the page in the desk's
  colours, the buttons' strip in the menu bar's, the border colour;
  dialogs over the desk's colours. The Theme page's "use" draws
  Settings again in that theme at once.
- **S3 decisions (the user, 2026-11-12):** the time gets its own page,
  **Time**, after System (seven pages: Theme, Desktop, System, Time,
  Drives, REU, Pointer); System keeps turbo, the slow list and
  hibernation. Turbo: a row "full speed / off / step" and a stepper
  "[-] step [+]" over the 16 steps, shown in MHz (both U64 kinds, as
  gush's `turbo`), applied at once (FE_TURBO) and saved (`turbo=N`,
  `turbo=off`, no key for full speed). The time zone: the UTC offset
  with [-] and [+] in 15-minute steps (`[time] offset=` seconds) and
  summer time "EU rule / off" (the EU rule is new kernal work: the
  last Sundays of March and October, 01:00 UTC). Hibernation: a row
  off, 15 s, 30 s (the default), 1 min, 5 min (`hibernate=0/15/30/60/
  300`).
- **From GeoDesk64's settings (the user, 2026-11-12, after reading
  the GeoDesk64 manual and the GDOS64 FastBoot guide; behaviour only,
  own code, credited where derived):** adopted as settings: copy
  conflicts (ask, today's behaviour / replace / skip / only newer, a
  sync), ask before deleting (yes / no; the question for folders with
  contents stays), the sort order (name / date / size / type, folders
  first), the pointer's colour (Pointer page), GEOS's own colours for
  programs' dialogs, menus and file selector as theme lines (S4), icon
  colours by GEOS file type (a theme option, S4), a background picture
  (a geoPaint picture behind the desktop; later). Adopted without a
  setting: two panes come back with both panes' folders; the list is
  read again after every desk accessory. On the roadmap: pinned
  programs in the sidebar (as GeoDesk64's AppLinks), undelete (deleted
  files shown and restored when not overwritten). Not taken: the
  printer and input driver choice, the icon cache options, GDOS's
  driver configuration, a "save settings" command (GeoUltra writes at
  once), FastBoot (GeoUltra starts from its cartridge and hibernates).
- **The GeoDesk64 items done (2026-11-12):** both panes keep their
  folders (inifile.s PanesKeep writes `[desktop] pane2=` when it
  changed, from the core's new Leave before every program or desk
  accessory; DeskRead puts it back into the other pane's state; the
  pane in use is the file engine's current folder and comes back on
  the left); the list is already read again after a desk accessory
  (Back draws and reads it); the sort order `sort=name|date|size|type`
  (sort.s Lead: date newest first, size largest first, type by GEOS
  type; folders first in all); `copy=ask|replace|skip|newer` (tree.s
  CopyFile: skip leaves a moved file in place; newer compares the GEOS
  dates, an undated file never newer); `delete=ask|now` (the folder
  question stays). The Desktop page has the rows Sort by, Existing and
  Delete. The desktop's core has 2 bytes left (`deskPrefs`, `sortMode`
  and `Leave` took the rest): new desktop features need room made
  first. The pointer's colour (2026-11-12): `[system] pointercolour=`
  0-15 at boot (mount.s), FE_POINTER's r2H at once; kept in the INFO
  block (`$C0F3`, the free bytes after GeoUltra's own fields), which
  module 0 gives sprite 0 at each program's start (it held a fixed
  blue); the Pointer page's colour row with - and +, the theme files'
  colour names. Still to do of the list: the theme items (S4), the
  background picture.
- **S4 decisions (the user, 2026-11-13):** the Theme page in compact
  rows: Theme [-] name [+] with "use" and a new copy; Part [-] name
  [+] (the theme file's lines); the part's style as a choice row; Ink
  and Paper as 16 swatches each; a preview strip across the page under
  them (a mini desktop: menu bar, sidebar, rows, status), redrawn at
  each change. The palette's RGB editing in S4 too (a colour picked,
  its R, G, B with - and +, sent to the Ultimate 64 at once). GEOS's
  own colours: a theme line `programs=ink on paper` that every program
  gets at its start (the kernal's screencolors, one colour pair as in
  GEOS 2.0; dialogs and menus inside programs keep it; colouring those
  separately, as MegaPatch, would need resident kernal room). Icon
  colours by GEOS file type: a theme option in the icon view only (list
  rows of 9 pixels share the C64's 8 x 8 colour cells).
  Steps: S4.1 the theme format's tables shared (src/inc/themedef.inc,
  the desktop's themefile.s and the editor); S4.2 ini.inc on more than
  one text (a theme file beside SETTINGS.INI); S4.3 the editor (theme,
  part, style, swatches, preview, save, use, new copy); S4.4 the
  palette's RGB; S4.5 programs= in the kernal; S4.6 icon colours by
  type (the desktop's core needs room first).
  **S4.3 done (2026-11-13):** the Theme page (ptheme.s, overlay 5): the
  THEMES folder listed, the theme in use first; Theme [-] [+] (unsaved
  changes: asked), "use", "copy" (a new name: its file at Save); Part
  [-] [+] over themedef.inc's lines; the style row laid out by measured
  widths; Ink and Paper as 16 coloured cells, the chosen one framed;
  the preview (border, menu bar, toolbar, sidebar, heading, list, a
  selected row, status) in colour cells. The theme's text is the core's
  second (UseTheme), written by Write as THEMES/<name>.ini. Fixed on
  the way: inifile.inc renamed the temporary file to the whole path
  (THEMES/x.ini), which FE_RENAME refuses after the old file was
  already deleted; it now passes the name's last part (SETTINGS.INI
  was not affected). Tests: s4.py (8 checks in VICE), s4u64.py
  (Custom.ini on the U64: only its border line changed; restored).
  **S4.4 done (2026-11-13), the palette:** the part after the lines;
  the paper row picks the colour to change, the style row holds R, G,
  B with - and + (steps of 4) and "none" (palette= out, the
  Ultimate's own palette back). A theme without palette= starts from
  the Ultimate's palette now (GET_PALETTE), in VICE from the U64's
  default (DefaultPal, read from a U64-II). Each step goes to the
  Ultimate at once (SET_PALETTE_COLOR) and rewrites palette= (16
  RRGGBB, as the desktop reads it). (The overlay had 76 bytes left
  then; 831 since the theme parser moved to the core, 2026-11-14.)
  **Delete (2026-11-14):** a "delete" button left of the preview
  deletes the theme shown, its file at once, after a question; not the
  theme in use ("This theme is in use. Use another one first.") and not
  the last one. Test: s46u64.py. Tests: s4.py
  (VICE, 11 checks), s4u64.py (the change seen live with GET_PALETTE,
  palette= written and taken out; files restored).
  **S4.5 done (2026-11-13), programs=:** the theme line for the screen
  programs get (GEOS's screencolors): the desktop gives it to the
  kernal's progColours (info.s, $C0F4) when it takes a theme, and
  FirstInit gives it every program (default dark grey on light grey,
  as before). The Theme page lists it as a part after the lines'
  colours. Tests: s4.py (the part's index), s45u64.py (on the U64: a
  test theme with programs=white on blue, the kernal's byte and GEOS's
  screencolors after a boot; files restored). The same day, from the
  user's hand test: the Theme page's dialogs are drawn over the page's
  plain colours (the swatches no longer show through), the preview has
  a frame, and a "palette" button on the Part row goes to the palette.
- Pages:
  - *Theme:* the theme editor: each line of a theme file; colours from
    16 swatches (in the theme's palette) for ink and paper, plus the RGB
    value of a colour for themes with a palette (Ultimate 64); a small
    desktop mock on the page's right half, redrawn at each change; saved
    as a theme file.
  - *Desktop:* the view, the toolbar, the clock, two panes, the sort
    order, existing files, deleting (the choice of GEOS 2.0's deskTop
    removed 2026-11-13: GeoUltra's desktop only, the user).
  - *System:* turbo and the slow list (applications picked from the
    GEOS drives by their permanent names, up to 6; remove); the
    hibernation delay; time: the NTP server with a "now" button, the
    time zone and summer time (the EU rule or off), date and time by
    hand.
  - *Drives:* the images at the start (MOUNTS.INI, chosen from the
    Ultimate's folders), a DNP's size in tracks (with the REU room
    left), long names on or off per drive, a new empty image (D64, D71,
    D81, DNP).
  - *REU:* the legacy REU size applications see, a map of the 16 MB
    (system, drives, tasks, applications, free), the number of task
    slots (once tasks exist).
  - *Pointer:* 4 own designs: a classic arrow, a large arrow, a hand, a
    crosshair; applied at boot.

## Behaviour

- **OK** writes what changed and leaves (to the desktop, which reads
  its settings anew when it starts); **Save** writes and stays;
  **Cancel** leaves without writing (asking first when something
  changed). Changes are kept in memory until then, across pages.
- Settings that act at boot (the pointer, turbo, the drives at the
  start, the REU size, task slots) say so on their page ("from the next
  start"); the ones the kernal can take at once (the turbo step, the
  time, the pointer) are also applied at once.
- Without an Ultimate (VICE) the pages show the defaults and nothing is
  written (as the desktop does).

## Structure

- `src/settings/`: a VLIR application like the desktop: record 0 the
  core at `$0400` (the frame, the page list, the buttons, the INI text
  in memory, the drawing in the theme's colours), one overlay per page
  at `$5000-$5FFF` (records 1-6), loaded once into the application's
  REU bank 7 by `src/inc/ovlcore.inc` (as gush; drive E's programs
  each rebuild their REU state when started). `$6000-$7F3F` is GEOS's
  background screen (used for menus and dialogs).
- **`src/inc/ini.inc`, shared**: SETTINGS.INI (and MOUNTS.INI, theme
  files) read whole into a buffer (at most 2048 bytes; 3072 until 2026-11-13), then
  edited there: `IniFind` (a section and a key: the value's place),
  `IniSet` (a key's value replaced, or the line added at its section's
  end, the section added at the file's end when missing; other lines
  kept as they are, with their line ends), `IniDel`; written back as a
  temporary file that then takes the old one's place (as gush's
  `turbo -s` and the desktop do), so a failed write never leaves half a
  file. The routines work on the buffer only, so VICE tests cover them
  without an Ultimate; reading and writing the file are separate
  routines. gush's `sysset.s` and the desktop's `inifile.s` move onto it
  later (their own copies of the same work), each in its own commit.
- The theme: the core (chrome.s) lists THEMES, reads the theme in use
  at the start and parses its lines (ReadLine; moved from the Theme
  page's overlay on 2026-11-14), so Settings draws itself in it; the
  Theme page uses the same routines for the theme it shows.

## Steps

- **S1, the frame and the Desktop page:** the application on drive E,
  its start from the geos menu, the toolbar (home's place) and gush;
  the side list, OK, Cancel, Save; `ini.inc` with VICE tests on a
  buffer; the Desktop page (default desktop, view, toolbar, clock, two
  panes). Tests: the frame in VICE (pages switch, buttons), the INI
  routines in VICE, the Desktop page's writing on the U64 (the user's
  SETTINGS.INI set aside and restored, as d14u64).
  **S1 done (2026-11-12):** `src/inc/ini.inc` (IniFind, IniSet, IniDel;
  21 checks in VICE, tests/settings/ini.py) and `src/inc/inifile.inc`
  (IniPaths, IniLoad, IniSave through `SETTINGS.TMP`); the application
  `src/settings/` ("GU Settings" on drive E: GEOS names hold 16
  characters, the title says "GeoUltra Settings"): the frame, the side
  list, OK, Cancel (asking when changed), Save; choice rows (choice.s)
  as the pages' widget; the Desktop page (overlay 1). The desktop starts
  it from geos > settings and the toolbar (settings in home's place,
  next to gush); gush with `"/e/GU Settings"`. Test:
  tests/settings/s1.py (10 checks in VICE), s1g.py (gush), and on the
  U64 s1u64.py (6 checks: a test SETTINGS.INI with a comment and a
  [favourites] section, two options clicked, Save writes the two keys
  and keeps every other line byte for byte, OK starts the desktop with
  the new view; the user's SETTINGS.INI set aside and restored). The
  frame's colours follow the theme in S4.
- **S2, the Pointer page:** 4 designs in the kernal (own drawings),
  `[system] pointer=` read at boot, applied at once from the page.
  **S2 done (2026-11-12):** tools/mkpointers.py draws the designs (text
  art: a classic arrow, the kernal's own, a large arrow, a hand, a
  crosshair; each with its hot spot); the kernal's module 86
  (src/kernal/pointer.s) copies one into the pointer picture and sprite
  0 and sets PosPointer's offsets (24 and 50, less the hot spot: their
  operands, no new resident code); DrawSprite on sprite 0 (an
  application's own pointer) puts the offsets back, as GEOS 2.0 places
  it (14 resident bytes). Read at boot (mount.s PointerInit, after the
  modules are there) and applied at once by FE_POINTER (31, r2L = the
  design). The page (pptr.s, overlay 2): one choice row with each
  design's picture under it. Tests: s2.py (7 checks in VICE: the page,
  the INI text, sprite 0 and the offsets per design, DrawSprite's
  reset), s2u64.py (pointer=3 at boot on the U64); conformance 301 of
  301. A design lasts until an application draws its own pointer (as
  the arrow did before).
- **S3, the System page:** turbo and the slow list, hibernation, NTP
  and the time zone, date and time by hand.
  **S3 done (2026-11-12), the System page:** psys.s (overlay 3): turbo
  (full speed / off / step, the stepper in MHz for both U64 kinds,
  applied at once by FE_TURBO), the slow list (up to 6 names from the
  repeated slow= lines; add through GEOS's file dialog on drives A-D,
  the permanent name's start without its trailing spaces; remove the
  selected one), hibernation (off / 15 s / 30 s / 1 min / 5 min). New
  in the core: widgets.s (buttons with labels centred by measured
  width), choice options without a value (the key taken out: "full
  speed"). The Time page is S3b. Test: s3.py (9 checks in VICE).
  **S3b done (2026-11-12), the Time page:** ptime.s (overlay 4): the
  server (typed in GEOS's input dialog; empty: ntp= taken out), "now"
  (the settings written first, as the kernal reads [time] from the
  file, then FE_NTP), the zone with - and + in quarter hours from
  UTC-12:00 to UTC+14:00 (offset= seconds), summer time EU rule / off
  (summer=), the date and time typed as YYYY-MM-DD HH:MM (checked,
  then GEOS's clock and FE_SETTIME). The kernal: [time] summer=eu read
  in module 79; module 78 works out the UTC date first and adds an
  hour in the EU's summer time (the last Sundays of March and October
  at 01:00 UTC, the decision in module 79 for room). Found on the way:
  module 78's month loop skipped over a 3-byte instruction with a
  2-byte `bit`, so every date from February in a leap year came out
  as month 109 (2028 the first one hit; confirmed with the old code,
  fixed). Tests: tests/engine/dst.py (12 checks in VICE: both switches
  of 2026 to the second, summer and winter days, the rule off, a
  negative offset, February 2028), s3b.py (9 checks in VICE),
  s3bu64.py ("now" with pool.ntp.org on the U64: the clock right).
  **Changed 2026-11-13 (the user's hand tests and decisions):** the
  server from a list (time.google.com, time.windows.com, pool.ntp.org,
  custom); a zone step moves GEOS's clock by 15 minutes at once, summer
  time switched by an hour in the EU's summer time (clock.inc, shared
  with the desktop); "now" inverted while it asks. GeoUltra no longer
  writes the Ultimate's clock (its SET_TIME stored an hour less; its
  firmware keeps it with SNTP): a time changed here is kept as `[time]
  adjust=` (minutes from the Ultimate's clock, within 21 days), which
  the desktop adds after every cold start (the kernal's mark at $C0FB);
  "now" takes it out. Tests: s3b.py (13 checks), s3cu64.py (U64).
- **S4, the Theme page:** the theme editor (themefile.s's parsing
  shared, the mock preview, palettes).
- **S5, the Drives page:** MOUNTS.INI, DNP sizes, long names, new
  images.
- **S6, the REU page:** the legacy size, the map, task slots (the slots
  once tasks exist).

Beta 1 needs S1-S6's first versions (docs/DESIGN.md, "Releases").
