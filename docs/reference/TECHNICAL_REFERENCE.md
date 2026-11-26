# GeoUltra technical reference

What GeoUltra adds to and changes from GEOS 2.0, for people who write
or port GEOS programs. It is a delta: everything not mentioned here is
meant to behave as the Hitchhiker's Guide to GEOS (HG2G) and GEOS 2.0
describe it. GeoUltra aims for that; it does not promise that every
program written for GEOS 2.0 runs (see the manual, "What was tested").

The GEOS 2.0 interface itself is summarised in
[`GEOS_REFERENCE.md`](GEOS_REFERENCE.md) and, routine by routine, in
[`GEOS_API_REFERENCE.md`](GEOS_API_REFERENCE.md). How GeoUltra is built
inside is in [`ARCHITECTURE.md`](ARCHITECTURE.md).

<!-- toc -->
<ul>
<li><a href="#what-stays-where-geos-20-put-it">What stays where GEOS 2.0 put it</a>
</li>
<li><a href="#detecting-geoultra">Detecting GeoUltra</a>
</li>
<li><a href="#the-rest-of-the-information-block">The rest of the information block</a>
</li>
<li><a href="#extension-jump-table">Extension jump table</a>
</li>
<li><a href="#drives">Drives</a>
</li>
<li><a href="#the-file-engine">The file engine</a>
</li>
<li><a href="#the-reu-as-programs-see-it">The REU, as programs see it</a>
</li>
<li><a href="#tasks-hibernation-and-the-clipboard">Tasks, hibernation and the clipboard</a>
</li>
<li><a href="#jump-table-repair">Jump table repair</a>
</li>
<li><a href="#turbo-and-timing">Turbo and timing</a>
</li>
<li><a href="#input">Input</a>
</li>
<li><a href="#serial-numbers">Serial numbers</a>
</li>
<li><a href="#leaving-geos-tobasic">Leaving GEOS: ToBASIC</a>
</li>
<li><a href="#file-formats">File formats</a>
</li>
<li><a href="#compatibility-notes">Compatibility notes</a>
</li>
</ul>
<!-- /toc -->

## What stays where GEOS 2.0 put it

- The jump table `$C100`-`$C2D6` (157 entries), with the registers in and
  out and the "Destroys" lists of HG2G chapter 20. All entries exist.
- The information bytes `$C000`-`$C02F`: `bootName` "GEOS BOOT" at
  `$C006`, `version` `$20` at `$C00F`, `nationality`, `sysVersion`,
  `sysFlgCopy` (`$C012`), `c128Flag` (`$C013`, 0: a C64), `dateCopy`
  (`$C018`).
- The variables `$8000`-`$88FF`, the disk driver's jump area at `$9000`,
  the input driver at `$FE80`, printer drivers at `$7900`.
- The zero page: r0-r15 at `$02`-`$21`, the kernal's variables up to
  `$48`, a0-a9 left alone, `$80`-`$FA` free for applications.
- `$01` = `$30` (all RAM) outside the kernal's I/O sections; the
  interrupt saves A, X, Y and r0-r15.

GeoUltra also keeps some register values GEOS 2.0 leaves behind that
HG2G does not promise (for example A = the number of records and Y =
the current record after `OpenRecordFile`), because programs use them.

## Detecting GeoUltra

| Address | Bytes | Meaning |
| --- | --- | --- |
| `$C0E0` | "GU" | GeoUltra is running |
| `$C0E2` | 2 | version: major, minor |
| `$C0F5` | 6 | patch number, then the build's year (from 2000), month, day, hour, minute |

Test the signature before using anything else in this document. GEOS
2.0's own bytes (`bootName`, `version`) read as GEOS 2.0's.

## The rest of the information block

| Address | Name | Meaning |
| --- | --- | --- |
| `$C000` | `BootGEOS` | back to GeoUltra (from BASIC, and by RESTORE there): a reboot from the cartridge; mounted drives stay |
| `$C003` | `ResetHandle` | the same |
| `$C028`-`$C062` | | ToBASIC's buffers (do not use) |
| `$C0E4` | `guExtTable` | address of the extension jump table (below) |
| `$C0E6` | `guMouse2` | the right mouse button: bit 7 clear while it is held, bit 6 set at each press (the reader clears it) |
| `$C0F1` | `trapAddress` | the jump table entry a program called that ended in the trap (a word; should not happen: all entries exist) |
| `$C0F3` | `ptrColour` | the pointer's colour (0-15) |
| `$C0F4` | `progColours` | programs' colours: ink in the high nibble, paper in the low one (the desktop's theme sets it) |
| `$C0FB` | `guClockFresh` | 1 when the cold start took the time from the Ultimate's clock and nothing has set it since |
| `$C0FC` | `guPrnFast` | bit 7: GeoUltra's printer drivers use the faster bus timing |

## Extension jump table

`guExtTable` (the word at `$C0E4`) points to a table of 5-byte entries,
called with `jsr`. Each returns X = 0 or an error.

| Offset | Name | In | Out, notes |
| --- | --- | --- | --- |
| +0 | `GetCurDir` | | r1 = the current folder's header (track/sector); 0/0 on a drive without folders |
| +5 | `SetCurDir` | r0 = name of a folder in the current one | that folder is current; programs then see it as the whole disk, with its name |
| +10 | `DirUp` | | the parent folder is current |
| +15 | `DirRoot` | | the root is current |
| +20 | `MakeDir` | r0 = name | a new, empty folder (X = `$40` when the name exists) |
| +25 | `RemoveDir` | r0 = name of an empty folder | removed (X = `$41` when it is not empty) |
| +30 | `FileEngine` | A = function, the rest per function | the file engine (below) |

Folders exist on native drives (CMD native format, DNP images) and as
partitions on 1581 drives. The current folder is kept per drive.

## Drives

- **A-D** (devices 8-11) are disk images held in the REU: D64 (1541),
  D71 (1571), D81 (1581) or DNP (native, up to 255 tracks). Every drive
  is a track/sector block device with a BAM, as GEOS expects; changes
  are written back to the image on the Ultimate automatically.
  `driveType` holds GEOS's drive type with the RAM flag.
- **E** (device 12) is the system drive: read-only, with GeoUltra's own
  applications, desk accessories, fonts and printer drivers. `FindFile`,
  `GetFile` and `FindFTypes` look on E after the current drive, so
  programs find GeoUltra's tools and fonts from every disk.
- System fonts: fonts installed in `GEOULTRA/fonts` are found from every
  drive, as drive E's are.
- A native folder without a name in its header (as some PC tools make
  them) takes its entry's name in the parent folder as the disk name.

## The file engine

`FileEngine` (+30 in the extension table) works on paths across the
GEOS drives and the Ultimate's file system, converting GEOS files to and
from CVT where the target needs it. gush, GeoUltra's shell, and the
desktop are built on it.

Paths: `/a`-`/e` the GEOS drives, `/usb0`, `/usb1`, `/sd` and so on the
Ultimate's file system, `/` the list of both, relative paths from the
current directory. At most 127 bytes, zero-terminated. Names are exact
and case-sensitive on GEOS drives; wildcards `*` and `?` only in the last
part of `FE_OPENDIR`'s pattern. Names the Ultimate's FAT cannot hold
(`/ \ : * ? " < > |`) are stored as `%XX` there and read back. A disk
image on the Ultimate can be entered like a folder
(`/usb0/disks/work.d81/...`); it is lent a free drive slot for the call.

| No. | Name | In | Out |
| --- | --- | --- | --- |
| 0 | `FE_VERSION` | | r0 = the engine's version |
| 1 | `FE_STAT` | r0 = path, r1 = 16-byte info block, r2 = 0 or a 61-byte buffer | the info block; the long name (else the name) in r2's buffer; a GEOS file's header in `fileHeader` |
| 2 | `FE_OPENDIR` | r0 = a folder, a pattern, one name, or `/` | A = handle |
| 3 | `FE_READDIR` | Y = handle, r1 = info block, r2 = 61-byte name buffer, r3 = 0 or a 17-byte buffer | info, the long name (else the short one), the short name in r3's buffer; X = `FE_END_OF_DIR` at the end |
| 4 | `FE_CLOSE` | Y = handle (`$FF`: all) | |
| 5 | `FE_COPY` | r0 = source, r1 = target (a folder or a new name), r2L = flags | |
| 6 | `FE_MOVE` | as `FE_COPY` | |
| 7 | `FE_DELETE` | r0 = path | |
| 8 | `FE_MKDIR` | r0 = path, r2L = tracks (1581 partitions; 0: default) | |
| 9 | `FE_RMDIR` | r0 = path of an empty folder | |
| 10 | `FE_RENAME` | r0 = path, r1 = new name | |
| 11 | `FE_CD` | r0 = path | |
| 12 | `FE_PWD` | r0 = 256-byte buffer | |
| 13 | `FE_OPEN` | r0 = path, r2L = mode (read, write, append) | A = handle |
| 14 | `FE_READ` | Y = handle, r1 = buffer, r2 = length | r2 = bytes read |
| 15 | `FE_WRITE` | Y = handle, r1 = buffer, r2 = length | |
| 16 | `FE_DF` | r0 = a path on a drive | r1 = free, r2 = total (blocks; on the Ultimate KB) |
| 17 | `FE_MOUNT` | r0 = `/a`-`/d`, r1 = an image's path (63 characters at most; may end in `,tracks=N` for a DNP) | mounted (the old image written back first); `INSUFF_SPACE`: no room in the REU |
| 18 | `FE_UMOUNT` | r0 = drive path | written back and emptied |
| 19 | `FE_GETLONG` | r0 = path, r1 = 61-byte buffer | the long name, else the short one |
| 20 | `FE_SETLONG` | as `FE_RENAME` | |
| 21 | `FE_SELECT` | r0 = a file on a GEOS drive, r1 = 17-byte buffer | its drive and folder made current; its short name in r1's buffer (for `GetFile`) |
| 22 | `FE_RUNSYS` | r0 = an application's name on drive E | started; back only with an error |
| 23 | `FE_MOUNTINFO` | r0 = drive path, r1 = 64-byte buffer | r2L = its drive type, r3L = a native drive's tracks, r3H = its flags, the image's path in the buffer |
| 24 | `FE_MKIMG` | r0 = a new image's path, r1 = disk name (or 0), r2L = a DNP's tracks (0: 16) | an empty image made and saved |
| 25 | `FE_TURBO` | r2L = `$FF`: ask; 0-15: set | r1L = the Ultimate 64's speed step |
| 26 | `FE_HOME` | r1 = 32-byte buffer | the home folder's path |
| 27 | `FE_SETTIME` | (GEOS's date and time set first) | the CIA clock set from them |
| 28 | `FE_REBOOT` | Y = 0: a fresh start; 1: the session kept | drives written back and GeoUltra restarted; Y = 1 comes back after the restart with X = 0 |
| 29 | `FE_NTP` | r0 = a server's name, or 0 for SETTINGS.INI's | GEOS's clock set from it |
| 30 | `FE_UCI` | r0 = a command for the Ultimate, r1L = its length (2-128), r2 = reply buffer, r3 = its size | r3 = the reply's length, r4 = the status's first two characters |
| 31 | `FE_POINTER` | r2L = design (0-3), r2H = colour ($FF: as it is) | the pointer changed |
| 32 | `FE_TASK` | Y = 0: count; 1: the task popup; 2: r0 = a path a new task opens; 3: r0 = 64-byte buffer | see the tasks section |
| 33 | `FE_SPOOL` | Y = 0: state; 1: pause; 2: resume; 3: r0L = a job to cancel; 4: r0 = 256-byte buffer; 5: r0 = 13-byte buffer | the print queue |
| 34 | `FE_DRVSWAP` | r0L = 10 or 11: that drive and B swapped; 0: back | (for starting programs that only look on A and B) |
| 35 | `FE_RUNDOC` | r0 = application on drive E, r1 = document name, r2 = its disk name | started with the document; back only with an error |
| 36 | `FE_SERIALS` | r0 = an INI text, r1 = its length | its `[serials]` section in use at once |

Flags for `FE_COPY` and `FE_MOVE`: overwrite (else `FILE_EXISTS`), raw
(no CVT conversion), and a progress routine in r3, called after every
block with r4 = blocks done (return with C set to cancel). The engine
never asks the user: the caller does.

Info block (16 bytes): +0 kind (0 `/`, 1 drive, 2 folder, 3 GEOS file,
4 CBM file, 5 Ultimate file, 6 Ultimate directory), +1 CBM type byte,
+2 GEOS structure, +3 GEOS file type, +4 size (4 bytes; blocks on GEOS
drives), +8 date (year, month, day, hour, minute), +13 flags (bit 0
read-only, bit 1 GEOS file), +14 reserved.

Errors: GEOS's codes where they fit (`FILE_NOT_FOUND`, `DEV_NOT_FOUND`,
`INSUFF_SPACE`, `WR_PR_ON` for a locked file ...), `FILE_EXISTS` `$40`,
`DIR_NOT_EMPTY` `$41`, and the engine's own: `FE_CANCELLED` `$47`,
`FE_END_OF_DIR` `$48`, `FE_BAD_PATH` `$49`, `FE_NOT_FOLDER` `$4A`,
`FE_IS_FOLDER` `$4B`, `FE_BAD_HANDLE` `$4C`, `FE_NO_HANDLE` `$4D`,
`FE_NOT_SUPPORTED` `$4E`, `FE_ULTIMATE` `$4F` (the Ultimate said no),
`FE_MOUNTED` `$51`, `FE_NO_TASK` `$53`.

At most four handles (folders and files) are open at a time.

## The REU, as programs see it

GeoUltra needs a 16 MB REU and uses most of it itself (drives, tasks,
the print queue, the clipboard). A program sees **eight banks** of its
own (`ramExpSize` = 8): `DoRAMOp`, `StashRAM`, `FetchRAM`, `SwapRAM` and
`VerifyRAM` translate its banks 0-7 to an area of its task, so it never
reaches GeoUltra's banks, the drives or another task's data. Bank 0 is
also `MoveData`'s scratch, as on GEOS 2.0. Programs that program the REU's
registers themselves, rather than through these routines, reach the
physical banks and can destroy GeoUltra's data.

## Tasks, hibernation and the clipboard

- Several programs can run at once (C= + RUN/STOP switches). A task's
  whole 64 KB, its chip registers and its eight REU banks are kept while
  another runs. A switch happens only at the top of MainLoop, never
  inside a disk call, so a program needs nothing special for it. A VLIR
  file a task has open and changed is committed when the task is left
  and locked for the other tasks (`OpenRecordFile` there, and the file
  engine's delete, rename, move and write, refuse it) until its task
  closes it.
- Hibernation saves the session (all tasks) to the Ultimate's storage
  and resumes it after a power cycle.
- The clipboard: scrap files ("Text  Scrap", "Photo Scrap" and the
  like) are kept in one store in the REU, whatever the program's drive,
  so a paste finds the copy made in another program, on another drive
  or in another task. Programs reach it as before through `FindFile`,
  `DeleteFile`, `SaveFile` and the blocks these return.

## Jump table repair

The jump table is copied at the cold start and restored at every
`StartAppl` and `EnterDeskTop`. A program that patches the table keeps
its patch while it runs; the next program starts with the original
table.

## Turbo and timing

On an Ultimate 64 GeoUltra runs at the speed set in Settings. The
interrupt still comes once per frame, so timing based on it (process
timers, double-click, `Sleep`) stays as on a 1 MHz C64. Programs that
time themselves by counting cycles run faster; such a program can be
put on the 1 MHz list (SETTINGS.INI `[system] slow=`, by permanent
name), and `FE_TURBO` asks or sets the speed.

## Input

The input driver reads a 1351 mouse in port 1 (or the Ultimate 64's USB
mouse, which looks like one) and adds the right button at `guMouse2`
(above). The pointer's design and colour can be changed with
`FE_POINTER`.

## Serial numbers

`GetSerialNumber` returns, in this order: the number listed for the
running application (its class) in SETTINGS.INI's `[serials]`, the
system's choice (`[system] serial=`, or the user's own GEOS 2.0 boot
disk), else GeoUltra's own number. An optional, separate module helps
applications whose copy protection checks the original disk, for
licensed copies only; it is off by default (manual, "Serial numbers").

## Leaving GEOS: ToBASIC

`ToBASIC` works as in HG2G. In addition, a command `LOAD "name",dev`
(with `,1` and `:rest` optional) for a GeoUltra drive that holds the
file loads it from that drive when it fits between `$0801` and `$9FFF`
(at `$0801` without `,1`, at its own address with it), then types what
followed `:`, or `RUN` without `,1`. GEOS 2.0's deskTop starts large
BASIC and machine-code programs that way. Other commands go to the
serial bus unchanged. The boot files of other GEOS systems (GEOS 2.0,
Wheels, MegaPatch3, GDOS64) are refused with a dialog, by an entry in r5
and by a command alike. RESTORE in BASIC, or `SYS 49152`, returns to
GeoUltra.

## File formats

- **CVT** (GEOS files on PC file systems): the usual Convert format;
  GeoUltra writes it when GEOS files are copied to the Ultimate's file
  system and reads it back.
- **MOUNTS.INI** (which image each drive holds), **SETTINGS.INI** (all
  settings) and **theme files**: plain text in the home folder
  (`/USB0/GEOULTRA/`), described in the manual.
- **DNP**: CMD native partition images, up to 255 tracks of 256 blocks;
  folders as CMD native subdirectories.

## Compatibility notes

- GeoUltra is a clean-room kernal: its code is written from the GEOS
  documentation, not taken from GEOS 2.0
  ([`CLEAN_ROOM.md`](CLEAN_ROOM.md)). Programs that jump into GEOS 2.0's
  kernal at addresses outside the jump table, or read its internal
  tables, will not find the same code there.
- Disk drivers are GeoUltra's own: drive code (programs that talk to the
  1541's DOS over the serial bus) does not reach GeoUltra's drives,
  which are images in the REU.
- There are no real serial-bus disk drives yet; printers on the bus
  work through GeoUltra's drivers and the Ultimate's printer emulation.
