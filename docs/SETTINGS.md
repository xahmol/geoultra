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
- **S4, the Theme page:** the theme editor (themefile.s's parsing
  shared, the mock preview, palettes).
- **S5, the Drives page:** MOUNTS.INI, DNP sizes, long names, new
  images.
- **S6, the REU page:** the legacy size, the map, task slots (the slots
  once tasks exist).

Beta 1 needs S1-S6's first versions (docs/DESIGN.md, "Releases").
