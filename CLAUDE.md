# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GeoUltra: a GEOS-compatible system for the C64 and C128 with an Ultimate
(U2+, U2+L, U64, C64 Ultimate) that does storage, RAM and system work
through the Ultimate Command Interface (UCI) and the REU, and stays
compatible with existing GEOS applications. Spun off from the GeoUTools
Oscar64 rebuild on 2026-10-28. **Planning stage: no code yet.**

Read [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) first: it holds the
decisions so far and the open questions.

## Decisions already taken (by the user)

- Name GeoUltra; separate repository; full compatibility with existing GEOS
  applications is a hard requirement.
- Kernal and drivers in assembler; desktop and tools may be C (Oscar64 with
  the geos-oscar64 library, see below).
- Inspired by GDOS64, MegaPatch3 and TopDesk, but no copying: those sources
  (area6510) are "all rights reserved", the reassembled kernal (mist64/geos)
  is Berkeley's code. Use them only as references for behaviour.
- C64 and C128 versions; Ultimate firmware 3.15 features (REU, palette,
  turbo, native file system, network/HTTP).

Recommended in the analysis, still to be confirmed with the user: hybrid
route (start as a patch on the user's GEOS 2.0, replace kernal parts with
clean-room code later), REU image RAM drives with UCI load/save, ca65/ld65
as assembler and linker, phase plan 1-4 with gates. Open questions are at
the end of FEASIBILITY.md: ask them before designing phase 1.

## References

- `docs/GEOS_REFERENCE.md` (curated) and `docs/GEOS_API_REFERENCE.md`
  (per routine): copies of `~/.claude/geos_reference.md` and
  `~/.claude/geos_api_reference.md` (global CLAUDE.md, "GEOS Projects").
- HG2G2022 PDF: https://github.com/geos64128/HG2G2022 (text: `mutool draw -F txt`).
- mist64/geos (kernal, drivers, `inc/*.inc`), MegaPatch3/GDOS64 sources
  (https://bitbucket.org/mkgit64/area6510; geoWrite files on D81, extract
  with `~/.claude/tools/geos/geosextract.py`).
- UCI: `~/git/ultimate-uci-oscar64/docs/UCILIB_MANUAL.md` (firmware 3.15
  commands incl. `DOS_CMD_LOAD_REU`/`SAVE_REU` with address and length, GEOS
  RAM disk commands, unlock sequence for a disabled Command Interface).
- geos-oscar64 (`~/git/geos-oscar64`): Oscar64 runtime and full C API for
  GEOS 64/128, tested in VICE and on the U64; usable for the desktop and
  tools. Its `docs/GEOSLIB_MANUAL.md` explains the zero page sharing.

## Test environment (from the GeoUTools work)

- VICE 3.8 (`x64sc`, `x128`): unattended GEOS boots with an AUTO_EXEC test
  program and `-limitcycles N -exitscreenshot` (`-exitscreenshotvicii` for
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

## Conventions

The user's global conventions apply (`~/.claude/CLAUDE.md`): docs in
`docs/` with upper-case names, Makefile conventions
(`~/.claude/makefile_conventions.md`: `.env` for IPs, `build/`,
`check-deploy`, pandoc PDFs), release and Facebook-post styles, code
attribution comments. Commit only when asked.
