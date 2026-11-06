# gush manual

gush is GeoUltra's shell: a text console for GEOS on a C64 with an
Ultimate, with commands for files and folders on GEOS drives and on the
Ultimate's own file system, scripts with variables and control flow,
pipes, and network commands. It is a GEOS application; programs started
from it run as they would from the desktop.

This manual describes gush as of step 3 (2026-11-06). The design and
the state of the work are in [GUSH.md](GUSH.md); writing your own
commands in [GUSH_COMMANDS.md](GUSH_COMMANDS.md); the file engine gush
uses in [FILE_ENGINE.md](FILE_ENGINE.md).

## Starting and leaving

- From geoFolder: its gush button (from any application, also under
  GEOS 2.0's deskTop).
- At boot instead of the desktop: `start=gush` in the `[system]`
  section of `SETTINGS.INI` (in the GEOULTRA folder on the stick).
- From a disk: gush is an ordinary GEOS application; a copy on any
  drive runs (it lives on drive E, the system drive, too).
- `exit` returns to the desktop (inside a script: ends the script).

At its start gush runs `HOME/gushrc` if it exists (a script: set
variables, `PATH`), and reads the history
of earlier sessions from `HOME/gush_history`. `HOME` is GeoUltra's home
folder on the stick (`/USB0/GEOULTRA`).

## The screen

53 columns by 24 rows of text, with a status line on top showing the
current folder and the time. Long input lines scroll sideways. gush
draws only on GEOS's foreground screen and redraws itself after a desk
accessory.

## Keys

| Key | |
| --- | --- |
| RETURN | run the line |
| DEL | delete the character before the cursor |
| INST | delete the character under the cursor |
| cursor left / right | move along the line |
| cursor up / down | the history: older / newer lines (128 kept, the newest 100 saved across sessions) |
| HOME | the cursor to the line's start |
| CLR | clear the screen |
| `<-` | complete the name before the cursor (below) |
| `↑` (the key left of RESTORE) | types `\|` (the C64 has no such key) |
| C= + `(` `)` `-` `'` `↑` | type `{` `}` `_` `` ` `` `~` |
| CTRL+A / CTRL+E | the line's start / end |
| CTRL+K / CTRL+U | cut the line after / before the cursor |
| CTRL+C, RUN/STOP | drop the line; stop `ls`, `more`, a copy's progress |

A mouse click on the input line puts the cursor there.

**Completion.** `<-` completes the word before the cursor from the names
in its folder (or the current one); a statement's first word is also
completed from gush's commands. The first `<-` adds as much as all the
names that fit agree on; with exactly one name it adds all of it,
followed by `/` for a folder or a space for a file. Pressing `<-` again
when nothing more can be added lists the names that fit. The word is
taken as typed (quotes are not looked at); a space in a completed name
gets a `\` before it.

## Paths

One tree for everything:

| Path | |
| --- | --- |
| `/a` ... `/d` | GEOS drives A-D (their images, folders and 1581 partitions) |
| `/e` | the system drive in the cartridge, read-only (gush, geoFolder; `/e/bin`: external commands); it needs one of A-D free while a command uses it |
| `/usb0`, `/usb1`, `/sd` | the Ultimate's file system |
| `/` | the list of the above |

Relative paths, `.` and `..` work as usual. Long names and short names
both work. On GEOS drives names are exact and case-sensitive; on the
Ultimate case-insensitive. GEOS files copied onto the Ultimate become
`name.cvt` (CVT) and come back as GEOS files; `-R` copies raw.

## Command lines

- **Words** are separated by spaces. `"..."` and `'...'` keep spaces;
  `\` takes the next character as it is.
- **Wildcards** `*` and `?` in a word's last part are replaced by the
  matching names (none: the word stays as typed).
- **Variables:** `NAME=value` sets one (names up to 16 characters,
  values up to 250); `$NAME` or `${NAME}` uses it, also inside `"..."`
  but not inside `'...'`. `set` lists them, `unset NAME` removes one.
  `$?` is the last status: 0 when the line worked, otherwise not 0.
  Preset: `HOME`, `PATH`.
- **Statements:** `;` separates statements on one line. `#` at a word's
  start begins a comment.
- **Redirection:** `> file` (new), `>> file` (appended), `< file`
  (input for `cat`, `more`, `read`, external commands). Error messages
  and questions stay on the screen.
- **Pipes:** `a | b | c` runs the commands one after the other, each
  one's output becoming the next one's input (at most 32 KB per stage).
  `if` and `while` conditions may be pipelines; a block (`while ...
  done`) cannot be a stage.

## Control flow

```
if test -f letter; then echo there; elif test -d letter; then echo folder; else echo none; fi
while read LINE; do echo "> $LINE"; done < list
for F in *.cvt; do cp $F /a; done
```

Blocks nest (16 open blocks at most). Conditions are commands: their
status decides (0 is true).

`test EXPR` and `[ EXPR ]`:

| Expression | True when |
| --- | --- |
| `-e path`, `-f path`, `-d path` | it exists / is a file / is a folder or drive |
| `-z word`, `-n word` | it is empty / not empty |
| `a = b`, `a != b` | the words are equal / differ |
| `a -eq b` (`-ne -lt -le -gt -ge`) | numbers (signed 16 bits) compare so |
| `! EXPR` | the opposite |

`read NAME...` reads a line (from the keyboard, a `<` file or a pipe):
one word to each name, the rest of the line to the last. At the end of
the input it fails (`while read` stops). `true` and `false` set the
status.

## Scripts

A plain text file (a CBM file on a GEOS drive, or a file on the
Ultimate) whose name is typed runs as a script; so does `source file
[words]`. In a script `$0` is its path, `$1`-`$9` its words, `$#` their
number; `exit N` ends it with status N. Scripts share the caller's
variables and may call other scripts (4 deep, 16 KB each). Lines end in
CR or LF.

## Commands

| Command | |
| --- | --- |
| `ls [-l] [path...]` | list; `-l` with type, size, date and the short name |
| `cd [path]`, `pwd` | change / show the current folder (`cd` alone: the start drive) |
| `cp [-frR] source... target` | copy; asks before overwriting unless `-f`; `-r` folders; `-R` raw (no CVT) |
| `mv [-fR] source... target` | move or rename |
| `rm [-f] path...` | delete (asks unless `-f`) |
| `mkdir [-t tracks] path...`, `rmdir path...` | folders (`-t`: a 1581 partition's size) |
| `cat [path...]`, `more [path...]` | show files (or the input); `more` a page at a time |
| `df [path]` | free and total space |
| `mount`, `mount image /drive`, `umount /drive` | the drives' images; mount or unmount one (written back, `MOUNTS.INI` updated) |
| `mkimg [-t tracks] type path [name]` | a new empty `d64`, `d71`, `d81` or `dnp` image on the Ultimate |
| `free` | the REU's use |
| `turbo [-s] [step]` | the U64's speed (0-15); `-s` saves it in `SETTINGS.INI` |
| `date [YYYY-MM-DD HH:MM[:SS]]` | show or set the clock (GEOS's and the Ultimate's) |
| `ntp [server]` | set the clock from a time server (`SETTINGS.INI` `[time] ntp=` and `offset=` seconds from UTC) |
| `reboot` | write the drives back and restart GeoUltra |
| `ifconfig` | the Ultimate's network address, netmask, gateway and MAC address |
| `wget [-O name] http://host[:port]/path` | download a file over HTTP into the current folder |
| `echo words...`, `clear`, `help [command]`, `exit [N]` | |
| `set`, `unset name...`, `source file [words]` | variables, scripts |
| `test`, `[`, `read`, `true`, `false` | see "Control flow" |

`help` lists the commands; `help NAME` shows one command's use.

**wget** speaks plain HTTP/1.0: no HTTPS, and redirects are not
followed (a `301`/`302` shows its status line). The file is named after
the URL's last part (`index.html` when there is none) unless `-O` gives
a name. The Ultimate resolves the host name itself; it offers no ping
and no separate name lookup, so gush has no `ping` or `host`.

## Programs and external commands

A word that is no command is looked for as a program: by its path when
it has a `/`, else in the current folder, the root of each drive A-D,
and the folders in `PATH` (default `/e/bin:/USB0/GEOULTRA/bin`: the system drive's
commands, then your own on the stick). What is found:

- a GEOS **application** is started (it replaces gush, as from the
  desktop); a document after its name is passed to it (`geoWrite
  letter`); a **desk accessory** runs and returns to gush (a program on
  `/e` takes no document);
- an **external command** (a GEOS file of class `gush cmd`, or its
  `.cvt` on the stick) is loaded and run inside gush: those of the
  system are in `/e/bin` (`wc`); put your own into `GEOULTRA/bin` on the
  stick to have them everywhere;
- a plain text file runs as a script.

`wc [file...]` is the example external command: lines, words and bytes
of files or of its input (`ls | wc`).

## Limits

- Lines up to 254 characters; 32 words a line.
- Not every GEOS file can be shown: `cat` refuses VLIR files (GEOS
  documents).
- gush aims at the GEOS conventions and sh's habits where they fit, but
  is no complete sh: what is not described here is not there.
