# gptool: geoPaint pictures on a PC

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
