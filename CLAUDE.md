# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GeoUltra: a GEOS-compatible system for the C64 and C128 with an Ultimate
(U2+, U2+L, U64, C64 Ultimate) that does storage, RAM and system work
through the Ultimate Command Interface (UCI) and the REU, and aims to run
existing GEOS applications. Spun off from the GeoUTools Oscar64 rebuild on
2026-10-28. **In development**: all GEOS 2.0 jump table entries exist;
GEOS 2.0's deskTop, geoWrite and geoPaint run in VICE, the deskTop on the
U64 from boot-mounted images.

Read [`docs/DESIGN.md`](docs/DESIGN.md) first: it holds the decisions
(cartridges, REU map, drives, DNP, phases) and what is still to verify or
open. [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) is the background
analysis; its route and phase recommendations are superseded.

## Decisions already taken (by the user)

- Name GeoUltra; separate repository; compatibility with existing GEOS
  applications is the aim (the GEOS 2.0 interface, checked against GEOS
  2.0). Documentation never promises full or 100% compatibility: the GEOS
  ecosystem has many versions, add-ons and developments, some lost in time.
  Likewise no promise of hardware compatibility with all peripherals:
  best effort, list what was tested.
- Full transparency about the use of AI: README "Use of AI", the
  `Co-Authored-By` line in every commit, and a mention in release notes,
  Facebook posts and blog texts. Standing rule for every update: keep the
  README section current with what the AI does in the project.
- Kernal, drivers and the core OS applications (desktop, gush the shell,
  file manager, settings, mount dialogue, geoFolder) in assembler
  (ca65/ld65), the shared file engine as a kernal extension (overlay
  modules, extension jump table); C (Oscar64 with the geos-oscar64
  library, see below) only for other tools and tests (user, 2026-11-04:
  speed and above all size, and no C runtime or compiler quirks).
- Free-standing clean-room kernal from the start (no patch release); the
  user's GEOS 2.0 is only the test oracle.
- Boot from cartridge: C64 Megabyter (type 86, at most 1 MiB, runs in VICE
  3.10 and on the Ultimate), C128 Ultimate C128 cartridge (type 1 sub 2).
- Ultimate 64 family first; a C64 with an Ultimate II+ next, the C128 last.
- 16 MB REU required; DA swap, tasks, spooler and clipboard in the REU;
  whole-image REU drives with automatic write-back.
- Inspired by GDOS64, MegaPatch3 and TopDesk, but no copying: those sources
  (area6510) are "all rights reserved", the reassembled kernal (mist64/geos)
  is Berkeley's code. Reading them for behaviour questions is allowed; never
  copy code, tables or structure, and credit the source in a comment where
  behaviour was derived from it.
- C64 and C128 versions; Ultimate firmware 3.15 features (REU, palette,
  turbo, native file system, network/HTTP).

## Compatibility contract (constrains all code)

Existing applications see only the GEOS 2.0 surface, so it must stay byte
for byte where GEOS 2.0 put it (details in FEASIBILITY.md, "Compatibility
contract"):

- Jump table `$C100`-`$C31x` with the same registers in/out and "Destroys"
  behaviour as HG2G chapter 20, info bytes `$C000`-`$C02F`, GEOS 128 additions.
- Variables `$8000`-`$88FF`, disk driver jump area at `$9000`, input driver
  at `$FE80` (`$FD00` on the 128), printer drivers at `$7900`.
- Zero page: r0-r15 `$02`-`$21`, kernal variables up to `$48`, a0-a9
  untouched, `$80`-`$FA` free for applications (geos-oscar64 relies on it).
- Every drive must look like a track/sector block device (`GetBlock`/
  `PutBlock`, BAM, VLIR), whatever the Ultimate stores underneath.
- Turbo must not change jiffy-based timing (process timers, double-click).
- Clean-room: no Berkeley assets either (BSW font, standard icons, deskTop).

## Build and test

`make` builds `build/geoultra64.crt` (boot ROM, kernal, 1351 driver;
docs/ARCHITECTURE.md), `make vice` / `make vice-shot` run it in VICE 3.10.
`make conformance` (1541) and `make conformance81` (1581 images) compare
kernal routines with GEOS 2.0 in VICE
(tests/conformance/*.py, tools/harness/): every newly implemented jump
table routine gets cases there, written from HG2G, and must pass before
it counts as done. The GEOS 2.0 oracle disk is the user's own
(`GEOS_ORACLE`), never committed.

`tools/harness/apprun.py NAME [events]` runs a GEOS application from an
applications disk (drive B, `GEOS_APPS_DISK`, the user's own) on GeoUltra
in VICE and renders the screen (docs/ARCHITECTURE.md, "Conformance
harness").

Only the hardware smoke tests exist so far (`tests/smoke/`, results in
DESIGN.md "Verified on hardware"): `make smoke` builds the Megabyter test
cartridge (ca65/ld65, packed by `tools/mkcrt.py`) and an Oscar64 UCI test,
`make smoke-vice` runs the cartridge in VICE 3.10, `make smoke-u64` runs
both on the U64 from `.env` (`ULTIP1`), `make smoke-u64-restore` switches
the REU and Command Interface off again. Oscar64 test code that hands
buffers to REU DMA must use `volatile` buffers and `__noinline` REU
wrappers (docs/OSCAR64_MANUAL.md), or stores get dropped.

Planned:

From FEASIBILITY.md, "Build chain" and "Testing": `make` builds the kernal,
drivers, desktop and cartridge images with ca65/ld65 (one linker config per
machine) and C tools with Oscar64; `make test` runs VICE checks; `make e2e`
drives the U64 through c64bridge/REST; `make deploy` uploads by FTP.
VICE has no UCI emulation, so every UCI code path needs the hardware loop;
the REU RAM-drive layer and the kernal can be tested in VICE (with a VICE REU).

## References

- `docs/GEOS_REFERENCE.md` (curated) and `docs/GEOS_API_REFERENCE.md`
  (per routine): copies of `~/.claude/geos_reference.md` and
  `~/.claude/geos_api_reference.md` (global CLAUDE.md, "GEOS Projects").
- HG2G2022 PDF: https://github.com/geos64128/HG2G2022 (text: `mutool draw -F txt`).
- mist64/geos (kernal, drivers, `inc/*.inc`), MegaPatch3/GDOS64 sources
  (https://bitbucket.org/mkgit64/area6510; geoWrite files on D81, extract
  with `~/.claude/tools/geos/geosextract.py`).
- pagetable.com (Michael Steil), via `https://www.pagetable.com/search.json`
  (all article texts): GEOS copy protection traps (149), Inside geoWrite
  1-9 (overlays, screen recovery, fonts, zero page, copy protection,
  localization, file format, copy & paste, keyboard; 240 is part 5), the
  reverse-engineered GEOS 2.0 and geoWrite 2.1 sources (mist64 GitHub),
  why GEOS boot disks break (parts 1-2), the GEOS 2.0 master images,
  TopDesk and its source, the Klaus Finke collection, geowrite2rtf,
  Final Cartridge III with GEOS, the Ultimate C64 KERNAL API, Commodore
  peripheral bus series.
- UCI: `~/git/ultimate-uci-oscar64/docs/UCILIB_MANUAL.md` (firmware 3.15
  commands incl. `DOS_CMD_LOAD_REU`/`SAVE_REU` with address and length, GEOS
  RAM disk commands, unlock sequence for a disabled Command Interface).
- geos-oscar64 (`~/git/geos-oscar64`): Oscar64 runtime and full C API for
  GEOS 64/128, tested in VICE and on the U64; usable for the desktop and
  tools. Its `docs/GEOSLIB_MANUAL.md` explains the zero page sharing.

## Test environment (from the GeoUTools work)

- VICE 3.10 in `~/.local/opt/vice-3.10/bin` (`x64sc`, `x128`; built from
  `~/vice-3.10`, needed for the Megabyter cartridge) for interactive use,
  and a headless build (no window, no sound) in
  `~/.local/opt/vice-3.10-headless/bin` (from `~/vice-3.10-headless`,
  `--enable-headlessui`) for every unattended run: the harness, `vice-shot`,
  `smoke-vice`. The user does not want VICE windows and sound popping up
  during automated runs. VICE 3.8 stays in `/usr/local/bin`: unattended GEOS boots with an AUTO_EXEC test program and `-limitcycles N -exitscreenshot` (`-exitscreenshotvicii` for
  the 40-column screen in x128, `-40col`/`-80col`).
- Ultimate 64-II at 192.168.1.148 (firmware 3.15a) through the c64bridge
  MCP server; screenshots with GeoUTools' `tests/e2e/shot.py` (VIC stream).
  GEOS 2.0 boots from 1541 images only with the stock drive ROM (the
  configured JiffyDOS ROM with Extra RAM fails); D81 images are faster.
  Mouse automation: write `mouseXPos`/`mouseYPos` ($3A-$3C), inject a press
  with `mouseData` ($8505) = 0 and `pressFlag` ($39) |= $20; joystick-port
  fire taps work for icons and lists but not reliably for menus.
- GEOS boot disks (user's own, never commit or redistribute):
  `~/geos-dev/u64-usb/` (GEOS 64/128 2.0, Wheels, MP3, GDOS64, RAM boot
  sets), `~/geos-dev/finke/` (Klaus Finke collection).

## Code-quality sweeps (user, 2026-10-30)

A full review of the code at fixed moments: at the end of each phase
step (DESIGN.md "Phases"), before each release, and at the latest after
about ten feature commits since the previous sweep. Not a diff review:
all of `src/` and `tools/`. Checklist for this code:
- **Overflows:** fixed buffers and their longest input (`cmdBuf`, paths,
  names, `TEXT`, dialog and list buffers), copies bounded by length,
  stack room taken and given back, stack depth in nested overlay calls.
- **Leaks:** UCI files and directories left open on error paths, REU
  banks allocated and not freed, overlay modules or stack frames not
  unwound, interrupt state (`sei`/`cli`, `php`/`plp`), the CPU port (`$01`),
  VIC/CIA/sprite state, turbo speed not restored.
- **Errors:** every UCI status and every `X` error checked or deliberately
  ignored (with a comment); no path that continues with stale data.
- **Contract:** registers, zero page and "Destroys" as HG2G; overlay
  rules (overlay.s); segment budgets (`build/*.map`) and how close each
  is to full.
- **Clarity:** dead code, comments that no longer match the code,
  duplicated logic that drifted.
- **Maintainability (user, 2026-11-04):** can someone new change this
  safely? Routines short and with one job, each with a header comment
  (input, output, what it destroys); named constants instead of magic
  numbers; no hidden coupling (shared variables, register or flag
  assumptions across modules and overlay boundaries) without a comment
  at both ends; overlay modules split by function, not by whatever
  fitted; shared code in includes rather than copies; tests that cover
  the routine so a change can be checked.
Findings are fixed in their own commits; the sweep is logged in
docs/DESIGN.md "Code sweeps" (date, scope, findings, what was fixed,
what stays open). Last sweep: 2026-10-30; next at the end of the
current phase step, or after about ten feature commits.

## Conventions

The user's global conventions apply (`~/.claude/CLAUDE.md`): docs in
`docs/` with upper-case names, Makefile conventions
(`~/.claude/makefile_conventions.md`: `.env` for IPs, `build/`,
`check-deploy`, pandoc PDFs), release and Facebook-post styles, code
attribution comments. Commit only when asked.
