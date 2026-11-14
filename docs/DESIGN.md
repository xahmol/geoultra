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
| System drive | (User, 2026-10-29.) A read-only drive with GeoUltra's own GEOS files (desk accessories such as geoFolder and the settings DA, fonts, drivers, tools), built by our own tools into the cartridge image and copied to the REU at boot (banks 2-17, "ROM mirror"). It is drive **E** (device 12; since 2026-11-06 a native image with folders, `/e/bin` for gush's commands, shown by the file engine in a free drive slot when a path names it, user's decisions), outside A-D: GEOS 2.0's variables and existing applications know only A-D, so applications never get E as their drive and all four letters stay free for the user's images; GeoUltra's kernal and the new desktop use it ("E: System"), the kernal switching to it only briefly and invisibly. **Merging**: when an application lists desk accessories or fonts (`FindFTypes` for `DESK_ACC` or `FONT`), the kernal adds those of drive E to the list, and loading one that is not on the application's drive falls back to E, so every application's geos menu and font menu offer them. **The drive's root folder too** (user, 2026-11-04, built): applications in a folder of a native drive also get the root folder's desk accessories and fonts, before drive E's. **Built (2026-10-29)**: E's blocks show as tracks 221-255 of every drive (the image relocated at build time), so applications that keep track/sector pairs (geoWrite's fonts) read them too; checked in VICE with geoFolder and a test font in geoWrite 2.0 (ARCHITECTURE "System drive"). Not on native drives with more than 220 tracks |
| Directories | Approved by the user 2026-10-29 (design with mock-ups: https://claude.ai/artifact/LuumH5NBYSykn74ByyJYA8). **On disk**: native (DNP) drives get CMD native subdirectories (CBM type DIR entries with their own header and directory chain, as CMD HD/RAMLink, MegaPatch3, Wheels and GDOS64 write them), created, entered, renamed, moved and deleted (with contents after a confirmation); 1581 images: CBM DOS partitions that meet the sub-directory rules (whole tracks, at least 120 blocks, track 40 outside) act as folders, also nested, created (size rounded to tracks), entered and deleted (built 2026-11-04 and checked against the real 1581 DOS: entering, leaving, using, creating with a size in tracks, deleting when empty); 1541/1571 stay flat. **Long names** on top: the normal 16-character names stay (a valid disk for every system and application); GeoUltra keeps long names (up to 60 characters, mixed case) in one file per folder, `GU.LONGNAMES` (USR, sequential: per file its directory block and slot, short name and long name), short names made from the long name (first 13 characters, then `~1`, `~2` to stay unique), entries whose short name changed elsewhere repaired; the desktop hides the file; a setting per drive switches long names off. The 18-page directory limit stays for 1541/1581, native folders allow more. **Kernal**: a current folder or partition per drive; `OpenDisk`, `Get/PutDirHead`, the BAM, directory, file and VLIR routines work inside it, so existing applications see it as the whole disk; a change behaves like a disk change (noticed at the next `OpenDisk`); kept in a hibernated session and per task; extended jump table: `GetCurDir`, `SetCurDir`, `DirUp`, `MakeDir`, `RemoveDir`, `GetLongName`, `SetLongName`, `MoveFile` (re-link within a drive). **Existing applications** reach other folders three ways: the `geoFolder` desk accessory (each drive's current folder, links to the mount dialogue), folders listed in `DBGETFILES` (`..` and `/name` before the files; choosing one enters it, only real file names go back to the application; on by default, a setting turns the listing off for an application), and keys in file dialogs (RETURN on a folder enters, DEL goes up). **Ultimate file system**: a full file manager in the desktop (browse USB/SD in the same views and two panes; copy, move, rename, delete with confirmation, new folder; mount into A-D, unmount with write-back, create D64/D71/D81/DNP images; GEOS files leave as `.cvt` and come back as GEOS files, other files plain, folders recursively; mounted images cannot be moved, renamed or deleted). Build order: native folders and the current folder in kernal and driver with the extended jump table, then 1581 partitions; `DBGETFILES` with folders and keys, geoFolder; desktop core with the modern view, the Ultimate file manager and the mount dialogue; long names; classic view |
| Desktop | New, own design (user, 2026-10-29, replacing the earlier Workbench-style idea; mock-ups: https://claude.ai/artifact/2yrZuKGyDceuaFJ2Do4gsq). One core (drives, directories, sorting, copy, move, delete, rename, mount, starting applications, task bar, hibernation) with interchangeable views, each a VLIR record of the desktop application loaded on demand. **Modern** (default): GEOS menu bar and conventions kept (geos menu with desk accessories, file / view menus); sidebar with drives A-D, Ultimate folders and recent documents; the current directory in a list; an action strip for the selection; a task bar with running applications and Suspend. Views of the list, switched with a key or the view menu: list (names), detailed (name, type, size, date; sortable), icons (from the GEOS file headers). Two panes as an option (key or `view > two panes`) for copying and moving between drives and directories. **Classic** (a setting, `desktop > style`, also by key): GEOS 2.0-like notepad with pages and icons, drive icons on the right, on the same core. Overlapping windows (TopDesk style): possibly later, only on demand. Stays a normal GEOS application towards the kernal (`EnterDeskTop` starts it) **Order and first milestone (user, 2026-11-06):** after gush step 3, first the file engine's read-only drive E by path (`/e`: listing, stat, read, copy from it; programs and gush's external commands found in `/e/bin`), then the desktop. Milestone 1: the Modern view with the list view only: menu bar (geos menu with the desk accessories, file, view), sidebar with drives A-D, E and the Ultimate's roots, the current folder as a list of names; open or start, copy, move, delete, rename, new folder, all through the file engine. The Ultimate's file system is a full peer of the drives (browse, copy to and from with CVT as in gush, delete, rename, folders; a disk image opened mounts it, asking for the drive). No task bar yet (room kept in the layout; it comes with the task switcher). While it was built the new desktop was opt-in (`SETTINGS.INI` `[system] desktop=geoultra`); since 2026-11-11 (user) it is the default and the cold start ends in it, `desktop=geos` brings back GEOS 2.0's deskTop. The detailed and icon views, two panes and the Classic style follow as their own steps **Details (user, 2026-11-06, second design round):** the list in GeoUltra's own system font with columns at fixed pixel positions (name, type, size, date; long names clipped at their column); copying and moving by copy or cut, then paste in the destination (the same later in two panes); the sidebar holds drives A-D, drive E, the Ultimate's roots, favourite folders (kept in `SETTINGS.INI`) and recent documents; keys: cursor up and down move the selection, SHIFT extends it, RETURN opens, cursor left goes up a folder, DEL deletes (asking), and the menus carry GEOS-style C= shortcuts (C=C copy, C=X cut, C=V paste, C=R rename, C=N new folder, C=Q quit) |
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
| Themes | A theme sets the 16 palette colours (firmware 3.15a palette control on the U64; not yet released for the C64 Ultimate (user, 2026-11-11); applies to every program, original GEOS applications included), GEOS's colour defaults (desktop background, notepad and pad colours `$8FE8-$8FF0`, border, pointer), the desktop pattern and optionally the system font style (same metrics, so dialogs stay right). Built-in presets (classic GEOS grey, idi8b colours, dark, high contrast) plus an editor page in GeoUltra Settings; themes are INI files in GEOULTRA/THEMES. On an Ultimate II+ (no palette control) only the colour choices apply. GeoUltra's desktop (user, 2026-11-06): a theme is a set of design elements (title bar, headings, selection, cursor, icons, scroll strip, status line, ...) each with a style and colours by name, never palette numbers; default theme GeoUltra (docs/DESKTOP.md, "Look and themes") |
| Hardware wording | Peripherals (drives, interfaces, mice and other input devices, printers, expansions) are supported on a best-effort basis: the documentation lists what was tested on which hardware and never promises that all devices work |
| AI transparency | Fully open about the use of AI: the README's "Use of AI" says who decides and who writes, every commit written with AI carries a `Co-Authored-By: Claude` line, and release notes, posts and blog texts mention it |
| Compatibility wording | GeoUltra aims at the GEOS 2.0 interface and is checked against GEOS 2.0; the documentation never promises full or 100% compatibility (the GEOS world has many versions, add-ons and developments, some lost), and names what was actually tested |
| Boot mounts | Restore the last session from the mount list (with its write-back state), plus the read-only system drive |
| System font | New 9-point design with the BSW metrics (height, baseline, similar widths), so old applications' dialogs and menus lay out correctly |
| Input driver | 1351 mouse in port 1 in the ROM (also what the U64's USB mouse emulation presents); other drivers load as files |
| Task switcher | Hot key checked in the IRQ (for example C= + RUN/STOP) opens a task list; also a desktop menu entry. A switch saves the whole 64 KB of the task to its REU bank (about 65 ms each way at 1 MHz) plus its VIC, SID and CIA registers, and only at the top of MainLoop (the IRQ just sets a flag), never inside a disk call. Before leaving a task with a changed open file (`fileWritten`), the file is committed as `UpdateRecordFile` does and stays locked for the other tasks (open, delete, rename fail with a clear message) until its task closes it; on return the task's current drive's BAM is read again. Each task has its own legacy REU area. Same approach as MegaPatch3's TaskManager (behaviour idea only) |
| Settings | `GeoUltra Settings`: an application with index-card pages (GDOS64 style), also a desk accessory and a desktop menu entry. Pages: drives (mount list, write-back, backups), memory (legacy REU size, task slots), Ultimate (turbo, REU, clock/NTP), input, printing (virtual printer, print to file, network push), desktop (colours, palette, view defaults), system (serial number, hot keys, boot options). One readable INI-style file in GEOULTRA (`[section]`, `key=value`), editable on a PC too; applied at boot and when saved |
| Real IEC drives | Best effort. Aim: own turbo disk drivers per drive type (1541, 1581, 1571, then CMD FD/HD), clean-room, turbo off around every transfer. Route: first an import/export tool in the desktop (whole disk to an REU image drive and back, for CBM-DOS drives that follow the standard protocol, phase 3); then a slow universal IEC driver (standard serial protocol, also the base for drive detection and turbo code upload, and a fallback to try with devices such as SD2IEC or Pi1541 and drives without a turbo driver); then the turbo drivers, one drive type at a time (phase 6). Which drives and devices work is decided by testing, not promised. Drivers live in the `$9000` area (the C64 Kernal ROM hides `$E000` while it is mapped) and may use zero page `$90-$9F` |
| Boot splash | Shown by the boot ROM during a cold boot only (skipped on reset recovery), no artificial delay: light-blue "U" logo with dithered shadow, desktop window with pointer, folder/floppy/printer icons, "GeoUltra", tagline "Graphical desktop for the Ultimate", and a narrow black band (cell rows 22-24) with a compact redraw of the idreamtin8bits (idi8b) logo on the left (64 x 20, every bar of the original as a 1-pixel bar, each letter in its own colour cells) and the version line (since 2026-11-14 the full version as GeoUltra info shows it, vMAJOR.MINOR.PATCH-YYYYMMDD-HHMM, read from the built kernal's info block; the user's request) and boot status line stacked to its right (light red for errors such as no REU or no Command Interface). Generated by `tools/splash/mksplash.py` (320 x 200 hires bitmap and colour matrix) |
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

**Version 1.0 (the user, 2026-11-14):** Beta 1, then the rest of
phase 3 (task switching, printing, spooler, clipboard), the documents
(user manuals, technical reference, developer guide) and the serial
numbers per application (`[serials]` and the Settings card); after that
the 1.0 release. Phases 4 (Ultimate II+), 5 (GEOS 128) and 6 (real IEC
drives) and the network roadmap are 1.x and later.

**Releases and documentation (the user, 2026-11-12):**

- **Beta 1, at the end of the desktop work in phase 3** (confirmed by the
  user 2026-11-12; Ultimate 64
  family only): after two panes with drag and drop, the settings tool's
  first version (theme editor, desktop, system with REU and drives,
  pointer designs), a stabilisation step (tenth sweep, full regression in
  VICE and on the U64, a hand-test checklist for the user) and first
  user manuals. Before printing and task switching (large on their own)
  and before phase 4 (the Ultimate II+). With release notes, the
  Facebook post and blog text, and a first-look video made the
  established way (VIC-stream capture driven by a scene script, Piper
  "Alba" voice-over, title and closing cards). The video's driver
  (agreed with the user 2026-11-13): an autopilot loaded into the C64
  before the take, which moves the pointer smoothly along the scene
  list (eased paths, not jumps), presses and releases the button
  (clicks, double clicks, drags) and types, from inside GEOS (an
  interrupt-level routine through GEOS's own mouse and key variables),
  so that the recording needs one start command and no memory reads
  that disturb the picture (at most a done flag once a second).
  Done 2026-11-14: a sneak peek at version 0.1 (the repository stays
  private until the release), live at https://youtu.be/KjweEX6IJIk;
  made with tools/video (autopilot.s, pilot.py, scenes.py, edit.py),
  announced on Facebook and a forum.
  Scenes: the boot and splash, the desktop (list and icon view, themes,
  two panes, drag and drop), the mount dialogue, geoWrite and geoPaint
  from folders, gush, GeoUltra Settings (themes, palette, pointer,
  time). Filmed when the hand tests, the file box drive letters and
  the Settings Drives and REU pages are done.
- **Auto-exec files at the cold start** (the user, 2026-11-14, put on
  the roadmap after a question online): as GEOS 2.0's boot runs the
  boot disk's AUTO_EXEC files (input and printer drivers, configuration
  tools) before the deskTop, GeoUltra's cold start should run those of
  drive A (or a configured drive and folder) before its desktop; today
  they can only be started by hand (GetFile handles them). Decided by
  the user (2026-11-14): a list in SETTINGS.INI, `[system]
  autoexec=/a/CONFIGURE` lines (a path with its drive and folder), run
  in that order at a fresh cold start only (not after a resumed
  session), skipped while SHIFT is held (the user, the same day: C=
  stays the resume's key alone, so a fresh start after a broken session
  still runs them; both held: a fully clean start); only GEOS AUTO_EXEC
  files; edited on a new **Start** page in
  GeoUltra Settings (a list with add (a file dialog of AUTO_EXEC files
  on A-E), remove, up and down; room there for later start-up
  choices). Kernal part built 2026-11-14 (src/kernal/autoexec.s, modules
  92-93: the list read into REU bank 1 $1C00 at the cold start's end,
  EnterDeskTop's module 0 starting the next one; U64 test autou64.py:
  two files in the list's order, a missing one skipped, firstBoot FALSE
  meanwhile and TRUE after). Settings' Start page built the same day
  (pstart.s, overlay 8: the list, add through a browser of the GEOS
  drives' folders and AUTO_EXEC files, remove, up, down; VICE test
  s7.py).
- **User manuals** (when design and functions are stable): system (boot,
  drives and images, MOUNTS.INI, hibernation, turbo, the REU), desktop
  (docs/DESKTOP_MANUAL.md), gush (docs/GUSH_MANUAL.md), settings,
  geoFolder.
- **Technical reference** (before 1.0): GeoUltra's additions to and
  changes from the Hitchhiker's Guide to GEOS, as a delta document: the
  information block and signature, the extension jump table, the file
  engine API, folders and long names, native drives, the REU map and the
  applications' REU, hibernation, turbo, the input driver's right
  button, CVT, the file formats (MOUNTS.INI, SETTINGS.INI, themes),
  compatibility notes.
- **Developer guide** (separate, before 1.0): detecting GeoUltra and
  using its additions from a program, gush's external commands
  (docs/GUSH_COMMANDS.md), the geos-oscar64 C library, building and
  testing.

## Roadmap: network and Ultimate applications (the user, 2026-11-12)

On the roadmap (the user, 2026-11-12: all of them), after the first
release; the order below is the suggested one (smallest first, each
building on the one before), to be fixed when phase 3 ends. The Ultimate
gives TCP and UDP sockets (UCI
network target: connect, read up to a packet of 896 bytes, write; no
listening sockets in firmware 3.15) and an HTTP target (firmware 3.15;
the library's functions are untested on hardware, and a raw exchange
does not show the server's status code).

- **Telnet BBS client with PETSCII and colour: feasible, medium scope.**
  The cleanest way is for the terminal to switch the VIC to text mode
  with the machine's own character ROM while it runs (exact PETSCII, 16
  colours per character, hardware scrolling help; no glyphs copied) and
  back to the GEOS bitmap for its menus and dialogs, GEOS's interrupt
  and processes running on. A bitmap renderer (40 x 25 in 8 x 8 cells,
  one colour pair per cell, as PETSCII has) would also work, with REU
  DMA for scrolling. Needed: PETSCII control codes (colours, reverse,
  cursor, clear), a minimal telnet negotiation (IAC answered with
  refusals), its own keyboard reading for the C= and SHIFT graphics keys
  (GEOS's driver turns C= + key into shortcuts), a phone book, and
  downloads (XMODEM, Punter) through the file engine onto any drive.
  Speed is not the problem: the socket delivers far faster than a modem.
- **A light web browser for HTTP sites: feasible, larger scope.** The
  target (the user, 2026-11-12) is exactly the sites made for old
  machines: FrogFind (search and modern pages simplified, served over
  HTTP) and the like (68k.news, text-only sites). HTTPS: research on
  supporting it in the Ultimate's firmware is going on (the user); if it
  comes, the browser takes it through the firmware, not on the 6502. GEOS suits the
  rendering: proportional fonts, bold and italic, headings in larger
  sizes, word wrap, links as underlined text. Pages kept in the REU (16
  MB) and parsed as a stream; HTTP/1.0 over a raw TCP socket (status
  codes and redirects); UTF-8 folded to the GEOS character set; forms
  only as simple search fields; images left out (alt text), at most
  small ones later. A Gopher client is the cheap first step: plain text
  and menus, the same rendering and history, a fraction of the work.
- **The terminal in GEOS's look (the user's question, 2026-11-12):**
  keeping the menu bar and the task bar, in hi-res, is possible: the
  GEOS bitmap's colours go per 8 x 8 cell, as PETSCII's per character
  (one background), so a 40-column grid on the cells keeps every
  character's colour exactly; the glyphs drawn into the bitmap from the
  machine's own character ROM at run time; scrolling by REU DMA. The
  cost is rows: the menu bar (2 cell rows) and a status or task bar (1)
  leave 22 of a BBS's 25. Suggested: a 40 x 22 window on the bottom
  rows as the normal view, plus a key for a full 40 x 25 screen (the
  menu back by key or the pointer at the top); to settle in the
  terminal's design round.
- **Decided (the user, 2026-11-13): ANSI with 80 columns in a 4 x 6
  font**, the 4x6 font of the u64-bbcbasic project (`src/fonts/4x6.bdf`:
  X11's misc-fixed 4x6 by Janne V. Kujala, public domain; credited in
  the source and the README): 80 columns fill the 320 pixels, 6-pixel
  rows give 33 rows in 200 lines (25 of a BBS beside the menu and the
  task bar); the colour clash of two characters per cell as described
  below.
- **ANSI as well (the user's question, 2026-11-12):** the colours fit:
  ANSI gives each character a foreground and a background, a hi-res
  cell has exactly one of each (also the 16 backgrounds of "iCE
  colours"); with an Ultimate 64 palette the 16 VIC colours become the
  PC's 16 (exact, as the theme palettes), on an Ultimate II+ the
  nearest VIC colours. The character set (code page 437's box drawing
  and blocks) must be own drawings, 8 pixels high (clean-room: not the
  PC's font). The limit is width: ANSI is 80 columns, 320 pixels give
  4-pixel characters, two per colour cell, so two neighbours of
  different colours clash (plain text and menus mostly fine, detailed
  art not). Suggested: both views by key: 80 columns (4 x 8 glyphs,
  the whole width, the cell's colours from one of its two characters)
  and 40 columns (8 x 8 glyphs, exact colours, the view panning with
  the cursor or the mouse); 22 rows beside the menu and the task bar,
  the full-screen switch for 25. The C128's VDC has 80 columns but in
  text mode one background for all characters; its bitmap mode has
  cells as on the C64. Speed (the user, 2026-11-12): the C128 runs at 2
  MHz at most and reaches the VDC through two registers, a byte at a
  time, while the U64's turbo makes software drawing and scrolling
  cheap; the U64 is the better target. To decide later (the user).
- **The order** (in rising order of scope; the browser last, after the
  Gopher client and the terminal):
  1. *Fetch* (a gush command first, a dialog later): a file from an
     HTTP URL onto a drive or the Ultimate, CVT files converted as with
     copy. Small; gives access to GEOS software archives.
  2. *A plain text editor* for files on the Ultimate and SEQ files
     (MOUNTS.INI, SETTINGS.INI, themes, read-me files): those cannot be
     opened from the desktop now. Small to medium, reuses the desktop's
     fonts and dialogs.
  3. *A calendar desk accessory* on the NTP clock (month view, the
     date's day of the week). Small.
  4. *A music desk accessory on the Ultimate 64's Ultimate Audio* (MOD
     files played by the hardware, so GEOS keeps running; the library
     has the MOD player). Small to medium; U64 only.
  5. *A Gopher client* (above), as the network's showcase before any
     browser.
  6. *The BBS terminal* (above).
  7. *The web browser* (above), on the Gopher client's rendering and
     history.

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
| Right mouse button (2026-11-11, the user's hand test, tests/desktop/mouse2u64.py): the U64's USB mouse as a 1351 in port 1 | Passes: four right presses each seen in `guMouse2` ($80 -> $40 held -> $C0 released, the press kept), the left button only in `mouseData`; the context menu can use it |
| REU DMA reads the Megabyter ROM window (banks 1-7 stashed from `$8000`, compared with the CPU's view) | Pass on the U64 at 1 MHz and at 64 MHz (manual turbo), and in VICE 3.10 |
| The REU keeps its content across a reset | Pass: signature and boot counter survive `machine:reset`, and also starting another cartridge with `run_crt` |
| The Megabyter cartridge autostarts again after a reset | Pass (the basis of reset recovery) |
| `SAVE_REU` after a seek writes at the file position | Pass: 256 bytes written in place at `$1000` in a 64 KB file opened with attribute `$03` (read/write, existing), size unchanged |
| `LOAD_REU` after a seek reads from the file position | Pass (the basis of the later track-cache mode) |
| Disk images open and load into the REU whole (`tests/smoke/gud64.c`, 2026-10-29): `OPEN_FILE` with `$01` (and `$03`) then `LOAD_REU` | Pass for a D64 in `/Temp`, and read-only from the USB stick for a D64 (174 848 bytes), a D81 (819 200) and a DNP (4 521 984); headers (18/0, 40/0, 1/1) correct in the REU. The UCI manual's note that a read-open of a disk image returns `89,NOT A DISK IMAGE` does not hold on the U64-II with firmware 3.15a (corrected in library 1.4.3). The firmware's GEOS RAM disk trial load (`$41`) returns `91` |
| Write-back (2026-10-29, test copies in `/USB0/GEOULTRA/test`) | Pass: a block written on drive B (D64) reached the image a few seconds later, only that block changed, size unchanged; two separate blocks on drive A (D81, first and last block) likewise; the backup in `GEOULTRA/BACKUP/` equals the image as mounted; after a reset with an unsaved change the session was kept and written back. The firmware's copy command (`$0B`) copies into a folder, keeping the name |
| Palette control (2026-11-11) | Pass on the U64-II, firmware 3.15a: `GET_PALETTE`, `SET_PALETTE` and `RESET_PALETTE` through `FE_UCI` (control target 4); the desktop's theme palettes (tests/desktop/d7u64.py). Not yet released for the C64 Ultimate |
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
| GeoUltra Settings writing SETTINGS.INI (2026-11-12, step S1) | Pass on the U64 (tests/settings/s1u64.py, 6 checks): started from the desktop, two Desktop-page options clicked, Save wrote the file through SETTINGS.TMP with the two keys changed and every other line (a comment, [favourites]) byte for byte as before; OK went back to the desktop, which started with the chosen view. The user's SETTINGS.INI set aside and restored (compared) |
| Desktop regression after two panes and drag and drop (2026-11-12, build 47739f0) | Pass on the U64: d6u64 9 (mount and unmount through the desktop), d8u64 7 (copy, move, delete on the Ultimate, CVT paste), d10u64 14 (copy, move, delete on native drive C), d12u64 3 (Info on Ultimate files); the user's SETTINGS.INI kept and restored byte for byte, MOUNTS.INI unchanged. Two panes and drag and drop themselves: VICE (d13) and the user's hand tests |
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
For the next sweep (the user, 2026-11-14): take every "step" and
"phase" out of the code and above all the UI (gush's welcome line still
says "step 3"); the program speaks of what it does, not of the plan's
stages.

Log:

| Date | Scope | Findings | Fixed | Open |
| --- | --- | --- | --- | --- |
| 2026-11-14 (2) | Thirteenth sweep, about a dozen feature commits after the twelfth (0f7c5e6..d0ad3c0): disk images as folders (engineimg.s, modules 88-90; sysenter.s HideE, HDrive, HMark, Usable), the DNP size at mount (enginesize.s, module 91), long names off per drive (enginelong.s OvShort, enginemount.s OvInfo now module 69, Line; mount.s SizeOption), [system] legacy= (mount.s), the desktop's open.s and errors, menu shortcuts (desktop.s Shortcuts), the hidden inactive selection (list.s IsSelected), icon colours by type (iconview.s Tint, gridTop; themefile.s, theme.s, themedef.inc), Settings' Theme page part (ptheme.s), the REU page (preu.s), the Drives page (pdrives.s), the splash's version (mksplash.py). Scans: unused imports over src/kernal, src/desktop, src/settings, now with the included files read too (the old scan missed symbols used only in .inc files and so could not check the kernal), the assembler's warnings, budgets, buffers against their longest input, the U64 tests' defaults | (1) FE_MOUNT accepted an image another drive already had (older; the Drives page's browser made it easy): two REU copies of one file would write over each other. (2) 22 unused imports in ten kernal files (most older; enginesize.s and sysenter.s from this round). (3) The older U64 tests (e3u64, e4u64, mntu64) booted whatever cartridge the U64's flash held unless given one: a test of today's build ran an older one (as gu64.py did before). Checked without findings: the Drives page's paths (bpath 128 for FE_HOME's 32 and Join's bound, tpath 146 for 63 + ',tracks=255', names cut at 47 or left out), ReadDir closes its handle on every path, the image's REU copy (the path at $01:1A00, feInfo kept at $1A40 around every nested call, dropped by a writing call, a mount and a resume), Shortcuts run again at every start (the x found anew), Tint's colour for a type not set | (1) module 65 Twice: refused with FE_MOUNTED (the drive being mounted again, a resize, not counted); mntu64.py checks it (A's image onto /d), the Drives page says 'Another drive has that image.'; (2) removed (the kernal builds the same); (3) the cartridge defaults to build/geoultra64.crt | Budgets: kernal modules 22 (2 free), 69 (4), 90 (4), 24 (14), 81 (15), 70 (29), 65 (38), INIT 38, KEXT 26; the desktop core 363, overlay 4 199; Settings' overlays 5 348, 6 2.6 KB, 7 771. The nested overlay depth of an image path is about four calls deeper (24, 88, 90, 68 and the Ultimate's folder change): not measured on the U64 yet. d9 still occasionally slow in the full suite. Not re-read: the kernal outside the files named, gush, tools/video |
| 2026-11-14 | Twelfth sweep, scoped to what changed since the eleventh (01503ac..04da09d): kernal module 77/79's reading of SETTINGS.INI in parts (enginentp.s), Settings in the theme (src/settings/chrome.s, settings.s, settings.inc; the Dialog calls in psys.s and ptime.s), the theme delete (ptheme.s DeleteIt, chrome.s InUse, DeleteTheme), the desktop's reversed sort and column headings (sort.s Keys and Lead, inifile.s DeskRead and SortSave, theme.s ClockTick's sortDue, list.s Header, HeadBold, SortArrow, listin.s SortUnder, SortCol, SortFlip, NewSort, the arrow among the letters), the places' list for two panes (listin.s PlaceMenu, MenuGo, MenuRun, NewItem, PutItem). Scans: unused imports and exports over all of src/desktop and src/settings (a script), buffers against their longest input, the assembler's warnings on a full rebuild, budgets | (1) Deleting a copied theme that was never saved did nothing: it has no file yet, FE_DELETE gives FILE_NOT_FOUND, and DeleteIt kept the name in the list. (2) Unused imports and exports: 14 in ptheme.s and 14 in chrome.s left by the move to chrome.s; in the desktop, 11 imports and 15 exports (some older than the eleventh sweep, whose scan missed them), and inifile.s's header still named side.s's Store. (3) listin.s's warning "Didn't use zeropage addressing for ROOT_LEN" (used before its definition; older). Checked without findings: module 77's Part and Whole (the tail kept, a later read's error taken as the end, a line longer than TEXT_MAX ends the reading), module 79's Keep; chrome.s's buffers (buf 48 for the 32-byte home path plus THEMES, name 64 for FE_READDIR's 61, the delete question at most 36 of buf's 48), Colours' interrupt state and CPU port; DeskRead's "-" (the flag kept on the stack around Pick); SortSave's sortVal (6: "-" and four letters and the zero); PlaceMenu's items (ITEMS_MAX 12: up to 5 drives, 4 roots, favourites cut off), rpath (ROOT_LEN + 2 for "/", 7 characters and the zero) | (1) DeleteIt takes FILE_NOT_FOUND as deleted: the name goes from the list; U64 test s46u64.py gained the case (an unsaved name put into the list, delete, Yes), all 9 checks pass. (2) removed; the desktop and Settings binaries are byte for byte as before. (3) ROOTS_MAX and ROOT_LEN defined before ReadRoots | Budgets: the desktop core 806 bytes free (BSS to $4CD9), overlays 4 (inifile) 238, 8 (listin) 546; Settings' core CODE to $1AA3, overlay 5 827 bytes free, 4 842; kernal modules 77 438 and 79 477 of 496. d9 still timing-flaky in the full desktop suite (passes alone). Not re-read: the kernal and gush outside enginentp.s, tools/video (tools for the video only) |
| 2026-11-13 | Eleventh sweep, scoped to what changed since the tenth (the user agreed to keep the budget for the video): GeoUltra Settings (all of src/settings), the desktop's INI code on ini.inc (inifile.s), the pane letters and roots list (listin.s), the error texts (errors.s), the image refusal (tree.s), kernal module 87 (drvlist.s) and the dialog (dialog.s), the root merge and E's desk accessories first (rootmerge.s, sysdrive.s), the clock (enginesys.s, hibernate.s, info.s, src/inc/clock.inc), ini.inc's segment and iniSkip. Scans: imports and exports no longer used (a script over all modules), files and handles closed on every path, interrupt state, flags shared across modules commented at both ends, budgets | (1) The desktop core had 0 bytes left. (2) The kernal's NTP module reads only SETTINGS.INI's first 511 bytes (enginentp.s TEXT_MAX): a longer file can hide [time] from it (the server at boot silently not asked). (3) Unused imports and exports left from the changes (drvlist.s, dialog.s, listin.s, inifile.s, ptheme.s, psys.s). Checked without findings: ReadRoots closes its directory on every path; clock.inc restores the interrupt state; iniSkip set before the first lookup in both programs; lettersDue and gfDrvPick commented at both ends; module 87's reading of the dialog table (command at dbIndex - 3) | (1) the INI limit 2048 instead of 3072 in the desktop, Settings and gush (the files are about 130 bytes): the core has 1024 bytes free; (3) removed | (2) fixed 2026-11-14: modules 77/79 read the file in parts of 511 bytes, whole lines parsed, the unfinished last line carried into the next part; module 79's line skip also passes lines over 255 characters (it looped on them); U64 test gu64.py ntp_long (1125 bytes with ntp= across byte 511, exactly 511 bytes); modules 77 438 and 79 477 of 496 bytes. Budgets: kernal CODE 0 bytes free, IOCODE 0, KCODE 2, KEXT 31; module 15 ~100, 17 ~100, 87 ~260; the desktop core 1024, overlays 4 (inifile) 353 and 8 (listin) ~1.2 KB; Settings' overlay 5 28 bytes. Not re-read this time: the kernal and gush outside the files named, tools/ |
| 2026-11-12 (2) | Tenth sweep, at the end of the two-pane step (12 feature commits after the ninth): the context menu and Info (ctxmenu.s, overlay 7), the menus and keys, overlay 8 (listin.s: list input, drag and drop, the drop marker, ListEnd and SelAll), two panes (panes.s, list.s's pane state and split status line, desktop.s DropDo), panes= in SETTINGS.INI (inifile.s), the tests d13 and d14u64. Only src/desktop changed since the ninth; kernal, drivers and tools carried over. Scans: the overlay rule over every overlay's code and the core routines it reaches (a script over the sources: no overlay reaches another overlay's stub), interrupt and CPU-port state, buffer bounds (Info's lines, EntryPath into dropPath, the favourite's copy), header comments, budgets | (1) The drag sprite had no colour set (the kernal sets sprites 0 and 1 only). (2) A click in one pane and a quick click on the same row number in the other counted as a double click. (3) A drop into the folder it came from (its own drive's sidebar line, the other pane on the same folder) pasted onto itself. (4) Clarity: SelAll's comments on the old 256-byte selection, dropAt in the core though only overlay 8 used it, panes.s's header, the sidebar search duplicated in desktop.s Press and listin.s SideLine. Checked without findings: ctxmenu.s's sei sections all end in plp, Info's lines bounded (name 26, class 20, lines 40); SwapPane's parts within their pages; EntryPath bounded at 255; the paste path uses only text's first 256 bytes (dropPath at text + 1024) | (1) blue as the pointer; (2) PaneSwitch ends a pending double click; (3) SamePath, the other pane's whole path fetched; (4) comments and the assert on SEL_LEN, dropAt into overlay 8, a cross-reference at both ends of the sidebar search (one routine would need an overlay call from Press or room in the core) | C=T and C=M with both panes on the same folder still paste onto themselves (a FILE_EXISTS question; the guard would need core room). The icon view has no drop marker. Budgets: the desktop's core ends at `$4FCF` (48 bytes free); overlays 1-8: 3.0, 2.8, 0.9, 1.4, 1.4, 1.7, 2.0, 1.7 KB of 4 KB; REU bank 6 as in P1 (overlays `$0000-$7FFF`, history `$8000`, icon cache `$9000-$FDFF`, generic icons `$FE00`); kernal modules as in the eighth sweep |
| 2026-11-12 | Ninth sweep, about ten feature commits after the eighth: the right button (mouse1351.s, info.s), the toolbar (toolbar.s, tooldraw.s, overlay 5), the history (history.s), the toolbar's theme colour, the icon view (iconview.s, tools/mkbigicons.py), menus and dialogs in the theme and the frame (theme.s, list.s Frame), Ultimate files (tree.s OneCopy, mount.s's dialog, list.s SizeKB), the sort (sort.s, overlay 6), the moves of the built-in themes and scratch into overlays 1 and 4, the boot ROM's trigger write; the new tests (d9, d10u64, d11, the d-tests' sorted positions). Scans: the overlay rule (no overlay calls another overlay's stub or a core routine that loads one: Draw, Redraw, Back, View, FavAdd, Theme, Toolbar, SideLoad, SortNow are only reached from MainLoop code), the sort run from appMain (safe: DoDlgBox clears appMain while a dialog runs, dialog.s), header comments, budgets | (1) Found and fixed during the period, in their own commits: the boot ROM's REU trigger wrote $30 into the input driver at $FF00 (7475801); d8u64 refused to run with a user's SETTINGS.INI and now keeps and restores it. (2) Clarity: the toolbar's action routines had no header comments. (3) A considered guard (sort only at the top-level MainLoop's stack) turned out not needed (dialogs clear appMain) and was not kept; the reason is a comment in ClockTick | (2) headers added | Budgets: the desktop's core ends at `$4FDC` of `$4FFF` (35 bytes): the context menu needs room made first (candidates: open.s's program and document starting, the sidebar's list drawing, desktop.s's menu building, as overlays where no overlay calls them); overlays 3.0, 2.8, 0.9, 1.3, 1.0 and 1.7 KB of 4 KB; REU bank 6: overlays `$0000-$5FFF`, generic icons `$7000`, history `$8000`, icon cache `$9000-$FFBF`. Kernal modules as in the eighth sweep (61: 3 bytes, 22: 4, 27: 6, 49: 8); the input driver `$109` of `$17A` |
| 2026-11-11 (3) | Eighth sweep, part 2: the D7a code read again line by line against the checklist: theme.s, themefile.s, icons.s, list.s's progress line and RUN/STOP check, the desktop's ovl.s, errors.s, src/inc/ovlcore.inc, tools/mkicons.py; buffers measured against their longest text from the link map (build/desktop/desktop.lbl) | (1) Overflow: clockText 24 bytes, the 12-hour text at 10-12 o'clock 26 with its zero: the theme's name (curName, right after it) became "m". (2) The clock's clear started at x 200, the right-aligned text further left: pixels of a wider text stayed. (3) Overflow: stBuf 48 bytes, the progress line with a 5-digit block count 49. (4) A theme file the desktop writes can reach ~900 bytes, ThemeLoad read 600 (a palette at the end cut off). (5) Clarity: a magic 1 for the solid title bar, ovl.s's header (records 1 to 3), a dead `ldy`; mkicons.py drew broken or clipped icons for a bad width or a long label without a word | (1) CLOCK_TEXT_LEN 26, d5.py checks curName after the 12-hour clock at 12:42 (fails with the old buffer); (2) cleared from the last text's left edge; (3) ST_BUF_LEN from its parts; (4) FILE_MAX 1024, asserted to fit the INI text it reads into; (5) ST_SOLID, header, removed; mkicons.py refuses both | Tests: test-desktop 57 (VICE), d7u64.py 12 (U64). The eighth sweep is complete |
| 2026-11-11 (2) | Eighth sweep, part 1, after D7a (themes, theme files and palettes, busy pointer and progress line, the desktop's VLIR overlays, recursive copy/move/delete, Ultimate-to-Ultimate copy and move, library 1.4.5/1.4.6). The user's four extras (DESKTOP.md): (1) one folder walk for gush and the desktop, (2) FE_NTP tried twice, (3) Ultimate copies within one folder, (4) room in the desktop's core. Scans over src/desktop, src/gush and the engine modules: FE_OPEN/FE_OPENDIR handles stored before `txa`; `sei` only after `php` with its `plp` (or a deliberate `cli`), the CPU port saved and restored; budgets from build/*.map | (1) Maintainability: gush's tree.s and the desktop's tree.s held two copies of the same walk, grown apart (the desktop's own error and progress handling, gush's path checks). (2) FE_NTP gave up after one lost UDP answer. (3) A copy within one Ultimate folder, or under another name into a folder holding the source's name, was refused (FE_NOT_SUPPORTED). (4) The desktop's core had about 110 bytes left, too few for the toolbar, the right button and the history. Scans: no findings | (1) src/inc/treewalk.inc with hooks (WalkFile, WalkFail, WalkFailDst, WalkSkip); a folder that cannot be made is now reported about the target (cec1c4a). (2) two tries (27ae7ae). (3) module 85 through GU.TMP at the volume's top (4faa66f). (4) the INI files into desktop overlay 4 (650d930): the core ends at $4B3A, 1221 bytes free | Budgets: kernal modules 61 (3), 22 (4), 27 (6), 49 (8), 10 (13), 2 (14); 84 at 421 and 85 at 437 of 496; desktop overlays 2.2, 2.7, 0.8, 1.2 KB of 4 KB; gush's core to $4A38, HIGHBSS to $7E72. Tests on one build: VICE engine 128, desktop 55, gush 188, conformance 301 and 28 (1581); U64 engine 113, gush 48, du64 12, d6u64 9, d7u64 12, d8u64 5. Part 2: the row above |
| 2026-11-11 | Seventh sweep, after desktop D6 (ten feature commits since the sixth: D5a, D5b, the themes design, gush's handle fix, the desktop's fixes of 2026-11-06, D6, the default switch and the cold start without the banner, the REU driver's empty drive). Read again: all of src/desktop (desktop.s, list.s, open.s, actions.s, side.s, mount.s), the changed kernal parts (init.s, mount.s's settings, sysdrive.s, reudrv.s's Locate), gush's hist.s, redir.s, sysset.s. Scans: every FE_OPEN/FE_OPENDIR handle stored before `txa` (all of src); every opened file or folder closed on each path (desktop); buffers against their longest input (path 256, entryName 63, the favourites' 64-byte slots, iniPath 48, the INI text 3073, the mount dialog's lines 12, ejectName 64; FE_MOUNT itself refuses a path over 63); the CPU port and interrupts (list.s Modifiers: saved, restored); the desktop's zero page ($80-$87, 8 bytes); coupling commented at both ends (REU banks 1-4 entries and 5 clipboard; mount.s on actions.s's full and Append); budgets | (1) Maintainability: the six desktop modules defined their own copies of 68 constants (entry points, engine functions and kinds, layout), two names with different values (INFO_LEN 16/64, NAME_LEN 61/17). (2) list.s: an unused label; ListRead ignored FE_PWD's error without a comment. (3) The kernal: a stale "instead of the banner" comment, MainLoop imported by init.s and no longer used. Found and fixed before, in their own commits: the mount dialog's lines (Y lost in NamePart), the REU driver's empty drive (the desktop could not start without an image) | (1) src/desktop/desktop.inc, the clashing names renamed; the desktop byte for byte the same; (2), (3) fixed | Budgets: vectors 0, BFCODE 1, the driver area 1 (DRIVER and DRVEXT 5 below KEXT), KLO 3, IOCODE 8, CODE 18; modules 61 (3), 22 (4), 27 (6), 49 (8), 43 (12), 10 (13), 2 (14); the desktop to $360F of $5FFF. Open: the desktop's progress line and recursive delete (D4); the dispatcher's room for new engine functions (2 more); the writer that damaged geoFolder on the test D81 (DESKTOP.md "Open bugs"); the mount dialog has no VICE test (no Ultimate files there) |
| 2026-11-06 (2) | Sixth sweep, after 13 feature commits since the fifth: drive E as a native image and `/e` (module 81, the engine's path, handles, root listing), the driver's ROM window guard and module 82, gush's keys, history recall and drive switch, the desktop D1-D4, `tools/sysreloc.py`'s DNP mode, `mkappsdnp.py`'s strict option. Scans: CPU port and interrupts in the new code, FE_OPEN/FE_OPENDIR with their FE_CLOSE, buffers against their longest input (the desktop's paths, names, clipboard; drives.s's slots), coupling commented at both ends (H_DRIVE's bit 7 for E; the desktop's REU banks 1-4 entries, 5 clipboard; ownDesk between mount.s, sysdrive.s and load.s), budgets | (1) The desktop's path join (srcPath, "/", a name) had no bound on a 256-byte buffer. (2) desktop.s kept constants of code that moved to list.s, and its header described D1 only. Found and fixed before, in their own commits: the driver's ROM window (the deskTop hang), the overlay slot as a string's home (EnterDeskTop's name), the matrix read without I/O (the desktop's clicks), `dir2Head` across E's header load | (1) bounded at 255 characters (an over-long path fails in the engine with an error shown); (2) removed, header rewritten | Budgets: the dispatcher (module 22) 4 bytes, KCODE 3, CODE 19, the driver area 11, INIT 43, module 81 97; gush's core to `$4A0C`, high area to `$7E72` (205 bytes); the desktop to `$18C9`. Open: the desktop's progress line and recursive delete (D4); the dispatcher's room for new engine functions (2 more) |
| 2026-11-06 | Fifth sweep, end of gush step 3: what changed since the fourth (gush step 3: variables, redirection, scripts, control flow, pipes, the history file, the VLIR overlays, completion, external commands, wget and ifconfig; `src/cmds` and wc; engine module 80 `FE_UCI`; `tools/vlircvt.py`; the gush tests). The kernal outside enginenet.s and the dispatcher's table is unchanged since the fourth and was not re-read. Scans: interrupts and the CPU port (php/sei/plp, `$01` saved and restored), every FE_OPEN/FE_OPENDIR with its FE_CLOSE on each path, buffers against their longest input (wget's host, name, request and status line; the module's 4 KB; completion's names; `.cvt` names), overlay data set before use (it survives while the overlay stays), no call from one overlay into another (`gtables.py`), budgets | (1) The `sta`/`bne` trap in the statement and stage scanners (3.5, fixed then). (2) A pipe read's limit compared the low byte only (3.5). (3) gush's test helper took the last of two labels of one name (a module's own `lineLen` over the editor's). (4) wget: the socket's close reported errors after a finished download; a status line shorter than 12 characters was read past its end. (5) Maintainability: the info-block, kind and open-mode constants and the transient area defined again in up to eight files. (6) GUSH.md's memory section described two overlays | (1)-(4) fixed (3.5, 3.7, 3.9); (5) one definition each in gush.inc; (6) rewritten | Budgets: gush's core to `$480E` (2 KB below the transient area), overlays 3.3, 2.4, 0.9 and 2.9 KB of 4 KB; zero page to `$9F` of `$DF`; HIGHBSS to `$7D72` of `$7F3F`; all eight application REU banks in use (bank 7: the overlays, 16 of 64 KB). Kernal: module 22 12 bytes (6 functions), module 80 162 of 496; the others as in the fourth sweep. Drive E is not reachable by path yet (`/e/bin` in PATH finds nothing): modules there need that engine step. `ping`/`host`: not possible with the Ultimate's network target |
| 2026-11-05 (2) | Fourth sweep, end of gush step 2: what changed since the third (engine E4: CVT, Ultimate streams, mount/umount/FE_MOUNTINFO, mkimg; FE_TURBO, FE_HOME, FE_SETTIME, FE_REBOOT, FE_NTP; the boot's turbo=N and NTP step; gush sys.s, sysset.s, the mouse; the U64 tests). Scans: carry kept in multi-byte loops (after FE_NTP's cpx find), self-modifying code in overlay modules (after FE_READ/FE_WRITE's), header comments; every Ultimate file opened in modules 56-79 checked for a close on each path; stack measured on the U64 (mount, write-back, mkimg, ntp, CVT: nothing below $0190, at least 144 bytes free); gush's buffers (imgPath, diskName, iniPath, the SETTINGS.INI text) bounded | (1) gush mkimg's type table read "6788" for "678n": dnp unknown. (2) turbo -s: the [system] match turned "[" into "{" (a second [system] added), and a file without a final line end got the new lines glued on. (3) Module 67 had its own copy of the home-folder code. (4) The dispatcher (module 22) had 8 bytes left, 2 per function, and an unused entry. (5) Five routines without a header comment | (1)-(5) fixed in their own commits, with U64 checks for (1) and (2) | A shared send-without-data helper (copied as Send/Exec in modules 45, 56-58, 67, 70, 71) does not fit feult.inc: module 61 has 3 bytes free. The dispatcher: 14 bytes, room for 7 functions; step 3 moves its table out when it needs more. Budgets: BFCODE 1, KCODE 3, DRVEXT 8, IOCODE 8, CODE 23, INIT 81; modules 61 (3), 15 (5), 27 (6), 49 (8), 43 (12), 10 (13), 22 (14), 2 (14), 37 (16), 57 (18), 66 (20), 75 (22); 80 modules. gush: 10.3 KB code, BSS to $4C1D |
| 2026-11-05 | Third sweep, end of gush step 1.6: what changed since the second (file engine E3 and L, `src/gush`, geoFolder's gush button, the U64 and gush test drivers); stack depth measured in VICE (`cp -r` five folders deep with a long name: 164 bytes of stack left below MainLoop's); segment budgets from `build/*.map` | (1) Rename on the Ultimate (module 43) built the RENAME command in `uCmd` first and checked its length after: two long names ran into `dirEntryBuf`. (2) gush's program start copied a word longer than a name into its path without a bound. (3) Dead symbols `FE_UNAME_MAX`, `KEY_BS`, `firstPath`. (4) `gu64.py` never removed the old gush from drive A's test image (c1541's `-delete` does not match GEOS's lower-case names) and fetched the image while a write-back was pending, so the U64 ran an old gush | (1) both names measured before the command is built (`Fits`); (2) a word longer than a name is not looked for on the drives' roots, the copy bounded by the check; (3) removed; (4) old copies deleted through GeoUltra, the test waits for `wbPending` 0 before it touches the image | Budgets tight: BFCODE 1 byte free, KCODE 3, DRVEXT 8, IOCODE 8, CODE 23; overlay modules 15 (5 free), 27 (6), 49 (8), 43 (12): new kernal work needs new modules, not growth of these |
| 2026-11-04 | Second sweep, the first with the maintainability criterion: everything changed since the first (folders and 1581 partitions, root merge, DNP resizing, write-back retry, overlay addressing, `tools/sysreloc.py`, `tools/mkappsdnp.py`) read in full; the rest of `src/` checked for duplicated constants and drive-type logic and for segment budgets | (1) RemoveDir on a 1581 freed any CBM partition at sector 0, also one that is no sub-directory or not formatted as one. (2) GetCurDir on a drive without folders returned X = the device number instead of 0. (3) SetGEOSDisk inside a 1581 partition searched for the border block from track 40, not from the partition. (4) `tracks=` in MOUNTS.INI wrapped above 255 and accepted 0-1. (5) Maintainability: the drive-type check written out in five places, the 1581 helpers (sizes, validity, BAM entry) in three copies, the drive flags in four files and `SLOW_BANK` in two; a comment naming the wrong module; two deliberately ignored errors without a comment; the folder file's header described native folders only. (6) Budgets: `CODE` 6 bytes free, `KCODE` 3, `IOCODE` 8, `KEXT` 1, `DRVEXT` 2, module 15 5, module 2 14. (7) `sysreloc.py` looped forever on a directory chain that loops | (1) RemoveDir checks as SetCurDir (whole tracks, track 40 outside, header "D" linked to t/3), new test case. (2) X = 0 with r1 = 0/0. (3) from the directory track. (4) bounded (2-255, else no resize). (5) `IsType`/`Is1581`/`Native` in `foldershared.inc`, `part81.inc` and `bam81.inc`, `drvflags.inc`; comments fixed. (6) The dialog box drawing and recovery moved into module 11: `CODE` 105 bytes free. (7) refused with a message | (6) the other resident segments stay nearly full: the file engine (phase 3) must cost almost no resident bytes (one dispatcher entry, not a stub per call), and moving more rarely used routines out of `KCODE`/`IOCODE` stays open. The rest of `src/` (unchanged since the first sweep) was not re-read line by line |
| 2026-10-30 | All of `src/kernal`, `src/drivers` (buffers, UCI open/close and error paths, interrupt state, overlay rules, stack use, segment budgets); `tools/` read for the same | (1) The write-back ignored SEEK/SAVE_REU errors and cleared the change map and flag anyway: a failed write (stick removed, file write-protected, stick full) lost the changes silently. (2) `UciData` copied any reply in full: into `SCRATCH` (one page before the mount table being built) a long reply (control `$50`'s log) could overwrite the table. (3) Menus with more than 15 items or 4 levels, more than 20 processes or sleepers overrun their tables, as in GEOS 2.0 (the application's responsibility there too). (4) Segment room: `CODE` 1 byte, `KCODE` 3, `IOCODE` 12, overlay module 15: 5. (5) Stack: an application start uses about 104 bytes (the gate's saved r0-r15 and the speed list) plus overlay frames. (6) `irq.s` imported `WbCheck` unused. Checked without findings: every UCI file opened in mount, write-back and hibernation is closed on every path; `sei` always with `plp` or a deliberate `cli`; nested overlay calls keep their values resident | (1) a failed write keeps map and flag and is tried again after 5 s (`RETRY_DELAY`); (2) `UciData` stops at `dataLimit`; (6) removed | (1) verified on the U64 the same day (see "Verified on hardware"). (3) clamps once there is room. (4) partly done the same day: module addresses computed instead of tables, 55 bytes of `CODE` freed and new modules free of resident cost; moving rarely used `CODE` routines into modules stays open. (5) watch with new stack users |

## For the user, at the computer

To do (updated 2026-11-13 evening), on the U64 with the cartridge from
`/SD/idi8b/geoultra/` (drive C is the apps DNP, 8 MB). The whole list
was gone through by hand on 2026-11-13 (see "Hand tests 2026-11-13"
below); left to redo after the fixes:

- Settings' lines kept in SETTINGS.INI (the INI bug, "Requests" below):
  then again: delete "at once" (7.4), copy "newer" with dated documents
  (7.3), the pointer kept after a reboot (10.4), the turbo step and
  hibernation kept, two panes kept after a program (7.5).
- The Time page after its fixes: the zone and summer time changing the
  clock at once, "now" with feedback and the date line redrawn, the
  hour lost after a reboot with a time set by hand (8.4).
- After the next build: the frame round the swatch rows, the readable
  error texts (a drop on a full drive), up to 10 themes, delete on the
  Theme page.
- New on 2026-11-14 (cartridge deployed; automatic tests passed in
  VICE and on the U64), to try by hand:
  - Settings drawn in the theme in use (title bar, side list mark,
    colours) with a few themes; "use" on the Theme page repaints it.
  - Theme page: delete a theme (asks first; the theme in use and the
    last one refused); a copy deleted before Save.
  - Sorting: the arrow at the path line's right end, Size and Date
    headings in the detailed view (click, again, a third time), the
    arrow among the letters with two panes; sort= in SETTINGS.INI.
  - Disk images on the Ultimate: a double click goes into one like a
    folder (a D64 and a D81; a small DNP), copy files in and out
    (check the image afterwards, e.g. by mounting it), delete or
    rename inside, ".." out; a mounted image ("It is mounted: open its
    drive."); a program inside ("Mount the disk image to open it.");
    with drive D in use too (no empty letter: "It needs an empty drive
    A-D."); a large DNP beside the 8 MB drive C ("Not enough free REU
    for it."). Mounting from the context menu and toolbar still works.
  - The menus' keys right-aligned (geos, file, view menus).
  - Two panes: a selection in one pane hidden when the other is
    active, back when it is active again.
  - The boot splash's full version line (matches GeoUltra info).
  - Icon colours by type: on the Theme page's "icons by type" part give
    a few types a colour (none, off), Save, use the theme: the icon view
    coloured by type; Settings' Desktop page "Icon colours: off" turns
    them off for every theme.
  - Settings' Drives page: choose an image for an empty drive in the
    browser, long names off and on, none (unmount), a new image, a
    DNP's resize; the REU page's grid with your drives.

Done 2026-11-11: the right mouse button on the U64 ("Verified on
hardware").

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

Hand tests 2026-11-13 (the user at the U64, one at a time): the right
button, the menus and keys, the toolbar's buttons, sorting, the icon
view, the look and two panes pass. Found and fixed the same day: geos >
gush and settings did nothing (RunSys's name lost in r0), the delete
question named another file (now the entry or "N entries"), a drag never
started at turbo speed (the wait counted in rounds, now by the clock;
an unselected entry can be dragged at once), the desktop ignored the
folder chosen in geoFolder with two panes, the Settings boxes not in
columns, the theme dialogs over coloured cells, geoWrite 2.1 and geoPaint
patched for MegaPatch 3 hung at Open (DBGETFILES with MegaPatch's flag
bits, now taken as the plain list), the root merge searching again
inside itself, geoFolder falling off full geos menus (drive E's desk
accessories now first, with a place kept for them). New in Open
dialogs: a double click opens (a folder entered, a file opened).

Later the same day (the user, tests 2-12 of the list): drag and drop
(all six steps), its extras (a drop on drive B said "error $03": the
1541 image had 27 blocks free, correct but to be worded), Settings'
start, Desktop page, Cancel, the palette, the theme editor ("Mine"),
sorting, copy "skip", the System page (turbo, slow list, hibernation),
the pointer designs, two panes kept after a reboot, CVT to usb0 and
back pass. Fixed the same day: geoFolder, programs and documents not
starting with two panes (PanesKeep changed r6, r2, r3), Settings'
dialogs over coloured cells, the palette after Cancel (the desktop puts
the Ultimate's own back when its theme has none). Dropped by the user:
the choice of GEOS 2.0's deskTop and the Classic style. Failed: see the
list above (the INI bug, the Time page).

Hand tests 2026-11-14 (the user, build 060f600): a disk image dropped
on drive C refused ("Disk images stay on the Ultimate"), the places'
list under a pane's path text, the U button's roots, the frame round the
Theme page's swatch rows and Copy with a full list: all pass. The
earlier retests of 2026-11-13 evening (Settings' lines kept, the Time
page, MegaPatch's drive letters, the pane letters) pass as well.

Requests from the same session, to do:
- Done 2026-11-13: the GeoUltra info box: the version as
  vMAJOR.MINOR.PATCH-YYYYMMDD-HHMM (as UBoot64-v2; the numbers in the
  Makefile, the kernal's info block holds them, $C0E2 and $C0F5-$C0FA),
  no credits (the user: they belong in the README), "splash" shows
  drive E's splash file; tests/desktop/d16.py.
- Done 2026-11-13: gush's close button, an "x" at the right end of its
  status line (tests/gush/g22.py).
- Changed 2026-11-13 after the user's test (kernal module 87,
  drvlist.s; tests/drives/filedialog.py, mpdialog.py): the letters only
  in boxes that ask for MegaPatch 3's drive button (DBSETDRVICON, bit 6),
  and a click ends the dialog with MegaPatch's answer $88-$8B (the
  drive's number with bit 7; its -_G3_NewDlgBox read as behaviour
  reference): the application switches its own document drive. GEOS
  2.0's applications keep a document drive of their own and set it
  again after the box (geoWrite 2.1's openDocument), so a switch made
  inside the box was lost (error 1:05 opening a file from A). Originally
  (superseded): File boxes (DBGETFILES), decided by the user 2026-11-13: drive letters
  A B C D in every file box (not only for MegaPatch's DBSETDRVICON flag),
  four small buttons in the bottom strip left of the scroll arrows, only
  drives with an image, the current one inverted; a click switches the
  drive and builds the list anew (as entering a folder); the
  application gets the chosen name back on the current drive, as under
  MegaPatch. A new kernal overlay module (the resident areas are full).
  Built after the info box and gush's close button.
- Done 2026-11-14 (desktop.s Shortcuts: a GOTOX in each item, its x
  set at Start from the key's measured width; the desktop's own menus
  only, the user's choice): The menus: keyboard shortcuts right-aligned
  (by measured width).
- Done 2026-11-14 (docs/DESKTOP.md; the user chose the headings on the
  path line, a third click back to names; tests/desktop/d18.py):
  Sorting (the user, 2026-11-13): a reverse order (folders still first;
  sort= gets a "-" form, e.g. sort=-date), a small icon at the right of
  the path line that turns it round, and in the detailed view a click
  on a column's heading (name, size, date) sorts by it (a second click
  reverses).
- Done 2026-11-13: Settings' [desktop] lines lost (delete=, copy=,
  panes= ...; "delete at once" still asked). Cause: the desktop kept
  [desktop] as a list of four lines of its own (LIST_MAX), read no more
  and wrote only those four back at its next save. Now it reads and
  writes its keys with the shared ini.inc (inifile.s DeskText, KeyVal,
  SetLine: the file read anew, one key changed, written back); ini.inc's
  variables can live in the includer's overlay (INI_OV4). Measured on
  the U64 before and after (tests/desktop/d16u64.py). The empty
  [system] in the user's file: most likely the defaults chosen again in
  Settings (a default takes its key out); the pointer after a reboot
  (10.4) to retest (a plain reboot resumes the hibernated session,
  which may predate the change).
- Done 2026-11-14 (tests/desktop/d21.py, VICE): copy=newer with dated
  GEOS documents: tested only with plain files (no date) so far; a test
  with two dated documents (an older one left out, a newer one
  replacing).
- Disk images on the Ultimate's file system (decided by the user
  2026-11-13): (1) going into an image (D64, D71, D81, DNP) like a
  folder: the file engine loads it into free REU and serves it through
  a borrowed drive slot, as drive E (path /usb0/x/disk.d81/...), changes
  written back to the image when it is left; not for a mounted image;
  a large DNP only when the REU has room. (2) A double click on an image
  goes into it; mounting stays in the context menu, the toolbar and the
  mount dialog (until (1) exists a double click keeps mounting). (3)
  Disk image files (.d64 .d71 .d81 .dnp .g64) are not copied or moved
  onto GEOS drives A-D ("Disk images stay on the Ultimate's file
  system"); between Ultimate folders they may (not while mounted).
  Order: (3) now; (1) and (2) after the video's items. (1) and (2)
  done 2026-11-14 (engineimg.s, modules 88-90; open.s; FILE_ENGINE.md
  "Paths"; U64 tests tests/engine/imgu64.py, tests/desktop/d19u64.py). (3) done
  2026-11-13: tree.s ImageToGeos, before every single-file copy or move
  (paste, drag and drop, copy and move to the other pane), the message
  "Disk images stay on the Ultimate" (errors.s, ERR_IMAGE $60). The
  desktop core is full after it (0 bytes): room first for the next.
- Done 2026-11-14 (src/settings/chrome.s; VICE test-settings, the
  U64 with GeoUltra, Night, Flat and Mono: stripes, line and solid
  title bars, invert, bar and frame selections; the Theme page's
  overlay 1.1 KB free after the parser moved to the core):
  GeoUltra Settings in the desktop's theme (the user, 2026-11-13): its
  colours from the theme in use (desk, menu bar, frame lines, the side
  list's selection), and more chrome: frame lines round the whole
  window and between its parts, and a title bar with a stripe pattern
  (as GEOS windows have) carrying "GeoUltra Settings". The Theme page's
  "use" then repaints Settings itself in the theme at once (the user's
  test 2026-11-13: "use" changing nothing on the screen felt wrong).
- Done 2026-11-13 (the letters, U and the places' list under the path
  text; listin.s MenuRun, tests/desktop/d17.py): Two panes, a drive per pane (decided by the user 2026-11-13; the
  Ultimate's roots by a "U" button after E, the user the same day: a
  list under it of the roots that are there, sd, usb0, usb1, usb2): drive
  letters A B C D E at the right end of each pane's path line (only
  drives with an image; the pane's own drive inverted), a click
  switches that pane's drive; a click on the path text opens a list
  under it with what the sidebar holds (drives, the Ultimate's roots,
  favourites). The path text loses that room (cut from the left
  sooner). The desktop core has little room: list and letters in an
  overlay.
- Two panes: the inactive pane's selection hidden (kept, shown again
  when it is active; done 2026-11-14: list.s IsSelected answers none
  while panes.s draws the inactive pane, tests/desktop/d20.py); the new-folder report (left pane read, both path
  lines inverted) not reproduced in VICE yet: which way it was made.
- Done 2026-11-13: the Time page's NTP server from a list
  (time.google.com, time.windows.com, pool.ntp.org, as UBoot-v2) or
  custom (tests/settings/s3b.py).
- Done 2026-11-13 (the Time page, the user's test): a zone step shifts
  GEOS's clock by 15 minutes at once, summer time switched on or off by
  an hour when the date is in the EU's summer time (over midnight into
  the next day or the one before; the user chose the shift over asking
  the server); "now" stays inverted while it asks, the date line drawn
  again after, a failure said. The hour lost after a reboot
  (measured on the U64, 2026-11-13): the Ultimate's SET_TIME stores an
  hour less than given (firmware 3.15a, zones Western Europe and UK),
  while its GET_TIME gives the clock as the firmware's SNTP keeps it, in
  local time. Decided by the user: GeoUltra no longer writes the
  Ultimate's clock (FE_SETTIME, NTP, gush's date set only GEOS's and the
  CIA's) and takes its time as local time at a cold start. A time
  changed in GeoUltra (set..., zone, summer time) persists as `[time]
  adjust=` (minutes from the Ultimate's clock), added by the desktop
  after every cold start; "now" (a server) takes it out (the user's
  choice; tests s3b.py, s3cu64.py).
- Done 2026-11-13: up to 10 themes (the desktop's menu and Settings;
  the user), Copy with a full list says "Room for 10 themes. Delete one
  first." Done 2026-11-14: delete on the Theme page (a "delete" button
  left of the preview: asked first, "Delete the theme <name>? Its file
  goes at once."; the theme in use stays, "This theme is in use. Use
  another one first."; the last one stays; the one before shown after);
  room from the parser's move to the core, no second overlay needed
  (overlay 5: 831 bytes free). Test tests/settings/s46u64.py (its own
  Ztest theme; the user's files only read).
- Done 2026-11-13: the desktop's error dialog in words for the common
  errors (not enough room, directory full, cannot be written to, a file
  of that name, folder not empty, not found), the number for the rest.
- Done 2026-11-13: `make deploy` uploads only the cartridge; the apps
  DNP (drive C in the test folder) goes up with `make deploy-apps`.
- Closing an application on a large image (the 8 MB apps DNP) takes
  seconds: the whole image is written back. A message while it runs
  ("Writing drive C back"), and only the changed tracks: the Command
  Interface seeks in an open file (`DOS_CMD_FILE_SEEK`) and saves an REU
  range into it (`DOS_CMD_SAVE_REU` with address and length); to test
  on the U64: an open for writing that does not truncate the image.
- Done 2026-11-14: tests/gush/gu64.py edited a mounted image outside
  GeoUltra (FTP and c1541), which damaged geoFolder on the test D81 (the
  REU copy written back over it): gush and geoFolder now go onto drive A
  through FE_COPY (their CVTs in a scratch folder); the test also sets
  aside the user's HIBERNAT.BIN and gush_history (its reboot resumed
  or used them) and puts them back, boots build/geoultra64.crt by
  default, and takes the expected mount list and MOUNTS.INI line from
  the file itself (it had A and B only); 52 of 52 pass on the U64.

## Still open

- The GEOS 2.0 deskTop's geos menu does not list drive E's desk
  accessories (geoFolder): the deskTop collects them while reading drive
  A's directory itself, not through `FindFTypes`, where the kernal adds
  E's (applications such as geoWrite list them). GeoUltra's own desktop
  will; until then geoFolder is reached from an application's geos menu
  (user's hand test 2026-11-06).

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
