---
title: GeoUltra PC tools
subtitle: "Version 0.9 (Beta 1): geosdisk, gwtool, gwgen, gptool, mkappsdnp, mkgeosfont"
---

# About these tools

GeoUltra comes with a few programs for a PC (Windows, macOS, Linux) that
help with GEOS files outside the C64: making and filling disk images,
exchanging geoWrite documents with Word, Markdown and PostScript,
turning geoPaint pictures into PNG and back, building an applications
image, and making GEOS fonts. They are in the repository's `tools/`
folder (with the modules they use, `localcfg.py`, `mkfont.py` and
`fonts/`); the scripts of GeoUltra's own build and tests are in
`tools/dev/`.

**What you need:** Python 3.11 or later. **Pillow** (`pip install
pillow`) for pictures (gptool, pictures in gwtool, mkgeosfont).
gwtool and gptool write a new D64 or D81 with VICE's **c1541** (from the
PATH, or the folder `VICE_BIN` in `.env`); geosdisk needs no other
programs. **ghostscript** (`ps2pdf`) turns PostScript into PDF.

Run them from the repository's folder:

    python3 tools/geosdisk.py list apps.d81

Common to all of them:

- **Disk images**: D64, D71, D81 and DNP (CMD native, with folders: a
  name may carry its folder, `Writing/Letter`).
- **CVT**: GEOS Convert's format, one file holding a whole GEOS file.
  The Ultimate keeps GEOS files in this form, and GeoUltra converts
  them when you copy them to a drive.
- **Names** are as in the image's directory: case matters. Put names
  with spaces in quotes.

# geosdisk: GEOS disk images

    tools/geosdisk.py new IMAGE [--name=NAME] [--id=XY] [--tracks=N]
    tools/geosdisk.py list IMAGE
    tools/geosdisk.py add IMAGE SOURCE [SOURCE ...] [--folder=PATH] [--replace] [--seq]
    tools/geosdisk.py extract IMAGE [NAME ...] [--out=DIR]
    tools/geosdisk.py delete IMAGE NAME [NAME ...]
    tools/geosdisk.py rename IMAGE OLD NEW
    tools/geosdisk.py mkdir IMAGE PATH
    tools/geosdisk.py build RECIPE.toml
    tools/geosdisk.py pack ARCHIVE.lnx SOURCE [SOURCE ...]

- **new** makes an empty GEOS disk image of the type its name ends in
  (`.d64`, `.d71`, `.d81`, `.dnp`; a DNP has `--tracks=N` tracks of 64
  KB, 2-255, 8 by default). It is a GEOS disk at once: GEOS and
  GeoUltra need not convert it first.
- **list** shows every file with its GEOS type, structure, class, date
  and size.
- **add** puts files onto an image: a CVT file; a file from another
  image (`other.d81:Name`, `apps.dnp:Writing/geoWrite`); every file of
  a Lynx archive (`.lnx`, or one file of it, `x.lnx:NAME`); or a plain
  file (as a PRG, `--seq` as a SEQ), named after the file.
  `--folder=PATH` puts them into a folder of a DNP; `--replace`
  replaces a file of the same name.
- **extract** writes GEOS files as CVT files and plain ones as `.prg` or
  `.seq` (all files when no name is given) into `--out=DIR` (the
  current folder by default).
- **delete**, **rename**, **mkdir** (a folder on a DNP).
- **build** makes a whole DNP from a recipe (the format of mkappsdnp,
  below).
- **pack** writes files into a Lynx archive (GEOS files as CVTs inside
  it), as GEOS archives on the internet are often kept.

Images may also be read from a **G64** (a GCR disk image: read as its
D64) and from inside **.gz** and **.zip** files (`x.zip:inner.d64`).

Examples:

    tools/geosdisk.py new FONTS.DNP --tracks=8 --name="System fonts"
    tools/geosdisk.py add FONTS.DNP "fonts/English/Roma.cvt" "fonts/English/Mykonos.cvt"
    tools/geosdisk.py add work.d81 "GeoCalc.d64:GEOCALC" geowrite.cvt
    tools/geosdisk.py extract archive.zip:apps.d64 --out=apps

The first two make GeoUltra's system font image (docs/manuals/GEOULTRA_MANUAL.md,
"System fonts"): copy `FONTS.DNP` into `GEOULTRA` on the stick.

# gwtool: geoWrite documents

`tools/gwtool.py` reads geoWrite documents from a disk image on a PC and
writes geoWrite 2.x documents: it converts geoWrite 1.x documents, joins
several documents into one, and exchanges documents with Word and
Markdown both ways. Python 3; writing a D64 or D81 uses VICE's `c1541`;
pictures from Word or Markdown need Pillow.

## Commands

    tools/gwtool.py list IMAGE
    tools/gwtool.py convert IMAGE OUT [NAME ...] [--fonts]
    tools/gwtool.py merge IMAGE OUT NEWNAME NAME [NAME ...] [--fonts] [--start=N]
    tools/gwtool.py docx IMAGE OUT.docx NAME [NAME ...] [--page-breaks=records] [--start=N]
    tools/gwtool.py fromdocx IN.docx OUT NAME [--wide]
    tools/gwtool.py md IMAGE OUT.md NAME [NAME ...] [--page-breaks=records]
    tools/gwtool.py frommd IN.md OUT NAME [--wide] [--font=NAME]
    tools/gwtool.py ps IMAGE OUT.ps NAME [NAME ...] [--letter] [--fonts=DIR] [--bitmap]

- **IMAGE**: a D64, D71, D81 or DNP. On a DNP a name may include its
  folder: `Writing/Letter`.
- **OUT**: a new `.d64` or `.d81` image (made with `c1541`, from the PATH
  or `~/.local/opt/vice-3.10/bin`), or else a folder that gets one CVT
  file per document (for GEOS converters, or `c1541 -geoswrite`).
- **list** shows each geoWrite document: its version (1.x or 2.x), its
  pages and pictures.
- **convert** turns the named documents (all of them when no name is
  given) into geoWrite 2.x documents; 2.x documents are copied as they
  are.
- **merge** joins the named documents, in the order given, into one 2.x
  document called NEWNAME: their pages one after another, their pictures
  renumbered. Each document starts on a new page.
- **--fonts** also copies the font files the documents use (found by
  font ID on IMAGE), so geoWrite shows them as they were.
- **--start=N** (merge) sets the first page number geoWrite prints.

Example: the twenty parts of a school paper into one document, the table
of contents first, page numbers from 3:

    tools/gwtool.py merge "g03 geowrite.d64" bigbrother.d64 "Big Brother" \
        "Big Brother Inh." "Big Brother 0" "Big Brother 1" ... "Big Brother 18" \
        --fonts --start=3

## Word (docx)

`docx` writes one document (or several, joined first as by `merge`) as
a Word document; 1.x documents are converted on the way. No packages
are needed (tools/gwdocx.py writes the .docx itself). What is carried
over:

- **Text and paragraphs:** line breaks become paragraphs, TAB a tab,
  geoWrite's page breaks Word page breaks. `--page-breaks=records` also
  starts each geoWrite page on a new Word page (for documents whose
  parts each began on a new page, as a joined one).
- **Rulers:** left and right margin, the first line's indent, tab stops
  (decimal ones too), alignment (left, centred, right, justified), line
  spacing (1, 1.5, 2).
- **Fonts and styles:** each GEOS font as a Windows font that looks
  alike (University: Century Gothic, California: Arial, Roma: Times New
  Roman, Cory and Commodore: Courier New, Dwinelle: Old English Text MT;
  others by their GEOS name), the size at 0.9 times the GEOS size in
  points (GEOS sizes are dots of 1/80 inch); bold, italic, underline,
  outline, superscript, subscript, reverse (white on black).
- **Page:** A4, the text area 6 or 8 inches wide as in geoWrite, centred;
  `--start=N` the first page number.
- **Header, footer, pictures:** as Word header and footer; pictures as
  PNG images at 80 dpi (not yet tried on a document with pictures).

Restrictions: Word lays the text out again with its own fonts, so lines
and pages break elsewhere; characters outside ASCII that a GEOS font
draws in place of others come out as the ASCII character.

## From Word (fromdocx)

`fromdocx` makes a new geoWrite 2.1 document NAME from a Word document
(tools/docxgw.py). Word's styles are followed (document defaults, the
paragraph and character styles, the theme's fonts, numbering):

- **Fonts:** each Word font becomes one of GeoUltra's own font families
  on drive E (Times, Cambria, Georgia: GU Serif; Courier, Consolas: GU
  Mono; Arial, Calibri and most others: GU Sans; ...), at the nearest
  size it has (9 to 24 dots, 1.11 times Word's points); bold, italic,
  underline, outline, superscript and subscript.
- **Paragraphs:** margins, first line, up to 8 tab stops (left and
  decimal), alignment, line spacing 1, 1.5 or 2; space after a paragraph
  as an empty line; list items with "- " or their number; a table row as
  one line with its cells at tab stops; page breaks.
- **Pictures:** dithered to black and white at 80 dpi, at most the text
  width. **Header and footer:** their text.
- **Text:** ASCII; accented letters lose their accents, typographic
  quotes and dashes become plain ones, anything else "?" (counted in a
  warning).
- `--wide`: 8 inches of text instead of 6.

geoWrite keeps one page per record and lays pages out again itself:
open the new document once and choose file > update.

Example:

    tools/gwtool.py fromdocx letter.docx letter.d64 "Letter"

## Markdown (md, frommd)

`md` writes a document (several: joined first, as `merge`) as Markdown
(tools/gwmd.py); `frommd` makes a new geoWrite 2.1 document from a
Markdown text (tools/mdgw.py), laid out as `fromdocx` does.

From geoWrite to Markdown:

- **Headings:** a paragraph wholly in a size larger than the body text
  (the size most of the text has) is a heading: the largest size `#`,
  the next `##`, and so on.
- **Styles:** bold `**`, italic `*`, underline `<u>`, superscript and
  subscript `<sup>` `<sub>`; text in a fixed-width font (GU Mono,
  Commodore, Cory) as `code`, whole paragraphs of it as a code block.
- **Lists and tables:** paragraphs starting with "- " or "1. " stay list
  items; two or more lines in a row with the same number of tabs become
  a table, the first line its header.
- **Pictures:** PNG files at 80 dpi in a folder next to the Markdown
  file (`OUT_files/picture1.png`), linked with `![...]`.
- **Page breaks:** `<!-- pagebreak -->` (invisible when the Markdown is
  shown); `--page-breaks=records` adds one at every geoWrite page.
- **Header and footer:** as comments at the start and the end.
- Fonts, sizes (other than headings), alignment, margins and tab
  positions have no Markdown form and are not written.

From Markdown to geoWrite:

- `#` to `######` and underlined headings (`===`, `---`): bold GU Sans
  24, 18 and 14 dots for levels 1 to 3, 12 below; the body GU Sans 12
  (`--font=NAME` sets another family by a Word font name, e.g.
  `--font=Times` for GU Serif).
- Paragraphs (lines joined; two spaces or `\` at a line's end is a line
  break); `**bold**`, `*italic*`, `` `code` ``, `<u>`, `<sup>`, `<sub>`;
  links as their text with the address in brackets.
- Lists (`-`, `*`, `+`, `1.`), also nested and with `[ ]` / `[x]`; block
  quotes (indented, italic); code blocks (fenced or indented, GU Mono);
  tables (cells at tab stops, the header bold); a rule as a centred
  "* * *".
- Pictures `![text](file.png)` next to the Markdown file; addresses on
  the web are not fetched.
- Page breaks: `<!-- pagebreak -->`, `\pagebreak` or `\newpage` on a
  line of their own.
- Strike-through (`~~`) has no GEOS style and is dropped; other HTML
  tags are left out; a YAML front matter block is skipped.

Examples:

    tools/gwtool.py md bigbrother.d64 bigbrother.md "Big Brother"
    tools/gwtool.py frommd README.md readme.d64 "ReadMe" --font=Times

## PostScript (ps)

`ps` writes the document (several: joined first, as `merge`) as a
PostScript file, laid out as geoWrite lays it out, so lines and pages
break where they break in geoWrite (tools/gwps.py). `ps2pdf OUT.ps`
makes a PDF of it; any PostScript printer prints it.

    tools/gwtool.py ps "g03 geowrite.d64" letter.ps "Letter"
    ps2pdf letter.ps

- **Fonts:** the LaserWriter fonts and GeoUltra's GU fonts (font IDs
  27-37: LW_Roma or GU Serif, LW_Cal or GU Sans, LW_Barrows or GU Mono
  and the rest) become the printer's own fonts as real text: Times,
  Helvetica, Courier, Avant Garde, Bookman, Helvetica Narrow, New
  Century Schoolbook, Palatino, Zapf Chancery, Symbol, Zapf Dingbats,
  in bold and italic where the document has them. Each word is placed
  where geoWrite puts it and fitted to geoWrite's width for it.
- Every other font is drawn from its own bitmap glyphs, at 80 dots an
  inch as on the C64's printer, as GeoUltra draws them (bold,
  underline, reverse; italic and outline plain). gwtool looks for the
  font files on IMAGE, then in `--fonts=DIR` (CVT files), then among
  GeoUltra's GU fonts (`build/fonts`, made by `make fonts`). A font
  found nowhere is drawn in the system font, with a warning.
- **--bitmap** draws the LW and GU fonts from their bitmaps too: the
  document looks exactly as on the C64's printer, without real text.
- BSW (the system font, ID 0) and BSW128 (GEOS 128's, ID 128) are
  drawn in GeoUltra's own system font, which has BSW's widths.
- Pictures are drawn as they are, at 80 dots an inch.
- The page: 480 or 640 dots wide (6 or 8 inches) and the document's
  page height, centred on A4 (`--letter`: US Letter). The header and
  footer are drawn on every page, not on a title page.

Checked against geoWrite: tests/print/psref.py prints a document with
geoWrite 2.1 on GeoUltra (VICE, GU Epson FX-80) and compares every page
dot for dot with gwtool's PostScript rendered by ghostscript (with
`--bitmap` where the document has LW or GU fonts, as the printer gets
bitmaps). Two documents, all pages the same (2026-11-19): GeoUTools'
manual (11 pages: the system fonts, bold, underline, outline, tab
stops, pictures) and a test document of its own (3 pages: a header and
a footer; left, centred, right and justified text; 1.5 and 2 line
spacing; GU Serif, Sans and Mono at 10-24 points mixed on a line;
reverse and italic; decimal tab stops; a hanging indent; BSW128).
What the comparison taught about geoWrite: 2 dots of leading under
every line, with 1.5 and 2 spacing the room added above the text; a
line's height comes from the fonts that have characters on it; a space
that passes the right margin ends the line and keeps its word; pictures
are centred between the margins on a card, 2 rows up into the line
above; the underline row is the line only; a reversed space is drawn
plain; the body starts at the header height and the footer ends at the
page height that the file header keeps; a "Write Image V2.0" document
is printed as a 480-dot page whatever its margins (so gwtool's
`fromdocx --wide` and `frommd --wide` now write V2.1). Not checked
yet: real text against a LaserWriter, bitmap fonts other than the GU
and system fonts, superscript and subscript.

## What a conversion changes

A geoWrite 1.x page starts with a 20-byte ruler (margins and 8 tab
stops) without an escape code; a 2.x page starts with a 27-byte ruler
escape, which adds the first line's margin (the left margin), the line
spacing and alignment, and reserved bytes. The rest of each page stays
byte for byte; the file header gets version "V2.0" and geoWrite 2.x's
document fields (first page 1, no title page, no header or footer, page
height 752 dots). This is what geoWrite 2.1 itself does when it opens a
1.x document ("Converting earlier file to V2.0"): checked by comparing
its result with gwtool's, which is the same byte for byte.

## Restrictions

- geoWrite repaginates when it opens a document whose page height
  differs from the printer's, so pages may break differently.
- 61 pages and 63 pictures at most per document (geoWrite's limit).
- Rulers inside the text and pictures of 1.x documents are taken as
  having the 2.x layout without the added ruler bytes; gwtool warns
  when it meets them, as no 1.x document with them was available to
  check.
- The disk name of a new image is "converted".
- `ps`: geoWrite's page number, date and time fields in the header and
  footer are not filled in yet; superscript and subscript are drawn on
  the line; italic and outline are drawn plain in bitmap fonts (as
  GeoUltra draws them), and as real italic and outline in the LW and GU
  fonts.

## Sources

The geoWrite 2.x format: Michael Steil, "Inside geoWrite - 7: File
Format and Pagination", pagetable.com; how geoWrite measures a line
(for `ps`): the same article, behaviour only. The 1.x differences: observed by
comparing a document before and after geoWrite 2.1 converted it. Own
code; the image reading is tools/mkappsdnp.py's.

# gwgen: geoWrite documents from a description

    tools/gwgen.py DESCRIPTION.toml OUT [--ps=FILE.ps] [--letter]

Makes a geoWrite 2.1 document from a text description: paragraphs with
their font, size, style, alignment, margins, tabs and spacing; pictures;
page breaks; a header and a footer. GeoUltra's sample brochure and quick
start guide are made with it (`samples/`, `make samples`). OUT is a new
D64 or D81, or a folder for a CVT; `--ps` also writes the document as
PostScript (as `gwtool ps`), to check it or to make a PDF.

```
[document]
name = "Letter"            # 16 characters at most
width = 480                # 480 (6 inches) or 640 (8 inches)
font = "GU Serif"          # the default font and size of the blocks
size = 12
header = "Club news"       # optional, on every page; header_font,
footer = "Page footer"     # header_size, header_align (footer_ too)

[[block]]                  # a paragraph
text = "Plain, **bold**, *italic*, __underlined__, ^^outline^^."
font = "GU Sans"           # a GU family: GU Serif, Sans, Mono, Book ...
size = 18                  # 9, 10, 12, 14, 18 or 24
align = "center"           # left, center, right, justify
spacing = 1                # 1, 1.5 or 2
left = 0                   # margins in dots (80 an inch); indent: the
right = 0                  # first line's, from the left margin
indent = 0
tabs = [120, 240]          # tab stops, dots from the left edge
after = 1                  # empty lines after it
keep = true                # on the same page as the next block

[[block]]                  # a picture (PNG, JPEG ...)
picture = "shot.png"
width = 320                # dots, a multiple of 8
threshold = 128            # black below it (0-255); or dither = true

[[block]]                  # a part of a C64 screenshot, pixel for pixel
picture = "desktop.png"
crop = [0, 0, 320, 144]    # x, y, width, height (on 8-pixel cards)
scale = 1                  # no scaling (0.5 for a doubled screenshot)
colour = true              # each card's two colours from the picture

[[block]]
pagebreak = true
```

Pictures are at most 144 lines high: geoWrite 2.1 prints a taller one
wrongly (the text after it is garbled) and genuine GEOS 2.0 crashes on
taller ones still when they are scrolled back to, so
gwgen scales them down (keeping their proportions); with `scale` a
picture that does not fit is an error. Each picture carries a colour
byte for every 8 x 8 card, as geoWrite's own pictures do (`colour` takes
them from the picture; else dark grey on light grey). geoWrite shows and
prints the pixels; a crop of a C64 screen on card boundaries with
`scale = 1` keeps its exact pixels.

`\t` in a text is a TAB, `\n` a new line with the same ruler. Text is
ASCII. gwgen lays every page out as geoWrite does, with the GU fonts
(`make fonts`), and starts a new page when the next block would not
fit, so the document opens in geoWrite as it was laid out.

# gptool: geoPaint pictures

`tools/gptool.py` turns geoPaint documents in a disk image into picture
files (PNG, JPEG, GIF, BMP: any format Pillow writes), and pictures into
geoPaint documents. Python 3 with Pillow; writing a D64 or D81 uses
VICE's `c1541`, as `gwtool` does.

## Commands

    tools/gptool.py list IMAGE
    tools/gptool.py export IMAGE NAME OUT.png [--mono] [--crop] [--scale=N]
    tools/gptool.py import IN.png OUT NAME [--colour] [--no-dither] [--fit]
                           [--ink=N] [--paper=N] [--threshold=N]

- **IMAGE**: a D64, D71, D81 or DNP; on a DNP a name may include its
  folder (`Art/Logo`).
- **OUT** (import): a new `.d64` or `.d81` image, or a folder that gets a
  CVT file.
- **list** shows each geoPaint document and how many of its 45 strips
  (two card rows each) hold something.
- **export** writes the whole page, 640 x 720 pixels, in the C64's
  colours: each 8 x 8 card in its own foreground and background colour
  (VICE's palette). `--mono`: black on white. `--crop`: only the drawing,
  without the empty page around it. `--scale=N`: N times larger, pixels
  kept sharp.
- **import** makes a geoPaint document from a picture, at the top left
  of the page. A picture larger than the page is scaled down to fit;
  `--fit` also enlarges a smaller one to fill the page (proportions
  kept).
  - Black and white (the default): Floyd-Steinberg dithering for photos;
    `--no-dither` with `--threshold=N` (0-255, 128 by default) for line
    art. `--ink=N` and `--paper=N` set the two colours (C64 colour
    numbers: 0 black, 1 white, 2 red, 6 blue, 11 dark grey, 15 light grey
    ...).
  - `--colour`: each 8 x 8 card gets the two of the 16 C64 colours that
    fit its pixels best, each pixel the nearer of the two. As on the C64
    itself a card has only two colours, so photos show blocks where
    colours meet; drawings with large areas of colour come out best.
    The picture's most common colour counts as its background: it fills
    the page around the picture, and shapes in other colours become set
    pixels, so they also show where geoPaint shows no colour.

Examples:

    tools/gptool.py export geos.d81 "GEOSMP.PIC" geosmp.png --crop --scale=2
    tools/gptool.py import logo.png art.d64 "Logo" --colour
    tools/gptool.py import photo.jpg art.d64 "Photo" --fit

## The format

From HG2G, appendix F ("geoPaint"): a VLIR file of 45 records, each two
card rows of the 80 x 90 card page: 2 x 80 cards of 8 bytes, 8 zero
bytes, and 160 colour bytes (foreground in the high nibble, background
in the low), compressed as one stream: a command of 0-63 takes that many
bytes as they are, 65-127 repeats the next 8 bytes (a card) command - 64
times, 129-255 repeats the next byte command - 128 times. An empty
record is a blank strip. Documents gptool writes have the class "Paint
Image V1.1" (geoPaint 2.0's) and all 127 record entries (the unused ones
empty, as GEOS expects).

## Checked

- Four documents from the GDOS64 and MegaPatch disks exported correctly,
  and every strip of them compressed again by gptool decompresses to
  the same bytes (`tests/tools/gptool_test.py`).
- A picture imported in colour opens in geoPaint 2.0 (VICE, 2026-11-18).
- Pixels survive import and export unchanged (black and white without
  dithering), and a coloured square comes back in its colours.

# mkappsdnp: an applications image

    tools/mkappsdnp.py MANIFEST.toml

Builds one DNP image with folders from your own GEOS disks: for example
all your applications, sorted into folders, on one drive. The manifest
names the sources (disk images, or folders of CVT files) and which files
go into which folder. The manifest and the image are yours; keep them
outside the repository.

```
[dnp]
out = "my-apps.dnp"            # relative to the manifest
name = "My applications"       # disk name, at most 16 characters
id = "MA"
tracks = 48                    # 64 KB each; 0: as small as fits (+25%)
strict = false                 # true: a missing file stops the build

[sources]                      # name = image or folder of CVTs
geos = "~/geos/GEOS64.D81"
calc = "~/geos/GeoCalc.d64"

[[folder]]
path = ""                      # "" is the root
files = ["geos:GEOWRITE", "geos:GEOPAINT"]

[[folder]]
path = "Office"                # "A/B": nested
files = ["calc:GEOCALC"]
all = ["calc"]                 # optional: every file of these sources
```

A file is `source:name`: the name as in the directory, with
`Folder/Name` for a folder inside a DNP source; for a folder source, the
CVT file's name. Files not found are reported, and the build goes on
(unless `strict`). `geosdisk.py build` takes the same manifest.

# mkgeosfont: GEOS fonts from outline fonts

    tools/mkgeosfont.py FONT.otf ID NAME SIZES OUT.cvt [--info TEXT] [--fix FILE] [--pcf PATTERN]

Renders an OpenType or TrueType font into a GEOS font file (a CVT), as
GeoUltra's own GU fonts are made. Check the font's licence before you
share the result.

- **ID**: the GEOS font ID (0-1023; pick one no other font of yours
  uses). **NAME**: the font's name in menus. **SIZES**: the point sizes,
  comma-separated (`10,12,14,18,24`; a GEOS point is a pixel at 80 dots
  an inch, the font's height in rows).
- The glyphs are rendered without anti-aliasing; the widths follow the
  outline font's design, so documents break lines as with its
  original.
- `--info TEXT`: the text in the font file's info box.
- `--fix FILE`: hand-drawn glyphs for small sizes, where rendering loses
  strokes: a Python file with `FIXES = {size: {char: drawing}}`, each
  drawing the glyph's rows (`#` ink, `.` paper).
- `--pcf PATTERN`: take the shapes from a bitmap font (PCF) per size
  (`%d` the size), the widths from the outline font.

Example:

    tools/mkgeosfont.py MyFont.otf 600 "My Font" 10,12,14,18 myfont.cvt

Add the CVT to `GEOULTRA/fonts` on the stick, and GeoUltra installs it
as a system font at its next start; or put it on an image with
`geosdisk.py add`.
