# File engine (design proposal)

Status: **proposal, 2026-11-04, for the user's approval.** Decisions it
builds on: docs/DESIGN.md, "Shell: gush", "Languages" and "gush and file
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
- **Application memory:** none. Buffers: `diskBlkBuf` and `fileHeader`
  between disk calls (as GEOS's own routines do), scratch `$9F70-$9FFF`
  for the running module, state in the REU.
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
    ...                     ; arguments in r0-r4 (below)
    jsr FileEngine          ; guExtTable + 30 (extension entry 6)
                            ; X = 0 or an error; results in r0-r4

`FileEngine` is `jsr OvlCall / .byte 22, 0`: module 22 is a dispatcher
holding a table of (module, entry) per function. It calls the function
through a `jsr OvlCall` in its own code whose two inline bytes it has
just written: OvlCall reads them before it fetches the other module and
brings module 22 back on the way out, so the modified bytes are only
needed for that moment. Zero further resident bytes per function.

C callers (geos-oscar64) get a thin wrapper per function later.

## Paths

- One tree. `/a`-`/d`: GEOS drives A-D (devices 8-11); `/e`: drive E,
  read-only; `/usb0`, `/usb1`, `/sd`: the Ultimate's file system (passed
  to the Ultimate as `/Usb0/...` etc.).
- On GEOS drives, folder components are native folders or 1581
  sub-directory partitions (entered with folders.s's own routines); the
  last component is a file name, at most 16 characters.
- Relative paths are taken from the engine's current directory (`FE_CD`,
  `FE_PWD`), one per caller kind (gush; the desktop), kept in the REU.
  `.` and `..` work everywhere; `..` at a drive's root goes to `/`.
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
| 1 | `FE_STAT` | r0 = path, r1 = 32-byte info block | info: kind (drive, folder, GEOS file, CBM file, Ultimate file or directory), size (blocks or bytes), GEOS class, type and structure, date, read-only |
| 2 | `FE_OPENDIR` | r0 = path (pattern in the last part allowed) | A = handle |
| 3 | `FE_READDIR` | A = handle, r1 = info block | info as `FE_STAT` plus the name; X = `END_OF_DIR` (an own code) at the end |
| 4 | `FE_CLOSE` | A = handle | |
| 5 | `FE_COPY` | r0 = source, r1 = target (a folder or a new name), r2L = flags | |
| 6 | `FE_MOVE` | as `FE_COPY` | (same drive and kind: a rename or a moved entry, else copy then delete) |
| 7 | `FE_DELETE` | r0 = path | |
| 8 | `FE_MKDIR` | r0 = path, r2L = tracks (1581; 0: default) | |
| 9 | `FE_RMDIR` | r0 = path of an empty folder | |
| 10 | `FE_RENAME` | r0 = path, r1 = new name | |
| 11 | `FE_CD` | r0 = path | |
| 12 | `FE_PWD` | r0 = buffer (128 bytes) | |
| 13 | `FE_OPEN` | r0 = path, r2L = mode (read, write, append) | A = handle |
| 14 | `FE_READ` | A = handle, r1 = buffer, r2 = length | r2 = bytes read |
| 15 | `FE_WRITE` | A = handle, r1 = buffer, r2 = length | |
| 16 | `FE_DF` | r0 = path on a drive | r1 = free, r2 = total (blocks; Ultimate: KB) |
| 17 | `FE_MOUNT` | r0 = drive path (`/a`), r1 = image path | (step 2) |
| 18 | `FE_UMOUNT` | r0 = drive path | (step 2) |

Flags for `FE_COPY` and `FE_MOVE`: overwrite (else `FILE_EXISTS`),
raw (no CVT conversion), and a progress vector in r3 (called after every
block with r4 = blocks done; the routine returns C set to cancel). The
engine never asks the user: gush asks before an overwrite or delete
(decision: always, unless `-f`), the desktop shows its own dialog.

Errors: GEOS's codes where they fit (`FILE_NOT_FOUND`, `FILE_EXISTS`,
`INSUFF_SPACE`, `WR_PR_ON`, ...), GeoUltra's `$40`/`$41` as for
folders, new ones from `$48`: end of directory, bad path, not a folder, handle not open,
too many handles, the Ultimate's error (its status text kept for
`FE_ERRTEXT`, a later function).

Handles: at most 4 open at a time (directories and streams), each about
64 bytes of state in REU bank 1, with the current directories and the
path buffers.

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

## Modules (estimate, numbered from 22)

| Module | Holds |
| --- | --- |
| 22 | dispatcher, save and restore of the caller's state |
| 23-24 | path parser: drive, folders (entering them), name; current directories |
| 25-26 | GEOS directory listing and stat (patterns) |
| 27 | Ultimate directory listing and stat |
| 28-29 | delete, rename, mkdir, rmdir (GEOS and Ultimate) |
| 30-32 | copy GEOS to GEOS, scratch banks, Ultimate transfers |
| 33-34 | CVT out and in |
| 35-36 | streams: open, read, write, close |
| 37 | mount, umount (step 2; sharing the image code with mount.s) |

Shared code goes into includes assembled into each module that needs it
(`uci.inc`: send, status, data; `path.inc`; `info.inc`). The UCI helpers
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

## Open for the user

- This proposal as a whole (calling convention, function list, path
  rules, module plan, order of work).
- The `%XX` escape for names the Ultimate's file system cannot hold.
