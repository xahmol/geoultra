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
  and fields, OK, Cancel and Save at the bottom; in the theme's look
  (the menu bar's colours for the frame, as the desktop's dialogs).
- Pages:
  - *Theme:* the theme editor: each line of a theme file; colours from
    16 swatches (in the theme's palette) for ink and paper, plus the RGB
    value of a colour for themes with a palette (Ultimate 64); a small
    desktop mock on the page's right half, redrawn at each change; saved
    as a theme file.
  - *Desktop:* the default desktop (GeoUltra's or GEOS 2.0's), the
    view, the toolbar, the clock, two panes.
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
  files) read whole into a buffer (at most 3072 bytes, as today), then
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
- The theme: read through the same code as the desktop's theme files
  (themefile.s's parsing moves into a shared include in step S4, when
  the editor needs to write them too; until then the frame takes the
  menu bar's colours from SETTINGS.INI's theme by the desktop's rules).

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
  tests/settings/s1.py (10 checks in VICE). Still to do in S1: the
  writing on the U64 (a test as d14u64), the theme's colours (with S4).
- **S2, the Pointer page:** 4 designs in the kernal (own drawings),
  `[system] pointer=` read at boot, applied at once from the page.
- **S3, the System page:** turbo and the slow list, hibernation, NTP
  and the time zone, date and time by hand.
- **S4, the Theme page:** the theme editor (themefile.s's parsing
  shared, the mock preview, palettes).
- **S5, the Drives page:** MOUNTS.INI, DNP sizes, long names, new
  images.
- **S6, the REU page:** the legacy size, the map, task slots (the slots
  once tasks exist).

Beta 1 needs S1-S6's first versions (docs/DESIGN.md, "Releases").
