# File engine (design proposal)

Status: **approved by the user, 2026-11-04** (with the `%XX` escape);
steps E1 and E2 implemented (below, "State of the work"). Decisions it builds
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
| 1 | `FE_STAT` | r0 = path, r1 = 16-byte info block | info (below); a GEOS file's header in `fileHeader` |
| 2 | `FE_OPENDIR` | r0 = a folder, a pattern in a folder, one name, or `/` (the drives) | A = handle |
| 3 | `FE_READDIR` | Y = handle, r1 = info block, r2 = name buffer (17 bytes; 65 from E3) | info, the name zero-ended; X = `FE_END_OF_DIR` at the end |
| 4 | `FE_CLOSE` | Y = handle, `$FF`: all (a program starting afresh) | |
| 5 | `FE_COPY` | r0 = source, r1 = target (a folder or a new name), r2L = flags | |
| 6 | `FE_MOVE` | as `FE_COPY` | (same drive and kind: a rename or a moved entry, else copy then delete) |
| 7 | `FE_DELETE` | r0 = path | |
| 8 | `FE_MKDIR` | r0 = path, r2L = tracks (1581; 0: default) | |
| 9 | `FE_RMDIR` | r0 = path of an empty folder | |
| 10 | `FE_RENAME` | r0 = path, r1 = new name | |
| 11 | `FE_CD` | r0 = path | |
| 12 | `FE_PWD` | r0 = buffer (128 bytes) | |
| 13 | `FE_OPEN` | r0 = path, r2L = mode (read, write, append) | A = handle |
| 14 | `FE_READ` | Y = handle, r1 = buffer, r2 = length | r2 = bytes read |
| 15 | `FE_WRITE` | Y = handle, r1 = buffer, r2 = length | |
| 16 | `FE_DF` | r0 = path on a drive | r1 = free, r2 = total (blocks; Ultimate: KB) |
| 17 | `FE_MOUNT` | r0 = drive path (`/a`), r1 = image path | (step 2) |
| 18 | `FE_UMOUNT` | r0 = drive path | (step 2) |

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
- **Ultimate to REU and back without the CPU:** a file on the Ultimate
  is loaded whole into a scratch area of free drive banks (`LOAD_REU`,
  banks taken from the allocation table for the copy and given back),
  and written whole from there (`SAVE_REU`). The CPU only walks the
  blocks between that area and the GEOS drive, through `diskBlkBuf`.
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

Still to come (estimate): the Ultimate's listing and stat; scratch
banks, Ultimate transfers; CVT out and in; streams; mount
and umount (sharing the image code with mount.s).

Shared code goes into includes assembled into each module that needs it
(`engine.inc`: constants, the work area, the REU layout; `fereu.inc`:
REU state and handles; `feresolve.inc`: paths, names, entering folders;
`feinfo.inc`: info blocks; `fehandle.inc`: a free handle; `fename.inc`:
a name into a directory entry; `festream.inc`: stream handles; later
`uci.inc`: send, status, data). The UCI helpers
now in mount.s, writeback.s and hibernate.s move into `uci.inc` first, so
there is one copy of them in the source. Mounting at run time needs
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

## Order of work

1. **E1:** dispatcher, paths, current directory, stat, directory
   listing, delete, rename, mkdir, rmdir on GEOS drives; tests.
2. **E2:** copy and move between GEOS drives; streams on GEOS files.
3. **E3:** the Ultimate's file system: listing, stat, raw copy both ways,
   delete, mkdir; U64 tests. Then **gush step 1** (decided: it includes
   the Ultimate's file system).
4. **E4:** CVT both ways, streams on the Ultimate, mount and umount;
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
- Known limits: renaming a folder changes its directory entry, not the
  name in its header (shown as the disk name inside it); native drives
  are covered by the same code but not yet by the test. Copying a folder
  or a REL file is refused (`FE_IS_FOLDER`, `FE_NOT_SUPPORTED`). On a
  native drive the BAM lives in the image, so a copy that fails half way
  leaves its blocks taken (Validate frees them); on the other drives the
  BAM in memory is dropped. The progress routine must not call the
  engine.
