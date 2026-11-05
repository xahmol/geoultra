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

- gush is a VLIR file (since 2026-11-06, ovl.s). Record 0, the resident
  core, at `$0400-$4FFF` (to `$44F2`): console, line editor, history,
  parser, executor, variables, scripts, redirection and pipes, starting
  programs, and `cd`, `ls`, `echo`, `pwd` and the other small commands.
  Records 1 and 2, the overlays, linked at the **transient area**
  `$5000-$5FFF` (4 KB): overlay 1 the file commands (`cp`, `mv`, `rm`,
  `mkdir`, `rmdir`, `cat`, `more`, `df`, `cp -r`), the system commands
  (`mount`, `umount`, `mkimg`, `free`, `reboot`) and the history file;
  overlay 2 `turbo`, `date`, `ntp` and `test`, `[`, `read`, `true`,
  `false`. At its start gush reads both records once (its index block
  from its own directory entry, which GetFile leaves in `dirEntryBuf`;
  drive E's blocks are reachable from every drive) into its REU bank 7,
  4 KB each; a stub in the core (`jsr OvlGo / .byte overlay / .addr
  routine`) fetches an overlay from there when another one is in the
  area (a 4 KB DMA). Overlay code calls the core and its own overlay,
  never another overlay; an overlay's data is scratch (it comes back as
  built with each fetch); its BSS stays in the core. External commands
  (step 3.8) load into the same transient area, so their API is the
  core's.
- The large buffers (`HIGHBSS`: the screen shadow, the words, file
  texts, paths) in the background screen buffer `$6000-$7F3F` (to
  `$7D72`), which gush does not draw on: it draws the foreground only
  and redraws from its shadow (step 3, sub-step 0). Before a desk
  accessory starts, `$6000-$7F3F` goes to gush's REU bank 3 and comes
  back after it (prog.s, `High`), so an accessory that draws into the
  background buffer cannot harm it. A GEOS dialog or window of gush's
  own later does the same: the high area kept, the dialog shown, the
  area back, the screen redrawn from the shadow (GEOS's own recovery
  from the background buffer would show gush's data).
- gush's application REU banks: 1 the history (128 lines), 2 `cp -r`,
  3 the high area around desk accessories, 4 scripts, 5 typed lines and
  pipelines, 6 pipes, 7 the overlays: all eight in use (bank 0 is
  MoveData's scratch).
- `src/gush/*.s`, one ld65 configuration (the core to `gush.bin`, the
  overlays to `gush.bin.1` and `.2`), made into a VLIR CVT by
  geos-oscar64's `geosapp.py` (record 0 and the header) and
  `tools/vlircvt.py` (the records), on drive E by the existing
  system-drive build (`SYSFILES`, as geoFolder).

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
- **Step 2 so far (2026-11-05, on engine step E4):** `cp`/`mv` convert
  GEOS files to and from CVT on the Ultimate, `-R` raw; `cat`/`more` on
  the Ultimate (a sequential GEOS file's CVT shows its data); `mount`
  (the drives' images), `mount image /drive`, `umount /drive` (gush's own
  drive refused; its current directory moves to `/` when it was on the
  drive); `mkimg [-t tracks] type path [name]` (".type" added to the
  path when missing; the disk name the file's name unless given; a DNP
  of 16 tracks without `-t`). `help` finds its usage lines through a
  pointer now (they no longer fit one page). `free` (the drives' REU
  banks), `turbo [-s] [step]` (both MHz tables: step 15 is 48 MHz on a
  U64 or Elite I and 64 MHz on an Elite II or C64 Ultimate, which the
  register does not tell; `-s` writes `turbo=N` into SETTINGS.INI's
  `[system]`, every other line kept, through SETTINGS.TMP), `date
  [YYYY-MM-DD HH:MM[:SS]]` (GEOS's clock, the CIA's time of day and the
  Ultimate's clock; years 1980-2079). Tests g10.py (VICE) and gu64.py.
  `reboot`: every drive written back, the hibernated session dropped,
  the C64 restarted through the Ultimate (GeoUltra boots afresh).
  `reboot -u` (the Ultimate itself, decision 4) is not there: the
  Command Interface has no command for it (only the Ultimate's menu and
  its network interface can). `ntp [server]` (decision 6): the server
  given, else SETTINGS.INI's `[time] ntp=`, with `[time] offset=`
  seconds from UTC (signed; 0 without it, so a clock kept in local time
  needs it); the same at every cold start when `ntp=` is set. Tested on
  the U64 with the offset measured from the clock first, so the test
  leaves it as it was. Known (user, 2026-11-05): the U64's present
  official firmware reads its clock back in summer time (CEST instead of
  CET), so a clock set in winter reads an hour off; fixed in unofficial
  builds, accepted here. The mouse (decision 7): gush starts mouse mode
  (it had none: no pointer, no clicks), and a press on the input line
  puts the cursor on the character pressed, or at the line's end (only
  while the editor has the keys); test g11.py.
- Step 2 is complete (2026-11-05).
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

## Step 2 (decisions, user, 2026-11-05)

Step 2 is built on file engine step E4 (docs/FILE_ENGINE.md).

1. **CVT:** `cp` and `mv` between a GEOS drive and the Ultimate convert
   GEOS files to `.cvt` and back (decided 2026-11-04); `cp -R` copies
   raw instead (a `.cvt` stays a `.cvt` file on the GEOS disk, a GEOS
   file goes out as its data, as in step 1).
2. **`mount image drive`, `umount drive`:** like the mount dialogue:
   write-back on `umount`, `MOUNTS.INI` updated so the next boot comes
   back with the same images. An image of another type changes the
   drive's type; refused for the drive gush was started from and for
   drive E.
3. **`mkimg type path`:** new d64, d71, d81 and dnp images (dnp with
   `-t tracks`), formatted with a disk name; code shared with the mount
   dialogue.
4. **System commands:** `free` (REU use), `turbo` (show and set the
   U64's speed; for the session, `turbo -s N` also saves it in
   `SETTINGS.INI`), `date` (show, and set the Ultimate's clock),
   `reboot` (GeoUltra, after the write-back; `reboot -u` resets the
   Ultimate: not possible, see "State of the work").
6. **NTP (user, 2026-11-05, replacing "no `ntp` for now"):** the U64
   Elite II and the C64 Ultimate sync their clock at boot themselves;
   older U64s and the Ultimate II+ do not. One kernal overlay module,
   ported from GeoUTime (GeoUTools, the user's own code, credited): a
   boot step when `SETTINGS.INI` `[time] ntp=server` is set (off by
   default; `offset=` seconds from UTC), and `ntp [server]` in gush for a
   sync by hand.
7. **Mouse (user, 2026-11-05):** a click in the input line places the
   cursor there; nothing more for now.
5. **`cat`/`more` on the Ultimate:** as on GEOS drives: a `.cvt` of a
   sequential GEOS file shows its data, a VLIR one is refused.

## Step 3 (decisions, user, 2026-11-05)

Scripting, external commands and network, on the decisions of
2026-11-04 (DESIGN.md "Shell: gush": scripts by name or `source`,
`gushrc`, variables, `$1`-`$9`, `$#`, `$?`, `test`, `read`, comments).

1. **Script language:** a POSIX sh subset: `if`/`then`/`elif`/`else`/
   `fi`, `for NAME in words; do ... done`, `while ... do ... done`,
   `test` and `[ ]`, `$VAR`, `$1`-`$9`, `$#`, `$?`, `#` comments: scripts
   look like sh, only what does not fit is left out.
2. **External commands:** loadable modules: GEOS files of their own type,
   loaded into a fixed area of gush's memory and called with the words
   and a table of gush routines (print, the file engine, questions);
   gush stays. Own design (geoShell's transient commands are the idea,
   not the model).
3. **PATH:** `/e/bin`, then `bin` in the GEOULTRA home folder on the
   stick; changeable in `gushrc`.
4. **Redirection and pipes:** `>`, `>>`, `<` for everything a command
   prints (questions such as "overwrite?" stay on the screen); pipes in
   step 3, through a temporary file in the REU (the commands one after
   the other).
5. **Completion:** the `<-` key completes the word at the cursor
   (commands, then paths); pressed twice it lists the choices.
6. **History across sessions:** the newest 100 lines in
   `GEOULTRA/gush_history`, written when gush ends (exit, a program
   started), read at its start.
7. **Network:** `wget` (a URL into a file), `ifconfig` (the Ultimate's
   address and state), `ping`/`host` (as far as the Command Interface
   allows); an FTP or HTTP server stays on the roadmap.

## Step 3 plan (2026-11-05)

Sub-steps, each built, tested (VICE; the U64 where the Ultimate is
involved), committed and pushed on its own, so the work can stop after
any of them (also for rate limits) without leaving anything half done.
The U64 runs are gathered: one gu64 run per sub-step at most.

0. **Memory.** gush's code and data reach `$4C1D`; an application has
   up to `$5FFF`. gush draws only on the foreground screen, so the
   background buffer `$6000-$7F3F` (8 KB) becomes gush's: BSS (history
   buffer, file texts, the variable table) moves there, the code keeps
   `$0400-$5FFF`. External commands get a fixed area at its end.
1. **Variables and status:** `NAME=value`, `$NAME` and `${NAME}`,
   quoting (`'...'` literal, `"..."` with `$`), `set`, `unset`,
   `$?` (every command sets a status), `PATH` and `HOME` preset. The
   table in the application's REU (gush's own bank).
2. **Redirection:** `> file`, `>> file`, `< file` for every command's
   printed output (console output through a sink that writes to an
   engine stream; questions stay on the screen).
3. **Scripts:** a text file run by name (along `PATH`) or with `source`,
   `$1`-`$9`, `$#`, `$0`, `#` comments, `exit N`; `gushrc` in GEOULTRA
   run at the start.
4. **Control flow:** `if`/`then`/`elif`/`else`/`fi`, `while ... do ...
   done`, `for NAME in words; do ... done`, `test` and `[ ]` (files,
   strings, numbers), `read NAME`, `true`, `false`.
5. **Pipes:** `a | b`: `a`'s output into an REU temporary file, `b`
   reads it as its input.
6. **History across sessions:** the newest 100 lines in
   `GEOULTRA/gush_history`.
7. **Completion:** the `<-` key: command names, then paths; twice: the
   choices listed.
8. **External commands:** the module format (a GEOS file type, its
   header, load address in gush's area), the table of gush routines
   given to it (print, the file engine, questions, variables), loading
   along `PATH`; one example command; docs/GUSH_COMMANDS.md for writing
   them.
9. **Network:** `ifconfig`, `host`/`ping` (as far as the Command
   Interface allows: checked first on the U64), `wget URL [file]`.
10. **Sweep** at the end of the step.

Decisions for the rest of step 3 (user, 2026-11-05, design questions):
gush grows through **VLIR overlays**: a resident core (console, editor,
parser, executor) and records loaded on demand for groups of commands,
as geoWrite does. **External command modules** load into one fixed area
of 4 KB (freed by the overlays), one at a time: a GEOS sequential file
of a gush type, with a header (jump table, the gush API version).
**wget** does HTTP only (the Ultimate's TCP sockets), the file into the
current directory under the URL's last part, `-O name` to choose.
**Completion**: the first `<-` completes as far as all matches agree,
a second one lists the matches and shows the line again.

State: **3.0 (2026-11-05)** done (gush to `$3318`, the large buffers at
`$6000-$7973`). **3.1 (2026-11-05)**: variables in a 1 KB table in
gush's memory (vars.s; RAM rather than the REU: simpler, and enough),
names up to 16 characters, values up to 250; `NAME=value` words at the
start of a line set them and stay set (sh keeps such an assignment for
the one command only); `$NAME`, `${NAME}`, `$?` (1 when the line said
an error, else 0) outside quotes and in `"..."`, not in `'...'` or after
`\`; a value is not split into words; `set`, `unset`; `HOME` (the home
folder) and `PATH` (`/e/bin:` HOME `/bin`) at the start. `$0`-`$9` and
`$#` stay empty until scripts (3.3). Test g12.py. **3.2 (2026-11-05)**:
redirection (redir.s): an unquoted `>`, `>>` or `<` is a word of its
own (a marker byte from Parse), taken off the line with the file after
it; output goes through a 256-byte buffer into the file (`FE_WRITE`; a
new line is a CR), errors and questions (lines starting "gush: ") stay
on the screen, like sh's stderr; `cat` and `more` without a path read
the `<` file; `more` does not page into a file; `ls` into a file writes
a name per line. Test g13.py. **3.3 (2026-11-05)**: scripts
(script.s): a text file read whole into gush's REU (bank 4, 16 KB a
script, 4 deep), its lines run as typed lines are; run by `source file
[words]`, or by name: a plain file (CBM on a GEOS drive, or on the
Ultimate) that is no program runs as a script (a GEOS document still
says "no program"), looked for in the current folder, the drives' roots,
then along `PATH`; `$0` (its path), `$1`-`$9`, `$#`; `#` comments (a
word starting with `#` ends the line); `exit N` ends a script with
status N (outside one: the desktop); variables shared with the caller;
a redirection belongs to the level that made it (a script run with `>
file` writes there to its end; a second output redirection inside it
is refused); `HOME/gushrc` run at gush's start. Not yet: RUN/STOP
ending a script. Tests g14.py, gu64.py (gushrc). **3.4 (2026-11-05)**:
statements and control flow (flow.s): typed lines and scripts both run
through one executor, statement by statement (a line's end or an
unquoted `;` ends one; a typed line is copied to gush's REU bank 5 like
a script, read through a 256-byte page cache); `if`/`then`/`elif`/`else`
/`fi`, `while`/`do`/`done`, `for NAME in words`/`do`/`done`, nested; open
blocks on a frame stack (16), a level's state in arrays per script
depth (not on the 6502 stack); a branch not taken skipped, only its
keywords counted; `while` goes back to its statement at `done`, `for`
reads its statement again for the next word. `test` and `[ ]` (`-e -f
-d -z -n`, `=`, `!=`, `-eq -ne -lt -le -gt -ge` on signed 16-bit
numbers, `!`), `read NAME...` (keyboard, or the `<` file), `true`,
`false`. RUN/STOP between statements stops everything ("^C (stopped)").
A typed line must close its blocks (no continuation lines yet). Not
tested: RUN/STOP (VICE's monitor cannot hold a key). Test g15.py.
Memory: gush to `$5759` now; more buffers move to `$6000` or into
overlays when the next sub-steps need room. **3.5 (2026-11-05)**: pipes:
`a | b | ...` (an unquoted `|`), the stages one after the other: each
one's output into gush's REU (bank 6, two areas of 32 KB used in turn:
"pipe full" beyond), the next one's input from there (`cat`, `more`,
`read` read their input through one routine, redir.s `ReadIn`, from a
file or a pipe); a pipeline's text kept in bank 5 per script depth (a
stage may run a script with pipelines of its own); conditions of `if`
and `while` may be pipelines. A block cannot be a stage (`cat f | while
read L; ...`): a stage is one statement. Fixed on the way: the
`sta`/`bne` trap (`sta` keeps the flags of the `cmp` before it) in the
statement and stage scanners, which ended a quote as soon as it began;
the 16-bit limit of a pipe read. Test g16.py. Memory: the executor's
three page buffers moved to `$6000` (gush's code area to `$57B1`, the
high one to `$7C72`). **3.6 (2026-11-05)**: the history
across sessions (hist.s): the history keeps 128 lines (32 KB of REU bank
1); the newest 100 go to `HOME/gush_history` (the oldest first, a CR
after each) when gush ends (`exit`, an application started, `reboot`;
not when geoFolder's button starts a new gush), through a page buffer;
read back at gush's start before `gushrc`. Without `HOME` (VICE):
nothing. Test gu64.py (a reboot, then cursor up twice). **VLIR (2026-11-06)**: gush
became a VLIR file, the core and two overlays in a 4 KB transient area
(see "Memory and build"); the core ends at `$44F2`, 2.8 KB below the
area. `gtables.py` checks that no overlay calls into another one; g6
that gush started from drive E reads its overlays.

