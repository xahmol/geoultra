# gush, the GeoUltra shell (design proposal, step 1)

Status: **approved by the user, 2026-11-04** (the questions answered,
see "Decisions" at the end). Built on the decisions in docs/DESIGN.md
("Shell: gush", "gush and file engine decisions", "Languages") and on
the file engine (docs/FILE_ENGINE.md, steps E1-E3 and L). This document
settles what step 1 builds and how.

## What step 1 is

A full-screen GEOS application (assembler, ca65/ld65) with a text
console, a line editor and about 15 commands over the whole tree:
GEOS drives A-D (with folders and long names), drive E and the
Ultimate's file system. Starting GEOS applications by name. No scripting
yet (step 3), no CVT and no mount (step 2, with engine step E4); `cp`
between GEOS drives and the Ultimate is raw, as the engine does it now.

## Screen

- The 320x200 hi-res screen of GEOS, drawn directly into the bitmap with
  gush's own font: 6 pixels wide, 8 high (5x7 glyphs with a gap), so
  **53 columns and 25 rows**. Drawing through GEOS's `PutChar` would be
  slow and proportional; a monospaced console needs its own glyphs. The
  font is GeoUltra's own (clean-room, like the system font; ASCII 32-126
  plus a cursor block).
- Row 0 is a status line (inverted): the current directory, cut from
  the left when long, and the time. Rows 1-24 scroll.
- A text shadow of the screen (53x24 characters) in memory: scrolling,
  redrawing after a dialog or an application, and the tests read it.
- Scrolling moves the bitmap up by one text row (2560 bytes of the 8000;
  about 40 ms at 1 MHz, shorter with turbo).

## Keys and the line editor

GEOS hands keys to `keyVector` (codes from docs/GEOS_REFERENCE.md, 10).
GEOS ignores CTRL; gush looks at the CTRL key itself in the keyboard
matrix when a key arrives (no kernal change, other applications keep
GEOS 2.0's keyboard).

| Key | In gush |
| --- | --- |
| letters, digits, signs | typed at the cursor (insert mode) |
| RETURN | the line is run |
| DEL (KEY_LEFT/BACKSPACE) | the character before the cursor off |
| INST (KEY_INSERT) | the character under the cursor off |
| cursor left / right | the cursor along the line |
| cursor up / down | history: the older / newer line |
| HOME / CLR | the cursor to the start / the screen cleared |
| `<-` (KEY_LARROW) | completion: the name under the cursor completed from the folder's listing (a list when more fit) |
| CTRL+A, CTRL+E | start / end of the line |
| CTRL+K, CTRL+U | the line cut after / before the cursor |
| CTRL+C, RUN/STOP | the line dropped; a running command stopped (`cp`'s progress routine, `ls`, `more`) |

The input line is at most 254 characters (it scrolls sideways when it is
longer than the screen row). History: the last 32 lines, kept in the
application's REU (GeoUltra gives every application its own REU area
through `DoRAMOp`), so gush's own memory stays free.

## Syntax (step 1)

- Words separated by spaces; `"..."` and `'...'` keep spaces, `\` takes
  the next character as it is.
- `*` and `?` in the last part of an argument: replaced by the matching
  names (the engine's `FE_OPENDIR` patterns: on GEOS drives exact and
  case-sensitive, on the Ultimate case-insensitive), in listing order;
  none: the word stays as it is (as in `sh`).
- Paths as the engine takes them: `/a/...`, relative to the current
  directory, `.` and `..`; long names and short names both work.
- Options as single letters after `-` (`-l`, `-f`, `-r`), before the
  other arguments.
- Errors: the engine's error as text (`gush: cp: /a/x: file exists`),
  and the line's status for later (`$?` in step 3).

## Commands (step 1)

| Command | What it does |
| --- | --- |
| `ls [-l] [path...]` | listing; `-l` with type, size, date, and the short name when it differs |
| `cd [path]` | the current directory (none: the drive the system started from) |
| `pwd` | the current directory |
| `cp [-f] [-r] source... target` | copy (several sources: the target is a folder); asks before overwriting unless `-f`; raw between GEOS drives and the Ultimate (CVT in step 2); `-r` copies folders, made by gush from listings |
| `mv [-f] source... target` | move or rename |
| `rm [-f] path...` | delete; asks unless `-f` (decision: every delete asks) |
| `mkdir path...`, `rmdir path...` | folders (on a 1581 the partition's size: `mkdir -t N`) |
| `cat path...`, `more path...` | a sequential file's bytes as text (ASCII as GEOS shows it); `more` a page at a time; VLIR files (GEOS documents) refused for now |
| `df [path]` | free and total blocks (GEOS drives) |
| `echo words...` | the words |
| `clear` | the screen |
| `help [command]` | the commands, or one command's use |
| `exit` | back to the desktop |
| a program's name | a GEOS application started (below) |

`rm` and an overwriting `cp`/`mv` ask `y/n` (`a`: all) per file.
`cp` and `mv` show a progress line for files of more than 20 blocks
(the engine's progress routine; RUN/STOP cancels).

## Starting programs

A word that is no command and names a GEOS application (by path, or by
name along `PATH`: for now `/e/bin`, then the current directory) is
started the way the desktop starts one: its drive made current, its
folder entered, `GetFile` by its short name. gush is replaced (as by the
desktop); with the task switcher later it stays as a task. A document
after the name (`geoWrite letter`) is passed as the desktop does
(`r0`/`r2`/`r3`, the data disk's name). Desk accessories run on top of
gush and come back to it.

## Where gush lives

On drive E (the system drive in the cartridge) as `gush` and in
`/e/bin`'s place for now (drive E is flat); a copy on any disk runs as
well. Reached by a boot setting (`SETTINGS.INI`: start gush instead of
the deskTop), by a gush button in geoFolder (from any application,
also under GEOS 2.0's deskTop), and later by a menu item and button in
GeoUltra's own desktop.

## Memory and build

- Application space `$0400-$5FFF` (and up to `$7FFF` without the
  background screen buffer, which gush does not need: it redraws from its
  shadow). Estimate for step 1: console and font 3 KB, editor and
  history 2 KB, parser and wildcard expansion 2 KB, commands 5-6 KB,
  texts 2 KB: about 15 KB. More commands later go to VLIR records
  loaded on demand (GEOS overlays), as geoWrite does.
- `src/gush/*.s`, one ld65 configuration, built into a GEOS application
  file (sequential, then VLIR when it outgrows memory) on drive E by the
  existing system-drive build (`SYSFILES`, as geoFolder).

## Tests

- VICE (like the engine tests): gush started from drive E, keys put into
  GEOS's key queue, the screen's text shadow read back: every command,
  quoting and wildcards, the editor keys, history, completion, `rm`'s
  question, errors; the files checked through the engine and in the
  images (Python), as tests/engine does.
- The U64 (feu64.py): the same on `/usb0` (in `/USB0/GEOULTRA/test`),
  and starting an application from a long-named folder.

## Order of work

1. The application frame: start, screen, font, the status line, the
   text shadow, scrolling, exit.
2. The line editor and history; key tests.
3. The parser: words, quotes, wildcards; `echo`, `pwd`, `cd`, `ls`.
4. The file commands: `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `cat`,
   `more`, `df`, with the questions and the progress line.
5. Starting applications; `help`, `clear`; the boot setting and the
   gush button in geoFolder.
6. U64 run, code sweep, docs (a gush manual: `docs/GUSH_MANUAL.md`).

## State of the work

- **1.1-1.4 (2026-11-04), in VICE:** the frame (con.s: own 6x8 font,
  status line with the path and time, text shadow, scrolling), the line
  editor and history (edit.s: insert, DEL, INST, cursor keys, HOME, CLR,
  CTRL+A/E/K/U/C through the keyboard matrix, RUN/STOP, 32 lines of
  history in the application's REU bank 1, lines up to 254 characters
  scrolling sideways), words and wildcards (parse.s: quotes, backslash,
  `*`/`?` through `FE_OPENDIR`), the commands (cmds.s: `exit`, `clear`,
  `echo`, `pwd`, `cd`, `ls [-l]`; files.s: `cp`, `mv` with questions and
  a progress line, `rm`, `mkdir -t`, `rmdir`, `cat`, `more`, `df`).
  Tests: tests/gush/g1-g4.py (`make test-gush`). gush is on drive E
  (`SYSFILES`). Code about 5.5 KB, buffers 3.8 KB.
- **1.5 (2026-11-04):** `help`, starting programs (prog.s: an
  application or desk accessory by path, or by name in the current
  directory and then the roots of drives A-D; the engine's `FE_SELECT`
  makes its folder current, `GetFile` starts it; after a desk accessory
  gush redraws its screen from the shadow), the boot setting
  (`SETTINGS.INI` `[system] start=gush`: the cold start calls the
  engine's `FE_RUNSYS`, which starts an application from drive E).
  Tests: g5.py, g6.py in VICE; tests/gush/gu64.py on the U64 (the
  Ultimate's file system through gush, geoFolder started and closed;
  `make test-gush-u64`); the boot setting checked on the U64 by hand.
- **1.6 (2026-11-04):** geoFolder's gush button (drawn like the system
  icons by `tools/mkicons.py --icon`; it calls `FE_RUNSYS`, gush replaces
  the application), `cp -r` (tree.s: each folder's listing read whole
  into the application's REU bank 2 before its entries are copied, so no
  listing stays open; folders up to 8 deep, 255 entries each, 1024 in
  all; a 1581 partition made as big as its source). Tests g7.py, g8.py.
- **1.7 (2026-11-05):** a document after an application's name
  (`geoWrite letter`), passed as the deskTop passes one: `ST_LD_DATA`,
  r2 the name of the document's disk, r3 its name. Its drive and folder
  are made current first, then the program's (user, 2026-11-05: a
  document on another drive switches drives); on one drive both must be
  in one folder (checked by the file's first block, so a file of the same
  name in the program's folder does not count). Applications find their
  document's drive by the disk name (geoWrite 2.1 compares it with drive
  A's and otherwise takes drive B). Errors of gush's own: one document at
  a time, a desk accessory takes none, not in the program's folder.
  Test g9.py with DocPeek (tests/gush/docpeek.s), an application that
  keeps what it was passed; the desk accessory case in gu64.py.
- Step 1 is complete. The time stays as the clock says (GeoUltra always
  has the Ultimate's clock; only VICE counts from 00:00).
- Drive E is not yet in the file engine's tree: programs on it are not
  found by name (`/e/bin` in the design); `FE_RUNSYS` starts them by name.
- A test hook: `testCtrl` (edit.s) makes the editor take CTRL as held
  (VICE's monitor cannot hold a key); `keyQueue`, `qHead`, `qTail` are
  exported from the kernal for the tests' answers.

## Decisions (user, 2026-11-04)

1. **Font:** a new 6x8 monospaced font in GeoUltra's style (clean-room).
2. **Starting gush:** a boot setting in `SETTINGS.INI` (start gush
   instead of the deskTop) and a gush button in geoFolder, both in step
   1; GeoUltra's own desktop gets a gush menu item and button when it is
   built. A copy on a disk always works.
3. **Status line:** yes: row 0, the current directory and the time; 24
   text rows.
4. **`cd` without an argument:** the root of the drive the system
   started from (a home folder can come with `gushrc` in step 3).
5. **`cat` on GEOS documents:** VLIR files are refused in step 1 (the
   engine's streams refuse them); geoWrite as text can come later.
