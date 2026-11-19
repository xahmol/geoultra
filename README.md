# GeoUltra

A GEOS-compatible system for the **Commodore 64 with an Ultimate** that
does its storage, RAM and system work through the Ultimate: disk images
as REU RAM drives loaded and saved through the Ultimate Command
Interface, the Ultimate's file system in the desktop, network time,
printing to the Ultimate's printer emulation and to PDF, and on the
Ultimate 64 family turbo speed and the palette. Versions for the
Ultimate II+ on a C64 and for the C128 are planned.

GeoUltra aims to run existing GEOS applications: it keeps the GEOS 2.0
jump table, variables and zero page contract, and every kernal routine is
checked against GEOS 2.0's behaviour. It does not promise that every GEOS
application runs: the GEOS world has many versions, add-ons and later
developments, some of them lost, and applications that rely on
undocumented internals may not work. The same holds for hardware:
peripherals are supported on a best-effort basis, and the documentation
lists what was tested.

**Status: heading for Beta 1** (Ultimate 64 family). What is there:

- a clean-room kernal with all GEOS 2.0 jump table entries, booted from a
  cartridge file on the Ultimate; GEOS 2.0's deskTop, geoWrite 2.1 and
  geoPaint 2.0 run on it;
- its own **desktop**: a file manager for the GEOS drives and the
  Ultimate's file system, two panes, drag and drop, icons, themes,
  mounting disk images, going into images like folders;
- **tasks** (several programs at once, switched with C= + RUN/STOP),
  **hibernation** across a power cycle, one **clipboard** for all drives;
- **printing** through a queue in the REU: its own Epson FX-80 and
  Commodore MPS drivers, PDF files, and **GU PostScript**, which writes
  geoWrite documents as PostScript;
- its own **fonts** (ten GU families), system fonts for every disk;
- **GeoUltra Settings**, **gush** (a shell with scripts and network
  commands), serial numbers per application;
- **PC tools** for disk images, geoWrite documents (Word, Markdown,
  PostScript) and geoPaint pictures.

## Documents

For users:

| File | Contents |
| --- | --- |
| [`docs/GEOULTRA_MANUAL.md`](docs/GEOULTRA_MANUAL.md) | **The user manual**: installing and starting, the desktop, drives and disk images, programs and tasks, Settings, themes, printing, fonts, serial numbers, gush, the files on the stick, limits, what was tested |
| [`docs/TOOLS_MANUAL.md`](docs/TOOLS_MANUAL.md) | **The PC tools**: geosdisk (disk images), gwtool (geoWrite documents: convert, merge, Word, Markdown, PostScript), gptool (geoPaint pictures), mkappsdnp (an applications image), mkgeosfont (GEOS fonts) |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Rules for pull requests and what a bug report needs |

`make docs` makes PDFs of them (pandoc and XeLaTeX).

Design and internals:

| File | Contents |
| --- | --- |
| [`docs/DESIGN.md`](docs/DESIGN.md) | The decisions, the phases, what was verified in VICE and on hardware, the code sweeps |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | How it is built: cartridge, boot, kernal, overlays, REU map, drivers, tests |
| [`docs/FILE_ENGINE.md`](docs/FILE_ENGINE.md) | The file engine, the kernal extension the desktop, gush and Settings use |
| [`docs/DESKTOP.md`](docs/DESKTOP.md) | The desktop: design, plan, state of the work |
| [`docs/SETTINGS.md`](docs/SETTINGS.md) | GeoUltra Settings: decisions, structure, steps |
| [`docs/GUSH.md`](docs/GUSH.md) | gush, the shell: design, state of the work |
| [`docs/GUSH_COMMANDS.md`](docs/GUSH_COMMANDS.md) | Writing external gush commands |
| [`docs/PSW.md`](docs/PSW.md) | GU PostScript: how it works, tests |
| [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) | The original feasibility analysis (its route and phases superseded by DESIGN.md) |
| [`docs/GEOS_REFERENCE.md`](docs/GEOS_REFERENCE.md), [`docs/GEOS_API_REFERENCE.md`](docs/GEOS_API_REFERENCE.md) | GEOS technical reference and per-routine API (from The Hitchhiker's Guide to GEOS v2022) |

## Building from source

Needs cc65 (`ca65`, `ld65`), Python 3.11 or later with Pillow, and for
the tests VICE 3.10 (for the Megabyter cartridge) and Oscar64.

    make                 # build/geoultra64.crt and build/geoultra64.cfg
    make vice            # run it in VICE 3.10
    make conformance     # kernal routines against GEOS 2.0 (your own GEOS 2.0 disk: GEOS_ORACLE)
    make docs            # the PDFs of the README and the manuals
    make deploy          # upload to the Ultimate (ULTIP1 in .env)

The conformance tests and the application tests use your own GEOS disk
images (environment variables `GEOS_ORACLE`, `GEOS_APPS_DISK`); they are
never part of the repository.

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
applications installed under your GEOS run; Settings' Serials page sets
another number, or one per application, and the desktop offers to set
it when an application refuses.

GeoUltra has optional measures that go further: answering each
application with the serial it stored, and letting an application from a
D64 image of its original disk install itself. These bypass Berkeley's
copy protection. They are **off by default** and are switched on on
Settings' Serials page (or `[system] protection=bypass` in
`GEOULTRA/SETTINGS.INI`). They live in one separate module,
`src/kernal/bypass.s`; `make BYPASS=0` builds GeoUltra without it.

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
The manuals (docs/GEOULTRA_MANUAL.md, docs/TOOLS_MANUAL.md) are written
by the AI from the code, its tests and Xander's design decisions, and
checked against the code where it states a fact (keys, settings, file
names); Xander reviews them.
Tests reduce the risk of mistakes; they do not exclude them.

Clean-room: the AI reads GEOS reference sources (the reassembled GEOS 2.0
kernal, MegaPatch3 and GDOS64 sources) for behaviour questions only and
does not copy their code, tables or structure; code whose behaviour was
taken from such a source names it in a comment.

