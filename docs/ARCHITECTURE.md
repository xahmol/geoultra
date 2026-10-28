# GeoUltra: architecture

How the C64 system is built and laid out. Decisions and their reasons are
in [`DESIGN.md`](DESIGN.md); this document is the technical map, kept up
to date as the code grows.

## Source tree

| Path | Contents |
| --- | --- |
| `src/inc/` | `geos.inc` (GEOS 2.0 interface: zero page, variables, constants), `hw.inc` (VIC-II, CIA, SID, REU, Megabyter) |
| `src/kernal/` | the kernal, one file per area (info block, init, IRQ, MainLoop, graphics, ...); `jumptab.txt` lists the 157 GEOS 64 2.0 jump table entries in address order |
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
   up) and writes `build/gen/image.inc`, the load table the boot code
   uses: REU offset, C64 address and length per image.
4. ca65/ld65 build bank 0 (`src/boot/`) with that table; `mkcrt.py`
   writes `build/geoultra64.crt`.

## Boot (C64, Megabyter)

1. Reset: the C64 Kernal finds CBM80 in bank 0 and jumps to the
   cartridge, which runs `IOINIT` from the C64 Kernal (CIA set-up), copies
   the loader to `$0200` and runs it from there.
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
| `$9000-$9D7F` | disk driver jump table and REU block driver (small), then the **overlay slot**: rarely used kernal code fetched from the REU on demand |
| `$C000-$C0FF` | information block (`BootGEOS`, `bootName`, `version` = `$20`, `c128Flag`, `GU` signature, extension table pointer) |
| `$C100-$C2D6` | GEOS 2.0 jump table, 157 entries |
| `$C2D7-$CFFF` | kernal code |
| `$D000-$DFFF` | RAM under I/O: kernal data and code that runs with `$01 = $30` |
| `$E000-$FE7F` | kernal code |
| `$FE80-$FFF9` | input driver (`MOUSE_BASE`) |
| `$FFFA-$FFFF` | NMI, reset and IRQ vectors in RAM |

VIC-II: bank 2 (`$8000-$BFFF`), colour matrix `$8C00`, bitmap `$A000`
(`$D018 = $38`), sprite pictures from `$8A00` (sprite pointer `$28` for
sprite 0, the mouse pointer).

## Run-time conventions

- `$01 = $30` (all RAM) outside the kernal's I/O sections, as in GEOS 2.0;
  the IRQ handler saves `$01`, banks in I/O and restores it.
- The IRQ handler saves A, X, Y and r0-r15, as in GEOS 2.0 (applications
  and the geos-oscar64 runtime rely on it).
- Raster IRQ once per frame (line 250, in the lower border).
- Unimplemented jump table entries end in a trap: border colour cycling,
  the entry number at `$C0F0` (readable through the monitor or REST).

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

## Attribution

Interface addresses (jump table entries, variables, zero page) come from
*The Hitchhiker's Guide to GEOS v2022* (HG2G2022) and, where HG2G does not
list them, the reassembled kernal's `inc/jumptab.inc` and
`inc/geossym.inc` (mist64/geos, Maciej Witkowiak). They are the published
interface that applications are compiled against; no code or tables are
taken from those sources.
