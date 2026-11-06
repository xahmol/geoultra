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
| Image protection | Before the first write-back after a mount, the image is copied once into `GEOULTRA/BACKUP/` under its own name (the firmware's copy command takes a destination folder and keeps the name, so `<name>.bak` beside the image is not possible with it; an older copy of that name is replaced); after that changed runs are written in place. Central folder confirmed by the user (2026-10-29) |
| Write-back | Automatic: changed runs a few seconds after the last write (from MainLoop, never inside a disk call), and on unmount, `EnterDeskTop`, `ToBasic` and reset recovery |
| Home folder | `GEOULTRA` folder for settings, mount list, backups and task state, searched on `/Usb0`, `/Usb1`, `/SD` in that order (first found wins; created on the first device present) |
| Mount dialogue | A file browser on the Ultimate file system (UCI directory commands) mounts an image into drive A-D, unmounts (with write-back) and creates new images. Reachable from the new desktop, from inside any application as a desk accessory (`geoMount`, so every application's GEOS menu offers it) and by a hot key checked in the IRQ like the task switcher. A mount on the drive an application is using behaves like a disk change on real GEOS: the application sees the new disk at its next `OpenDisk`. Formats: D64 (35 and 40 tracks), D71, D81, DNP; G64 (GCR, confirmed) is decoded to blocks at mount time (read-only first; writing back would need re-encoding) |
| System drive | (User, 2026-10-29.) A read-only drive with GeoUltra's own GEOS files (desk accessories such as geoFolder and the settings DA, fonts, drivers, tools), built by our own tools into the cartridge image and copied to the REU at boot (banks 2-17, "ROM mirror"). It is drive **E** (device 12), outside A-D: GEOS 2.0's variables and existing applications know only A-D, so applications never get E as their drive and all four letters stay free for the user's images; GeoUltra's kernal and the new desktop use it ("E: System"), the kernal switching to it only briefly and invisibly. **Merging**: when an application lists desk accessories or fonts (`FindFTypes` for `DESK_ACC` or `FONT`), the kernal adds those of drive E to the list, and loading one that is not on the application's drive falls back to E, so every application's geos menu and font menu offer them. **The drive's root folder too** (user, 2026-11-04, built): applications in a folder of a native drive also get the root folder's desk accessories and fonts, before drive E's. **Built (2026-10-29)**: E's blocks show as tracks 221-255 of every drive (the image relocated at build time), so applications that keep track/sector pairs (geoWrite's fonts) read them too; checked in VICE with geoFolder and a test font in geoWrite 2.0 (ARCHITECTURE "System drive"). Not on native drives with more than 220 tracks |
| Directories | Approved by the user 2026-10-29 (design with mock-ups: https://claude.ai/artifact/LuumH5NBYSykn74ByyJYA8). **On disk**: native (DNP) drives get CMD native subdirectories (CBM type DIR entries with their own header and directory chain, as CMD HD/RAMLink, MegaPatch3, Wheels and GDOS64 write them), created, entered, renamed, moved and deleted (with contents after a confirmation); 1581 images: CBM DOS partitions that meet the sub-directory rules (whole tracks, at least 120 blocks, track 40 outside) act as folders, also nested, created (size rounded to tracks), entered and deleted (built 2026-11-04 and checked against the real 1581 DOS: entering, leaving, using, creating with a size in tracks, deleting when empty); 1541/1571 stay flat. **Long names** on top: the normal 16-character names stay (a valid disk for every system and application); GeoUltra keeps long names (up to 60 characters, mixed case) in one file per folder, `GU.LONGNAMES` (USR, sequential: per file its directory block and slot, short name and long name), short names made from the long name (first 13 characters, then `~1`, `~2` to stay unique), entries whose short name changed elsewhere repaired; the desktop hides the file; a setting per drive switches long names off. The 18-page directory limit stays for 1541/1581, native folders allow more. **Kernal**: a current folder or partition per drive; `OpenDisk`, `Get/PutDirHead`, the BAM, directory, file and VLIR routines work inside it, so existing applications see it as the whole disk; a change behaves like a disk change (noticed at the next `OpenDisk`); kept in a hibernated session and per task; extended jump table: `GetCurDir`, `SetCurDir`, `DirUp`, `MakeDir`, `RemoveDir`, `GetLongName`, `SetLongName`, `MoveFile` (re-link within a drive). **Existing applications** reach other folders three ways: the `geoFolder` desk accessory (each drive's current folder, links to the mount dialogue), folders listed in `DBGETFILES` (`..` and `/name` before the files; choosing one enters it, only real file names go back to the application; on by default, a setting turns the listing off for an application), and keys in file dialogs (RETURN on a folder enters, DEL goes up). **Ultimate file system**: a full file manager in the desktop (browse USB/SD in the same views and two panes; copy, move, rename, delete with confirmation, new folder; mount into A-D, unmount with write-back, create D64/D71/D81/DNP images; GEOS files leave as `.cvt` and come back as GEOS files, other files plain, folders recursively; mounted images cannot be moved, renamed or deleted). Build order: native folders and the current folder in kernal and driver with the extended jump table, then 1581 partitions; `DBGETFILES` with folders and keys, geoFolder; desktop core with the modern view, the Ultimate file manager and the mount dialogue; long names; classic view |
| Desktop | New, own design (user, 2026-10-29, replacing the earlier Workbench-style idea; mock-ups: https://claude.ai/artifact/2yrZuKGyDceuaFJ2Do4gsq). One core (drives, directories, sorting, copy, move, delete, rename, mount, starting applications, task bar, hibernation) with interchangeable views, each a VLIR record of the desktop application loaded on demand. **Modern** (default): GEOS menu bar and conventions kept (geos menu with desk accessories, file / view menus); sidebar with drives A-D, Ultimate folders and recent documents; the current directory in a list; an action strip for the selection; a task bar with running applications and Suspend. Views of the list, switched with a key or the view menu: list (names), detailed (name, type, size, date; sortable), icons (from the GEOS file headers). Two panes as an option (key or `view > two panes`) for copying and moving between drives and directories. **Classic** (a setting, `desktop > style`, also by key): GEOS 2.0-like notepad with pages and icons, drive icons on the right, on the same core. Overlapping windows (TopDesk style): possibly later, only on demand. Stays a normal GEOS application towards the kernal (`EnterDeskTop` starts it) |
| Mouse pointer | Several pointer designs to choose from (user, 2026-10-30, for the roadmap): a set of own sprite shapes (classic arrow and others) chosen on the settings card (desktop page) and in SETTINGS.INI, applied at boot and when changed; applications that set their own pointer keep doing so. Designs and details to work out (phase 3, with the settings application) |
| Shell: gush | (User, 2026-11-04: name and roadmap.) **gush**, the GeoUltra shell: a command-line terminal with Linux-like syntax, inspired by Maurice Randall's geoShell (GEOS 64/128 and Wheels, 1992/2000; its own syntax, resident and loadable "transient" commands) but not a copy of it. One tree for everything: the GEOS drives and the Ultimate's file system (`/a/Writing`, `/e`, `/usb0/Geos`), `cp` between them converting GEOS files to and from CVT. Commands: `ls` (`-l`), `cd`, `pwd`, `cp`, `mv`, `rm`, `mkdir`, `rmdir`, `cat`/`more`, `df`, `find`, starting programs by name along a `PATH`; Ultimate: `mount`/`umount`, `free` (REU), `turbo`, `date`/`ntp`, `reboot`, later network (`wget`). External commands as GEOS files in `/e/bin` with a documented interface. A text console with line editing and history (narrow font, about 53 columns on 40-column screens). In assembler (ca65), like the other core applications (decision 2026-11-04, "Languages"). **Scripting** (user, 2026-11-04): scripts are text files (on GEOS drives or the Ultimate's file system), started by name or with `source`, plus a startup script; variables (`NAME=value`, `$NAME`, an environment with `PATH`), script arguments (`$1`-`$9`, `$#`) and the exit status `$?`; `if`/`then`/`else`/`fi`, `for`/`while` loops, `test`/`[ ]` (file exists, string and number comparisons), comments, `echo` and `read`; redirection into files (`>`, `>>`), pipes later (through temporary files in the REU). Steps: (1) core: console, parser, about 15 file commands on GEOS drives, starting programs; (2) the Ultimate file system, CVT conversion, mount and system commands; (3) scripting as above, external commands, network. Built on the file-manager engine that the desktop uses too (a shared library); gush is that engine's first user, before the graphical file manager (cheaper to build and test with scripted commands). Phase 3 |
| gush and file engine decisions | (User, 2026-11-04, design questions.) **Paths:** one tree with drive letters at the root: `/a`-`/d` the GEOS drives, `/e` the system drive, `/usb0`, `/usb1`, `/sd` the Ultimate's file system. **Names:** exact and case-sensitive, `*` and `?` wildcards, quotes or backslash for spaces. **Copying:** GEOS files to the Ultimate's file system become `.cvt` automatically and convert back when copied to a GEOS drive; plain SEQ/PRG copied as they are. **Safety:** every delete and overwrite asks, unless `-f`. **Engine interface:** path-string calls for whole-file operations (stat, directory listing, copy, move, delete, mkdir, mount) and handles for streams (`cat`, redirection, later pipes). **Build order:** the engine first, as its own deliverable with its own test suite (VICE and U64 scripts like the conformance harness), then gush on it, then the desktop. **gush form:** a full-screen GEOS application first, a smaller desk-accessory version later. **Console:** about 53 columns with an own 6-pixel font; line editor with cursor keys and history, completion (on a key the C64 has, e.g. `<-`), Emacs keys (CTRL+A/E/K/U, CTRL+C). **Settings:** `gushrc` (startup script) and `gush_history` in the GEOULTRA folder. **Starting applications:** by name, replacing gush as the desktop does (`geoWrite letter` opens the document); with the task switcher gush stays as a task. **Step 1** includes the Ultimate's file system (`ls`, `cd`, raw `cp` on `/usb0` etc.); CVT, mount and system commands in step 2, scripting, external commands and network in step 3. **gush step 1 design** (user, 2026-11-04): docs/GUSH.md (own 6x8 font, status line, started by a boot setting and from geoFolder, later from GeoUltra's desktop menu and a button). **Long names before gush** (user, 2026-11-04): long names in the kernal's files and the engine come right after engine step E3, so that gush, CVT and the engine's interface are made once for them; the desktop, `DBGETFILES` and geoFolder parts keep their place (docs/FILE_ENGINE.md, "Long names") |
| gush step 2 and engine E4 decisions | (User, 2026-11-05, design questions.) CVT automatic both ways with `cp -R` for raw; `mount`/`umount` like the mount dialogue (write-back, `MOUNTS.INI` updated, the drive's type follows the image, not for gush's own drive or drive E); `mkimg` for d64/d71/d81/dnp; `free`, `turbo` (session, `-s` saves), `date`; NTP (2026-11-05, replacing "no ntp"): one kernal module from GeoUTime's logic, a boot step when `SETTINGS.INI` `[time] ntp=` is set and `ntp` in gush; a mouse click places gush's cursor, `reboot` (`-u` the Ultimate); `cat` on an Ultimate `.cvt` as on GEOS drives. Details: docs/GUSH.md "Step 2" |
| gush step 3 decisions | (User, 2026-11-05, design questions.) POSIX sh subset for scripts; external commands as loadable modules in gush's memory with a table of gush routines; PATH `/e/bin`, then GEOULTRA/bin; `>`, `>>`, `<` for all output and pipes through an REU temporary file, both in step 3; completion on the `<-` key; 100 history lines in GEOULTRA/gush_history; `wget`, `ifconfig`, `ping`/`host`; FTP/HTTP server on the roadmap. Details: docs/GUSH.md "Step 3" |
| Languages | (User, 2026-11-04.) Kernal, drivers and the core OS applications (desktop, gush, file manager, settings, mount dialogue, geoFolder) in assembler (ca65/ld65). The file engine they share (paths over the GEOS drives and the Ultimate's file system, CVT conversion, copying, mounting) is a kernal extension: overlay modules in the REU reached through the extension jump table, so it costs none of an application's memory and third-party applications can use it. C (Oscar64 with geos-oscar64) only for other tools and tests. Reasons: size above all (C code 1.5-3 times larger, about 23 KB of application memory), speed on 1 MHz machines (the Ultimate II+ target), and no C runtime or compiler quirks (zero page shared with GEOS, REU DMA buffers that needed `volatile`, the Oscar64 fast-call patch) |
| Printing | Native support for the Ultimate's virtual printer (the IEC printer emulation, device 4, rendered to PNG on the Ultimate file system): an own GeoUltra driver in Epson FX-80 mode, default when the virtual printer is enabled; the print spooler in the REU feeds every driver. Print to file in a print folder in GEOULTRA: PDF with one 1-bit page image per page (own PDF writer in the driver), and PostScript capture (the stream of LaserWriter-type drivers, so geoWrite/geoPublish text keeps outline fonts) as `.ps`. Network push of finished jobs (firmware 3.15 network commands): HTTP upload to a GeoUltra receiver script on the PC (Python, in this repo) by default, which stores the jobs and runs `ps2pdf` on PostScript ones (real-text PDFs), or FTP upload to any server as the alternative; address, port and method in the settings. Real text directly in a C64-made PDF is not planned (the driver only sees pixel bands; PostScript to PDF needs an interpreter) |
| System patterns | Own pixel designs, but at each of the 32 numbers the same kind of pattern as GEOS 2.0 (lines, dots, bricks, ...), so application screens (title bars, scroll areas) look as intended |
| Mount list | `MOUNTS.INI` in the GEOULTRA folder (searched on `/USB0`, `/USB1`, `/SD`), section `[drives]` with `A=/USB0/Geos/GEOS64.D81` and so on; GeoUltra creates the folder with an empty list on the first device present when none exists |
| Hibernation | The running state survives a power cycle: the system bank, the current task's 64 KB with its VIC, SID and CIA registers, the suspended tasks, spooler and clipboard (only banks in use) are written with `SAVE_REU` to a hibernation file in GEOULTRA (drives are not in it: their changes go to the image files by write-back first). Saved by a Suspend command (desktop menu and hot key, then "safe to switch off"), automatically at quiet moments (a while without input, after the write-back), and when leaving with ToBASIC or a reset from the menu. At boot a valid hibernation file is loaded back and the session resumes automatically; a key held at power-on (C=) starts fresh. Quiet moment: a setting (SETTINGS.INI and the settings card, "off" possible), default 30 s without a key or mouse button after a change (user, 2026-10-29; done: `[system] hibernate=` seconds, `0` off). The applications' legacy REU: only the banks applications wrote to are saved (tracked in `DoRAMOp`; user, 2026-10-29) |
| Themes | A theme sets the 16 palette colours (firmware 3.15 palette control on the U64 / C64 Ultimate; applies to every program, original GEOS applications included), GEOS's colour defaults (desktop background, notepad and pad colours `$8FE8-$8FF0`, border, pointer), the desktop pattern and optionally the system font style (same metrics, so dialogs stay right). Built-in presets (classic GEOS grey, idi8b colours, dark, high contrast) plus an editor page in GeoUltra Settings; themes are INI files in GEOULTRA/THEMES. On an Ultimate II+ (no palette control) only the colour choices apply |
| Hardware wording | Peripherals (drives, interfaces, mice and other input devices, printers, expansions) are supported on a best-effort basis: the documentation lists what was tested on which hardware and never promises that all devices work |
| AI transparency | Fully open about the use of AI: the README's "Use of AI" says who decides and who writes, every commit written with AI carries a `Co-Authored-By: Claude` line, and release notes, posts and blog texts mention it |
| Compatibility wording | GeoUltra aims at the GEOS 2.0 interface and is checked against GEOS 2.0; the documentation never promises full or 100% compatibility (the GEOS world has many versions, add-ons and developments, some lost), and names what was actually tested |
| Boot mounts | Restore the last session from the mount list (with its write-back state), plus the read-only system drive |
| System font | New 9-point design with the BSW metrics (height, baseline, similar widths), so old applications' dialogs and menus lay out correctly |
| Input driver | 1351 mouse in port 1 in the ROM (also what the U64's USB mouse emulation presents); other drivers load as files |
| Task switcher | Hot key checked in the IRQ (for example C= + RUN/STOP) opens a task list; also a desktop menu entry. A switch saves the whole 64 KB of the task to its REU bank (about 65 ms each way at 1 MHz) plus its VIC, SID and CIA registers, and only at the top of MainLoop (the IRQ just sets a flag), never inside a disk call. Before leaving a task with a changed open file (`fileWritten`), the file is committed as `UpdateRecordFile` does and stays locked for the other tasks (open, delete, rename fail with a clear message) until its task closes it; on return the task's current drive's BAM is read again. Each task has its own legacy REU area. Same approach as MegaPatch3's TaskManager (behaviour idea only) |
| Settings | `GeoUltra Settings`: an application with index-card pages (GDOS64 style), also a desk accessory and a desktop menu entry. Pages: drives (mount list, write-back, backups), memory (legacy REU size, task slots), Ultimate (turbo, REU, clock/NTP), input, printing (virtual printer, print to file, network push), desktop (colours, palette, view defaults), system (serial number, hot keys, boot options). One readable INI-style file in GEOULTRA (`[section]`, `key=value`), editable on a PC too; applied at boot and when saved |
| Real IEC drives | Best effort. Aim: own turbo disk drivers per drive type (1541, 1581, 1571, then CMD FD/HD), clean-room, turbo off around every transfer. Route: first an import/export tool in the desktop (whole disk to an REU image drive and back, for CBM-DOS drives that follow the standard protocol, phase 3); then a slow universal IEC driver (standard serial protocol, also the base for drive detection and turbo code upload, and a fallback to try with devices such as SD2IEC or Pi1541 and drives without a turbo driver); then the turbo drivers, one drive type at a time (phase 6). Which drives and devices work is decided by testing, not promised. Drivers live in the `$9000` area (the C64 Kernal ROM hides `$E000` while it is mapped) and may use zero page `$90-$9F` |
| Boot splash | Shown by the boot ROM during a cold boot only (skipped on reset recovery), no artificial delay: light-blue "U" logo with dithered shadow, desktop window with pointer, folder/floppy/printer icons, "GeoUltra", tagline "Graphical desktop for the Ultimate", and a narrow black band (cell rows 22-24) with a compact redraw of the idreamtin8bits (idi8b) logo on the left (64 x 20, every bar of the original as a 1-pixel bar, each letter in its own colour cells) and the version line and boot status line stacked to its right (light red for errors such as no REU or no Command Interface). Generated by `tools/splash/mksplash.py` (320 x 200 hires bitmap and colour matrix) |
| Colours | The desktop's dark grey on light grey stays the base; subtle colour accents in the idi8b logo colours (light blue, purple, light red; light green and cyan only on dark backgrounds), also in the desktop itself |
| Serial number | `GetSerialNumber` returns, in this order: the serial listed for the running application in `[serials]` of SETTINGS.INI (`permanent name=hex`), the serial the running application stored when it was installed (opt-in, see below), the `[system]` choice (`serial=hex`, or the user's own GEOS 2.0 boot disk: read from a mounted drive's `GEOBOOT`, file block 82 offset 183, as found on the user's disks; done), else GeoUltra's own default. Measures (user, 2026-10-29): (1) **jump table repair**: a copy of the jump table in the REU, restored at `EnterDeskTop` and `StartAppl`, so that sabotage by applications that find a foreign serial (the deskTop increments the `LdDeskAcc` vector; done, see ARCHITECTURE) and damage by buggy programs do not persist; (2) **install on GeoUltra** (done, without a table: a hook behind `NewDisk` answers the drive-code check, ARCHITECTURE "Install on GeoUltra"): an application's first-run check of its original disk (drive code looking for the gap signature, impossible on REU drives) passes, so it keys itself to the user's serial as on a 1541; only on 1541 images (D64) made from the original disk, as such checks accept only 1541/1571 drive types; not yet tried with a real original's image (none in the user's collection); (3) **expected serial per application** (done, `src/kernal/bypass.s`): instead of a table per application, the instructions after the call are examined for the comparison with `r0` and the stored number is read from there (ARCHITECTURE, "Serial number per application"); a table only for applications whose check does not follow the call; (4) **re-key on request**: the Serial card rewrites an application's stored serial to the user's own (backup first). (2)-(4) bypass Berkeley's copy protection: in public releases, off by default, switched on in SETTINGS.INI (`[system] protection=bypass`); the documentation says so plainly. UI: a "Serial numbers" card in GeoUltra Settings (application and desk accessory) showing the number in use and its source, the choice (own GEOS boot disk with "Find on drives", fixed number, GeoUltra default), the bypass switch and the per-application list; "Add..." takes an application's serial from the image of the GEOS boot disk it was installed under, by hand entry, or from applications that keep it readable (GEOMERGE). When an application ends right after starting or shows its known refusal dialog, a notice explains the setting and opens the card with that application filled in. Public releases include (2)-(4), arranged to keep the take-down risk low (user, 2026-10-29): all bypass code in one separate source file and overlay module (`src/kernal/bypass.s`) with its own notice at the top, nothing else depending on it; `make BYPASS=0` builds GeoUltra without it, so a take-down can remove only that module; the per-application table holds only permanent names, offsets, keys and lengths: no Berkeley code, byte patterns or extracted serial numbers; no GEOS software in the repository or releases; wording in code, docs, release notes and posts says "use your licensed applications", never "crack" or "unprotect", and never advertises running unlicensed copies; jump table repair (1) stays in the normal kernal (it is general robustness). Disclaimer (user, 2026-10-29): README, DESIGN and the Settings card state that the measures are only for applications of which the user owns a licensed copy; on screen, switching the bypass on shows once (and the card always shows in small text): "For applications you own a licensed copy of. GEOS software is still under copyright; use is your own responsibility." The refusal notice repeats the first sentence. Background: pagetable.com 149 ("Copy Protection Traps in GEOS for C64") and 240 ("Inside geoWrite 5: Copy Protection") |
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
- **Built (2026-10-30)**: `src/cfg/geoultra64.cfg` (copied to
  `build/geoultra64.cfg`; `make checkcfg` checks it against the Ultimate
  in `.env`: repeated items are per-device alternatives). The start-up
  check is `TurboInit` in the cold start (after the mounts, before a
  resume): when `$D031` reads `$FF` it writes only the two Turbo Control
  lines to `/Temp/uci_config.cfg` and sends control `$50` without payload
  (a payload is taken as the file name); REU and Command Interface are not
  touched (they are on already when the boot got this far, and applying
  REU settings might clear the REU). On the U64-II with Turbo Control
  saved "Off" and the cartridge started from the flash setting: status
  "89" (the C64U line skipped), Turbo Control "U64 Turbo Registers" in
  memory, the saved settings unchanged. Then `$D031` = `$8F` (maximum,
  badline stalls off); `InitForIO`/`DoneWithIO` switch to 1 MHz and back
  around serial-bus work. Per application (overlay module 16,
  `speed.s`, from the gate at the start of `LdApplic`): 1 MHz for the
  permanent names listed in SETTINGS.INI `[system] slow=NAME` (one per
  line, up to 6, matched as the start of the permanent name, case as in
  the file header), full speed for all others, so the desktop gets full
  speed back; `turbo=off` switches turbo off, `turbo=N` (0-15, user
  2026-11-05: gush's `turbo -s N` writes it) starts at that speed step. `[time]` (user 2026-11-05): `ntp=server`
  syncs the clocks at every cold start and is the default of gush's
  `ntp`; `offset=` seconds from UTC (signed). The list lives in REU bank
  3 at `$FF00` (padding of the cartridge image, filled anew at each boot,
  not hibernated), so a resumed session follows the current SETTINGS.INI;
  the speed in use comes back with it (`turboNow`). Measured on the U64-II with `slow=geoWrite`
  (a test only; geoWrite needs no 1 MHz): deskTop 64 MHz, geoWrite 1 MHz
  (`$D031` = `$00`), after quitting geoWrite 64 MHz again. No
  application is known yet that needs the list.

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
| 31-187 | Drives, handed out in 64 KB units through the allocation table |
| 188-191 | File engine: one Ultimate listing per handle (docs/FILE_ENGINE.md; until the allocation table hands out scratch banks at run time) |
| 192-255 | Applications' legacy REU, one area of 8 banks per task slot (task n: banks 192 + 8n to 199 + 8n; their banks 0-7 as `ramExpSize` = 8 shows them; bank 0 is also MoveData's DMA scratch). `DoRAMOp` translates bank n to the current task's area, so applications never reach system banks, drives, task slots or each other's data |

Fixed system part: 31 banks at the bottom and 68 at the top; 157 banks
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

**DNP of another size than the drive (investigated 2026-10-30, user's
question; built 2026-11-04: MOUNTS.INI `A=path,tracks=N`, see "Verified
on hardware").** Today a DNP always loads whole, the
track count taken from the file size (`ImageSize`), and the driver uses
only that count (`drvTracks`: locating, free count, allocation), never the
BAM header's last track (1/2 `$08`). The user's GDOS64 `ramapps.DNP` is
such a mismatch (header 191 tracks, file 69: GDOS64 saved the used front
of a larger RAM drive); it mounts and writes safely already. A drive size
of its own (MOUNTS.INI `A=path,tracks=N`, the mount dialogue, a new RAM
drive) would work like this:
- **DNP smaller than the drive:** load the file into the first banks, then
  grow it: BAM header `$08` = N, the BAM bits of the new tracks set free.
  Write-back then extends the file (to check on the hardware: a UCI write
  past the end of a file), or the drive is saved as a new image.
- **DNP larger than the drive:** load only the first N tracks. Safe only
  when the image's BAM shows no used block after track N; GeoUltra checks
  that first and refuses otherwise (the files there would be lost), BAM
  header `$08` = N. Write-back must not leave the original file with a
  header that disagrees with its length: save the N tracks as a new image,
  or write the whole file anew, after a confirmation.
- **Full or fragmented large DNPs:** a file-level import instead (files
  and folders copied one by one, packed at the front), as
  `tools/mkappsdnp.py` does on the PC; later the desktop's file manager.

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
| 3 | File-manager engine with gush, the shell, as its first user; desktop and tools (settings, mount dialogue, themes, mouse pointer designs), hibernation, swapping (tasks, spooler, clipboard), printing (virtual printer, PDF, PostScript, network push and the PC receiver), clock, palette |
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
- 2026-10-29: writing to a native drive (DNP): `make test-native` saves,
  reads back and deletes sequential and VLIR files, grows the directory
  and checks that BAM changes without `PutDirHead` are dropped; geoWrite
  2.0 from the user's ramapps.DNP creates a document ("GU native doc",
  VLIR, type 7) and takes typed text.
- 2026-10-29: writing to a 1571 drive (D71): `make test-d71` on an empty
  D71 formatted by the test: save, read back, delete, BAM changes dropped
  without `PutDirHead`, directory growth, and `SetNextFree` sequences
  across both sides matching a model of GEOS 2.0's 1571 driver.

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
| Write-back (2026-10-29, test copies in `/USB0/GEOULTRA/test`) | Pass: a block written on drive B (D64) reached the image a few seconds later, only that block changed, size unchanged; two separate blocks on drive A (D81, first and last block) likewise; the backup in `GEOULTRA/BACKUP/` equals the image as mounted; after a reset with an unsaved change the session was kept and written back. The firmware's copy command (`$0B`) copies into a folder, keeping the name |
| Boot mounts from `MOUNTS.INI` (2026-10-29) | Pass: the first boot created `/USB0/GEOULTRA` with an empty list (`[drives]`); with `A=/USB0/Geos/GEOS64.D81` and `B=/USB0/Geos/neos-mouse-driver-for-geos.d64` both images loaded into the REU (banks 31 and 44), the kernal opened drive A ("GEOS 64"), and GEOS 2.0's deskTop, started through `EnterDeskTop`, showed both drives and the D81's 45 files |
| Serial number and applications (2026-10-29, test copies: A = GEOS64.D81, B = ramapps.DNP) | Pass: the cold start read the user's serial (`$58B5`) from GEOBOOT on drive A; geoWrite 2.1 from drive A starts without the "same GEOS disk" refusal, geoWrite 2.0 from the native drive B starts (both to their start dialog, launched with `GetFile` through `appMain`) |
| Clock from the Ultimate's real-time clock (2026-10-29) | Pass: after the cold start GEOS showed the Ultimate's date and time (`DOS_CMD_GET_TIME`, "2026/10/29 18:44:..."); a first try showed the next day: `ClockInit`'s read of the TOD hours left the TOD latched on 12 AM, so the first `TimeUpdate` saw an afternoon hour on a morning clock (fixed: `TodSet` reads the tenths first) |
| Hibernation core (2026-10-29) | Pass: `HibSuspend` (called through `appMain`) wrote `GEOULTRA/HIBERNAT.BIN` (720 896 bytes); after a change in RAM and on the screen and a reset, the cold start resumed the session (the change gone, the code after the call running on, the clock continuing from 00:00:53 to 00:01:10), the file deleted. Quiet moment: after a marked change and about 10 s without input the file was written by itself, and resumed after a reset. The power cycle itself not tested yet |
| Hibernation, real power cycle (2026-10-30) | Pass after three fixes. Boot from the U64's flash (Cartridge = geoultra64.crt, REU and Command Interface saved), drives A/B on test copies, the deskTop with an icon selected, 30 s quiet: `HIBERNAT.BIN` written; power off about 5 s and on: the deskTop came back with the icon still selected, the file deleted, the clock right. With C= held: a fresh start (banner, drives mounted, file kept). Found on the way: (1) at power-on `/USB0` appears seconds after the C64 starts: `FindHome` made a second, empty home on SD; it now searches up to 10 s first. (2) The U64 keeps the REU on the board: after the power-off the old mount table still had its signature, with noise elsewhere and a noise bit as "unsaved changes", and was kept on every boot (no drives); `KeepDirty` now checks every entry. (3) `ClearTable` never cleared the table (`ldx #$9F` / `bpl`), and the paths of unused drives kept old REU contents, so the session's mounts never matched after a power cycle; both cleared now. (4) Right after power-on the Ultimate's clock reads 2025/01/11 until its network time: a year before 2026 is taken as not set, the session's time goes on, asked again each minute (`RtcCheck`). U64 firmware 3.15a has US daylight-saving dates for "Western Europe" (CEST until 1 November); fixed upstream (1541ultimate `cea55764`, issues #659/#660), not in 3.15a |
| Drive E with the deskTop (2026-10-30) | The deskTop showed drive A as "GEOULTRA SYSTEM" and asked for that disk: searching E's directory replaced `curDirHead`; now kept in REU bank 1 `$1800` meanwhile. geoFolder does not appear in the GEOS 2.0 deskTop's geos menu: traced in VICE, the deskTop never calls `FindFTypes` for desk accessories (at its start only once, for type SYSTEM; opening the geos menu calls no kernal routine); it lists the desk accessories of the open disk from its own directory reading. Left so (getting them in would mean adding drive E's files to every disk's directory, which the deskTop would then offer to copy, rename and delete): GeoUltra's own desktop will list drive E's desk accessories; meanwhile geoFolder can be copied to a disk (`build/tools/geofolder.cvt`). Applications that use `FindFTypes` (geoWrite) show it |
| DirMaster and native folders (2026-10-30) | DirMaster's DNP (folders TEST/INNER, a file) read by GeoUltra: entering, the file found, up and to the root. GeoUltra's folder with a file opened by DirMaster, Validate clean. Header byte `$26` (entry offset) is the same in both (offset of the type byte). DirMaster leaves `$04-$13` (name), `$24/$25` and "1H" empty; GeoUltra fills them (CMD layout); DirMaster shows our name bytes where the ID should be (cosmetic). Inside a DirMaster folder GeoUltra's disk name is empty (to take the entry's name then) |
| Turbo (2026-10-30) | Pass on the U64-II: after `TurboInit` the CPU reads `$D031` = `$8F`, and a 64 200-cycle loop (the method of the Ultimate library's `uii_turbo_probe_max`) took 16 raster lines three times: 64 MHz (48 MHz would be about 22, 1 MHz about 1000). Code injected through `appMain` runs with `$01` = `$30`: a measurement must switch I/O on itself (a first try waited on RAM at `$D012` and hung) |
| Write-back retry (2026-10-30) | Pass on the U64: drive B's image (a test copy) renamed over FTP, the drive changed (`GetDirHead`/`PutDirHead`): the write-back failed, the drive stayed marked changed and the write-back was scheduled again every 5 s; after renaming the image back it was written within the next retry (the flag cleared, the file's time updated) |
| DNP resizing (2026-11-04) | Pass on the U64 with copies of the applications DNP (36 tracks, data on tracks 1-29): `tracks=48` mounted with 5 116 of 12 288 blocks free, `tracks=30` with 508 of 7 680 (`CalcBlksFree`, as computed from the BAM), both flagged `F_RESIZED`; after a change each write-back wrote its image anew at its size (3 145 728 and 1 966 080 bytes; the originals in BACKUP), BAM header and free blocks agreeing and all 183 files byte-identical to the source; `tracks=20` on the 30-track image was refused (drive not mounted, file untouched) |
| Refusing CONFIGURE (2026-10-30) | Pass on the U64 and in VICE: GEOS 2.0's CONFIGURE (it loads its own disk drivers over `$9000` and crashed GeoUltra) is stopped at the start of `LdApplic` (the GEOS 2.0 deskTop calls it directly, not through `GetFile`); the desktop is started anew and shows "Configure is not for GeoUltra" first. Returning to the deskTop instead gave "System error near $4D77", and showing the dialog before the restart also broke it: by the time it calls `LdApplic` the deskTop has dismantled part of itself |
| GEOS 2.0 system disk survey (2026-10-30, U64, the GEOS 2.0 deskTop) | PAINT DRIVERS and CONVERT V2.5 start and quit cleanly. RBOOT (BASIC type) leaves through `ToBasic`: the deskTop passes `LOAD"RBOOT",8`, which goes to the U64's real IEC drive 8 (not GeoUltra's REU drive A) and finds nothing; the session saved on the way out was resumed by a reboot. GEOS and GEOBOOT (also BASIC) take the same path. CONFIGURE: refused (above) |
| Writing to a native drive (2026-10-29, test copy of ramapps.DNP as drive B) | Pass: `SaveFile` of a 1000-byte file through GeoUltra's driver; after the write-back the image file on the stick has exactly the directory block, header, 4 data blocks and BAM block 1/5 changed, the entry and data read back from the file are right, the free count went down by 5; the backup was made in `GEOULTRA/BACKUP` first |
| SETTINGS.INI and the serial number per application (2026-10-29, a temporary SETTINGS.INI, removed again) | Pass: `serial=1234` sets the serial (geoWrite 2.1 then refuses: "Please reboot your system using the same GEOS disk"); with `protection=bypass` added, the same geoWrite 2.1 starts |
| GeoUltra cartridge boots its own kernal to the GEOS screen (phase 1 milestone) | Pass on the U64 and in VICE 3.10 |
| 1351 input driver with the U64's USB mouse emulation (Mouse Mode "Mouse", port 1) | Pass: smooth movement, clamped exactly to 0-319 / 0-199, button presses in `mouseData`, `MOUSE_BIT`/`INPUT_BIT` set |
| 1351 input driver with a real Commodore 1351 in port 1 | Pass: smooth movement, clamped to 0-319 / 0-199, button presses, no drift while the mouse lies still (15 s of identical samples) |
| Keyboard driver (matrix scan, repeat, queue, GEOS key codes) | Pass on the U64: letters, Shift, `C=` shortcuts (`$80` + key), F1/F7/F2, cursor keys, RETURN, DEL; repeat after holding; space with the 1351 in port 1 arrives as a key, not as a click |
| Processes and MainLoop dispatch | Pass in VICE (blinking process, injected mouse press reaches `otherPressVec`) |

Still to check: on the C128, REU DMA from the external function ROM
(DMA reaches bank 0 RAM only, UCILIB manual) and the maximum C128
cartridge size on a U2+, plus the purpose of `$DF7E`.

## Applications tried (2026-10-29, VICE)

Every C64 application and desk accessory of the user's "GEOS64Unkeyed"
collection (unkeyed or de-protected versions, from the USB stick),
started with `GetFile` from drive B on GeoUltra (`apprun.py`), screen
after 10 s; failures compared with GEOS 2.0 in VICE (application disk in
drive 9). Only starting is tested here, not working with the program.

| Program (permanent name) | Kind | Disk | Result |
| --- | --- | --- | --- |
| grabber basic | APP | GeoBasic (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| basic       V1.0 | APP | GeoBasic (Unkeyed).D64 | stopped at once: calls `ClearRam` with I/O on, which GeoUltra had under I/O (fixed: routines placed as on GEOS 2.0); still no start dialog, not pursued (GeoBasic was never finished and is known to be buggy) |
| geoClock-40 V1.1 | DA | GeoBasic (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOMERGE    V1.0 | APP | GeoCalc (Unkeyed).D64 | GetFile error `$02`, the same on GEOS 2.0 |
| geoText     V1.0 | APP | GeoCalc (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Grabber     V2.0 | APP | GeoCalc (Unkeyed).D64 | refuses: "System unter Verwendung der ... GEOS-Diskette rebooten" (German version, keyed, not unkeyed) |
| TEXT GRABBER 2.0 | APP | GeoCalc (Unkeyed).D64 | crashed in code under I/O (fixed); now the same screen as on GEOS 2.0 |
| GEOLASER    V2.0 | APP | GeoCalc (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoWrite    V2.0 | APP | GeoCalc (Unkeyed).D64 | refuses: keyed to another serial (runs with `protection=bypass`) |
| WRITE 2 KEY V1.0 | DA | GeoCalc (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOCHART    V1.0 | APP | GeoChart (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Text Mgr    V2.1 | DA | GeoChart (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Photo Mgr   V2.1 | DA | GeoChart (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoDex      V1.0 | DA | GeoDex (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOMERGE    V2.0 | APP | GeoFile (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOFONT     V2.0 | APP | GeoFont (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOLABEL    V1.2 | APP | GeoLabel (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoPaint    V2.0 | APP | GeoPaint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Geo_PxlPzzlrV1.0 | APP | GeoPaint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GeoReplicatrV2.0 | APP | GeoPaint (Unkeyed).D64 | "Cannot find printer driver": none on the disk (as expected) |
| GP_Viewer   V1.0 | DA | GeoPaint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOPRINT    V1.2 | APP | GeoPrint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoSidPlayer  V1 | APP | GeoPrint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| FontViewer  V1.0 | APP | GeoPrint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOS>PM/PS  V1.0 | DA | GeoPrint (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoProgPatchV2.0 | APP | GeoProgrammer Patch 2.1.D64 | dialog box with GEOS 128 position flags (`DOUBLE_W`) was drawn into the kernal; fixed to draw as GEOS 2.0 does (the box partly off to the side, as there) |
| geoPublish  V1.0 | APP | GeoPublish (Unkeyed).D64 | garbled screen (mosaic) - **the same on genuine GEOS 2.0** on the U64 (2026-10-29, this image as drive B, started with `GetFile` from the deskTop's MainLoop), so a defect of this unkeyed image, not of GeoUltra. Details: geoPublish patches the `OpenRecordFile` vector (+14, past `FindFile`) and fills `dirEntryBuf` from its own table at `$750F`, which nothing initialises; with zeros there it happens to start |
| GEOSPELL    V1.1 | APP | GeoSpell (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoWrite    V2.1 | APP | GeoWrite (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Linker .obj V1.0 | APP | GeoWrite (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Converter   V7.0 | APP | GeoWrite (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Calculator  V1.0 | DA | GEOS Applications (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| note pad    V2.0 | DA | GEOS Applications (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Word P W P  V1.0 | APP | GEOS Better Working Publisher Side 1 (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Photo Mgr   V1.3 | DA | GEOS Better Working Publisher Side 1 (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Calendar I  V1.2 | DA | GEOS Desk Pack Plus (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Blackjack   V1.2 | DA | GEOS Desk Pack Plus (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Icon Editor V2.0 | APP | GEOS Desk Pack Plus (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| geoDex      V2.0 | DA | GEOS Desk Pack Plus (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Photo Mgr   V2.0 | DA | GEOS Desk Pack Plus (Unkeyed).D64 | "This program can only run on a C128" (correct) |
| TEXT GRABBER 2.3 | APP | Write Utilities (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOLASER    V2.1 | APP | Write Utilities (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| GEOMERGE    V2.1 | APP | Write Utilities (Unkeyed).D64 | starts (dialog, menu or window as expected) |
| Prfrnce Mgr V1.0 | DA | GEOS 64 v2.0 (UnKeyed).D64 | starts (dialog, menu or window as expected) |
| Pad Color Mgr  V | DA | GEOS 64 v2.0 (UnKeyed).D64 | starts (dialog, menu or window as expected) |
| Alarm clock V1.0 | DA | GEOS 64 v2.0 (UnKeyed).D64 | starts (dialog, menu or window as expected) |
| Paint Drvr  V1.0 | APP | GEOS 64 v2.0 (UnKeyed).D64 | starts (dialog, menu or window as expected) |
| CONVERT     V2.5 | APP | GEOS 64 v2.0 (UnKeyed).D64 | starts (dialog, menu or window as expected) |
| GEOSBUSTERS V4.0 | APP | GEOS Busters 4.0.D64 | asks for its own disk (correct) |
| geoMusic    V1.0 | APP | GeoMusic (Unkeyed).D64 | starts (dialog, menu or window as expected) |

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

## Code sweeps

Full code-quality reviews at fixed moments (CLAUDE.md "Code-quality
sweeps": end of each phase step, before each release, at the latest
after about ten feature commits). Criteria: overflows, leaks, error
handling, the GEOS contract, clarity, and since 2026-11-04 (user)
maintainability: short single-purpose routines with header comments,
named constants, no undocumented coupling across modules, overlay
modules split by function, shared code in includes, tests per routine.
Log:

| Date | Scope | Findings | Fixed | Open |
| --- | --- | --- | --- | --- |
| 2026-11-06 | Fifth sweep, end of gush step 3: what changed since the fourth (gush step 3: variables, redirection, scripts, control flow, pipes, the history file, the VLIR overlays, completion, external commands, wget and ifconfig; `src/cmds` and wc; engine module 80 `FE_UCI`; `tools/vlircvt.py`; the gush tests). The kernal outside enginenet.s and the dispatcher's table is unchanged since the fourth and was not re-read. Scans: interrupts and the CPU port (php/sei/plp, `$01` saved and restored), every FE_OPEN/FE_OPENDIR with its FE_CLOSE on each path, buffers against their longest input (wget's host, name, request and status line; the module's 4 KB; completion's names; `.cvt` names), overlay data set before use (it survives while the overlay stays), no call from one overlay into another (`gtables.py`), budgets | (1) The `sta`/`bne` trap in the statement and stage scanners (3.5, fixed then). (2) A pipe read's limit compared the low byte only (3.5). (3) gush's test helper took the last of two labels of one name (a module's own `lineLen` over the editor's). (4) wget: the socket's close reported errors after a finished download; a status line shorter than 12 characters was read past its end. (5) Maintainability: the info-block, kind and open-mode constants and the transient area defined again in up to eight files. (6) GUSH.md's memory section described two overlays | (1)-(4) fixed (3.5, 3.7, 3.9); (5) one definition each in gush.inc; (6) rewritten | Budgets: gush's core to `$480E` (2 KB below the transient area), overlays 3.3, 2.4, 0.9 and 2.9 KB of 4 KB; zero page to `$9F` of `$DF`; HIGHBSS to `$7D72` of `$7F3F`; all eight application REU banks in use (bank 7: the overlays, 16 of 64 KB). Kernal: module 22 12 bytes (6 functions), module 80 162 of 496; the others as in the fourth sweep. Drive E is not reachable by path yet (`/e/bin` in PATH finds nothing): modules there need that engine step. `ping`/`host`: not possible with the Ultimate's network target |
| 2026-11-05 (2) | Fourth sweep, end of gush step 2: what changed since the third (engine E4: CVT, Ultimate streams, mount/umount/FE_MOUNTINFO, mkimg; FE_TURBO, FE_HOME, FE_SETTIME, FE_REBOOT, FE_NTP; the boot's turbo=N and NTP step; gush sys.s, sysset.s, the mouse; the U64 tests). Scans: carry kept in multi-byte loops (after FE_NTP's cpx find), self-modifying code in overlay modules (after FE_READ/FE_WRITE's), header comments; every Ultimate file opened in modules 56-79 checked for a close on each path; stack measured on the U64 (mount, write-back, mkimg, ntp, CVT: nothing below $0190, at least 144 bytes free); gush's buffers (imgPath, diskName, iniPath, the SETTINGS.INI text) bounded | (1) gush mkimg's type table read "6788" for "678n": dnp unknown. (2) turbo -s: the [system] match turned "[" into "{" (a second [system] added), and a file without a final line end got the new lines glued on. (3) Module 67 had its own copy of the home-folder code. (4) The dispatcher (module 22) had 8 bytes left, 2 per function, and an unused entry. (5) Five routines without a header comment | (1)-(5) fixed in their own commits, with U64 checks for (1) and (2) | A shared send-without-data helper (copied as Send/Exec in modules 45, 56-58, 67, 70, 71) does not fit feult.inc: module 61 has 3 bytes free. The dispatcher: 14 bytes, room for 7 functions; step 3 moves its table out when it needs more. Budgets: BFCODE 1, KCODE 3, DRVEXT 8, IOCODE 8, CODE 23, INIT 81; modules 61 (3), 15 (5), 27 (6), 49 (8), 43 (12), 10 (13), 22 (14), 2 (14), 37 (16), 57 (18), 66 (20), 75 (22); 80 modules. gush: 10.3 KB code, BSS to $4C1D |
| 2026-11-05 | Third sweep, end of gush step 1.6: what changed since the second (file engine E3 and L, `src/gush`, geoFolder's gush button, the U64 and gush test drivers); stack depth measured in VICE (`cp -r` five folders deep with a long name: 164 bytes of stack left below MainLoop's); segment budgets from `build/*.map` | (1) Rename on the Ultimate (module 43) built the RENAME command in `uCmd` first and checked its length after: two long names ran into `dirEntryBuf`. (2) gush's program start copied a word longer than a name into its path without a bound. (3) Dead symbols `FE_UNAME_MAX`, `KEY_BS`, `firstPath`. (4) `gu64.py` never removed the old gush from drive A's test image (c1541's `-delete` does not match GEOS's lower-case names) and fetched the image while a write-back was pending, so the U64 ran an old gush | (1) both names measured before the command is built (`Fits`); (2) a word longer than a name is not looked for on the drives' roots, the copy bounded by the check; (3) removed; (4) old copies deleted through GeoUltra, the test waits for `wbPending` 0 before it touches the image | Budgets tight: BFCODE 1 byte free, KCODE 3, DRVEXT 8, IOCODE 8, CODE 23; overlay modules 15 (5 free), 27 (6), 49 (8), 43 (12): new kernal work needs new modules, not growth of these |
| 2026-11-04 | Second sweep, the first with the maintainability criterion: everything changed since the first (folders and 1581 partitions, root merge, DNP resizing, write-back retry, overlay addressing, `tools/sysreloc.py`, `tools/mkappsdnp.py`) read in full; the rest of `src/` checked for duplicated constants and drive-type logic and for segment budgets | (1) RemoveDir on a 1581 freed any CBM partition at sector 0, also one that is no sub-directory or not formatted as one. (2) GetCurDir on a drive without folders returned X = the device number instead of 0. (3) SetGEOSDisk inside a 1581 partition searched for the border block from track 40, not from the partition. (4) `tracks=` in MOUNTS.INI wrapped above 255 and accepted 0-1. (5) Maintainability: the drive-type check written out in five places, the 1581 helpers (sizes, validity, BAM entry) in three copies, the drive flags in four files and `SLOW_BANK` in two; a comment naming the wrong module; two deliberately ignored errors without a comment; the folder file's header described native folders only. (6) Budgets: `CODE` 6 bytes free, `KCODE` 3, `IOCODE` 8, `KEXT` 1, `DRVEXT` 2, module 15 5, module 2 14. (7) `sysreloc.py` looped forever on a directory chain that loops | (1) RemoveDir checks as SetCurDir (whole tracks, track 40 outside, header "D" linked to t/3), new test case. (2) X = 0 with r1 = 0/0. (3) from the directory track. (4) bounded (2-255, else no resize). (5) `IsType`/`Is1581`/`Native` in `foldershared.inc`, `part81.inc` and `bam81.inc`, `drvflags.inc`; comments fixed. (6) The dialog box drawing and recovery moved into module 11: `CODE` 105 bytes free. (7) refused with a message | (6) the other resident segments stay nearly full: the file engine (phase 3) must cost almost no resident bytes (one dispatcher entry, not a stub per call), and moving more rarely used routines out of `KCODE`/`IOCODE` stays open. The rest of `src/` (unchanged since the first sweep) was not re-read line by line |
| 2026-10-30 | All of `src/kernal`, `src/drivers` (buffers, UCI open/close and error paths, interrupt state, overlay rules, stack use, segment budgets); `tools/` read for the same | (1) The write-back ignored SEEK/SAVE_REU errors and cleared the change map and flag anyway: a failed write (stick removed, file write-protected, stick full) lost the changes silently. (2) `UciData` copied any reply in full: into `SCRATCH` (one page before the mount table being built) a long reply (control `$50`'s log) could overwrite the table. (3) Menus with more than 15 items or 4 levels, more than 20 processes or sleepers overrun their tables, as in GEOS 2.0 (the application's responsibility there too). (4) Segment room: `CODE` 1 byte, `KCODE` 3, `IOCODE` 12, overlay module 15: 5. (5) Stack: an application start uses about 104 bytes (the gate's saved r0-r15 and the speed list) plus overlay frames. (6) `irq.s` imported `WbCheck` unused. Checked without findings: every UCI file opened in mount, write-back and hibernation is closed on every path; `sei` always with `plp` or a deliberate `cli`; nested overlay calls keep their values resident | (1) a failed write keeps map and flag and is tried again after 5 s (`RETRY_DELAY`); (2) `UciData` stops at `dataLimit`; (6) removed | (1) verified on the U64 the same day (see "Verified on hardware"). (3) clamps once there is room. (4) partly done the same day: module addresses computed instead of tables, 55 bytes of `CODE` freed and new modules free of resident cost; moving rarely used `CODE` routines into modules stays open. (5) watch with new stack users |

## For the user, at the computer

Done 2026-10-30: the DirMaster reference DNP, the hibernation power cycle
(with and without C=), and the GEOULTRA/test and BACKUP folders (both kept).

To try by hand after gush step 3 (2026-11-06; the automatic tests ran in
VICE and on the U64, docs/GUSH.md "Step 3"): completion with `<-` while
typing; `wget http://...` and `ifconfig`; an external command: copy
`build/cmds/wc.cvt` into `GEOULTRA/bin` on the stick, then `wc FILE` or
`ls | wc` from any folder; the history across a `reboot` (cursor up); RUN/STOP held during
`while true; do echo x; done` (it should stop the loop).
Ideas welcome for which commands should become external ones, and
whether `/e` (drive E) should be reachable by path next (then modules
could live on the system drive).

## Still open

- The Command Interface unlock at boot (`$AB` to `$D038`, `$CD` to `$D036`,
  mount.s) did not bring the UCI up on the U64 on 2026-11-04 after a
  GDOS64 session had left it disabled in the running settings (nothing
  mounted). Retested the same day with the interface disabled after a
  plain reboot: the unlock worked. `MountAll` now waits up to about 2 s
  for the interface after the unlock (as the Ultimate library does); the
  state after a GDOS64 session is still to retest.
- geoPublish: both unkeyed copies the user has fail on GeoUltra, genuine
  GEOS 2.0 (VICE) and GDOS64 (U64, user's test 2026-11-04): defective
  copies; a working one later, e.g. from the original disks through the
  serial bypass.
- Native folders: inside a folder without a name in its header (DirMaster
  leaves it empty) take the parent entry's name as the disk name.
- BASIC programs on GeoUltra drives: the GEOS 2.0 deskTop starts a BASIC
  file with `ToBasic` and the command `LOAD"name",8`, which goes to the
  real IEC bus. `ToBasic` could recognise that command, load the file
  from the GeoUltra drive itself (it already can, with r5) and type RUN.
  Together with that: refuse GEOS 2.0's RBOOT, GEOS and GEOBOOT there
  (they would restart GEOS 2.0 over GeoUltra; RBOOT from the REU, where
  GeoUltra's data is), and the boot files of Wheels, MegaPatch3, GDOS64.

- Conformance: in the menu interaction tests GEOS 2.0 shows "System error"
  after a click on the third item of a three-item vertical sub-menu
  (tests/conformance/menu.py, `action`); GEOS 2.0 bug or test artefact
  still to find out.

- Extended jump table: settled, `guExtTable` (`$C0E4`) points to it
  (ARCHITECTURE, "Folders").
