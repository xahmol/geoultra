# GeoUltra: feasibility analysis

2026-10-28, Xander Mol (analysis written with Claude). Living version with
the drawn diagrams: <https://claude.ai/artifact/2hTJyBkVqc9yoHJpZTQPXx>
(private Claude Docs page).

A GEOS-compatible system that does all its storage, RAM and system work
through the Ultimate (UCI file system, REU, turbo, palette, network) is
feasible for both the C64 and the C128, provided it keeps the GEOS 2.0 jump
table, variables and zero page contract byte for byte. The safest route is
a staged build in ca65: start with an Ultimate disk driver and boot loader
on top of GEOS 2.0, with a clean-room kernal as an optional later stage.

## What the Ultimate gives GEOS

The decisive feature: the UCI can move file data straight into the REU and
back (`DOS_CMD_LOAD_REU`/`SAVE_REU` with address and length), so whole disk
images and applications load at REU DMA speed, without a serial bus or turbo
loader.

| Ultimate feature (firmware 3.15) | Machines | What it buys a GEOS system |
| --- | --- | --- |
| UCI DOS target: files and directories on USB/SD, paths, partitions | U2+, U2+L, U64, C64U; C64 and C128 | Native file browser, import/export of `.cvt`/`.d64`/`.d81`/`.dnp` without leaving GEOS |
| File to/from REU at any address (`DOS_CMD_LOAD_REU`/`SAVE_REU`) | all | Disk images as REU RAM drives loaded in seconds; write-back on demand or at shutdown |
| GEOS RAM disk commands (`LOAD_INTO_RAMDISK`, `SAVE_RAMDISK`, `GET_RAMDISK_INFO`) | all, fw 3.10f+ | Firmware already knows GEOS RAM drives; compatible with GeoUMount's model |
| REU up to 16 MB, REU preload image (`CTRL_CMD_LOAD_REU`) | all | RAM boot of the whole system plus several 16 MB-class native RAM drives |
| Drive emulation (1541/1571/1581) and image mounting via UCI | all | Optional real-drive compatibility path; mounting from the desktop |
| Turbo 1-64 MHz (U64 Elite II, C64U: 64 MHz; U64/Elite I: 48 MHz) | U64 family | GEOS UI and drawing several times faster; safe because no IEC timing remains |
| Palette (`GET/SET_PALETTE`) | U64 family | Themes, desktop colours |
| Network: TCP/UDP sockets, HTTP target (fw 3.15) | all with network | NTP clock at boot, downloads, a networked file manager |
| Real-time clock (`DOS_CMD_GET/SET_TIME`) | all | No CMD RTC or GeoUTime step needed |
| SoftIEC target (fw 3.15) | all | Possible bridge for software that insists on IEC devices |

## Compatibility contract

Existing applications only run unchanged if everything they can see stays
where GEOS 2.0 put it; MegaPatch3 and GDOS64 prove this is achievable with a
different implementation behind the same surface.

- **Jump table** `$C100`-`$C31x`, every entry with the same registers in and
  out and the same "Destroys" behaviour (HG2G chapter 20), plus the GEOS 128
  additions and the information bytes at `$C000`-`$C02F` (version `$20`,
  `c128Flag`, `bootName`).
- **Variables** at their addresses: `$8000`-`$88FF` (buffers, `appMain` and
  the other vectors, `driveType`, `curDrive`, `dlgBoxRamBuf`), `$9000` disk
  driver jump area, input driver at `$FE80` (`$FD00` on 128), sprite and
  colour areas.
- **Zero page**: r0-r15 at `$02`-`$21`, kernal variables to `$48`, a0-a9
  untouched, and `$80`-`$FA` free for applications outside disk calls
  (Oscar64 GEOS programs rely on this).
- **Disk model**: track/sector blocks, BAM, directory and file header
  blocks, VLIR index blocks, `GetBlock`/`PutBlock` on arbitrary blocks. Many
  applications (geoWrite, geoPublish, copy tools) walk blocks directly, so
  every GEOS drive must look like a block device, whatever the Ultimate
  stores underneath.
- **Memory**: application space `$0400`-`$5FFF`, background buffer
  `$6000`-`$7F3F`, desk accessory swap behaviour, AUTO_EXEC boot order.
- **Timing**: MainLoop/IRQ structure, process timers per frame, double-click
  timing; turbo must not change jiffy-based timing.
- **Drivers**: printer drivers at `$7900` and input drivers keep their
  interfaces, so existing driver files load.

Not required: the deskTop file itself, Configure, the internal layout of the
kernal, or the original disk drivers.

## Routes compared

The hybrid route is the recommendation: it ships something useful within
weeks, never needs Berkeley's code to be redistributed, and becomes a full
clean-room system piece by piece.

| Route | What is written | Berkeley code shipped | Time to first use | Compatibility risk |
| --- | --- | --- | --- | --- |
| A. Patch system on the user's GEOS 2.0 (the MegaPatch model) | Ultimate disk driver, boot/RAM-boot loader, installer that patches the kernal, desktop and tools | no (user provides GEOS 2.0) | weeks | low: the original kernal stays |
| B. Clean-room kernal | everything: ~16 KB kernal, drivers, boot, desktop | no | many months | highest: every undocumented behaviour must be found again |
| C. Hybrid (recommended) | start as A; replace kernal parts one by one with clean-room code behind the same jump table, until nothing of GEOS 2.0 is needed | no | weeks, full independence later | low at first, then controlled per replaced part |

Why not fork an existing system: the reassembled GEOS kernal (mist64/geos)
is Berkeley's copyrighted code, and Markus Kanet's MegaPatch3/GDOS64 sources
are published with all rights reserved (free to use and distribute the
programs, but no licence to derive). Both stay references for behaviour, as
the GEOS technical reference already uses them.

## Proposed architecture

Only the bottom of the stack is new: applications keep talking to an
unchanged GEOS 2.0 surface, and a new driver layer turns every disk, boot and
system request into UCI and REU operations.

```
 Existing applications                 New desktop and tools
 (geoWrite, geoPaint, GeoUTools,       (C with geos-oscar64: browse
  desk accessories, drivers)            USB/SD, mount, CVT import/export)
            |                                      |
 ===== GEOS 2.0 surface, byte for byte: jump table $C100, variables =====
 =====  $8000-$88FF, zero page r0-r15 and a0-a9, GEOS 128 additions =====
            |
 Kernal: graphics, menus, dialogs, files, VLIR
 (the user's GEOS 2.0 first, clean-room parts later)
            |
 Ultimate driver layer (new, ca65):
   REU image drives        Boot and RAM boot           UCI services
   (block I/O by REU DMA   (system image via UCI       (files, network,
    at $9000)               into REU)                   RTC, turbo)
            |
 Ultimate hardware: UCI at $DF1C, REU up to 16 MB, USB/SD files, network;
 turbo and palette on the U64 family
```

The new desktop is an ordinary GEOS application that also calls the UCI
services directly, which is how it can browse the stick and mount images.

## Storage design

Every GEOS drive is an REU-resident disk image that the UCI loads from and
saves to a file on USB/SD; the kernal only ever sees fast RAM drives, and the
Ultimate file system sits one level up, in the desktop.

1. **Image RAM drives.** Mounting an image (`.d64`, `.d71`, `.d81`, or `.dnp`
   up to 16 MB) means one UCI call: `LOAD_REU` of the whole file into a free
   REU range. The disk driver then serves `GetBlock`/`PutBlock` by REU DMA
   (`FetchRAM`/`StashRAM`, about 1 MB/s), the way MegaPatch3's RAM drivers
   do. This keeps the block model exact, so copy tools, VLIR and BAM code
   all work.
2. **Write-back.** Changed blocks are tracked in a dirty map; `SAVE_REU`
   writes the image back to its file on demand (desktop menu), on unmount,
   before `ToBasic`/reset, and optionally on a timer. A power loss before
   write-back loses changes: the main design risk, which needs a clear UI.
3. **Native file system access** happens in the desktop and tools, not in
   the kernal: browsing USB/SD, mounting images, importing a `.cvt` (parse it
   and write a GEOS file with the normal kernal calls) and exporting one. A
   virtual drive that shows host files as GEOS files directly was rejected:
   it cannot offer stable track/sector blocks to applications.
4. **Booting.** A small loader PRG asks the UCI to load the system image into
   the REU and copies it down (RAM boot), then mounts the drives listed in a
   config file on the stick. No 1541/1581 involvement.
5. **Optional physical/emulated drives.** Ultimate emulated drives and real
   IEC drives can be kept through a classic serial driver; with turbo enabled
   that driver must drop to 1 MHz around IEC transfers.

The Ultimate firmware's own GEOS RAM disk commands (`LOAD_INTO_RAMDISK`,
`GET_RAMDISK_INFO`) cover part of this already and stay usable by
GeoUMount-style tools.

## C64 and C128

A C128 version is realistic only with an Ultimate II+ cartridge, and fills
a gap: GDOS64 is explicitly C64-only, and MegaPatch3 128 is the last
maintained GEOS 128 upgrade.

| Aspect | C64 (U2+ or U64/C64U) | C128 (U2+ cartridge) |
| --- | --- | --- |
| UCI, REU, file system, network, RTC | yes | yes (UCI at `$DF1C` works in 128 mode) |
| Turbo and palette | U64 family only | no (the U64 is a C64) |
| Kernal layout | GEOS 64 2.0 surface | GEOS 128 2.0 surface: front/back RAM, VDC 80 columns, `SetNewMode`, colour modes, extra jump table |
| Desktop | 320x200 | 40 and 80 columns, VDC colour (`VDC_CLR1`-`4`) |
| Test hardware | U64 at home, c64bridge E2E | C128D/DCR with U2+; no automated E2E |

Plan the C128 build as a second target of the same source tree from the
start (shared driver layer, separate kernal configs), as the mist64 sources
do with `bsw128`.

## Build chain

Use ca65/ld65 for the kernal and drivers: the only candidate with a real
linker, which an OS spread over `$0400`, `$5000`, `$9000`, `$BF40`-`$FFFF`,
REU images and two machines needs; the reassembled GEOS kernal and cc65's
GEOS includes are already ca65 sources to compare against.

| Assembler | Linker / segments | Two machines from one tree | Debug output for VICE | Fit |
| --- | --- | --- | --- | --- |
| ca65 + ld65 (cc65) | yes: object files, memory areas, overlays, `.map` | linker configs per target | `-Ln` labels, `--dbgfile` | best |
| 64tass | sections in one pass, no object files | conditional assembly | VICE labels | good second choice |
| ACME | no linker; `!pseudopc` | conditional assembly | VICE labels | fine for small tools, awkward for a multi-area kernal |
| KickAssembler | segments, scripting (Java) | scripted | VICE labels, `.dbg` | strong for demos; Java dependency |
| MADS | relocatable blocks, Atari-oriented | yes | labels | used in U64 BBC BASIC only because its source did |

Setup: `make` builds kernal, driver and boot loader with ca65/ld65, the
desktop and tools in C with Oscar64 and geos-oscar64, the disk images with
`c1541 -geoswrite` and geosapp.py; `make test` runs VICE checks; `make e2e`
drives the U64 through c64bridge/REST; `make deploy` uploads by FTP.

## Testing

VICE covers the kernal and the REU RAM-drive layer but not the UCI, so
every UCI path needs the hardware loop.

- **VICE (x64sc, x128)**: kernal behaviour, the jump table against HG2G, RAM
  drives in a VICE REU, 40/80 columns, unattended runs with
  `-exitscreenshot`/`-exitscreenshotvicii`.
- **Compatibility suite**: real applications through scripted sessions,
  compared screens; the unkeyed GEOS 2.0 disks and the GDOS64/MegaPatch3
  releases as reference.
- **Ultimate 64 E2E** (c64bridge/REST): boot, mount and write-back, network,
  turbo and palette. Pointer positioning by writing `mouseXPos`/`mouseYPos`;
  clicks are reliable when injected by setting `MOUSE_BIT` in `pressFlag`
  with `mouseData` = 0 (proven in the GeoUTools 2.0 tests, 2026-10-28).
- **C128**: manual runs on the C128D/DCR with an Ultimate II+.
- **No UCI emulation exists in VICE**; a UCI mock would need a VICE patch.

## Phases and effort

Phase 1 is the go/no-go test: if REU image drives plus a UCI boot run the
standard applications reliably on GEOS 2.0, the rest is a matter of time.

| Phase | Content | Gate |
| --- | --- | --- |
| 1 Ultimate driver (start here) | REU image drives, UCI boot and RAM boot; C64, on GEOS 2.0 | Apps pass on image drives, safe write-back |
| 2 Desktop and tools | browse, mount, CVT import/export; NTP clock at boot; turbo and palette | A month of daily use without data loss |
| 3 GEOS 128 | C128 with an U2+; 40 and 80 columns; VDC colour modes | Suite passes on a C128 in 40 and 80 columns |
| 4 Clean-room kernal | replace kernal parts; no GEOS 2.0 needed; free-standing release | Suite passes on the clean kernal |

Rough sizes for one developer: phase 1 a few weeks, phase 2 one to two
months, phase 3 about as long as phase 1 plus C128 test time, phase 4
several months and only once phases 1-3 are in daily use.

## Risks and open questions

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Changes in an REU image not yet written back when power goes | lost work | write-back on save, unmount, `ToBasic` and timer; "unsaved" marker; journal of dirty blocks |
| Applications relying on undocumented kernal internals | crashes on a clean-room kernal | hybrid route; compatibility suite |
| Turbo breaking timing-sensitive code | glitches | turbo off around IEC drivers; per-application turbo list |
| No UCI in VICE | slow test cycle | hardware E2E on the U64; optional VICE UCI mock |
| Licensing | cannot ship | user supplies GEOS 2.0 in phase A; clean-room code only; MP3/GDOS64 and mist64 as behaviour reference, never copied |
| Scope creep | never finishes | phase gates; apps after the system is stable |

Open questions:

- Is a dependency on the user's own GEOS 2.0 boot disk acceptable for the
  first release, or must release 1 be fully free-standing?
- Which desktop: a new one in C with geos-oscar64, or compatibility with
  existing deskTop/TopDesk/GeoDesk as the shell?
- Minimum firmware: 3.15 (full feature set) or 3.10f (wider user base)?
- C128 in phase 1, or C64 first with the C128 target kept buildable?

Sources: *The Hitchhiker's Guide to GEOS v2022*
([HG2G2022](https://github.com/geos64128/HG2G2022)); reassembled GEOS kernal
([mist64/geos](https://github.com/mist64/geos)); MegaPatch3 V3.3r12 and
GDOS64 V1.03 sources ([area6510](https://bitbucket.org/mkgit64/area6510));
[ultimate-uci-oscar64](https://github.com/xahmol/ultimate-uci-oscar64) UCI
manual; [cc65 GEOS library](https://github.com/cc65/cc65); geos-oscar64 tests
in VICE and on the U64 (October 2026).
