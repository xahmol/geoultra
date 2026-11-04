# File engine (design proposal)

Status: **approved by the user, 2026-11-04** (with the `%XX` escape);
steps E1-E3 implemented (below, "State of the work"). Decisions it builds
on: docs/DESIGN.md, "Shell: gush", "Languages" and "gush and file
engine decisions".

The file engine is the part of the kernal that works with files by path,
over the GEOS drives and the Ultimate's file system: listing, copying
(with CVT conversion), moving, deleting, folders, reading and writing
streams, and later mounting. gush is its first user, then GeoUltra's
desktop and file manager; third-party applications can call it too.

## Constraints

- **Resident memory:** nearly none left (code sweep 2026-11-04: `CODE`
  105 bytes, other resident segments 1-8). The engine costs **one
  5-byte entry** in the extension jump table; everything else lives in
  overlay modules.
- **Overlay modules:** at most 496 bytes each, one at a time in the slot
  at `$9D80`; no vectors into the slot; module variables lost across a
  nested overlay call (overlay.s). The engine is about 12-16 modules.
- **Application memory:** none. Buffers: `diskBlkBuf`, and `fileHeader`
  for the path (`fePath`) while it is walked; the overlay scratch
  `$9F70-$9FFF` as the engine's work area during a call (engine.inc;
  write-back and hibernation use it too, but only from MainLoop, never
  during an engine call); lasting state in REU bank 1 `$C000-$C2FF`.
- **UCI:** the engine uses DOS target 2. The write-back and hibernation
  use target 1 from MainLoop; on the same target, a write-back between
  two engine calls would close the engine's open file or directory
  (only one file may be open at a time per target: UCILIB manual).
- **The caller's state stays as it was:** `curDrive`, the drives'
  current folders, `curDirHead` and the BAM copy are saved at entry and
  restored at exit; a path on another drive or in another folder never
  changes what the application sees.

## Calling

    lda #FE_COPY            ; function number
    ...                     ; arguments in r0-r4 (below), a handle in Y
    jsr FileEngine          ; guExtTable + 30 (extension entry 6)
                            ; X = 0 or an error; A = a handle (FE_OPENDIR);
                            ; results in r0-r4, which are kept otherwise

`FileEngine` is `jsr OvlCall / .byte 22, 0`: module 22 is a dispatcher
holding a table of (module, entry) per function. It calls the function
through a stub in its own code (`Call: jsr OvlCall / .byte m, e`) whose
two bytes it has just written: OvlCall reads them before it fetches the
other module and brings module 22 back on the way out, so the modified
bytes are only needed for that moment. Zero further resident bytes per
function.

The caller's `curDrive` and the current folder of every drive are saved
at the start; when a drive was used, they are put back and the caller's
drive is opened again (`OpenDisk`: `curDirHead` and the BAM read anew,
so call the engine with your BAM changes written). Destroys r5-r15,
`diskBlkBuf`, `fileHeader` (a GEOS file's header after `FE_STAT`),
`fileTrScTab`, `dirEntryBuf`.

C callers (geos-oscar64) get a thin wrapper per function later.

## Paths

- One tree. `/a`-`/d`: GEOS drives A-D (devices 8-11); `/e`: drive E,
  read-only; `/usb0`, `/usb1`, `/sd`: the Ultimate's file system (passed
  to the Ultimate as `/Usb0/...` etc.).
- On GEOS drives, folder components are native folders or 1581
  sub-directory partitions (entered with folders.s's own routines); the
  last component is a file name, at most 16 characters.
- Relative paths are taken from the engine's current directory (`FE_CD`,
  `FE_PWD`), kept in the REU; one for now (gush and the desktop do not
  run at the same time), one per task when task switching comes.
  `.` and `..` work everywhere; `..` at a drive's root goes to `/`, at
  `/` it stays there.
- Names exact and case-sensitive. Wildcards `*` and `?` only in the last
  component of `FE_OPENDIR`'s pattern; gush expands its arguments from
  that listing, so every other call takes exact names.
- Paths are at most 127 bytes (zero-terminated, PETSCII as GEOS names;
  ASCII to the Ultimate). Names that the FAT file system cannot hold
  (`/ \ : * ? " < > |`) are written as `%XX` there and read back.

## Functions

| No. | Name | In | Out |
| --- | --- | --- | --- |
| 0 | `FE_VERSION` | | r0 = version |
| 1 | `FE_STAT` | r0 = path, r1 = 16-byte info block, r2 = 0 or a 61-byte buffer | info (below); its long name (else its name) in r2's buffer; a GEOS file's header in `fileHeader` |
| 2 | `FE_OPENDIR` | r0 = a folder, a pattern in a folder, one name, or `/` (the drives) | A = handle |
| 3 | `FE_READDIR` | Y = handle, r1 = info block, r2 = name buffer (61 bytes), r3 = 0 or a 17-byte buffer | info, the long name (else the short one) zero-ended, the short name in r3's buffer; X = `FE_END_OF_DIR` at the end |
| 4 | `FE_CLOSE` | Y = handle, `$FF`: all (a program starting afresh) | |
| 5 | `FE_COPY` | r0 = source, r1 = target (a folder or a new name), r2L = flags | |
| 6 | `FE_MOVE` | as `FE_COPY` | (same drive and kind: a rename or a moved entry, else copy then delete) |
| 7 | `FE_DELETE` | r0 = path | |
| 8 | `FE_MKDIR` | r0 = path, r2L = tracks (1581; 0: default) | |
| 9 | `FE_RMDIR` | r0 = path of an empty folder | |
| 10 | `FE_RENAME` | r0 = path, r1 = new name | |
| 11 | `FE_CD` | r0 = path | |
| 12 | `FE_PWD` | r0 = buffer (256 bytes) | |
| 13 | `FE_OPEN` | r0 = path, r2L = mode (read, write, append) | A = handle |
| 14 | `FE_READ` | Y = handle, r1 = buffer, r2 = length | r2 = bytes read |
| 15 | `FE_WRITE` | Y = handle, r1 = buffer, r2 = length | |
| 16 | `FE_DF` | r0 = path on a drive | r1 = free, r2 = total (blocks; Ultimate: KB) |
| 17 | `FE_MOUNT` | r0 = drive path (`/a`), r1 = image path | (step 2) |
| 18 | `FE_UMOUNT` | r0 = drive path | (step 2) |
| 19 | `FE_GETLONG` | r0 = path, r1 = 61-byte buffer | the long name, else the short one |
| 20 | `FE_SETLONG` | as `FE_RENAME` | (the same function) |

Flags for `FE_COPY` and `FE_MOVE`: overwrite (else `FILE_EXISTS`),
raw (no CVT conversion), and a progress vector in r3 (called after every
block with r4 = blocks done; the routine returns C set to cancel). The
engine never asks the user: gush asks before an overwrite or delete
(decision: always, unless `-f`), the desktop shows its own dialog.

Info block (16 bytes): +0 kind (0 `/`, 1 drive, 2 folder, 3 GEOS file,
4 CBM file, 5 Ultimate file, 6 Ultimate directory), +1 CBM type byte,
+2 GEOS structure, +3 GEOS file type, +4 size (4 bytes; blocks on GEOS
drives), +8 date (year, month, day, hour, minute; GEOS files), +13 flags
(bit 0 read-only, bit 1 GEOS file), +14 reserved. The GEOS class is in
`fileHeader` after `FE_STAT`.

Errors: GEOS's codes where they fit (`FILE_NOT_FOUND`, `STRUCT_MISMAT`,
`DEV_NOT_FOUND`, `INSUFF_SPACE`, `WR_PR_ON` $26 for a locked file, ...),
GeoUltra's `FILE_EXISTS` $40 and `DIR_NOT_EMPTY` $41 as for folders, and
the engine's own: `FE_CANCELLED` $47 (the progress routine stopped a
copy), `FE_END_OF_DIR` $48, `FE_BAD_PATH` $49 (too long, a
name too long, `/` or a drive where a file is needed), `FE_NOT_FOLDER`
$4A, `FE_IS_FOLDER` $4B, `FE_BAD_HANDLE` $4C, `FE_NO_HANDLE` $4D,
`FE_NOT_SUPPORTED` $4E (not yet, or not on this kind of path), and
`FE_ULTIMATE` $4F (the Ultimate's error; its status text kept for
`FE_ERRTEXT`, a later function).

Handles: at most 4 open at a time (directories and streams), 64 bytes of
state each in REU bank 1 (`$C100`), after the current directory
(`$C080`) and a layout signature (`$C000`, made at the first call after
power-on).

## Copying

- **GEOS drive to GEOS drive:** block by block through `diskBlkBuf`:
  header block, then each chain (sequential data or each VLIR record),
  blocks allocated on the target with `SetNextFree`, the directory entry
  written last (so a failed copy leaves no entry; its blocks are freed).
- **GEOS drive and Ultimate (E3, as built):** through the CPU, block by
  block: `READ_DATA` of 254 bytes into a block, `WRITE_DATA` in pieces of
  127 bytes (the command buffer is `fileTrScTab`). Measured on the U64:
  174848 bytes onto drive A in about 2 s. The REU route (`LOAD_REU` into
  scratch banks, `SAVE_REU` back) stays the plan for when that is too
  slow; it needs the allocation table at run time.
- **CVT:** GEOS files become `name.cvt` on the Ultimate (the format in
  docs/GEOS_REFERENCE.md, "CVT"; the same one as mkappsdnp.py reads),
  and `.cvt` files become GEOS files again on a GEOS drive. Plain CBM
  files (SEQ, PRG, USR) copy as they are, with `.seq`/`.prg`/`.usr`
  added and taken off. Raw flag: no conversion either way.
- **Drive E** is read-only: a source only.

## Modules (numbered from 22)

As built (src/kernal/engine.s, enginepath.s, enginedir.s,
enginefile.s, enginecopy.s, enginestream.s):

| Module | Holds |
| --- | --- |
| 22 | dispatcher, the caller's state, REU setup, `FE_VERSION`, `FE_PWD`, `FE_CLOSE` |
| 23 | path made absolute (`.`, `..`, the current directory) |
| 24 | path walked: the top part, the folders, the last part |
| 25 | `FE_STAT`, `FE_DF` |
| 26 | `FE_OPENDIR` |
| 27 | `FE_DELETE`, `FE_RENAME`, `FE_MKDIR`, `FE_RMDIR`, `FE_CD` |
| 28 | `FE_READDIR` (patterns; nearly full: the Ultimate's listing gets its own module) |
| 29 | `FE_COPY`, `FE_MOVE`: the source, the order, a move in one folder as a rename |
| 30 | the target of a copy: folder or name, overwrite, not onto itself |
| 31 | the blocks of a copy (header, chains, VLIR index), its directory entry, the BAM |
| 32 | `FE_OPEN` |
| 33 | a new file for `FE_OPEN` (CBM SEQ, one empty block) |
| 34 | `FE_READ` |
| 35 | `FE_WRITE` |

| 36 | the Ultimate: the exchange (I/O on, `uci.inc`), its status as an error, folders entered (in pieces when long) |
| 37 | `FE_STAT` on the Ultimate (open + `FILE_INFO`: `FILE_STAT` answers "82" on firmware 3.15a) |
| 38 | `FE_OPENDIR` on the Ultimate (read whole: no reply stays open between calls) |
| 39 | `FE_READDIR` on an Ultimate listing |
| 40 | `FE_READDIR` on `/`: drives A-D, then `usb0`, `usb1`, `sd` that can be entered |
| 41 | `FE_DELETE`, `FE_MKDIR`, `FE_RMDIR`, `FE_RENAME`, `FE_CD` on the Ultimate |
| 42 | `FE_COPY`/`FE_MOVE` onto the Ultimate: checks, the name (`%XX`, extension), open, close |
| 43 | `FE_COPY`/`FE_MOVE` from the Ultimate: the source, the target (module 30), the room, close, delete |
| 44 | its blocks onto the GEOS drive, the entry |
| 45 | a GEOS file's blocks onto the Ultimate |
| 46 | a new entry's fields from an Ultimate file (type from the extension, `%XX` decoded, the long name, size in blocks, FAT date) |
| 47 | an Ultimate listing read whole (`READ_DIR` into REU slots) |
| 48 | long names looked up: a long name to its file (checked in its slot), a file to its long name |
| 49 | `GU.LONGNAMES` kept: a record set (replaced, a free one, the file grown), dropped |
| 50 | short names made (13 characters and `~n`) |
| 51 | names: a listing's entries (long name, pattern, the file hidden), records dropped, `FE_GETLONG` |
| 52 | a copy's new entry and its long name |
| 53 | `GU.LONGNAMES` made |
| 54 | `FE_RENAME`/`FE_SETLONG`, `FE_MKDIR` with long names |

Still to come (estimate): CVT out and in; streams on the Ultimate; mount
and umount (sharing the image code with mount.s); Ultimate to Ultimate
copies.

Shared code goes into includes assembled into each module that needs it
(`engine.inc`: constants, the work area, the REU layout; `fereu.inc`:
REU state and handles; `feresolve.inc`: paths, names, entering folders;
`feinfo.inc`: info blocks; `fehandle.inc`: a free handle; `fename.inc`:
a name into a directory entry; `festream.inc`: stream handles;
`fematch.inc`: patterns; `fegive.inc`: a listing entry to the caller;
`feentry.inc`, `feblock.inc`, `feprog.inc`: a copy's entry, blocks and
progress; `fefat.inc`: FAT dates; `feult.inc`, `fecd.inc`: Ultimate
commands and folders; `uci.inc`: the UCI handshake, shared with mount.s,
writeback.s and hibernate.s since E3). Mounting at run time needs
mount.s's image code, which now lives only in the boot's `INIT`
segment: it moves into includes used by both.

## Tests

- `tests/engine/*.py` in VICE (like test-folders): every function on
  GEOS drives (1541, 1571, 1581 with partitions, native with folders),
  driven by small calling programs; results compared with the images
  as c1541 and the real 1581 DOS read them; the caller's state checked
  unchanged after each call.
- VICE has no UCI: Ultimate paths are tested on the U64 only, in
  `/USB0/GEOULTRA/test/engine` (copies, as every hardware test), with a
  test program run through the U64's REST interface and the results read
  back by FTP. Round trip: GEOS file -> CVT -> GEOS file, byte for byte.

## Long names (step L; approved by the user 2026-11-04)

Built between E3 and gush step 1 (user, 2026-11-04: so that gush, CVT
and the engine's interface are made once for long names). The design is
the approved one of docs/DESIGN.md ("Directories", "Long names"); this
section settles what it leaves open. The desktop, `DBGETFILES`, geoFolder
and the per-drive switch keep their place in the plan: they only read
long names through the routines below.

**The file.** `GU.LONGNAMES` in every folder that has long names (the
root on 1541/1571/1581 flat disks), a USR file of one chain. Records of
127 bytes, two in each block's 254 data bytes (never across blocks; the
design first had 96): directory block (track, sector), slot (the
entry's offset), the short name (16 bytes, $A0-padded), the long name
(up to 60 characters, zero-ended, 61 bytes), the rest free. A record with
track 0 is free and taken by the next long name; a record with the same
key is replaced. GeoUltra's listings do
not show the file; other systems do (a valid USR file, harmless).

**Which file a record belongs to.** The record counts while its slot
still holds an entry with that short name (as DESIGN.md has it). Also
keying on the first data block or the date was considered and dropped:
applications that save by deleting and writing anew (common) would lose
the long name at every save. The remaining risk, a new file with the
same generated short name in the same slot inheriting the long name, is
small, and that is usually the same document anyway.

**Changes behind GeoUltra's back.** No hooks in the kernal (46 resident
bytes left). Repair is lazy: a record whose slot no longer holds its
short name is ignored when read and dropped the next time the engine
writes the file. An application that renames a long-named file through
`RenameFile` loses the long name; Validate or a move by another system
does too.

**Short names.** The first 13 characters of the long name, then `~1` to
`~9` (then 12 characters and `~10` to `~99`), the first one free in the
folder. A long name of at most 16 characters that is a valid short name
is its own short name and gets no record.

**Characters.** Long names: printable ASCII ($20-$7E) without `/`, case
kept; spaces allowed (gush quotes them). Names and patterns stay exact
and case-sensitive on GEOS drives; on the Ultimate they become
case-insensitive, as FAT is (a change from E3, where patterns were
exact there too). On the Ultimate a long name is the FAT name, with
`%XX` for what FAT cannot hold and the type's extension (`.seq`,
`.prg`, `.usr`; `.cvt` from E4) as now.

**The engine's interface** (now, while it has no users):
- `FE_READDIR`: r2 = a buffer of 61 bytes on every drive: the long name,
  or the short name when there is none; r3 = a buffer of 17 bytes for
  the short name, or 0. Ultimate names longer than 60 characters are
  listed cut (info flag `FF_CUT`); in a path the last part may have up
  to 120 characters (it goes into one 128-byte command; a rename's two
  names together must fit one), folders longer go to the Ultimate in
  pieces.
- `FE_STAT`: r2 = 0 or a buffer of 61 bytes for the long name.
- Paths name files by long or short name. `FE_RENAME` sets a long name
  (and a new short name if needed); `FE_MKDIR` makes long-named folders;
  `FE_DELETE`, `FE_RMDIR` drop the record; `FE_COPY`/`FE_MOVE` carry it
  between GEOS drives and to and from the Ultimate.
- `GetLongName`/`SetLongName` become engine functions (`FE_GETLONG`,
  `FE_SETLONG`: r0 = path, r1 = buffer) instead of extension jump table
  entries: no resident bytes. (DESIGN.md listed them in the extended
  jump table.)
- Paths up to 255 bytes (two 60-character levels already reach 127).
  The current directory in the REU grows to 256 bytes (layout 2: made
  anew at the first call, as now after power-on).

**Memory.** `fePath` keeps all of `fileHeader` (256 bytes). The names
(`feName`, `feTmp`: 61 bytes each) move from the work area to
`fileTrScTab`, with the Ultimate's command buffer (128 bytes) after
them. A copy's VLIR index stays in `fileHeader`: the path is no longer
needed while the blocks are copied (a move resolves its source again
afterwards, as now). Ultimate folders are entered part by part when the
path does not fit one command (the Ultimate takes relative `CD`);
`WRITE_DATA` pieces become 120 bytes.

**When the disk is full.** The file operation itself completes; the long
name that does not fit is dropped (X = 0, the short name stays). Better a
file without its long name than no file.

**Tests.** VICE on 1541, 1581 (partitions) and native images: listings,
paths by both names, rename, delete, copy and move carrying the long
name, a long name lost after `RenameFile` by an application, stale
records dropped, the real 1581 DOS reading the folder; the U64 for the
Ultimate side (long FAT names both ways, case-insensitive paths).

## Order of work

1. **E1:** dispatcher, paths, current directory, stat, directory
   listing, delete, rename, mkdir, rmdir on GEOS drives; tests.
2. **E2:** copy and move between GEOS drives; streams on GEOS files.
3. **E3:** the Ultimate's file system: listing, stat, raw copy both ways,
   delete, mkdir; U64 tests.
4. **L:** long names in the kernal's files and the engine (above). Then
   **gush step 1** (decided: it includes the Ultimate's file system).
5. **E4:** CVT both ways, streams on the Ultimate, mount and umount;
   gush step 2.

## State of the work

- **E1 (2026-11-04):** dispatcher, paths, current directory, `FE_STAT`,
  `FE_OPENDIR`/`FE_READDIR`/`FE_CLOSE` with patterns and `/`, `FE_DF`,
  `FE_DELETE`, `FE_RENAME`, `FE_MKDIR`, `FE_RMDIR`, `FE_CD`, `FE_PWD` on
  GEOS drives A-D. `make test-engine` (tests/engine/e1.py): 54 checks on
  a D81 made by the real 1581 DOS (partitions as folders), the caller's
  state checked after every call, the image read back by the real DOS.
  Drive E and the Ultimate answer `FE_NOT_SUPPORTED`; so do the
  functions of later steps.
- **E2 (2026-11-04):** `FE_COPY` and `FE_MOVE` between GEOS drives and
  folders (CBM files, sequential and VLIR GEOS files; the copy keeps the
  entry's date; overwrite flag; progress routine with cancel; a move in
  one folder is a rename, else a copy and a delete), streams `FE_OPEN`
  (read, write, append), `FE_READ`, `FE_WRITE` on one chain (CBM files,
  sequential GEOS files; VLIR answers `STRUCT_MISMAT`; new files are CBM
  SEQ). `FE_WRITE` writes its blocks, the BAM and the entry's size before
  it returns, so `FE_CLOSE` only frees the handle. tests/engine/e2.py:
  the VLIR copy compared record by record with the original, drive B's
  root BAM checked against the blocks in use, the real 1581 DOS reads the
  results. The engine now calls files.s's `FindFile`, not the jump
  table's (which goes on to the root folder and drive E for desk
  accessories and fonts).
- **E3 (2026-11-04):** the Ultimate's file system (`/usb0`, `/usb1`,
  `/sd`; paths case-insensitive there, names in listings as stored):
  `FE_STAT` (files with size, date, read-only; folders; disk images are
  files), `FE_OPENDIR`/`FE_READDIR` (read whole into REU banks 188-191,
  one per handle, 64-byte slots: names up to 62 characters, 1024
  entries), `/` lists the tops that can be entered, `FE_CD`/`FE_PWD`,
  `FE_MKDIR`, `FE_RMDIR` (`DIR_NOT_EMPTY` from "01,DIRECTORY EMPTY"),
  `FE_DELETE`, `FE_RENAME`; raw `FE_COPY`/`FE_MOVE` both ways between a
  GEOS drive and the Ultimate (CBM files; sequential GEOS files with
  `FC_RAW`). Statuses: "FILE EXISTS" `FILE_EXISTS`, "FILE DOESN'T EXIST",
  "82", "83", "88" `FILE_NOT_FOUND`, "ACCESS DENIED" `WR_PR_ON`, others
  `FE_ULTIMATE`. Without a UCI (VICE) `DEV_NOT_FOUND`. Functions not
  written for Ultimate paths answer `FE_NOT_SUPPORTED` (the walk returns
  one only when the function sets `feUlt`). Tests: tests/engine/
  e3u64.py on the U64 (feu64.py calls the engine through `appMain`;
  uciprobe.s sends raw commands), everything in
  `/USB0/GEOULTRA/test/engine` and on the test images, removed again.
  The UCI handshake is now one source, `src/inc/uci.inc` (mount, the
  write-back, the clock and the engine; checked on the U64: boot mounts,
  clock, a write-back).
- **L (2026-11-04):** long names on GEOS drives (modules 48-54,
  enginelong.s; `GU.LONGNAMES` per folder): paths by long or short name
  (the walk looks long ones up, module 48), listings with long names and
  the short ones in r3, patterns on long names, `GU.LONGNAMES` hidden,
  `FE_STAT` and `FE_GETLONG`, `FE_RENAME`/`FE_SETLONG` (module 54),
  `FE_MKDIR`, new files (`FE_OPEN`, copies: module 52's entry, from GEOS
  drives and from the Ultimate), delete and rmdir drop the record after
  the file goes; copies to the Ultimate name the file by its long name.
  Short names: 13 characters and `~1`-`~9`, then 12 and `~10`-`~99`,
  the first free (module 50). Paths up to 255 bytes, the current
  directory 256 (REU layout 2), the names (61 bytes) in `fileTrScTab`
  with the Ultimate's command buffer (128 bytes) after them. On the
  Ultimate names and patterns case-insensitive. API: `FE_STAT` r2,
  `FE_READDIR` r3 (0 when not wanted), `FE_PWD` 256 bytes. Tests:
  tests/engine/long.py (VICE: the cases above, a stale record after an
  application's `RenameFile`, a path of 133 bytes, the records and the
  BAM read from the image, the real 1581 DOS reading `GU.LONGNAMES`);
  e3u64.py on the U64 (case, a folder path longer than one command).
- Known limits: renaming a folder changes its directory entry, not the
  name in its header (shown as the disk name inside it); native drives
  are covered by the same code but not yet by the test. Copying a folder
  or a REL file is refused (`FE_IS_FOLDER`, `FE_NOT_SUPPORTED`). On a
  native drive the BAM lives in the image, so a copy that fails half way
  leaves its blocks taken (Validate frees them); on the other drives the
  BAM in memory is dropped. The progress routine must not call the
  engine. Ultimate: patterns are case-sensitive; a GEOS name from a long
  Ultimate name is cut to 16 characters; listings show no sizes (each
  would need an open); copies between two Ultimate paths, CVT and
  streams there are later steps; the listing keeps interrupts on but
  runs with I/O on.
