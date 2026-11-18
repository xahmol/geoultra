# GeoUltra

A GEOS-compatible system for the **Commodore 64 and 128 with an Ultimate**
(Ultimate II+, Ultimate II+L, Ultimate 64, Commodore 64 Ultimate) that does
its storage, RAM and system work through the Ultimate: disk images as REU
RAM drives loaded and saved through the Ultimate Command Interface, RAM
boot, the Ultimate's file system in the desktop, network time, and on the
Ultimate 64 family turbo speed and the palette.

GeoUltra aims to run existing GEOS applications: it keeps the GEOS 2.0
jump table, variables and zero page contract, and every kernal routine is
checked against GEOS 2.0's behaviour. It does not promise that every GEOS
application runs: the GEOS world has many versions, add-ons and later
developments, some of them lost, and applications that rely on
undocumented internals may not work. The same holds for hardware:
peripherals are supported on a best-effort basis, and the documentation
lists what was tested.

**Status: in development.** The kernal implements all GEOS 2.0 jump table
entries; GEOS 2.0's deskTop, geoWrite and geoPaint run on it in VICE, and
the deskTop runs on an Ultimate 64 from disk images mounted at boot.
GeoUltra starts in its own desktop (in development: a list of the
drives' and the Ultimate's files, open, copy, delete, rename, new
folders, favourites, mounting and unmounting disk images, going into
disk images on the Ultimate like folders, themes as
editable files, on the Ultimate 64 with their own colour palettes). The
decisions are in [`docs/DESIGN.md`](docs/DESIGN.md), the structure in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Documents

| File | Contents |
| --- | --- |
| [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) | Feasibility analysis: Ultimate features, compatibility contract, routes, architecture, storage design, C64/C128, build chain, testing, phases, risks |
| [`docs/GEOS_REFERENCE.md`](docs/GEOS_REFERENCE.md) | GEOS technical reference (memory and zero page maps, kernal, file formats, GEOS 128, MegaPatch3/GDOS64/Wheels differences) |
| [`docs/GEOS_API_REFERENCE.md`](docs/GEOS_API_REFERENCE.md) | Per-routine kernal API (from The Hitchhiker's Guide to GEOS v2022) |
| [`docs/DESKTOP.md`](docs/DESKTOP.md) | GeoUltra's own desktop: design, plan, state of the work |
| [`docs/DESKTOP_MANUAL.md`](docs/DESKTOP_MANUAL.md) | Using the desktop: screen, views, files and folders, toolbar, disk images, drives (what works where), themes, settings |
| [`docs/SETTINGS.md`](docs/SETTINGS.md) | GeoUltra Settings, the settings application: decisions, structure, steps |
| [`docs/GUSH.md`](docs/GUSH.md) | gush, the GeoUltra shell: design, commands, state of the work |
| [`docs/GUSH_MANUAL.md`](docs/GUSH_MANUAL.md) | Using gush: keys, paths, command lines, control flow, scripts, commands |
| [`docs/GUSH_COMMANDS.md`](docs/GUSH_COMMANDS.md) | Writing external gush commands: format, calling convention, the routines gush offers, building |
| [`docs/GWTOOL_MANUAL.md`](docs/GWTOOL_MANUAL.md) | gwtool, a PC tool for geoWrite documents in disk images: list, convert geoWrite 1.x to 2.x, join several documents into one, to and from Word and Markdown |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Rules for pull requests: clean-room, coding practices, tests, descriptions, use of AI |

## Related projects

- [GeoUTools](https://github.com/xahmol/GeoUTools): GEOS tools for the
  Ultimate (mounter, NTP time, settings), being rebuilt with Oscar64.
- geos-oscar64: C library and runtime for GEOS applications with Oscar64
  (not yet published).
- [ultimate-uci-oscar64](https://github.com/xahmol/ultimate-uci-oscar64):
  Ultimate Command Interface library for Oscar64.

Code taken over from elsewhere (credited in the source as well): the NTP
exchange and date arithmetic of GeoUltra's `ntp` (src/kernal/enginentp.s)
come from GeoUTools' GeoUTime, which took the exchange from
[ntp2ultimate](https://github.com/MaxPlap/ntp2ultimate) by MaxPlap.

## Serial numbers and copy protection

GEOS applications from Berkeley Softworks key themselves to the serial
number of the GEOS boot disk they were installed under. GeoUltra answers
with the serial of your own GEOS boot disk when one is mounted, so
applications installed under your GEOS run.

GeoUltra has optional measures that go further: answering each
application with the serial it stored, and letting an application from a
D64 image of its original disk install itself on GeoUltra (both
available), and, planned, re-keying an application to your serial. These bypass Berkeley's copy protection. They are **off by
default** and must be switched on in `GEOULTRA/SETTINGS.INI`:

    [system]
    protection=bypass

They live in one separate module, `src/kernal/bypass.s`;
`make BYPASS=0` builds GeoUltra without it.

**Disclaimer.** These measures are intended only for using GEOS and GEOS
applications for which you own a licensed copy, for example on an
Ultimate after your original disks have worn out. They are not meant to
run copies you have no licence for. GEOS and its applications are still
under copyright, whatever their age, and the publication of
reverse-engineered source code does not grant a licence. Whether using
these measures is allowed depends on the law where you live; you use them
at your own responsibility. GeoUltra contains no Berkeley code and ships
no GEOS software.

## Licence

GNU GPL v3. GEOS is a trademark of its owners; GeoUltra contains no
Berkeley Softworks code.

### Fonts

GeoUltra's own GEOS fonts ("GU Serif", "GU Sans", ...; `make fonts`,
`tools/mkgufonts.py`) are drawn from two free sources, kept in
`tools/fonts/src` with their licences:

- the TeX Gyre fonts by Bogusław Jackowski and Janusz M. Nowacki (GUST
  e-foundry), under the GUST Font Licence (`tools/fonts/src/texgyre/`,
  `GUST-FONT-LICENSE.txt` and the README of each family). GeoUltra's
  fonts are changed versions (rendered as GEOS bitmap fonts, hand fixes)
  and carry their own names;
- the X Window System's 75-dpi bitmap fonts by Adobe Systems and Digital
  Equipment Corporation (`tools/fonts/src/adobe75/`, their copyright and
  permission notice in `COPYRIGHT.txt`), whose shapes are used at 10-14
  points.

Times, Helvetica, Palatino, New Century Schoolbook, ITC Avant Garde, ITC
Bookman and ITC Zapf Chancery are trademarks of their owners; GeoUltra's
fonts follow their metrics but are not those fonts.

## Use of AI

GeoUltra is developed with AI. Xander Mol takes the decisions (what
GeoUltra is, its design choices, priorities), tests on real hardware and
reviews; most of the code, tools, tests and documentation are written by
Claude (Anthropic) through Claude Code, at his direction. Every commit
written with AI says so in a `Co-Authored-By: Claude` line.

How the AI's work is checked: every kernal routine is compared with
GEOS 2.0's behaviour in VICE by the conformance harness
(`make conformance`, `make conformance81`), and hardware facts are
measured on an Ultimate 64 (docs/DESIGN.md, "Verified on hardware"). On
the Ultimate the AI also runs the tests itself through its network
interface (deploying builds, changing settings, reading memory, taking
screenshots), while Xander does the physical steps (power cycles, keys)
and judges what is on the screen. gush, the shell, has its own suites:
`make test-gush` in VICE and `tests/gush/gu64.py` on the Ultimate 64.
The desktop likewise: `make test-desktop` in VICE and
`tests/desktop/du64.py` and `d6u64.py` on the Ultimate 64.
Some steps are done unattended: on Xander's instruction the AI works
through steps he decided on, testing, committing and pushing each one,
and he reviews the result afterwards (the commits and docs/GUSH.md say
what was done and tested).
Tests reduce the risk of mistakes; they do not exclude them.

Clean-room: the AI reads GEOS reference sources (the reassembled GEOS 2.0
kernal, MegaPatch3 and GDOS64 sources) for behaviour questions only and
does not copy their code, tables or structure; code whose behaviour was
taken from such a source names it in a comment.

