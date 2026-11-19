# Contributing to GeoUltra

Thank you for wanting to help. GeoUltra is a clean-room GEOS-compatible
system for the C64 and C128 with an Ultimate, maintained by Xander Mol.
These rules keep it compatible, legally clean and testable. Please read
them before opening a pull request (PR).

## 1. Before you start

- **Open an issue first** for anything larger than a small fix: a new
  feature, a change of behaviour, a new file format or a change in the
  memory layout. Agree on the approach before writing the code; design
  decisions are taken by the maintainer and recorded in
  [`DESIGN.md`](docs/design/DESIGN.md).
- Read [`DESIGN.md`](docs/design/DESIGN.md) (decisions, what is verified on
  hardware, what is open) and [`ARCHITECTURE.md`](docs/reference/ARCHITECTURE.md) (how
  the kernal, drivers, overlays and REU are laid out).
- One topic per PR. Do not mix a fix with unrelated clean-ups or
  reformatting.

## 2. Clean-room rules (strict)

GeoUltra contains no code of Berkeley Softworks' GEOS, nor of its later
versions and add-ons. A PR that breaks these rules cannot be merged.

- **Never copy** code, tables, data structures or comments from:
  Berkeley's GEOS (also the reassembled sources, e.g. mist64/geos),
  MegaPatch3 and GDOS64 (area6510, "all rights reserved"), Wheels,
  TopDesk, or any other non-free GEOS software.
- You may **read** those sources to answer behaviour questions ("what
  does GEOS 2.0 return in X when ..."). Write your own code from the
  behaviour, and **credit the source** in a comment where behaviour was
  derived from it (file and what was taken).
- No Berkeley assets: no BSW font, standard icons, deskTop graphics or
  texts.
- **Never commit** disk images, ROMs or applications you do not have the
  right to distribute, including your own GEOS disks: tests take them
  from the contributor's own copies through environment variables
  (`GEOS_ORACLE`, `GEOS_APPS_DISK`, ...).
- Code adapted from free sources (with a compatible licence) carries a
  credit comment naming the author, where it can be found, and what was
  changed.
- Serial numbers and copy protection: wording is always about reusing
  **licensed copies**; the protection bypass stays an isolated, opt-in
  module (README, "Serial numbers and copy protection").

## 3. The compatibility contract

Existing GEOS applications only see the GEOS 2.0 interface, so it must
stay where GEOS 2.0 put it: the jump table (`$C100`-), the info block,
the variables `$8000`-`$88FF`, the driver areas, the zero page use
(`$80`-`$FA` free for applications), registers in and out and what each
routine destroys (HG2G chapter 20). See `CLAUDE.md` and
[`FEASIBILITY.md`](docs/design/FEASIBILITY.md), "Compatibility contract". Any change
that touches it needs a conformance case (section 5) and a note in the
PR.

## 4. Coding practices

- **Languages:** kernal, drivers, boot code and the core OS applications
  (desktop, gush, file manager, settings, mount dialogue, geoFolder) in
  6502 assembler for ca65/ld65, the shared file engine as a kernal
  extension; other tools and tests may be C with Oscar64 and the
  geos-oscar64 library; host tools in Python 3 (standard library where
  possible).
- **Match the surrounding code:** naming, comment density, layout,
  idioms. Each routine starts with a comment block saying what it does,
  its inputs, outputs and what it destroys (the HG2G style).
- **Named constants**, no unexplained magic addresses; hardware
  registers from `src/inc/hw.inc`, GEOS names from `src/inc/geos.inc`.
- **Memory is tight.** Say in the PR how segment sizes changed (`make`
  prints them in the `build/*.map` files). Rarely used code belongs in
  an overlay module; respect the overlay rules in `overlay.s` (no
  vectors into the slot, values that must survive a nested overlay call
  live outside the module, no overlay calls from interrupts).
- **Banking:** know which memory configuration code runs in (code under
  I/O, `$01` = `$30` in GEOS); never leave I/O, the C64 ROMs or
  interrupts in another state than you found them.
- **No silent behaviour changes:** a deliberate difference from GEOS 2.0
  is documented in `ARCHITECTURE.md` with the reason.
- **Documentation goes with the code:** update `ARCHITECTURE.md`,
  `DESIGN.md` ("Verified on hardware", "Still open") and the README in
  the same PR. Manuals live in `docs/` with upper-case names.

## 5. Tests: what must pass

Every PR states which of these were run and their results:

1. `make` (and `make BYPASS=1`) builds without errors or warnings.
2. `make conformance` (1541) and `make conformance81` (1581): all cases
   pass. These compare GeoUltra with GEOS 2.0 in VICE and need your own
   GEOS 2.0 disk (`GEOS_ORACLE`). One known flake: a GetString case
   occasionally fails on GEOS 2.0's side (`geos ee00`); rerun that file
   (`tools/dev/harness/harness.py tests/conformance/getstring.py`).
3. **A new or changed kernal routine** gets conformance cases written
   from HG2G, which pass before the routine counts as done.
4. The drive and feature tests for the area you touched:
   `test-native`, `test-d71`, `test-folders`, `test-filedialog`,
   `test-sysfont`, `test-bypass`; and an application run with
   `tools/dev/harness/apprun.py` where an application is affected.
5. **Hardware:** VICE has no Ultimate Command Interface, so code that
   uses the UCI, the REU's size, turbo or the Ultimate's file system is
   tested on a real Ultimate. Write down the device, firmware version
   and what you did and saw (DESIGN.md "Verified on hardware" is the
   model). Write tests only on copies of disk images, never on
   originals. If you changed `src/cfg/geoultra64.cfg`, run
   `make checkcfg`.

Never weaken or delete a test to make a PR pass; if a test is wrong,
fix it in its own commit and explain why.

## 6. Commits and pull requests

- Branch from `main`; keep the branch up to date by rebasing.
- **Commit messages:** a short summary line (what), then a body that
  says why, what was found, and how it was checked. One logical change
  per commit.
- **PR description**, with these headings:
  - *What and why* (link the issue)
  - *How it was tested* (commands and results, hardware with device
    and firmware, screenshots for anything visible)
  - *Compatibility* (does it touch the GEOS 2.0 interface? segment
    size changes?)
  - *Documentation* (which documents were updated)
  - *Use of AI* (section 7)
- Keep PRs small enough to review; split large work into steps.

## 7. Use of AI

AI assistants are welcome; GeoUltra itself is largely written with
Claude (README, "Use of AI"). The same openness applies to
contributions:

- **Disclose it.** Say in the PR which parts were written with which AI
  tool. Commits written with AI carry a `Co-Authored-By:` trailer naming
  the assistant.
- **You are responsible** for every line you submit: understand it, test
  it as in section 5, and be able to explain it in the review. "The AI
  wrote it" is not a reason to accept code.
- **The clean-room rules apply to the AI too.** Do not paste non-free
  GEOS sources into an assistant to have them rewritten; behaviour
  questions only, as in section 2.
- No invented facts: claims about GEOS behaviour, hardware or firmware
  must come from a test, a measurement or a named source.

## 8. Wording in documentation and releases

- Never promise full or 100% compatibility, with GEOS applications or
  with hardware: GEOS has many versions and add-ons. Say what was
  tested; everything else is best effort.
- Releases, posts and blog texts mention the use of AI.

## 9. Licence

GeoUltra is licensed under the GNU GPL version 3 ([`LICENSE`](LICENSE)).
By submitting a PR you agree that your contribution is published under
the same licence.

**Sign-off is required for contributions** (the Developer Certificate of
Origin, https://developercertificate.org): every commit in a PR carries a
`Signed-off-by: Your Name <email>` line, which `git commit -s` adds. With
it you confirm that you wrote the contribution, or took it from a source
whose licence allows it (and credited it), and that you may submit it
under the GPL. For GeoUltra this matters doubly: it is the contributor's
statement that the code is clean-room, and a person takes responsibility
for it whatever tool wrote it. A forgotten sign-off is added with
`git commit --amend -s` (or `git rebase --signoff main` for several
commits). The maintainer's own commits do not need it.

## 10. Reporting bugs

Open an issue with: the machine (C64 or C128) and Ultimate model with
its firmware version, the GeoUltra build (commit or release), the
applications and disk images involved (names only, never the images),
the steps to reproduce, what you expected and what happened, and a
screenshot where useful.
