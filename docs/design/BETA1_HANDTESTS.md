# Beta 1: hand tests on the Ultimate 64

> **Design record.** The checklist for the hand tests before Beta 1
> (DESIGN.md, "Beta 1": "a hand-test checklist for the user"). Results
> are written in DESIGN.md, "Verified on hardware".

Written 2026-11-19 for the user's test day. Everything the automated
suites cannot do: things that need the real Ultimate, real clicks in
applications, or a human eye. Use only copies of disk images
(`/USB0/GEOULTRA/test`); keep a note of each failure with what was on
the screen (a photo is fine).

Before you start: `make deploy` (or `make` and copy
`build/geoultra64.crt` to `/SD/idi8b/geoultra/`), the Cartridge setting
on it, REU 16 MB, Command Interface on. Copy
`build/samples/geoultra-samples.d81` to the test folder.

## 1. First start, as a new user (about 20 min)

Follow the quick start guide (`build/samples/quickstart.pdf`) word for
word, as someone who has never seen GeoUltra. Mark every place where
the guide and the screen disagree.

- [ ] Cold start from the cartridge: splash, then the desktop
- [ ] Mount disk images on A-D from the Ultimate browser (the mount
      icon on image lines, and the context menu's "mount")
- [ ] Start a program from a folder; back to the desktop
- [ ] Switch between programs (task list)
- [ ] Settings: change the theme, Save; it is kept after a reboot
- [ ] Switch off as the guide says; images written back (a changed file
      is there after the next start)

## 2. Untested on hardware so far (about 30 min)

- [ ] **Refusal notice (serials S5):** start a geoWrite that is keyed
      to another GEOS disk ("Please reboot your system using the same
      GEOS disk ..."). After OK the desktop asks "Set it in Settings?";
      Yes opens Settings on the Serials page with the class filled in;
      enter the number (or "from disk"), Save; geoWrite then starts.
- [ ] **Serials "from disk"** with your GEOS 2.0 boot disk image on a
      drive: it finds the drive and the number.
- [ ] **Context menu "mount"** on a disk image in the Ultimate browser
      (U64 only; never tried on hardware).
- [ ] **Resume of a task** that asked for the task list (taskReq $20):
      switch away from geoWrite and back, the document as it was.
- [ ] **Hibernation:** save the session, power cycle, resume: programs,
      drives and the open document come back.
- [ ] **Recent entries** of an unmounted image: "Not mounted. Mount
      it?" then it opens.
- [ ] **geoLaser pickup** (changed in the sweep of 2026-11-20):
      `python3 tests/print/pickupu64.py` (automated, on the U64; tell
      Claude when the U64 is free), or by hand: a `PS.<name>` SEQ file
      from geoLaser on drive A or B is moved to `GEOULTRA/print/<name>.ps`
      at the next desktop start, with a note.
- [ ] **Open a document** whose program is on another drive: the
      newest version starts and finds the document (drive B swapped
      with the document's drive while it runs, back afterwards).

## 3. Applications and documents (about 30 min)

- [ ] The samples D81: open **Brochure**, **Quick start** and **Letter**
      in geoWrite 2.1: pages break as in the PDFs, pictures and fonts
      right, nothing garbled; scroll through all pages.
      (Not yet checked in geoWrite at all: VICE stopped at geoWrite's
      copy check.)
- [ ] **GeoUltra logo** in geoPaint.
- [ ] **Clipboard:** copy text in one geoWrite document, paste it in
      another; copy in geoPaint, paste in geoWrite (the harness cannot
      click geoWrite's paste item).
- [ ] Desktop clipboard menu: show, save as file, clear.
- [ ] Two panes: drag a file from one drive to another, and into a
      folder; drag onto the trash.

## 4. Printing (about 30 min, the Ultimate's printer emulation on)

- [ ] GU Epson FX-80: print the brochure; the PNG in
      `GEOULTRA/print/epson` correct; the queue's percentage moves.
- [ ] GU Commodore MPS: one page.
- [ ] GU PDF A4 and Letter: the brochure; open the PDF on the PC.
- [ ] GU PostScript (context menu "make PostScript"): the brochure;
      `ps2pdf` on the PC; compare with `build/samples/brochure.pdf`.
- [ ] Cancel a job while it prints; pause and resume the queue.
- [ ] **Open issue to watch:** after an aborted geoWrite print the
      queue was once paused with "printer error" ($50). Abort a print
      in geoWrite and see whether the queue recovers.

## 5. Fonts (about 10 min)

- [ ] Context menu on a font file: "install as system font"; it shows
      in geoWrite's font menu (at once or after the restart, as the
      manual says); "uninstall" in the installed fonts folder.
- [ ] Settings, Printing page: "disk fonts: hide" hides the fonts of
      the disks, "show" brings them back.

## 6. gush and the network (about 10 min)

- [ ] `ls -l`, `cd`, `cp` (a file between drives), `df`, `free`,
      `mount`, `date`
- [ ] `ifconfig`, `ntp` (the clock set), `wget` of a small file over
      HTTP

## 7. Reading (in your own time)

- [ ] `docs/manuals/GEOULTRA_MANUAL.pdf`: read it once through; mark
      what is unclear, wrong or missing.
- [ ] `docs/manuals/TOOLS_MANUAL.pdf`: try one example of each tool on
      a PC (geosdisk list, gwtool docx, gptool export).
- [ ] README: the "Use of AI" section still says what the AI does.

## 8. Decisions for the release

- [ ] The pre-flight check (repository public): read the report and
      say go or no-go (the visibility is changed only after that).
- [ ] What goes into the release archive. Proposal: the cartridge
      (`geoultra64.crt`), `SETTINGS.INI` example, the two manual PDFs,
      the README PDF, the samples D81 and PDFs; not the design record.
- [ ] Release notes, Facebook post and blog text (with the AI
      mention), the video (already online as the sneak peek, or a new
      one).
