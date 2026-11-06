# Writing external gush commands

An external command is a small program that gush loads when its name is
typed, runs with the line's words, and forgets again: gush stays in
memory, the command borrows a 4 KB area of it. This file describes the
format, the routines gush offers and the rules. The example is `wc`
(`src/cmds/wc.s`). Design: docs/GUSH.md, "Step 3", sub-step 8.

API version 1 (gush step 3.8, 2026-11-06).

## Where gush finds one

A word that is no built-in command is looked for as a program: by its
path when it has a `/`, else in the current folder, in the root of
drives A-D and in each folder of `PATH`. A file found there is an
external command when

- on a GEOS drive: it is a GEOS `APPL_DATA` file of class `gush cmd`
  (the first 8 characters of the 12-character class), sequential;
- on the Ultimate's file system: it is that file's CVT, `NAME.cvt`
  (gush tries the name with `.cvt` added when `NAME` is not there;
  `cp` of the GEOS file onto the stick makes it). A plain file found
  under its own name is a script.

`PATH` is `/e/bin:/USB0/GEOULTRA/bin` by default (`gushrc` can change
it): the system's commands in the system drive's `bin` folder (built
into the cartridge, `src/sysdrive.toml`), then your own in
`GEOULTRA/bin` on the stick.

## Format

The file's data is the command's code, linked at `$5000`
(`GU_TRANS`), 4096 bytes at most including its variables (BSS), and
starts with

| Offset | Bytes | |
| --- | --- | --- |
| 0 | `"GCMD"` | magic |
| 4 | 1 | the API version it needs (`GU_API_VERSION`); a newer one than gush's is refused |
| 5 | `jmp Main` | the entry |

gush reads the file into `$5000-$5FFF` (refused with "not a gush
command, or for a newer gush" when the magic or the version is wrong,
or the file is larger than 4 KB) and calls `$5005`.

## Calling convention

- In: the words in gush's word list: `GU_ARGC` gives their number,
  `GU_ARG` (X = its number) each one. Word 0 is the command's name as
  typed. Quotes, `$VARIABLES` and wildcards are already done.
- Out: `rts` with **C clear** (done, `$?` = 0) or **C set** (failed,
  `$?` = 1). Say why before failing (`GU_FAIL` does both the message and
  the status for engine errors).
- Free for the command: r0-r15, the zero page `$E0-$EF` (`GU_ZP`), and
  its own 4 KB. Everything else belongs to gush (its zero page
  `$80-$DF`, its memory `$0400-$4FFF` and `$6000-$7F3F`) or to GEOS.
- Nothing stays: the area is gush's again as soon as the command
  returns (the next overlay or command overwrites it), and its
  variables start as they are in the file each time. BSS is not
  cleared.

## The routines (`src/cmds/gushapi.inc`)

A jump table at `$0403` that never moves; later versions only add
entries at its end. Registers not named as output are destroyed.

| Address | Name | In | Out |
| --- | --- | --- | --- |
| `$0403` | `GU_PUTC` | A: a character (`CR`: a new line) | |
| `$0406` | `GU_PRINT` | A/Y (low, high): a zero-ended text | |
| `$0409` | `GU_NEWLINE` | | |
| `$040C` | `GU_FILEENGINE` | A: function, Y: handle, r0-r4 (docs/FILE_ENGINE.md) | X: 0 or an error, A: a handle, r0-r4 |
| `$040F` | `GU_FAIL` | X: error, Y: the word it is about (`$FF`: none) | "gush: NAME: WORD: TEXT" said, `$?` = 1 |
| `$0412` | `GU_ARG` | X: a word's number | r0: its text |
| `$0415` | `GU_ARGC` | | A: the number of words |
| `$0418` | `GU_GETVAR` | r0: a name | C clear: r1 its value; C set: none |
| `$041B` | `GU_SETVAR` | r0: a name, r1: a value | C set: no room (said) |
| `$041E` | `GU_READIN` | r1: a buffer, r2: its length | r2: bytes read (0: the end), X: error; C set: no input given |
| `$0421` | `GU_DECIMAL` | r0-r1: a 32-bit number (r0L lowest), A: columns (right-aligned; 0: its own width) | |
| `$0424` | `GU_KEY` | | A: a key, waited for |

Output through `GU_PUTC`, `GU_PRINT` and `GU_NEWLINE` follows the
line's redirection: into a file with `>`, into the next command with
`|`. The input (`GU_READIN`) is the `<` file or the previous command's
output in a pipe; without either, C comes back set. Never draw on the
screen yourself: gush redraws from its own copy of the text.

Engine errors (the file engine's codes, docs/FILE_ENGINE.md) and gush's
own codes print their text through `GU_FAIL`; any other number prints
as "error N".

## Building

```
ca65 -I src/inc -I src/cmds -o build/cmds/NAME.o src/cmds/NAME.s
ld65 -C src/cmds/cmd.cfg -o build/cmds/NAME.bin build/cmds/NAME.o
geosapp.py src/cmds/NAME.toml build/cmds/NAME.bin build/cmds/NAME.cvt
```

`make` does this for every `src/cmds/NAME.s` with a `NAME.toml` named in
the Makefile. The `.toml` (geos-oscar64's `geosapp.py`):

```
[file]
name = "wc"
type = "APPL_DATA"
load = 0x5000
class = "gush cmd"
version = "V1.0"
author = "..."
info = "What it does."
```

Put the CVT on the stick in `GEOULTRA/bin` (by FTP, or with gush's `cp`
from a GEOS drive), or the GEOS file on a GEOS drive.

## Example: wc

`src/cmds/wc.s` counts lines, words and bytes of the files named, or of
its input (`echo a b | wc`, `wc < file`), and prints a total for more
than one file. It shows each part: the header, `GU_ARGC`/`GU_ARG`, the
file engine (`FE_OPEN`, `FE_READ`, `FE_CLOSE`), `GU_READIN`,
`GU_DECIMAL`, `GU_FAIL` with the word an error is about, and the C
flag on return.
