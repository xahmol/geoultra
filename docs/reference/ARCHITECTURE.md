# GeoUltra: architecture

How the C64 system is built and laid out. Decisions and their reasons are
in [`DESIGN.md`](../design/DESIGN.md); this document is the technical map, kept up
to date as the code grows.

## Source tree

| Path | Contents |
| --- | --- |
| `src/inc/` | `geos.inc` (GEOS 2.0 interface: zero page, variables, constants), `hw.inc` (VIC-II, CIA, SID, REU, Megabyter) |
| `src/kernal/` | the kernal, one file per area (info block, init, IRQ, MainLoop, graphics, ...); `jumptab.txt` lists the 157 GEOS 64 2.0 jump table entries in address order |
| `src/drivers/` | disk drivers at `$9000` (`reudrv.s`: REU image drives), linked with the kernal into `build/reudrv64.bin` |
| `src/input/` | input drivers (`mouse1351.s` is the one in the ROM) |
| `src/boot/` | cartridge bank 0: start-up and system loader |
| `tools/` | `genjumptab.py` (jump table with traps), `mkimage.py` (system image and its load table), `mkcrt.py` (Megabyter `.crt`) |
| `tests/smoke/` | smoke tests (hardware facts) |
| `tests/conformance/` | conformance cases, run by `tools/dev/harness/` against GEOS 2.0 |

## Build

1. ca65 assembles every kernal and driver source; `genjumptab.py` writes
   `build/gen/jumptab.s` from `jumptab.txt` and the symbols the sources
   export: an exported routine gets its `jmp`, every other entry jumps to
   a trap with its entry number.
2. ld65 links the kernal with `src/kernal/kernal64.cfg` into one 16 KB
   image of `$C000-$FFFF` (RAM under I/O and the input driver included).
3. `mkimage.py` packs the images into the system image (ROM banks 1 and
   up), the boot splash first (`--cpu 2`), and writes `build/gen/image.inc`,
   the load table the boot code uses: REU offset, C64 address and length
   per image.
4. ca65/ld65 build bank 0 (`src/boot/`) with that table; `mkcrt.py`
   writes `build/geoultra64.crt`.

## Boot (C64, Megabyter)

1. Reset: the C64 Kernal finds CBM80 in bank 0 and jumps to the
   cartridge, which runs `IOINIT` from the C64 Kernal (CIA set-up), copies
   the loader to `$0200` and runs it from there. The loader copies the
   boot splash (the first `IMG_CPU` images: bitmap to `$A000`, colours to
   `$8C00`) with the CPU straight from the ROM banks, so it also shows
   without an REU, and turns the display on. Status messages are
   pre-drawn strips of the splash's status line in bank 0
   (`tools/dev/splash/mksplash.py --boot`); errors colour the line light red.
2. The loader checks the REU (later also the UCI, 16 MB and the `.cfg`
   start-up check, DESIGN.md), then stashes ROM banks 1..n into the REU
   at `$020000` (bank 2 of the REU map) by DMA from `$8000`.
3. It switches the cartridge off (`$DE02 = $02`) and fetches each image
   from the REU to its C64 address. Images that cover `$D000-$DFFF` need
   all RAM visible during the DMA, but the REU registers are I/O: the
   loader sets up the transfer with the `$FF00` trigger enabled, switches
   `$01` to `$30` and starts the DMA by writing to `$FF00`.
4. It jumps to the kernal's cold start, which sets up the VIC-II, the
   screen, IRQ and input driver and enters MainLoop.

Later: a warm start checks the REU signature (reset recovery) and skips
step 2.

## C64 memory map (GeoUltra)

The GEOS 2.0 map stays as it is for applications (GEOS_REFERENCE.md
section 2). GeoUltra's own use of the system areas:

| Range | GeoUltra |
| --- | --- |
| `$4F00-$5FFF` | at boot only: the cold start (`INIT`, `build/init64.bin`: `ColdStart`, `DiskInit`, `ClockInit`; it ends in `EnterDeskTop`, the banner is gone since 2026-11-11), loaded by the boot ROM and started at `$4F00` (moved down from `$5000` on 2026-11-04 when it had grown; `$4000-$4E7F` holds mount.s's buffers); applications overwrite it later |
| `$9000-$9A7F` | disk driver: vectors `$9000-$902F`, jump table `$9030-$904D`, REU image driver (now to about `$97EB`); planned: the **overlay slot**, rarely used kernal code fetched from the REU on demand |
| `$9A90-$9C7F` | `KEXT`: resident kernal code that no longer fits at `$C000-$FFFF` (the clock, the file list's click and arrow routines, the task and scrap store stubs) |
| `$9D80-$9FFF` | the **overlay slot**: one overlay module at a time (src/kernal/overlay.s) |
| `$9C80-$9D7F` | `dir3Head` (third BAM block of a 1581 image, as GEOS 2.0) |
| `$BF40-$BFFF` | `BFCODE` (`build/kbf64.bin`): `PutDecimal`; GEOS 2.0's kernal starts here too, so applications leave it alone |
| `$C000-$C0FF` | information block (`BootGEOS`, `ResetHandle`, `bootName`, `version` = `$20`, `c128Flag`, `dateCopy` at `$C018`, the reboot code, ToBASIC's buffers, `GU` signature, extension table pointer) |
| `$C100-$C2D6` | GEOS 2.0 jump table, 157 entries |
| `$C2D7-$CFFF` | kernal tables (RODATA) and variables (DATA) |
| `$D000-$DFFF` | RAM under I/O, as GEOS 2.0 uses it: the system font, the fill patterns (GEOS 2.0: `$D010`) and only those routines that GEOS 2.0 also keeps there (file, load and VLIR routines, `SetDevice`, `ReadByte`, the file list of `DBGETFILES`); see "Code under I/O" |
| `$E000-$FE7F` | kernal code |
| `$FE80-$FFF9` | input driver (`MOUSE_BASE`) |
| `$FFFA-$FFFF` | NMI, reset and IRQ vectors in RAM |

VIC-II: bank 2 (`$8000-$BFFF`), colour matrix `$8C00`, bitmap `$A000`
(`$D018 = $38`), sprite pictures from `$8A00` (sprite pointer `$28` for
sprite 0, the mouse pointer).

## x coordinates with GEOS 128 flags

GEOS 2.0 (64) has no `NormalizeX`: applications that pass `DOUBLE_W`
(`$8000`) or `ADD1_W` (`$2000`) on the C64 (geoProgPatch) get the
drawing routines' arithmetic as is. `LineOp` and `PointAddr` do as GEOS
2.0: any high byte other than 0 counts as one page (the card count is the
low byte of the 16-bit difference). `VerticalLine` in GEOS 2.0 adds the
whole x word and writes off-screen (also into its own kernal through the
back buffer); GeoUltra draws nothing there for x from 512 (the screen is
the same, memory stays intact). Six conformance cases (graphics.py).

## Code under I/O

Applications may call any routine that GEOS 2.0 keeps outside `$D000`-
`$DFFF` with I/O banked in (GeoBasic calls `ClearRam` with `$01 = $35`).
So only the jump table entries whose code GEOS 2.0 has under I/O may be
there on GeoUltra, with code that never writes `$01` itself; the entries
are compared with a running GEOS 2.0 (its jump table targets): `GetRealSize`,
`i_FillRam`, `SaveFile`, `SetGDirEntry`, `BldGDirEntry`, `FollowChain`,
`GetFile`, `FindFile`, `LdFile`, `LdDeskAcc`, `LdApplic`, `FreeFile`,
`GetFHdrInfo`, `DeleteFile`, `FindFTypes`, `RstrAppl`, `FastDelFile`,
`RenameFile`, the VLIR routines, `SetDevice`, `ReadByte`. Data under I/O
is read wrongly with I/O in, as on GEOS 2.0 (font, patterns), but does
not crash. Text, arithmetic, string, memory and graphics routines are in
`KCODE`/`CODE`/`BFCODE`; the `GraphicsString` interpreter is overlay
module 5 (`GraphicsString` and `i_GraphicsString` stay resident).

## System font

`tools/fonts/system9.py` is GeoUltra's own 9-point design in a readable
source form; `tools/mkfont.py` builds the GEOS font structure (header,
index table, bitstream) into the kernal's IODATA segment. Its metrics
(advance widths, height 9, baseline offset 6, set width 60, spacing column
on the left) were measured on GEOS 2.0 with the harness so that layouts
of existing applications stay the same. Text routines read the font with
`$01 = $30`.

Text behaviour of GEOS 2.0 found with the harness (and copied):
characters overwrite their whole cell; the underline row holds only the
line, over the cell minus its last column (the whole cell when bold),
then reverse applies; LF moves down `curHeight + 1`, UPLINE up
`curHeight`; a character whose top would be above line 0 is not drawn;
with outline `GetRealSize` reports the baseline 2 lower.

## Menus and the pointer

As GEOS 2.0 (`src/kernal/menu.s`): only the current menu level reacts
to presses; a press turns the mouse off until a menu is drawn again; an
action item flashes asynchronously (MainLoop keeps running) and is
called with the item number in A; `DoPreviousMenu` recovers the level
and redraws the parent. The interrupt level clamps the pointer to the
mouse limits and sets `faultData` (the 1351 driver does not clamp);
MainLoop calls `mouseFaultVec` while `faultData` is set and clears it.

The right mouse button (2026-11-11, for the desktop's context menu):
the 1351 driver reads it from port 1's "up" line (CIA 1 port B bit 0,
read with no keyboard column driven, as the left button) and reports it
only in GeoUltra's info block: `guMouse2` (`$C0E6`), bit 7 clear while
it is held (as `mouseData`), bit 6 set at each press until the reader
clears it (a click between two reads is kept). GEOS applications see
nothing new; with another input driver loaded the byte stays `$80`.
Tests: d5.py in VICE (port 1 as VICE's joyport I/O simulation,
`-controlport1device 37`, all eight lines high when idle or the
keyboard scan sees a joystick); tests/desktop/mouse2u64.py on the U64
by hand (passed 2026-11-11 with the U64's USB mouse).

## Icons

As GEOS 2.0 (`src/kernal/icon.s`): `DoIcons` draws the enabled icons with
`BitmapUp`, turns icons on (menus off when the mouse was off) and calls
`StartMouseMode` with the table's pointer position. A press that the
current menu does not take goes to the icons: hit test by cards; per
`iconSelFlag` the icon flashes asynchronously (presses are ignored
meanwhile) or stays inverted; the routine gets r0L = icon and r0H =
TRUE on a double click (`dblClickCount` still running, counted down per
frame). `BitmapUp` has its own decoder for the compacted format
(repeat, unique, bigcount; one stream over all lines).

## Dialog boxes

As GEOS 2.0 (`src/kernal/dialog.s`): `DoDlgBox` saves the state into
`dlgBoxRamBuf` (zero page `$22-$38`, globals `$849B-$84C0`, the icon
table, the kernal state block `KSTATE` and the sprites; the linker checks
that it fits in 417 bytes), sets the dialog environment (mouse and icons
on, menus off: measured; no processes), draws the box with its shadow
one card right and down, runs the commands with r5-r10 kept, activates
the collected icons and runs MainLoop; `RstrFrmDialogue` restores the
state, recovers the area and returns from `DoDlgBox` with r0L =
`sysDBData`. The system icons OK..DISK are GeoUltra's own
(`tools/dev/mkicons.py`, 48 x 16, label centred by measured width). Not yet:
`DBGETFILES` (the file system).

## File list in dialogs (DBGETFILES)

The box (124 x 88 pixels at the command's offset), five rows of 14 with
the names in bold, up to 15 files from `FindFTypes` (names in
`fileTrScTab`), the arrow icon from six files on, the name already in the
caller's buffer selected and the selection kept in view when scrolling,
as GEOS 2.0. The selected name is always copied to the buffer (r5). The
arrow picture is GeoUltra's own; `AddIcon` is split so the arrow icon can
be placed at a computed position (`IconAt`). The row click and arrow
routines live in `KEXT`. Conformance cases compare the list with GEOS
2.0 pixel for pixel (the oracle disk has at most three files of a type,
so the arrows are checked with `apprun.py`-style runs only).

## Text input

As GEOS 2.0 (`src/kernal/getstring.s`): `GetString` prints the default
text, installs its own key handler (the caller's `keyVector` becomes the
routine called after RETURN with X = length) and a margin fault routine,
and turns on the text prompt: sprite 1, a one-pixel line of font height
+ 1 rows, blinking every 60 frames via `alphaFlag` at interrupt level.
DEL, backspace, INSERT and cursor right delete (the cell is cleared by
`PutChar`'s BACKSPACE); control keys and shortcuts are ignored.

## Drawing details found with the harness

- With both buffers on, pattern drawing (`HorizontalLine`, `VerticalLine`,
  `Rectangle`, `FrameRectangle`), `DrawPoint` and `DrawLine` take the
  background byte as the source and write the result to both screens;
  `InvertLine` instead copies the whole inverted foreground byte.
- `DrawLine` is Bresenham as GEOS 2.0 (start at the smaller x, or y for
  steep lines; error 2 * minor - major); a horizontal line that is not
  recovered is drawn by `HorizontalLine`.
- `GraphicsString`: rectangle corners sorted, the new point becomes the
  pen, the y delta uses only its low byte, `ESC_PUTSTRING` ends the
  string; `ESC_GRAPHICS` in text continues it.

MainLoop enables interrupts on every pass, as GEOS 2.0: routines such as
`DoDlgBox` may be entered with them off.

## Run-time conventions

- `$01 = $30` (all RAM) outside the kernal's I/O sections, as in GEOS 2.0;
  the IRQ handler saves `$01`, banks in I/O and restores it.
- The IRQ handler saves A, X, Y and r0-r15, as in GEOS 2.0 (applications
  and the geos-oscar64 runtime rely on it).
- Raster IRQ once per frame (line 250, in the lower border).
- Unimplemented jump table entries end in a trap: border colour cycling,
  the entry number at `$C0F0` (readable through the monitor or REST).

## Disk driver

`src/drivers/reudrv.s` serves drives A-D, each a whole disk image in the
REU (DESIGN.md, "Drives A-D"). The kernal's jump table reaches the disk
routines through the vectors at `$9000` (`jumptab.txt`: `Name = ($9016)`);
applications call `$9030-$904D` directly.

- **Blocks:** `Locate` turns track/sector into a block number for the
  drive type (1541 speed zones, 1571 second side after block 683, 1581
  40 per track, native 256 per track) and an REU address: the drive's
  first bank (`ramBase`) plus the block number as bank and page. One block
  is one 256-byte DMA; the CPU port is `$35` only around the DMA.
- **The KERNAL ROM window (2026-11-06):** applications call `ReadBlock`,
  `WriteBlock` and `VerWriteBlock` between `InitForIO` and `DoneWithIO`,
  which (as on GEOS 2.0, printer drivers rely on it) leaves the KERNAL
  ROM over `$E000`. Whatever the driver uses above `$D000` (`Dir81`,
  `folderT`/`folderS`, `sysActive`, the overlay stubs and `OvlLoad`)
  is then ROM. So the header swap (`HeaderSwap`) and the header loading
  (`DirHead`, behind `GetDirHead`/`PutDirHead`) run with the CPU port at
  `$35` and give the caller's value back; the rest of the block path
  (`Locate`, the DMA, `MarkDirty`) uses only driver and `$8000` data.
  Found with the GEOS 2.0 deskTop on a 1581 drive A: it ran the ROM's
  "BYTES FREE" text and its stack ran over (tests/drives/desktop81.py).
  New driver code must keep to this: no kernal code or data above
  `$D000` on the block path, or the port switched around it. `OpenDisk`
  (never called in that window) is overlay module 82, for the room.
- **Errors as GEOS 2.0:** track 0 or beyond the disk `INV_TRACK` (2), a
  sector beyond the track `$20` (what the 1541 turbo reports); GEOS 2.0
  then fills the buffer with the drive's stale buffer, GeoUltra leaves it
  alone.
- **Writes** set the block's bit in the drive's dirty map and, on the
  first write, the changed flag in the mount table (both in REU bank 1),
  for the later write-back to the Ultimate file. A read-only drive returns
  `WR_PR_ON`.
- **Mount table** (REU `$01:0100`): `"GUMT"`, version; per drive at
  `$01:0120 + 32 * slot` type (1-4), first bank, tracks (native), flags.
  Dirty maps at `$01:2000 + $2000 * slot`. `DiskInit` (cold start) sets
  `driveType` (`$80 | type`, as GEOS RAM drives), `ramBase` and `NUMDRV`
  from it, makes drive A (8) current and opens it.
- **REU bank 1, the system bank** (2026-11-15: the task areas had been
  put on the native BAM's working copy, found while testing GeoLudo;
  check this map before taking room there):

  | Address | Use |
  |---|---|
  | `$0100-$03FF` | mount table, image paths (`$0200`), home path (`$0300`) |
  | `$0400-$040C` | hibernation header (signature, build ID; the parts: the current task, task slots, legacy banks, the print queue's extra banks and the first of them) |
  | `$0500-$0532` | hibernation: VIC and CIA 2 registers |
  | `$1000` | the jump table's copy (`RepairJumpTab`) |
  | `$1800` | `curDirHead` kept meanwhile (drive E) |
  | `$1A00-$1A5F` | a disk image gone into: its path, `feInfo` |
  | `$1C00-$1DFF` | auto-exec list (autoexec.s) |
  | `$1E00-$1E7F` | task table (task.s) |
  | `$2000-$9FFF` | dirty maps, `$2000` per drive A-D |
  | `$A000-$BFFF` | native drives: the BAM's working copy (reudrv.s `NAT_WORK`, (tracks + 8) / 8 pages) |
  | `$C000-$C78F` | the file engine: state, current directory, handles, Ultimate paths, `FE_WSAVE` |
  | `$D000-$E03F` | task popup: the screen rows it covers (task.s) |
  | `$E100-$E307` | task popup: their colours |
  | `$E400-$E57F` | per task slot the VIC registers |
  | `$E600-$E63F` | the path a new task opens (`FE_TASK`) |
  | `$E700-$E712` | print queue: its header (spool.s `Q_*`) |
  | `$E800-$F9FF` | free (until 2026-11-16 the printer driver slots, which did not fit: now in bank 27 at `$2000`) |

  Not in bank 1 (it comes back from HIBERNAT.BIN on a resume, after the cold start): the cold start's `fontsOn` and `guPrnFast` for a resumed session are in bank 17 at `$FF00` (the ROM mirror's unused last bank; sysdrive.inc `COLD_KEYS`). The `[serials]` table is there too, at `$F000` (serials.s: a count, 32 entries of a class and a serial).
  | `$FA00-$FAFF` | print queue: the job table, 16 of 16 bytes (`JOBTAB`) |
- **InitForIO / DoneWithIO** live in the driver: they bank the C64 Kernal
  ROM in over `$E000` (for serial printer drivers), so they and anything
  running between them must not lie at `$E000-$FFFF`. They also set the
  clock register `$D030` to 1 MHz for the transfer (C128, U64 turbo).
- **Allocation (1541 images):** `SetNextFree` picks blocks exactly as
  GEOS 2.0 does (sector + `interleave`, one less from track 25; following
  tracks at 2 * distance + 4 + interleave; never back to lower tracks; the
  directory track only when the search starts on it), so files land on
  the same blocks. `BlkAlloc`, `NxtBlkAlloc`, `AllocateBlock`,
  `FreeBlock`, `FindBAMBit`, `GetFreeDirBlk`, `AddDirBlock` (BAM change
  left in `curDirHead`, as GEOS 2.0) and `SetGEOSDisk` build on it.
  `interleave` = 8 from `DiskInit`.
- **1581 images** as GEOS 2.0's 1581 driver: block 40/0 is read with
  bytes `$04-$1C` swapped with `$90-$A8` (the disk name where a 1541 has
  it) and swapped back around a write; `GetDirHead` leaves `r4` at the
  last block read (`dir3Head`). Allocation: the BAM in `dir2Head` /
  `dir3Head`, six bytes per track from `$10`; `SetNextFree` takes the next
  sector, searches from the start track down to 1, then from 41 up to 80,
  once more from 39; `BlkAlloc` starts at track 35, or at 39 when called
  from `SaveFile` (GEOS 2.0 looks at its caller's return address; the
  kernal's SaveFile sets the driver's `saveFlag`) and goes back to 35
  after two blocks. Checked with `make conformance81`.
- Native (CMD format, `.dnp`): header 1/1 (swapped like the 1581's),
  directory chain from 1/34, BAM from 1/2 offset `$20`, 32 bytes a track,
  sector 0 in bit 7, a set bit free (checked against a DNP's file chains).
  The 1541/1581 BAM routines call `BamType`; on a native drive it takes
  the calling routine's return address (`nativeFrom`) and overlay module 3
  (`NativeOp`) does that routine's work (`FindBAMBit`, `AllocateBlock`,
  `FreeBlock`, `SetNextFree`: on from r3, then from track 1; `BlkAlloc`:
  from 1/0; `DirTrackFree`: the directory may grow anywhere), returning to
  the routine's caller. The BAM is used through a working copy in REU bank
  1 at `$A000` (module 6): `GetDirHead` loads it, `PutDirHead` writes it to
  the image and marks those blocks for the write-back, so changes without
  `PutDirHead` are dropped as GEOS 2.0 drops a changed `curDirHead`; one
  copy, for the drive in `natLoaded`. The 18-page directory limit of
  `GetFreeDirBlk` stays (GEOS 2.0's; MegaPatch 3 allows more on native).
  `make test-native` (tests/drives/write.py native): save, read back,
  delete, directory growth and the working copy, on a copy of a DNP.
- 1571 (`.d71`): as GEOS 2.0's 1571 driver (behaviour reference
  mist64/geos drv/drv1571.s): tracks 1-35 as on a 1541, 36-70 with the
  sector bits in `dir2Head` (block 53/0, 3 bytes a track) and the free
  counts in `curDirHead` from `$DD`; `SetNextFree` without the 1541's
  correction from track 25, tracks 18 and 53 only as the start, the sides
  alternating on a double-sided disk (1, 36, 2, 37, ...). `BamType` hands
  1571 drives to overlay module 7 like native ones to module 3. `make
  test-d71` (tests/drives/write.py d71) formats an empty D71 and checks
  saving, the in-memory BAM, the directory and SetNextFree sequences
  against a model of GEOS 2.0's rules.
- Not yet: native subdirectories and 1581 partitions (DESIGN.md,
  "Directories"), 40-track D64s.

## Files

`src/kernal/files.s` (in `IOCODE`, `$01 = $30`) reads files through the
jump table's `GetBlock`, which does its own turbo and I/O set-up per
block: kernal code at `$D000-$FFFF` cannot run between `InitForIO` and
`DoneWithIO`, because the C64 Kernal ROM is mapped then. GEOS 2.0 wraps a
whole `ReadFile` in one `InitForIO`; the result is the same, only real
IEC drivers (phase 6) will pay a little per block. Reading: `FindFile`,
`ReadFile` (track/sector table in `fileTrScTab` from offset 2, buffer
overflow leaves the block in `diskBlkBuf`), `ReadByte`, `FollowChain`,
`GetFHdrInfo`, `FindFTypes` (permanent-name filter through the header).

Writing (`src/kernal/filewrite.s`, in `CODE`): `WriteFile`, `SaveFile`
(header block, VLIR index block and data allocated in one `BlkAlloc`;
the header's info byte `$A0` is cleared, as GEOS 2.0 does), `SetGDirEntry`
(date only in the directory block), `BldGDirEntry`, `FreeFile` (VLIR
record chains through `fileHeader`), `DeleteFile`, `FastDelFile`,
`RenameFile`. GEOS 2.0 writes each file twice, the second time with
verify; one pass is enough for an REU image. The jump table addresses
the file code calls are in `src/inc/kcalls.inc`, apart from `geos.inc`,
because the disk driver's own routines carry those names.

VLIR (`src/kernal/vlir.s`, `IOCODE`): while a file is open its index
block is in `fileHeader`; the index block, the directory block and the
entry's offset are kernal variables (in `DATA`, so a task snapshot keeps
them). The BAM is read once before the first change (`fileWritten`);
`UpdateRecordFile`/`CloseRecordFile` write index, entry (date, size) and
BAM. As GEOS 2.0: `usedRecords` counts index entries up to the first
0/0 pair, `PointRecord` returns the record's first track in Y, an
emptied record is 0/$FF, `fileSize` is adjusted by the low byte of the
block count only.

## Boot mounts

`src/kernal/mount.s` (cold start, `INIT`): with a UCI (unlocked on
firmware 3.15 when not mapped), the home folder `GEOULTRA` is looked for
on `/USB0`, `/USB1`, `/SD`, or created with an empty `MOUNTS.INI`
(`[drives]`) on the first present. Every `A=` to `D=` line of `[drives]`
is mounted: the image's folder, `OPEN_FILE $01`, the type from the
extension (D64, D71, D81, DNP; a DNP's tracks from `FILE_INFO`), one
`LOAD_REU` of the whole image into the next free banks from 31, then the
mount table in REU bank 1 for `DiskInit`. Without a UCI (VICE), or when
the REU's table has a drive with unsaved changes (after a reset; there is
no write-back yet), the REU's table stays. The handshake (`src/inc/
uci.inc`, the one copy in the source, assembled into the boot code, the
resident write-back helpers in `DRVEXT`, the clock module 10 and the file
engine's module 36) follows the ultimate-uci-oscar64 library's corrected
`uii_sendcommand`; its reply data stops at an exact address (`dataEnd`). Diagnostics
at `$4E00` (see the source) until an application overwrites them.

## Write-back

A disk write marks the block in the drive's dirty map and starts a delay
of 150 frames (`WbTick` counts it down in the IRQ). When it has run out,
MainLoop (`WbCheck`) calls the write-back, overlay modules 1 and 2
(`src/kernal/writeback.s`); `EnterDeskTop` and `ToBASIC` call it first
too. Only with a UCI (the boot sets `uciPresent`). Per changed drive:
the image's path (stored at boot at REU `$01:0200 + 64 * drive`), its
folder; before the first write-back after a mount a copy into
`<home>BACKUP/` (the home path at `$01:0300`; deletes happen only after a
confirmed change into that absolute path); then the image is opened
(`$03`) and every run of non-zero dirty-map bytes is written with a seek
and one `SAVE_REU` straight from the REU (clipped to the image's size).
The map is cleared and the drive's changed flag too. The UCI command
routines, the DMA helper and the state are resident (`DRVEXT`, after the
driver; the driver's vectors must stay at `$9000`); the path and the
command buffer use the overlay slot's scratch area (`$9F70-$9FFF`).
Overlay modules are at most 496 bytes since then. A failed SEEK or
SAVE_REU keeps the map and the flag, and the write-back is tried again
after 5 s (code sweep 2026-10-30).

Module placement in the REU (2026-10-30): the linker writes the modules
one after another, `$1F0` bytes each (`build/overlays64.bin`); the
Makefile spreads them to a stride of `$200` (`build/overlays64s.bin`, in
the image at `$020000`), so `OvlLoad` computes module n's address
(`$020000 + n * $200`) instead of looking it up: no tables in the
resident `CODE` (55 bytes freed), and new modules cost no resident bytes
(up to 128).

## Serial number

`GetSerialNumber` returns `serialNumber` (DATA), set at the cold start:
`[system] serial=XXXX` (hex) in `GEOULTRA/SETTINGS.INI` (read in
`mount.s` right after the home folder is found), otherwise the serial of
the first mounted drive holding GEOS 2.0's `GEOBOOT` (permanent name
`GeoBoot     V1.0`; file block 82, offset 183, found on the user's GEOS
2.0 D64 and D81), otherwise GeoUltra's own default. With it, applications
installed under the user's GEOS (geoWrite 2.1, which otherwise asks to
"reboot using the same GEOS disk") run. `apprun.py --serial` sets it in
VICE.

## Folders (native drives)

`src/kernal/folders.s` (resident: the current folder per drive, the
extension table; overlay modules 12-14 with the shared helpers in
`src/inc/foldershared.inc`), plus three places in the disk driver.

- Format: CMD native subdirectories. A folder is a directory entry of CBM
  type DIR (`$86`) whose T/S is its header block; a header as the root's
  (1/1): `$00/$01` the first directory block, `$02` "H", name, disk ID,
  "1H", `$20/$21` its own T/S, `$22/$23` the parent header (0/0 at the
  root), `$24/$25` the block of its entry in the parent and `$26` the
  entry's offset (GeoUltra writes the offset of the type byte; to check
  against an image made by CMD software). The BAM is shared.
- Current folder: `folderT`/`folderS` per drive (header T/S, 1/1 the
  root; in RAM, so kept by hibernation). The driver's `DirHead` reads and
  writes that header as `curDirHead`, `HeaderSwap` swaps it (the disk
  name to `$90` as GEOS 2.0 has it), and `FirstDirBlock` (also used by
  `Get1stDirEntry`, `GetFreeDirBlk`) starts at its link: existing
  applications see the folder as the whole disk, with its name.
- Extension jump table at `guExtTable` (`$C0E4` points to it), 5 bytes an
  entry, X = 0 or an error: +0 `GetCurDir` (r1 = the folder, 0/0 without
  folders), +5 `SetCurDir` (r0 = name of a folder in it), +10 `DirUp`, +15
  `DirRoot`, +20 `MakeDir` (r0 = name; X = `$40` when the name exists),
  +25 `RemoveDir` (r0 = name of an empty folder; X = `$41` when not
  empty). `MakeDir` takes two blocks near the current folder (header and
  first directory block); `RemoveDir` frees them through the BAM's
  working copy, so a refused one changes nothing. +30 `FileEngine` (A =
  function: files by path, [FILE_ENGINE.md](../design/FILE_ENGINE.md)).
- `SetGEOSDisk` moved to module 13 (driver room), now also on native
  drives (border block from 1/0); `SaveState`/`RestoreState` moved to
  module 11 (room in CODE for the table).
- Overlay rule learnt here: a module's own bytes are fetched anew after
  every nested overlay call, so variables that must survive one (here
  across `SetNextFree`) are resident.
- `make test-folders` (tests/drives/folders.py): MakeDir, SetCurDir (name,
  root files not seen), SaveFile/ReadFile inside, DirUp, RemoveDir refused
  and then done, the free count back.
- File dialogs (`DBGETFILES`, dialog.s, under I/O): on a native drive
  `GfFolders` puts `..` (not at the root) and the folders as `/name`
  before the files found by `FindFTypes` (within the 15 places; the files
  move down, the last ones drop out); `gfDirs` counts those rows. A folder
  is found again by its position among the DIR entries (`GfScan`), so no
  names are kept and 16-character names work. OPEN on such a row (the
  system icon, `GfOpen`) enters the folder (`..` its parent from
  `curDirHead` `$22/$23`) and builds the list anew; the dialog stays.
  With folders listed and no key routine of the dialog's own, `GfKeys`
  becomes `keyVector`: RETURN on a folder row enters it, DEL goes up.
  While a folder row is selected the application's name buffer is empty,
  so it never gets a folder name back. `make test-filedialog`
  (tests/drives/filedialog.py): geoWrite 2.0's Open dialog on a copy of the
  user's DNP lists the new folder first, RETURN enters it, DEL goes up. The disk name in an application's dialog
  ("On disk:") is the application's own text and stays.
- Not yet: 1581 partitions, renaming and moving folders, `MoveFile`, long
  names, geoFolder, the setting to switch the folders in file dialogs off.

## 1581 partitions as folders

(2026-11-04; the format as the real 1581 DOS writes it:
docs/reference/GEOS_REFERENCE.md, "1581 partitions and sub-directories".)
- State: `folderT`/`folderS` as for native drives; on a 1581 `folderS` =
  0 means "the partition starting at track `folderT`", the default 1/1
  the root (track 40). `Dir81` (folders.s, resident) gives the current
  directory track.
- Driver: `DirHead` reads the header and both BAM blocks from that track
  (`Patch81` sets the three `t1581` tracks); `FirstDirBlock` takes the
  directory start from the header's link for 1581 and native drives
  alike (`t/0` -> `t/3`); `HeaderSwap` and `Next1581` use the directory
  track instead of 40. Allocation needs nothing else: a partition's BAM
  marks every track outside it as used.
- Kernal (module 12 dispatches, module 18 does the work): `GetCurDir`
  gives `t/0` (`40/0` at the root); `SetCurDir` enters a CBM (`$85`)
  entry that is a valid sub-directory (sector 0, whole tracks, at least
  3, track 40 outside) with a formatted header ("D", link `t/3`), else X
  = `STRUCT_MISMAT`; `DirUp` finds the parent by walking from the root
  through the partitions that contain the current one (no parent pointer
  on disk); `DirRoot` as for native drives.
- File dialogs (`GfFolders`, `GfScan`) and geoFolder list CBM entries as
  folders on 1581 drives too (one that is no sub-directory is refused
  when opened).
- `make test-part81`: a D81 made by the real 1581 DOS in VICE (nested
  partitions), entered, left and written by GeoUltra, then read back by
  the real 1581 DOS.
- `MakeDir` on a 1581 (modules 19 and 20): r0 = name, **r2L = size in
  tracks** (0: 10, at least 3); the first run of that many fully free
  tracks of the current directory's BAM that does not include track 40;
  they are allocated there, the CBM entry written, and the partition
  formatted inside as the real DOS's "N0:" does (header "D"/"3D" with the
  disk's ID, BAM over all 80 tracks with only its own free and its first
  track's sectors 0-3 used, empty directory). `RemoveDir` (module 21)
  only on an empty partition that `SetCurDir` would enter (a formatted
  sub-directory; another CBM partition gives `STRUCT_MISMAT`): its tracks freed in the current BAM, the
  entry's type set to 0. Errors as on native drives (`FILE_EXISTS` $40,
  `DIR_NOT_EMPTY` $41, `INSUFF_SPACE`). `make test-part81` also has the
  real 1581 DOS select a partition GeoUltra made and write and read a
  file in it.

## System drive (drive E)

DESIGN.md "System drive": drive E (device 12), read-only, outside A-D.

- Image (since 2026-11-06 a native image with folders; a 1541 image
  before): built from GeoUltra's own GEOS files as CVTs (each
  `src/tools/NAME.s` assembled at `$0400`, packed by `tools/dev/geosapp.py`
  (a copy of geos-oscar64's); gush, gush's external commands). `src/sysdrive.toml` says
  which file goes into which folder (the system's applications, desk
  accessories and fonts in the root, which the kernal merges; gush's
  commands in `bin`); `tools/mkappsdnp.py` builds
  `build/sysdrive-plain.dnp` (8 tracks, `SYSDRV_TRACKS`) from it, and
  `tools/dev/sysreloc.py` moves every track/sector reference (the headers'
  directory, own block, parent and border fields; folder entries;
  directory chains; files' data, GEOS header, VLIR index and record
  chains; the BAM is read by position and stays) up by `SYSDRV_TRACK`
  (247): `build/sysdrive.dnp`, cut after its last used track (1 track,
  64 KB today), which `mkimage.py` places at REU bank 4 (`FILE@BANK4`).
  Constants in `src/inc/sysdrive.inc`.
- High tracks: the driver's `Locate` reads tracks 248-255 of every drive
  from bank 4 as a native image (block (track - 248) * 256 + sector);
  `WriteBlock` refuses them (`WR_PR_ON`). So a file found on E is read
  through the current drive, also by an application that keeps
  track/sector pairs: geoWrite reads a font's header, index block and
  records by them. Not on a native drive with more than 247 tracks, whose
  tracks are real (drive E is then left out).
- Showing E in a slot (overlay module 81, `src/kernal/sysenter.s`): a
  drive slot made drive E for a moment: native type, E's track count,
  ramBase = bank 4, F_READONLY, its root folder 1/1, E's root header in
  `curDirHead`; the slot's values are kept and put back. The driver keeps
  E's BAM out of the native BAM working copy while E is shown (`DirHead`
  tests `sysActive`). The kernal's searches (below) borrow the current
  drive's slot and keep `curDirHead` in REU bank 1; the file engine
  (`/e`) uses an empty slot only, for one engine call (FILE_ENGINE.md).
- Search (`src/kernal/sysdrive.s`, overlay module 15): E's root folder is
  read by borrowing the current drive's slot for a moment (module 81),
  resident saved values.
  Reading E's directory loads E's header into `curDirHead`: it is kept in
  REU bank 1 at `$1800` meanwhile (the GEOS 2.0 deskTop otherwise took
  drive A for "GEOULTRA SYSTEM" and asked for that disk).
  - `FindFTypes` ends in `SysFTypes`: for `DESK_ACC` and `FONT` with room
    left, it runs once more on E into the rest of the caller's buffer.
    For an application's font list (2026-11-16) module 116 then reads
    the font ID of each font in it (FindFile, the header block's `$80`)
    and takes out E's fonts whose ID one of the drive's own fonts has:
    one entry per ID, the user's (their LW_Roma, ID 27, hides GU Serif).
    Its state is in the overlay scratch (`$9F70-$9F98`): Enter and Leave
    are overlay calls. A place freed so stays empty (E's search already
    stopped at the list's limit).
  - `SysFindFile`: `FindFile`, and when the name is not found, E's
    directory; a desk accessory or font found there is returned (entry
    with E's high tracks). Used by `FindFile` from the jump table
    (`jumptab.txt`: `FindFile = SysFindFile`), `GetFile` and
    `OpenRecordFile`; the kernal's other callers (DeleteFile, RenameFile,
    SaveFile ...) keep plain `FindFile`, so they never touch E's files.
  - A desk accessory from E loads as any other (`LdDeskAcc` reads the
    high tracks); a font opened with `OpenRecordFile` reads its records
    the same way.
- The drive's root folder comes first (overlay module 17,
  `src/kernal/rootmerge.s`, user's decision 2026-11-04): on a native drive
  inside a folder, `FindFTypes` for desk accessories and fonts adds the
  root's after the folder's, and the `FindFile` fallback looks in the root
  before drive E. A root file's track/sector pairs are valid from any
  folder, so only the search changes: curDirHead's directory link (which
  `FirstDirBlock` reads on native drives) points at the root's directory
  (from its header, 1/1) for the search and is put back. Order: the
  current folder, the root, drive E. Checked in VICE with the applications
  DNP: geoWrite started from "Writing" lists the root's fonts.
- Refused applications (same module, `OvAppGate` at the start of
  `LdApplic`): by permanent name (now only GEOS 2.0's "Configure"); the
  flag `sysRefused`, then `EnterDeskTop`, which shows the reason
  (`OvRefused`) after `InitMachine`, before loading the desktop. The
  dialog is built in the stack page above the stack pointer: neither the
  overlay slot (`DoDlgBox` calls overlays) nor EnterDeskTop's own dialog
  (it lives in overlay module 0) can hold it.
- geoFolder (`src/tools/geofolder.s`, 133 bytes): one `DBGETFILES` dialog
  for a file type no file has, so the kernal lists only `..` and the
  folders; OPEN/RETURN/DEL move through them, DISK goes to the next drive,
  OK leaves the chosen folders current.
- Desk accessories are padded to whole blocks by `tools/dev/geosapp.py`
  (geos-oscar64 0.1.2's; before that by the Makefile): c1541 writes a short
  last block full, and a desk accessory's header end address must cover
  all it loads, or `LdDeskAcc` saves less of the application than
  `ReadFile` overwrites (geoWrite crashed after geoFolder until this;
  docs/reference/GEOS_REFERENCE.md section 17).
- Checked in VICE: geoFolder is the last entry of geoWrite 2.0's geos
  menu (the user's DNP as drive B), started from there and closed with
  OK, geoWrite goes on; GeoClock and Text Manager from drive B too.
  `make test-sysfont` puts a font from the user's disks on a test copy of
  E (block by block: c1541 3.10's `-geosread` writes no record data of a
  VLIR file) and patches it into a copy of the cartridge: geoWrite lists
  it in its font menu with its point sizes and types with it.
- No fonts of GeoUltra's own yet: the cartridge's E holds geoFolder only.

## Hibernation

`src/kernal/hibernate.s` (overlay modules 8 and 10, `Snap` at `$BF40`,
`Resume` in KEXT, `HibTick` in KCODE) and `src/kernal/hibresume.s` (module 9), with the
helpers both modules assemble in `src/inc/hibshared.inc`.

- `HibSuspend` (module 8): `WriteBackNow`, the VIC-II registers and CIA
  2's port A/B and direction to bank 1 (`$0500`, `$0530`) by REU DMA,
  then `Snap`: the stack pointer to `hibSP`, all 64 KB of RAM to REU bank
  19 (one DMA, triggered by a write to `$FF00` with all RAM visible). Then
  the header (signature `GUHIB1`, the build ID) to bank 1 at `$0400` and
  `GEOULTRA/HIBERNAT.BIN` (created or overwritten) with four parts, each
  one SEEK + `SAVE_REU`: bank 1, bank 19, bank 18 (desk accessory swap),
  banks 192-199 (the applications' REU), 704 KB. Returns X = 0.
  Since 2026-11-15 the parts are module 115's (`hibernate.s`, for
  saving and loading alike): bank 1, the scrap store (29-30), the task
  banks, bank 18, the tasks' legacy REU, the print queue's banks 27-28
  (always: the driver's work area between calls) and its extra banks
  (spool=, only while records are in the queue). Their sizes and the
  queue's first extra bank go into the header (`$0408-$040C`), as the
  resume runs before the cold start's SpoolInit; a part without banks
  is left out.
- `HibResumeOvl` (module 9) from the cold start, after `MountAll`: with
  a UCI, C= not held, the file there, its signature and build ID this
  kernal's, and its mount table (per drive type, bank, tracks; the image
  paths; the home path) the one just mounted, the four parts are loaded
  back, the file is deleted (an unplanned power-off later must not bring
  back an old state) and `Resume` (KCODE) copies bank 19 back to all of
  RAM. The CPU goes on in `Resume`, whose bytes are the same in the
  snapshot (same build), takes `hibSP` and returns from `Snap` a second
  time with A = 1 (`Resume` may be anywhere resident: those bytes are the
  same in the snapshot); `HibSuspend`'s resumed path restores the chips from
  bank 1 and starts the TOD at the session's time (module 10, `TodSet`:
  the Ultimate's clock is not read yet), and returns X = 0 to its caller.
- Clock: `RtcClock` (module 10, entry 3) asks the Ultimate's real-time
  clock (DOS command `$26`, "yyyy/mm/dd hh:mm:ss") at the cold start
  (after the mounts) and after a resume, sets year .. seconds and starts
  the TOD from them (`TodSet`: 12-hour BCD with the PM bit, the 6526's
  AM/PM flip at 12 handled as in `ClockInit`, and a read of the tenths
  first to release a latch left by an earlier read of the hours). Without
  a UCI (VICE) the build date at midnight stays.
- The build ID (`BUILD_ID`, seconds since 1970 modulo 65536 at build time)
  replaces a CRC of the code: KCODE and CODE modify themselves
  (`OvlCall`, `CallRoutine`). Both objects are rebuilt with every kernal
  change.
- Triggers: `ToBASIC` calls `HibSuspend` first (a resumed session then
  goes to the deskTop, not to BASIC); quiet moments: `HibTick` (interrupt,
  before `WbTick`) marks the session changed on a key or mouse button
  (pointer moves alone do not count: the 1351 jitters) and, after
  `hibLimit` * 256 frames without such input (default 6: about 30 s;
  SETTINGS.INI `[system] hibernate=` seconds, rounded to steps of about
  5 s, `0` off), makes a save due and sets
  `wbPending`; MainLoop's `WbCheck` runs the write-back, whose module 1
  then calls `HibSuspend`.
- Not yet: the Suspend command in the desktop, a hot key, a reset from
  the menu, the "safe to switch off" notice, saving only the banks in use,
  task slots, spooler and clipboard.

- Resized native drives (2026-11-04): MOUNTS.INI `A=path,tracks=N`
  (`SizeOption`); `ResizeFirst` gives the drive N banks and, when smaller,
  loads only N tracks; `ResizeThen` refuses a smaller drive whose BAM
  shows a used block after track N, sets the new tracks free when larger,
  and writes the BAM's last track (1/2 `$08`); the mount table flag
  `F_RESIZED` makes the first write-back open the file "create always"
  and save the whole image (module 2), so file length and BAM agree.
  `KeepDirty` accepts every known flag (`F_KNOWN`: dirty, read-only,
  backup made, resized); until 2026-11-04 it rejected `F_BACKUP`, so a
  written drive's unsaved changes were dropped at the next reset.
- Power-on (U64, 2026-10-30): `FindHome` searches up to 10 s for an
  existing GEOULTRA folder before creating one (`/USB0` appears seconds
  after the C64 starts); `KeepDirty` keeps an REU mount table only when
  every entry is plausible (the U64's REU holds a faded copy after a short
  power-off); `ClearTable` clears the table and the paths at
  `$01:0200-$02FF`, so `CheckFile` compares like with like; `RtcClock`
  takes a year before 2026 as "clock not set yet" (the Ultimate's default
  until its network time) and `RtcCheck` (MainLoop, before `WbCheck`)
  asks again once a minute.

## Serial number per application (optional)

`src/kernal/bypass.s`, overlay module 4, only built with `BYPASS=1` (the
default; `make BYPASS=0` leaves it out) and only used when SETTINGS.INI
has `[system] protection=bypass` (`bypassOn`). `GetSerialNumber` then
passes the caller's return address to `ExpectedSerial`, which examines
the 32 bytes after it for a load of `r0L`/`r0H` followed by a compare
with an absolute address, or a load from an absolute address followed
by a compare with `r0L`/`r0H` (LDA/CMP, LDX/CPX, LDY/CPY), and answers
with the bytes stored at those addresses. Nothing found, or both bytes
0 (not installed yet): the system's own serial number. The module holds
no data from any application. `apprun.py --bypass` switches it on in
VICE. Tested: geoWrite 2.1 installed under `$58B5` refuses with serial
`$1234` and starts with the bypass on; geoWrite 2.0 is unchanged.

### Install on GeoUltra

An application's first-run check for its original disk (geoWrite 2.1:
the block at 13/7 or 13/9, see "Inside geoWrite 5" on pagetable.com)
follows the `NewDisk` vector, takes the six bytes after the first
`STA $8B` there (on GEOS 2.0's 1541 driver: the calls that execute drive
code and fetch its status) and calls them between `InitForIO` and
`DoneWithIO`; X = 0 means original. The REU driver's `NewDisk` starts
with a `jmp` over such a sequence that is never run: `sta $8B / jsr
ProtExecute / jsr ProtStatus`. `ProtStatus` answers X = 0 only with the
module on (`bypass.s`), else `DEV_NOT_FOUND`, so the check fails cleanly
instead of scanning random memory. Both routines are in KCODE: between
`InitForIO` and `DoneWithIO` the C64 Kernal ROM covers `$E000`-`$FFFF`.
Such checks accept only 1541/1571 drive types, so it works on D64 images
made from the original disk (the protection block is an ordinary sector;
only the gap signature is lost). `make test-bypass` runs the check's
calling sequence in VICE (`tests/bypass/hook.py`).

The "unkeyed" collections (applications with the check removed and no
serial stored) run on GeoUltra without any of this; tested: geoWrite 2.1.

## Jump table repair

`SaveJumpTab` (cold start, last step) stashes the jump table `$C100`-`$C2D6`
to REU bank 1 at `$1000`; `RepairJumpTab` fetches it back in `StartAppl`
(after `SaveArgs`, as it uses r0-r3) and in `EnterDeskTop` (after the
write-back). A program that changed the table (a buggy one, or the
deskTop incrementing `LdDeskAcc` when it finds a foreign serial) cannot
break the next one. Programs that patch the table on purpose and expect
it to stay patched across applications lose the patch; auto-exec support
will take the copy after the auto-exec files have run.

## Overlays

Rarely used kernal routines live in overlay modules of at most 496 bytes
(`$1F0`), linked to run at `$9D80` (segments `OVL0`, `OVL1`, ... in
`build/overlays64.bin`, spread by the Makefile to a `$200` stride in
`build/overlays64s.bin`) and stored at the start of the system image, so
module n sits at REU `$020000 + n * $200` after the boot (mkimage's
`FILE@REU`: in the image, no load table row; `OvlLoad` computes the
address). A routine keeps a 5-byte resident stub, `jsr OvlCall` and
`.byte module, entry`; `OvlCall` fetches the module when another one is
in the slot (one REU DMA), calls the entry with A, X, Y and the flags as
at the stub, fetches the previous module back and returns to the stub's
caller, so overlay routines may call each other. Overlay code must never
install a vector into the slot (callbacks stay resident), and nothing
the IRQ or a BASIC program after `ToBASIC` may reach goes there (`ToBASIC`
and its NMI routine stay at `$Cxxx`). Module 0: `EnterDeskTop` with its
dialog, `FirstInit`, Panic's message (Panic takes the BRK address from
the stack resident, before the overlay call) and `CRC`.

| Module | Holds | Source |
| --- | --- | --- |
| 0 | EnterDeskTop, FirstInit, Panic's message, CRC | load.s |
| 1, 2 | write-back: all drives, one drive | writeback.s |
| 3 | native allocation | reudrv.s |
| 4 | serial-number measures (left out with `BYPASS=0`) | bypass.s |
| 5 | GraphicsString | gstring.s |
| 6, 7 | native BAM copy and free count; 1571 allocation | reudrv.s |
| 8, 9, 10 | hibernation: suspend, resume, the clock | hibernate.s, hibresume.s |
| 11 | dialog state (SaveState, RestoreState), the dialog box drawn and recovered | dialog.s |
| 12, 13, 14 | folders: the moves; SetGEOSDisk, RemoveDir; MakeDir | folders.s |
| 15 | drive E, the application gate, the refusal notice | sysdrive.s |
| 16 | turbo per application | speed.s |
| 17 | fonts and desk accessories from the root folder | rootmerge.s |
| 18-21 | 1581 partitions: entered and left, created, formatted, removed | folders.s |
| 22-80 | file engine: dispatcher; path made absolute, walked; stat and free space; directory opened; delete, rename, folders, cd; directory read; copy and move (source, target, blocks); stream opened, new file, read, written; the Ultimate: exchange and listing, stat, listing opened, entries, `/`, delete/folders/rename/cd; raw copies onto and from it; long names (`GU.LONGNAMES`): looked up, kept, short names, listing entries, rename/mkdir, new entries; (55: `FE_RUNSYS`, sysdrive.s); CVT onto and from the Ultimate (out, VLIR out, in, VLIR in, recognised); streams on the Ultimate (open, read, write, their setup); mounting (mount, umount, MOUNTS.INI); new images; turbo, home folder, clock for gush; NTP; the Ultimate's command interface for gush's network commands (`FE_UCI`) | engine.s, enginepath.s, enginedir.s, enginefile.s, enginecopy.s, enginestream.s, engineult.s, enginexfer.s, enginelong.s, enginecvt.s, enginestreamu.s, enginemount.s, enginemkimg.s, enginesys.s, enginentp.s, enginenet.s ([FILE_ENGINE.md](../design/FILE_ENGINE.md)) |
| 81 | drive E shown in a slot and hidden again (Enter, Leave, ShowE, HideE, a free slot) | sysenter.s |
| 82 | OpenDisk | reudrv.s |
| 83-85 | moves and copies between the Ultimate and GEOS drives | engineuu.s |
| 86 | the pointer's design and colour (boot, `FE_POINTER`) | pointer.s |
| 87 | the drive letters in the file box | drvlist.s |
| 88-90 | disk images gone into like folders: recognised, shown, entered, dropped | engineimg.s |
| 91 | a native image's size on mounting (`tracks=`) | enginesize.s |
| 92, 93 | auto-exec files and SETTINGS.INI's `[system]` at the cold start | autoexec.s |
| 94 | the date's roll-over (NextDay) | time.s |
| 95-99 | tasks: the popup (and the close question), the switch and a new task, the table and closing, `FE_TASK` | task.s |
| 100 | the file box's press; the text prompt's set-up (InitTextPrompt, from getstring.s, linked after dialog.s) | dialog.s, getstring.s |
| 101-104 | the scrap store: find, delete, save (data, entry) | scrap.s |
| 105-114, 120 | the print queue: set-up, the driver caught, recording, writing, playing, the driver lent, waiting for room, a job played or passed over, `FE_SPOOL`; "is the queue playing?" for the write-back | spool.s |
| 115 | the hibernation file's parts | hibernate.s |
| 116, 123, 124 | the system fonts: one entry per font ID, searched, their rules | sysdrive.s |
| 117 | a folder's (or 1581 partition's) first directory block | folders.s |
| 118 | drive B swapped with a document's drive (`FE_DRVSWAP`) and back | drvswap.s |
| 119, 125 | drive E in an occupied slot; a handle's drive, also `/f` | sysenter.s |
| 121, 122 | FONTS.DNP loaded and relocated at the cold start | mount.s |
| 126, 127 | serial numbers per application: SETTINGS.INI's `[serials]`, `FE_SERIALS`, the lookup | serials.s |

The scratch `$9F70-$9FFF` after the slot is shared by write-back and
hibernation (from MainLoop) and the file engine (its work area during a
call, `engine.inc`); neither runs inside the other.

Each module's use is in `build/kernal64.map` (`OVL<n>`); the linker
refuses one over `$1F0`. Code that several modules need is assembled into
each from an include (`foldershared.inc`, `part81.inc`, ...), as a module
cannot call another's code.

## Loading and starting

`src/kernal/load.s`: `GetFile` starts applications and auto-exec files
(`LdApplic`), runs desk accessories (`LdDeskAcc`) and loads other files
(`LdFile`, record 0 of a VLIR file). `StartAppl` resets the stack, runs
`InitMachine` (VIC, CIAs, keyboard, hardware vectors, then the dialog
environment with `mouseOn` = 0, `BRKVector` = Panic, `msePicPtr` =
`mousePicData`, as GEOS 2.0) and calls the application from MainLoop
(`MainLoopCall`).

- **Desk accessories** swap through REU bank 18 instead of GEOS 2.0's
  swap file: the memory the accessory loads over and the saved kernal
  state (`dlgBoxRamBuf` after `SaveState`) go to the same addresses in
  that bank; `RstrAppl` fetches both back, restores the stack and returns
  to `GetFile`'s caller.
- **EnterDeskTop** loads `DESK TOP` (version 1.5 or higher, as GEOS 2.0)
  from the current drive, then the others; until GeoUltra's own desktop
  exists this starts the user's GEOS 2.0 deskTop, which runs on the
  GeoUltra kernal in VICE.
- **Colours after the matrix:** the deskTop and the pad colour manager
  read colours from `$8FE8-$8FF0`; cold start and `FirstInit` set GEOS
  2.0's values there ($BB x 8, $BF).
- **BRK:** the IRQ entry saves A and X, then tests the B flag; a BRK
  leaves through `BRKVector` with X intact and the BRK address + 2 on the
  stack (as GEOS 2.0). (A first version read the stack with `tsx` before
  saving X and corrupted every interrupted routine's X.)
- **Sleep:** up to 20 sleepers, counted down per frame, continued from
  MainLoop after their `jsr Sleep`.
- Space: `KCODE` in the low kernal area (after `KSTATE`, up to `$CFFF`)
  holds code that fits nowhere else: the loader and the point and line
  routines.

`BitmapClip` and `BitOtherClip` share BitmapUp's decoder (one line at a
time, skipping bytes outside the window). BitOtherClip's data comes
through the application: `r13` before every stream byte, `r14` before
every packet outside a bigcount group (as GEOS 2.0, which cannot handle
bigcounts there either; HG2G).

## Leaving GEOS: ToBASIC and BootGEOS

`ToBASIC` (`src/kernal/tobasic.s`, in `KCODE`, which stays RAM while the
BASIC and Kernal ROMs are in) loads an optional PRG, sets up the C64
Kernal (CIAs, vectors, screen) and starts BASIC; a few CIA 2 NMIs later
it puts the command on the screen and RETURN in the keyboard queue, and
RESTORE then leads to `BootGEOS`. Its buffers lie in the information
block (`$C02B`), which BASIC programs leave alone. `BootGEOS` (`$C000`)
reboots GeoUltra from the cartridge (Megabyter on, `jmp ($8000)`); the
boot ROM itself starts the kernal through `ResetHandle` (`$C003`). REU
drives survive the reboot through the mount table; `sysFlgCopy` bit 5
tells programs that no boot disk is needed. Checked in VICE: the BASIC
screen after `PRINT 7*6` is the same as GEOS 2.0's, `SYS49152` returns to
GeoUltra with drive A still mounted.

## Clock

`src/kernal/time.s` (in `KEXT`): CIA 1's time-of-day clock is the master
clock, as in GEOS 2.0. At cold start the raster line count picks 50 Hz
(PAL) or 60 Hz for the TOD, the TOD starts at 12 AM and the date at the
build date (until the Ultimate's real-time clock is read, DESIGN.md).
Writing 12 to the TOD hours flips AM/PM on a 6526 (and in VICE): the
start writes `$92` and checks. MainLoop copies hour (0-23), minutes and
seconds, advances the date when the clock passes midnight (leap years
every fourth year, 99 -> 0) and handles the TOD alarm: `alarmSetFlag`
bit 7 calls `alarmTmtVector`, bit 6 beeps (own sound) the number of times
in its low six bits.

## Conformance harness

`make conformance` (`tools/dev/harness/harness.py`, VICE binary monitor client
`tools/dev/harness/vicemon.py`) boots GEOS 2.0 from the user's own disk and
GeoUltra in two VICE 3.10 instances, stops each at the top of its MainLoop
and saves a snapshot (`build/harness/*.vsf`). Per case it restores the
snapshot, clears both screen buffers, writes the inputs (registers,
r0-r15, a test pattern for `curPattern`, `dispBufferOn`, memory), calls
the routine through a trampoline at `$0340` with interrupts off, and
compares the listed outputs: screen buffers, A/X/Y, r-registers. Only
what HG2G says a routine returns or leaves unchanged is compared; the
registers it destroys may differ. GeoUltra's snapshot is rebuilt
automatically when the cartridge is newer; `CONF_REBUILD=1` rebuilds both.

- **Font swap:** BSW 9 in GEOS 2.0 has the same layout as GeoUltra's
  system font (widths, set width 60, height 9), so the harness writes our
  bitstream over BSW 9's (`$D2DC`) before every case: GEOS 2.0 then draws
  system-font text (menus, dialogs) with our glyphs and screens compare
  pixel for pixel.
- **System icon swap:** the harness finds GEOS 2.0's table of the six
  dialog system icons and points it at GeoUltra's icons placed at `$5C00`,
  so dialogs compare pixel for pixel too.
- **Event cases** (`events`): after the call MainLoop runs and the harness
  injects pointer moves, presses and releases (as the GeoUTools mouse
  automation: `mouseXPos`/`mouseYPos`, `mouseData`, `pressFlag`). Before
  such a case a clean-up routine stops the running application on both
  systems (GEOS 2.0: the deskTop): `appMain`, application vectors and
  processes off, `RecoverVector` back to the kernal default.
- **Behaviour reference:** where HG2G is not precise enough (menus), the
  reassembled kernal (mist64/geos) is read for behaviour only; such code
  carries a credit comment, and the harness checks the result.
- **Key events** (`{"key": code}`): the harness sets `appMain` to a
  one-shot routine that clears it, sets `keyData` and calls `keyVector`,
  so the key arrives exactly as from MainLoop on both systems. `poke`
  writes memory after the clean-up (which clears the vectors).
- **Disks:** GEOS 2.0 runs from a fresh copy of the oracle disk
  (`build/harness/oracle.d64`, so write tests never touch the user's
  disk); GeoUltra gets the same disk as drive A through a 16 MB REU image
  (`-reuimage build/harness/reu.bin`, not written back) holding a mount
  table and the image at bank 31. VICE snapshots restore GeoUltra's REU
  per case but not GEOS 2.0's disk: cases that write (`writes=True`) run
  after all others, and each one after the first gets a newly started
  GEOS 2.0 VICE with a fresh disk copy (the snapshot restores the booted
  system).
- **Applications:** `tools/dev/harness/apprun.py NAME [events]` boots
  GeoUltra with the oracle disk as drive A and an applications disk
  (`GEOS_APPS_DISK`, the user's own) as drive B, starts NAME with
  GetFile, plays mouse and key events and renders the screen to a PNG.
  Its key routine lives in GeoUltra's information block: applications
  use `$0200-$03FF` (a stub at `$02A0` crashed geoPaint).
- **Keys on GEOS 2.0:** now and then GEOS 2.0 has no `keyVector` when a
  case's first key arrives (its text input already gone); such a case runs
  once more on the GEOS 2.0 side. Keys wait until the delivery routine has
  run.
- **Snapshots stop exactly at MainLoop** through a permanent checkpoint:
  VICE 3.10 runs on after a temporary one, and a snapshot taken at a
  random point (for example inside the clock update, with I/O on) made
  every case start with `$01 = $35`. The trampoline also sets `$01 = $30`
  and reads the TOD tenths (unlatching the clock) before each case.
- **1581 set** (`--set d81`, `make conformance81`,
  `tests/conformance81/`): GEOS 2.0 boots the user's GEOS64.D81 on a 1581
  (`GEOS_ORACLE81`), GeoUltra mounts the same image. GEOS 2.0's emulated
  1581 only works reliably in the VICE that booted it, so that side boots
  afresh at the start, before every write case after the first and for
  every retry; a case whose oracle hangs runs once more.
- `--show NAME --area x0,y0,x1,y1 [--systems geos]` prints both screens
  as ASCII art; `HARNESS_TRACE=1` prints each case before it runs (to find
  one that hangs).

## Attribution

Interface addresses (jump table entries, variables, zero page) come from
*The Hitchhiker's Guide to GEOS v2022* (HG2G2022) and, where HG2G does not
list them, the reassembled kernal's `inc/jumptab.inc` and
`inc/geossym.inc` (mist64/geos, Maciej Witkowiak). They are the published
interface that applications are compiled against; no code or tables are
taken from those sources.
