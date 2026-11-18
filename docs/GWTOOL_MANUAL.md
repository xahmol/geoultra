# gwtool: geoWrite documents on a PC

`tools/gwtool.py` reads geoWrite documents from a disk image on a PC and
writes geoWrite 2.x documents: it converts geoWrite 1.x documents, and it
joins several documents into one. Python 3; writing a D64 or D81 uses
VICE's `c1541`.

## Commands

    tools/gwtool.py list IMAGE
    tools/gwtool.py convert IMAGE OUT [NAME ...] [--fonts]
    tools/gwtool.py merge IMAGE OUT NEWNAME NAME [NAME ...] [--fonts] [--start=N]
    tools/gwtool.py docx IMAGE OUT.docx NAME [NAME ...] [--page-breaks=records] [--start=N]

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

## Sources

The geoWrite 2.x format: Michael Steil, "Inside geoWrite - 7: File
Format and Pagination", pagetable.com. The 1.x differences: observed by
comparing a document before and after geoWrite 2.1 converted it. Own
code; the image reading is tools/mkappsdnp.py's.
