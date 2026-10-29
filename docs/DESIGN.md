# GeoUltra: design decisions

2026-10-28, Xander Mol (with Claude). Supersedes the route and phase
recommendations in [`FEASIBILITY.md`](FEASIBILITY.md), which stays as the
background analysis.

## Decisions

| Topic | Decision |
| --- | --- |
| Route | Free-standing clean-room kernal from the start; no hybrid/patch release. The user's GEOS 2.0 is only the test oracle. |
| Target order | Ultimate 64 family first (U64, Elite, C64 Ultimate): turbo and palette from the start. Then a C64 with an Ultimate II+ (same `.crt`, no turbo/palette), then the C128 with an Ultimate II+ |
| Clean-room rule | mist64/geos and area6510 (MP3, GDOS64) sources may be read to answer behaviour questions; no code, tables or structure are copied, and a comment credits the source wherever behaviour was derived from it |
| C64 boot medium | Protovision Megabyter cartridge (CRT type 86), image at most 1 MiB, so the same `.crt` runs in VICE 3.10 and on the Ultimate |
| C128 boot medium | Separate Ultimate C128 cartridge (CRT "C128 CARTRIDGE", type 1 subtype 2) |
| Kernal, drivers, desktop | All in assembler (ca65/ld65); the desktop is new, not a deskTop/TopDesk patch |
| REU | 16 MB required |
| Swapping | Desk accessory swap, task switcher, print spooler and clipboard all in the REU |
| Mounting | Whole images in the REU now; data structures ready for a later track-cache mode |
| `ramExpSize` | Configurable: by default a small legacy size (bank 0 plus a sandbox old applications may use freely; the rest is invisible to them), a desktop setting reports 255 banks. Default legacy size 512 KB (8 banks: bank 0 plus a 7-bank sandbox) |
| Extended API | A second, GEOS-style jump table (one entry per routine, r-registers in and out) at a fixed published address, found through a `GU` signature in the info area |
| Turbo | Maximum speed, with a per-application list (by permanent name string) of programs that need 1 MHz, and 1 MHz automatically around IEC transfers |
| Image protection | Before the first write-back after a mount, the image is copied once to `<name>.bak`; after that changed runs are written in place |
| Write-back | Automatic: changed runs a few seconds after the last write (from MainLoop, never inside a disk call), and on unmount, `EnterDeskTop`, `ToBasic` and reset recovery |
| Home folder | `GEOULTRA` folder for settings, mount list, backups and task state, searched on `/Usb0`, `/Usb1`, `/SD` in that order (first found wins; created on the first device present) |
| Mount dialogue | A file browser on the Ultimate file system (UCI directory commands) mounts an image into drive A-D, unmounts (with write-back) and creates new images. Reachable from the new desktop, from inside any application as a desk accessory (`geoMount`, so every application's GEOS menu offers it) and by a hot key checked in the IRQ like the task switcher. A mount on the drive an application is using behaves like a disk change on real GEOS: the application sees the new disk at its next `OpenDisk`. Formats: D64 (35 and 40 tracks), D71, D81, DNP; G64 (GCR, confirmed) is decoded to blocks at mount time (read-only first; writing back would need re-encoding) |
| Directories | Native (DNP) drives: subdirectories; 1581 images: partitions (CBM DOS "sub-directories"), entered, created and deleted as folders. Each drive has a current directory; `OpenDisk`, `GetDirHead`, the BAM and directory routines work on it, so existing applications see that directory as a whole disk (the MegaPatch3/GDOS64 model, own code). Changing directory: the new desktop, the file dialogs and new applications through the extended jump table |
| Desktop | New, own design, Workbench style: drive icons (all four drives A-D always, plus printer, trash and the Ultimate file system) on the desktop background, every drive usable at once (no drive swapping as in GEOS 2.0's deskTop); double-click opens a drive or folder in its own movable window; several windows at once, files dragged between them. Views per window: icons (from the GEOS file headers), small icons, list with details (name, type, size, date; sortable). Stays a normal GEOS application towards the kernal (`EnterDeskTop` starts it) |
| Printing | Native support for the Ultimate's virtual printer (the IEC printer emulation, device 4, rendered to PNG on the Ultimate file system): an own GeoUltra driver in Epson FX-80 mode, default when the virtual printer is enabled; the print spooler in the REU feeds every driver. Print to file in a print folder in GEOULTRA: PDF with one 1-bit page image per page (own PDF writer in the driver), and PostScript capture (the stream of LaserWriter-type drivers, so geoWrite/geoPublish text keeps outline fonts) as `.ps`. Network push of finished jobs (firmware 3.15 network commands): HTTP upload to a GeoUltra receiver script on the PC (Python, in this repo) by default, which stores the jobs and runs `ps2pdf` on PostScript ones (real-text PDFs), or FTP upload to any server as the alternative; address, port and method in the settings. Real text directly in a C64-made PDF is not planned (the driver only sees pixel bands; PostScript to PDF needs an interpreter) |
| System patterns | Own pixel designs, but at each of the 32 numbers the same kind of pattern as GEOS 2.0 (lines, dots, bricks, ...), so application screens (title bars, scroll areas) look as intended |
| Mount list | `MOUNTS.INI` in the GEOULTRA folder (searched on `/USB0`, `/USB1`, `/SD`), section `[drives]` with `A=/USB0/Geos/GEOS64.D81` and so on; GeoUltra creates the folder with an empty list on the first device present when none exists |
| Boot mounts | Restore the last session from the mount list (with its write-back state), plus the read-only system drive |
| System font | New 9-point design with the BSW metrics (height, baseline, similar widths), so old applications' dialogs and menus lay out correctly |
| Input driver | 1351 mouse in port 1 in the ROM (also what the U64's USB mouse emulation presents); other drivers load as files |
| Task switcher | Hot key checked in the IRQ (for example C= + RUN/STOP) opens a task list; also a desktop menu entry. A switch saves the whole 64 KB of the task to its REU bank (about 65 ms each way at 1 MHz) plus its VIC, SID and CIA registers, and only at the top of MainLoop (the IRQ just sets a flag), never inside a disk call. Before leaving a task with a changed open file (`fileWritten`), the file is committed as `UpdateRecordFile` does and stays locked for the other tasks (open, delete, rename fail with a clear message) until its task closes it; on return the task's current drive's BAM is read again. Each task has its own legacy REU area. Same approach as MegaPatch3's TaskManager (behaviour idea only) |
| Settings | `GeoUltra Settings`: an application with index-card pages (GDOS64 style), also a desk accessory and a desktop menu entry. Pages: drives (mount list, write-back, backups), memory (legacy REU size, task slots), Ultimate (turbo, REU, clock/NTP), input, printing (virtual printer, print to file, network push), desktop (colours, palette, view defaults), system (serial number, hot keys, boot options). One readable INI-style file in GEOULTRA (`[section]`, `key=value`), editable on a PC too; applied at boot and when saved |
| Real IEC drives | End state: own turbo disk drivers per drive type (1541, 1581, 1571, then CMD FD/HD), clean-room, turbo off around every transfer. Route: first an import/export tool in the desktop (whole disk to an REU image drive and back, any CBM-DOS drive, phase 3); then a slow universal IEC driver (standard serial protocol, also the base for drive detection and turbo code upload, and the fallback for SD2IEC, Pi1541 and drives without a turbo driver); then the turbo drivers, one drive type at a time (phase 6). Drivers live in the `$9000` area (the C64 Kernal ROM hides `$E000` while it is mapped) and may use zero page `$90-$9F` |
| Boot splash | Shown by the boot ROM during a cold boot only (skipped on reset recovery), no artificial delay: light-blue "U" logo with dithered shadow, desktop window with pointer, folder/floppy/printer icons, "GeoUltra", tagline "Graphical desktop for the Ultimate", and a narrow black band (cell rows 22-24) with a compact redraw of the idreamtin8bits (idi8b) logo on the left (64 x 20, every bar of the original as a 1-pixel bar, each letter in its own colour cells) and the version line and boot status line stacked to its right (light red for errors such as no REU or no Command Interface). Generated by `tools/splash/mksplash.py` (320 x 200 hires bitmap and colour matrix) |
| Colours | The desktop's dark grey on light grey stays the base; subtle colour accents in the idi8b logo colours (light blue, purple, light red; light green and cyan only on dark backgrounds), also in the desktop itself |
| Serial number | `GetSerialNumber` returns a fixed GeoUltra default, settable in the settings (stored in the GEOULTRA folder), so users can enter the serial number their applications were installed with (copy protection of some GEOS applications) |
| Clock | Ultimate real-time clock through UCI (`DOS_CMD_GET_TIME`) at every boot; optional NTP sync through the Ultimate's network |

## Cartridges

**C64, Megabyter (type 86).** `$DE00` selects one of 128 8 KB banks at
`$8000-$9FFF` (VICE: 1 MiB, 7 bits; the Ultimate allows 256 banks, but we
stay at or under 1 MiB). `$DE02` bit 1 = EXROM, bit 0 = GAME (set = active);
`$02` switches the cartridge off. The I/O must be visible in `$01` before
writing either register. VICE 3.10 has no TwoMegabyter (type 87); VICE
trunk r46306 (2026-10-27) still only has `megabyter.c`.

**C128, Ultimate type 1 subtype 2** (firmware `c64_crt.cc`,
`all_carts_v5.vhd`): external function ROM in 32 KB banks at `$8000-$FFFF`,
bank select at `$DF7F` (7 bits), a register at `$DF7E` (`ram_bank`, 3 bits,
purpose to be checked), REU and UCI allowed, Ultimate Audio blocked. It does
not pull EXROM/GAME, so the C128 stays in 128 mode and autostarts through the
function ROM's `CBM` signature; the MMU only maps it on request, so it never
overlaps GEOS 128's RAM. U2/U2+ only. Not in VICE (VICE has generic
16/32 KB function ROMs): VICE tests use a generic 32 KB ROM plus an REU image.

**Boot.** The cartridge is a boot ROM, not a runtime ROM: at cold boot it
copies its whole content into the REU (REU DMA straight from the ROM
window, verified on the U64 and in VICE 3.10), switches itself off and starts the kernal from
the REU. After a reset it restarts, finds a valid signature in REU bank 1
and restores the running system and the not yet written back drives from
the REU (warm boot in under a second); only a power cut loses unsaved data.

## Ultimate settings (`.cfg`)

Each cartridge ships with a `.cfg` of the same name next to it
(`geoultra64.crt` + `geoultra64.cfg`, `geoultra128.crt` +
`geoultra128.cfg`). Firmware 3.15 loads it automatically when the `.crt`
is started from the Ultimate's file browser (in memory only; the user's
saved settings stay untouched). Format and item names as the Ultimate's
own "Save settings"; values checked against the U64-II (firmware 3.15a,
REST `/v1/configs`, 2026-10-28):

```
[C64 and Cartridge Settings]
Command Interface=Enabled
RAM Expansion Unit=Enabled
REU Size=16 MB
[U64 Specific Settings]
Turbo Control=U64 Turbo Registers
Turbo Control=C64U Turbo Registers
CPU Speed=64
```

- The firmware silently skips lines it cannot apply, so one file serves
  every device: the second `Turbo Control` line is for the C64 Ultimate,
  the U64 section is ignored on a U2+. `CPU Speed=64` does not exist on the
  U64 and Elite I (maximum 48): the kernal sets the speed itself through
  the turbo registers (`$D030`/`$D031`, index 15 = the device's maximum),
  so the `.cfg` value is only the start value. Check the file against real
  devices with a `checkcfg` target (the u64-bbcbasic `tools/checkcfg.py`
  pattern).
- The C128 `.cfg` has only the C64 and Cartridge section (no turbo on a
  U2+).
- **Start-up check** (as in u64-bbcbasic): the `.cfg` is not loaded when
  the cartridge starts another way (REST `run_crt`, the Ultimate's
  start-up cartridge setting, VICE). The boot ROM checks for the UCI
  (unlock sequence `$D038`/`$D036` if needed), an REU of 16 MB and the turbo
  registers; if something is missing it writes the same settings to
  `/Temp/uci_config.cfg` and applies them with UCI control command `0x50`.
  It only does so when needed: changing REU settings may clear the REU,
  which would destroy what reset recovery relies on. If the UCI cannot be
  reached, a text screen tells the user to enable the Command Interface.
- Turbo runs at maximum by default: GeoUltra has no IEC transfers in its own
  drives, and the CIA timers keep real time under turbo (measured in
  u64-bbcbasic), so jiffy and process timing are unaffected.

## REU map (16 MB, 256 banks of 64 KB)

| Banks | Use |
| --- | --- |
| 0 | GEOS 2.0-compatible kernal bank (reboot copy, `MoveData` scratch) |
| 1 | System: bank allocation table, mount table, dirty bitmaps, config, boot signature |
| 2-17 | ROM mirror (1 MB): kernal, all disk drivers resident, desktop, and a read-only system drive with tools, fonts and drivers as GEOS files |
| 18 | Desk accessory swap |
| 19-26 | Task slots, one bank each: the whole 64 KB RAM of a suspended task (its chip registers in bank 1); count configurable |
| 27-28 | Print spooler |
| 29-30 | Clipboard (text scrap, photo scrap) |
| 31-191 | Drives, handed out in 64 KB units through the allocation table |
| 192-255 | Applications' legacy REU, one area of 8 banks per task slot (task n: banks 192 + 8n to 199 + 8n; their banks 0-7 as `ramExpSize` = 8 shows them; bank 0 is also MoveData's DMA scratch). `DoRAMOp` translates bank n to the current task's area, so applications never reach system banks, drives, task slots or each other's data |

Fixed system part: 31 banks at the bottom and 64 at the top; 161 banks
(about 10 MB) remain for drives. Fewer task slots or a smaller legacy size
per task (settings) give the rest back to the drives.

## Drives A-D

- One REU block driver for all drive types; geometry tables map track/sector
  to a linear offset (1541 speed zones, 1571, 1581, native). A block
  transfer is one 256-byte REU DMA.
- `driveType` = `$80 | type` (the GEOS RAM-drive convention; native = 4).
- Mount: one UCI `LOAD_REU` of the image file to the drive's bank range;
  the mount table holds path, type, REU base, size and dirty state.
- Dirty map: one bit per block in bank 1 (a 16 MB native drive needs 8 KB).
- Write-back of changed runs only: open the image with attribute `$03`,
  seek, then `SAVE_REU` that range (verified on the U64, see below).

## Native RAM drive and DNP

CMD native format: up to 255 tracks of 256 blocks; one track is exactly
64 KB, so track n = REU bank `base + n - 1` and the drive in the REU is
byte for byte a `.dnp` file. Import = one `LOAD_REU` (track count = file
size / 65536), export = one `SAVE_REU`, new = format N tracks in the REU.
Largest drive: 161 tracks (about 10 MB) with nothing else mounted and the
default task settings; a full
255-track DNP needs the later track-cache mode. BAM, allocation and
directory handling are disk driver routines in GEOS 2.0, so native support
lives in the driver; subdirectories and 1581 partitions follow the
current-directory model in the decisions table, with an extended API for
the new desktop and new applications.

## Berkeley assets to replace

System font (own 9-point font with BSW metrics: height and baseline, so
dialog layouts stay right), standard icons (OK, Cancel, ...), deskTop.
User-owned input and printer drivers keep loading as files.

## Phases

| Phase | Content |
| --- | --- |
Phases 1-3 target the Ultimate 64 family (and VICE 3.10 for what needs no
UCI).

| Phase | Content |
| --- | --- |
| 1 | Boot ROM with `.cfg` start-up check, REU manager, REU drive driver, core kernal (memory, math, graphics, processes/IRQ, input driver), turbo control, conformance harness against GEOS 2.0 in VICE |
| 2 | Text and fonts, menus, icons, dialogs, file system up to VLIR: geoWrite and geoPaint run |
| 3 | Desktop and tools (settings, mount dialogue), swapping (tasks, spooler, clipboard), printing (virtual printer, PDF, PostScript, network push and the PC receiver), clock, palette |
| 4 | C64 with an Ultimate II+: same `.crt`, without turbo and palette; test UCI unlock and REU on the U2+ |
| 5 | GEOS 128 cartridge on a C128 with an Ultimate II+, 40/80 columns |
| 6 | Real IEC drives: slow universal driver, then turbo drivers (1541, 1581, 1571, CMD FD/HD) |

## Verified in VICE

- 2026-10-28: GEOS 2.0's own deskTop, loaded and started by GeoUltra's
  `EnterDeskTop` from an REU image drive (VICE 3.10, harness REU image),
  runs on the GeoUltra kernal: menus, disk, printer and trash icons, the
  notepad with all files, icons and names as on GEOS 2.0 (no clock yet;
  one title bar pattern differs, see the open points).
- 2026-10-29: geoWrite 1.1 and geoPaint 1.1 (GEOS 1.2 applications disk)
  start from REU drive B (`tools/harness/apprun.py`): geoWrite creates a
  document and takes typed text, geoPaint creates a picture and draws
  pencil strokes; geoWrite's "Open" lists its documents with DBGETFILES
  and opens the selected one. The file list scrolls with GeoUltra's own
  arrow icon (six desk accessories on drive B).
- 2026-10-29: `ToBASIC` gives the same BASIC screen as GEOS 2.0 (`PRINT
  7*6`), `SYS49152` (`BootGEOS`) reboots GeoUltra with drive A mounted.

## Verified on hardware

Smoke tests in `tests/smoke/` (`make smoke-vice`, `make smoke-u64`), run
2026-10-28 on the Ultimate 64-II (firmware 3.15a) and in VICE 3.10:

| Check | Result |
| --- | --- |
| REU DMA reads the Megabyter ROM window (banks 1-7 stashed from `$8000`, compared with the CPU's view) | Pass on the U64 at 1 MHz and at 64 MHz (manual turbo), and in VICE 3.10 |
| The REU keeps its content across a reset | Pass: signature and boot counter survive `machine:reset`, and also starting another cartridge with `run_crt` |
| The Megabyter cartridge autostarts again after a reset | Pass (the basis of reset recovery) |
| `SAVE_REU` after a seek writes at the file position | Pass: 256 bytes written in place at `$1000` in a 64 KB file opened with attribute `$03` (read/write, existing), size unchanged |
| `LOAD_REU` after a seek reads from the file position | Pass (the basis of the later track-cache mode) |
| Disk images open and load into the REU whole (`tests/smoke/gud64.c`, 2026-10-29): `OPEN_FILE` with `$01` (and `$03`) then `LOAD_REU` | Pass for a D64 in `/Temp`, and read-only from the USB stick for a D64 (174 848 bytes), a D81 (819 200) and a DNP (4 521 984); headers (18/0, 40/0, 1/1) correct in the REU. The UCI manual's note that a read-open of a disk image returns `89,NOT A DISK IMAGE` does not hold on the U64-II with firmware 3.15a (corrected in library 1.4.3). The firmware's GEOS RAM disk trial load (`$41`) returns `91` |
| Boot mounts from `MOUNTS.INI` (2026-10-29) | Pass: the first boot created `/USB0/GEOULTRA` with an empty list (`[drives]`); with `A=/USB0/Geos/GEOS64.D81` and `B=/USB0/Geos/neos-mouse-driver-for-geos.d64` both images loaded into the REU (banks 31 and 44), the kernal opened drive A ("GEOS 64"), and GEOS 2.0's deskTop, started through `EnterDeskTop`, showed both drives and the D81's 45 files |
| GeoUltra cartridge boots its own kernal to the GEOS screen (phase 1 milestone) | Pass on the U64 and in VICE 3.10 |
| 1351 input driver with the U64's USB mouse emulation (Mouse Mode "Mouse", port 1) | Pass: smooth movement, clamped exactly to 0-319 / 0-199, button presses in `mouseData`, `MOUSE_BIT`/`INPUT_BIT` set |
| 1351 input driver with a real Commodore 1351 in port 1 | Pass: smooth movement, clamped to 0-319 / 0-199, button presses, no drift while the mouse lies still (15 s of identical samples) |
| Keyboard driver (matrix scan, repeat, queue, GEOS key codes) | Pass on the U64: letters, Shift, `C=` shortcuts (`$80` + key), F1/F7/F2, cursor keys, RETURN, DEL; repeat after holding; space with the 1351 in port 1 arrives as a key, not as a click |
| Processes and MainLoop dispatch | Pass in VICE (blinking process, injected mouse press reaches `otherPressVec`) |

Still to check: on the C128, REU DMA from the external function ROM
(DMA reaches bank 0 RAM only, UCILIB manual) and the maximum C128
cartridge size on a U2+, plus the purpose of `$DF7E`.

## Resident ROM

Keeping part of the cartridge mapped as resident ROM does not fit the
GEOS memory map, so the cartridge stays a boot and overlay store:

- `$8000-$9FFF` (the Megabyter window) holds the GEOS variables
  (`$8000-$88FF`) and the disk driver (`$9000`); while the ROM is mapped
  the CPU reads ROM there. `$A000-$BFFF` (a 16 KB window) is the screen
  bitmap, which GEOS reads back (XOR drawing, `RecoverRectangle`); the
  VIC-II would still show RAM, but the CPU would read ROM. Ultimax mode
  removes most of the RAM.
- Banking the ROM in briefly (interrupts off) for self-contained routines
  that never touch `$8000-$9FFF` is possible, but gains nothing: cartridge
  ROM runs at bus speed under turbo (1.5x against 55x for RAM, measured in
  u64-bbcbasic), and the whole ROM is in the REU already, at DMA speed.
- C128: the MMU maps the external function ROM only on request, so
  occasional ROM calls are possible there; decided in phase 5.

## Still open

- Conformance: in the menu interaction tests GEOS 2.0 shows "System error"
  after a click on the third item of a three-item vertical sub-menu
  (tests/conformance/menu.py, `action`); GEOS 2.0 bug or test artefact
  still to find out.

- Address of the extended jump table.
