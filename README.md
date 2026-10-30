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
the deskTop runs on an Ultimate 64 from disk images mounted at boot. The
decisions are in [`docs/DESIGN.md`](docs/DESIGN.md), the structure in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Documents

| File | Contents |
| --- | --- |
| [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) | Feasibility analysis: Ultimate features, compatibility contract, routes, architecture, storage design, C64/C128, build chain, testing, phases, risks |
| [`docs/GEOS_REFERENCE.md`](docs/GEOS_REFERENCE.md) | GEOS technical reference (memory and zero page maps, kernal, file formats, GEOS 128, MegaPatch3/GDOS64/Wheels differences) |
| [`docs/GEOS_API_REFERENCE.md`](docs/GEOS_API_REFERENCE.md) | Per-routine kernal API (from The Hitchhiker's Guide to GEOS v2022) |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Rules for pull requests: clean-room, coding practices, tests, descriptions, use of AI |

## Related projects

- [GeoUTools](https://github.com/xahmol/GeoUTools): GEOS tools for the
  Ultimate (mounter, NTP time, settings), being rebuilt with Oscar64.
- geos-oscar64: C library and runtime for GEOS applications with Oscar64
  (not yet published).
- [ultimate-uci-oscar64](https://github.com/xahmol/ultimate-uci-oscar64):
  Ultimate Command Interface library for Oscar64.

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
and judges what is on the screen.
Tests reduce the risk of mistakes; they do not exclude them.

Clean-room: the AI reads GEOS reference sources (the reassembled GEOS 2.0
kernal, MegaPatch3 and GDOS64 sources) for behaviour questions only and
does not copy their code, tables or structure; code whose behaviour was
taken from such a source names it in a comment.

