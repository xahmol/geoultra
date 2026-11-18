# gwtool: geoWrite documents on a PC

`tools/gwtool.py` reads geoWrite documents from a disk image on a PC and
writes geoWrite 2.x documents: it converts geoWrite 1.x documents, and it
joins several documents into one. Python 3; writing a D64 or D81 uses
VICE's `c1541`.

## Commands

    tools/gwtool.py list IMAGE
    tools/gwtool.py convert IMAGE OUT [NAME ...] [--fonts]
    tools/gwtool.py merge IMAGE OUT NEWNAME NAME [NAME ...] [--fonts] [--start=N]

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
