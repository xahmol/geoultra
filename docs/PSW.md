# GU PostScript

GU PostScript turns a geoWrite 2.x document into a PostScript file on
the Ultimate, in `GEOULTRA/print/<document>.ps`. The pages are laid out
as geoWrite lays them out, so lines and pages break where they break in
geoWrite. `ps2pdf` on a PC makes a PDF of it, and any PostScript printer
prints it. Decisions and plan: docs/DESIGN.md, "PostScript writer".

**State (2026-11-19): step P1 of six.** It writes documents in the
system fonts (BSW, BSW128) with bold, underline, reverse and outline,
tab stops, all alignments and line spacings, pictures, header and
footer, on A4. Documents with other fonts are written in the system
font for now (step P2: their own bitmaps; P3: the LW and GU fonts as
real text).

## Use

Start GU PostScript (drive E, once installed there) and choose a
geoWrite document in its file box; or start it with a document (the
desktop's "make PostScript" and a gush command follow in step P6). When
it is done it says where the file is.

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
`FE_OPEN`, `FE_WRITE`, `FE_CLOSE`).

Memory: the application at `$0400`, the page record at `$2C00` (7 KB),
header and footer, the font image, the output buffer and the line's
characters up to `$5FFF`, a picture record in the background screen's
place (`$6000-$7F3F`; the application draws on the foreground only).

## Tests

- `tests/print/psc64.py`: GU PostScript in VICE on GeoUTools' manual (11
  pages, pictures), the file engine's Ultimate calls answered by the
  test; its file must be the same as `gwtool ps`'s, byte for byte.
- `tests/print/psref.py`: `gwtool ps` against geoWrite's own printout,
  dot for dot (docs/GWTOOL_MANUAL.md, "PostScript").
