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
undocumented internals may not work.

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

## Related projects

- [GeoUTools](https://github.com/xahmol/GeoUTools): GEOS tools for the
  Ultimate (mounter, NTP time, settings), being rebuilt with Oscar64.
- geos-oscar64: C library and runtime for GEOS applications with Oscar64
  (not yet published).
- [ultimate-uci-oscar64](https://github.com/xahmol/ultimate-uci-oscar64):
  Ultimate Command Interface library for Oscar64.

## Licence

GNU GPL v3. GEOS is a trademark of its owners; GeoUltra contains no
Berkeley Softworks code.
