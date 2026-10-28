# GeoUltra: architecture

How the C64 system is built and laid out. Decisions and their reasons are
in [`DESIGN.md`](DESIGN.md); this document is the technical map, kept up
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
| `tests/conformance/` | conformance cases, run by `tools/harness/` against GEOS 2.0 |

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
   (`tools/splash/mksplash.py --boot`); errors colour the line light red.
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
| `$9000-$9C7F` | disk driver: vectors `$9000-$902F`, jump table `$9030-$904D`, REU image driver (now to about `$957A`), then the **overlay slot**: rarely used kernal code fetched from the REU on demand |
| `$9C80-$9D7F` | `dir3Head` (third BAM block of a 1581 image, as GEOS 2.0) |
| `$C000-$C0FF` | information block (`BootGEOS`, `bootName`, `version` = `$20`, `c128Flag`, `GU` signature, extension table pointer) |
| `$C100-$C2D6` | GEOS 2.0 jump table, 157 entries |
| `$C2D7-$CFFF` | kernal tables (RODATA) and variables (DATA) |
| `$D000-$DFFF` | RAM under I/O: the system font and other data only read with `$01 = $30` |
| `$E000-$FE7F` | kernal code |
| `$FE80-$FFF9` | input driver (`MOUSE_BASE`) |
| `$FFFA-$FFFF` | NMI, reset and IRQ vectors in RAM |

VIC-II: bank 2 (`$8000-$BFFF`), colour matrix `$8C00`, bitmap `$A000`
(`$D018 = $38`), sprite pictures from `$8A00` (sprite pointer `$28` for
sprite 0, the mouse pointer).

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
(`tools/mkicons.py`, 48 x 16, label centred by measured width). Not yet:
`DBGETFILES` (the file system).

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
- Not yet: allocation on 1571, 1581 and native images (it stops in
  `Trap`), native subdirectories and 1581 partitions (DESIGN.md,
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

## Conformance harness

`make conformance` (`tools/harness/harness.py`, VICE binary monitor client
`tools/harness/vicemon.py`) boots GEOS 2.0 from the user's own disk and
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
  per case but not GEOS 2.0's disk, so write cases must be repeatable.
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
