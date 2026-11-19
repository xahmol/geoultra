# GU PostScript

GU PostScript turns a geoWrite 2.x document into a PostScript file on
the Ultimate, in `GEOULTRA/print/<document>.ps`. The pages are laid out
as geoWrite lays them out, so lines and pages break where they break in
geoWrite. `ps2pdf` on a PC makes a PDF of it, and any PostScript printer
prints it. Decisions and plan: docs/DESIGN.md, "PostScript writer".

**State (2026-11-19): all six steps.** It writes documents in any
bitmap font (the system fonts, GeoUltra's GU fonts, the user's fonts:
found as geoWrite finds them) with bold, underline, reverse and
outline, tab stops, all alignments and line spacings, pictures, header
and footer, on A4. The LW and GU fonts (IDs 27-37) become the
printer's own fonts as real text: Times, Helvetica, Courier, Avant
Garde, Bookman, Helvetica Narrow, New Century Schoolbook, Palatino,
Zapf Chancery, Symbol, Zapf Dingbats (`realtext.s`). It is on drive E
and starts from the desktop and from gush with a document. On the U64
(2026-11-19) GeoUTools' manual (11 pages, pictures) takes about a
minute and its file is gwtool ps's byte for byte.

## Use

In the desktop, the context menu of a geoWrite document has **make
PostScript** (its second item). In gush: `"/e/GU PostScript"
"/b/letter"` (the document's path). Or start GU PostScript on its own
(drive E) and choose a geoWrite document in its file box. A
short box then asks for the paper (**A4** or **Letter**) and the look:
**Real** (the LW and GU fonts as the printer's own fonts: sharp at any
size, the text searchable in a PDF) or **C64** (every font from its
bitmaps, exactly as on the C64's printer). The line above the buttons
says what is chosen; **OK** writes the file, **Cancel** leaves. The box
starts with Settings' choice (Printing page: "Paper", "PS look"; in
`SETTINGS.INI` `[print] paper=letter` and `pslook=c64`; A4 and real text
without them). When it is done it says where the file is.

## How it works

The application (`src/psw`, assembler, about 7 KB) reads the document
twice through GEOS's VLIR calls (`OpenRecordFile`, `ReadRecord`):

1. **First pass** (`emit.s` Prescan): the header, footer and every page
   record: the number of pages, the page width (640 dots when a ruler
   reaches past 480 in a V2.1 document, else 480), and which characters
   each font and style uses.
2. **Prolog**: the PostScript procedures and one Type 3 font per font
   and style, made from the font's bitmap glyphs as GeoUltra's kernal
   draws them (`font.s`).
3. **Pages**: each page record laid out line by line as geoWrite
   measures lines (`layout.s`: margins, tab and decimal stops, the break
   after the last space, line height and leading, alignment and
   justification), written as runs of text; pictures decompacted as
   image masks (`picture.s`).

The text it writes is exactly what `gwtool ps` (tools/gwps.py) writes
for the same document: the PC tool is the reference. The output goes
through GeoUltra's file engine (`out.s`: `FE_HOME`, `FE_MKDIR`,
`FE_OPEN`, `FE_WRITE`, `FE_CLOSE`). The engine uses GEOS's buffers
`$8100-$84FF` as scratch, and `fileHeader` holds the open document's
record index, so `out.s` keeps those 1 KB around every engine call
(at `$7B40`; found on the U64, where the second page could not be read
after the first write).

Fonts (`font.s`): each font ID the document uses gets a slot (up to 16:
its widths, height, baseline and file name), found with FindFTypes and
the font ID in each FONT file's header. Only one record file can be
open at a time, so the document is closed after the first pass while
the fonts are looked for and their images read for the Type 3 glyphs,
and opened again for the pages.

Memory: the application at `$0400`, the page record at `$2D00` (7 KB),
header and footer, the fonts' widths and names, the output buffer, the
line's characters and the variables up to `$5FFF`; a font image while the prolog is
written, then a picture record, in the background screen's place
(`$6000-$7F3F`; the application draws on the foreground only).

## Tests

- `tests/print/psc64.py`: GU PostScript in VICE on GeoUTools' manual (11
  pages, pictures), the file engine's Ultimate calls answered by the
  test; its file must be the same as `gwtool ps`'s, byte for byte.
  `--doc=features`: psref.py's test document (GU fonts at 10-24
  points, header and footer, alignments, spacings, decimal tabs)
  against `gwtool ps`, with real text. `--letter`, `--c64` click those
  in the options box (gwtool ps `--letter`, `--bitmap`).
- `tests/print/psent.py`: started with a document from gush and from the
  desktop's context menu (the engine's `FE_RUNDOC`: an application on
  drive E with a document), each file the same as `gwtool ps`'s.
- `tests/print/psu64.py`: on the U64, the desktop's "make PostScript"
  on the manual, the file read back over FTP and compared with `gwtool
  ps`'s; the user's files put back.
- `tests/print/psref.py`: `gwtool ps` against geoWrite's own printout,
  dot for dot (docs/TOOLS_MANUAL.md, "PostScript").
