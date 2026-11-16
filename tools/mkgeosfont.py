#!/usr/bin/env python3
"""mkgeosfont.py - render an outline font into a GEOS font file (CVT).

    mkgeosfont.py FONT.otf ID NAME SIZES OUT.cvt [--info TEXT] [--fix FILE]
                  [--pcf PATTERN]

FONT.otf is an OpenType/TrueType font (GeoUltra's fonts: TeX Gyre, GUST
Font Licence; docs/DESIGN.md "Fonts"). ID is the GEOS font ID (10 bits),
NAME the file name and the font's name in menus ("GU Serif"), SIZES the
point sizes, comma-separated (GEOS: 1 point = 1 pixel at 80 dpi, the
font's height in rows). OUT.cvt is a VLIR CVT that c1541 -geoswrite and
GEOS converters read.

Each size is rendered by FreeType without anti-aliasing (PIL, mode "1":
hinted monochrome), the glyphs of characters 32-127 side by side:
- width: the glyph's design advance scaled to the size and rounded, not
  FreeType's hinted advance (Berkeley's LW fonts follow the same rule
  for the LaserWriter's metrics: measured on LW_Roma 2026-11-15, 10 or
  fewer of 95 widths differ from 10 points up; hinting gave more);
- baseline: the row the capitals end on (GEOS's baseline offset), with
  room above for the tallest of "H" and the ascenders (b d f h k l: their
  top row was lost at the capitals' height, 2026-11-15); a row lower
  than Berkeley's LW fonts at most sizes, which changes no widths;
- cell: a glyph whose ink reaches past its advance (Times' "f" to the
  right, "j" to the left) is moved inside its cell as far as the space
  on the other side allows (GEOS's glyphs cannot overlap); what still
  sticks out, and anything outside the point size's rows, is clipped.

Bitmaps (--pcf, the user's decision 2026-11-15: hand-tuned shapes, LW
widths): PATTERN names a PCF bitmap font per size ("%d" the size; the X11
75-dpi fonts from Adobe, permissive licence, its notices kept). For a
size that has one, each glyph's shape is taken from it, centred in the
cell the widths above give (so documents keep their line breaks), and
moved in as above; the rows from the bitmap font's own heights. FONT may
be "-" (no outline: Symbol): the widths are then the bitmaps' advances.
Glyphs that still do not fit are reported (candidates for --fix).

Hand fixes (--fix, the user's decision 2026-11-15: FreeType's small
sizes lose strokes): a Python file with FIXES = {size: {char: drawing}},
a drawing being the glyph's rows ("#" ink, "." paper), exactly the
size's height and the rendered width (the widths stay the metrics').

GEOS font file (HG2G2022 "Fonts"; checked against GEOS 2.0's fonts):
VLIR, record n = point size n, each record a font image (8-byte header:
baseline, set width in bytes, height, index table offset, bitstream
offset; 97 index words; the bitstream). File header: type FONT, class
"NAME V1.0", $61 the records' sizes (a word per size), $80 the font ID,
$82 the (ID << 6 | size) words, $A0 the info text. The icon is GeoUltra's
own drawing.

Written 2026 by Xander Mol for GeoUltra (own code).
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

BLOCK = 254
FIRST, LAST = 32, 127

# GeoUltra's own font file icon (24 x 21): "Aa" on a page.
ICON = """
........................
.######################.
.#....................#.
.#.......##...........#.
.#......#..#..........#.
.#.....#....#.........#.
.#.....#....#.........#.
.#.....######...####..#.
.#.....#....#......#..#.
.#.....#....#...#####.#.
.#.....#....#..#...#..#.
.#.....#....#...####..#.
.#....................#.
.#..################..#.
.#....................#.
.#..############......#.
.#....................#.
.#..##############....#.
.#....................#.
.######################.
........................
"""


def icon_bytes():
    rows = [r for r in ICON.strip("\n").split("\n")]
    assert len(rows) == 21 and all(len(r) == 24 for r in rows)
    out = bytearray()
    for r in rows:
        for b in range(3):
            v = 0
            for x in range(8):
                v = v << 1 | (r[b * 8 + x] == "#")
            out.append(v)
    return bytes(out)


def drawing(text, width, height, where):
    """A hand-fixed glyph: its rows as lists of 0/1, checked against the
    cell (WIDTH x HEIGHT)."""
    rows = [r.strip() for r in text.strip("\n").split("\n")]
    if len(rows) != height or any(len(r) != width or set(r) - set("#.") for r in rows):
        raise SystemExit("mkgeosfont.py: fix %s: %d rows of %d \"#.\" wanted"
                         % (where, height, width))
    return [[c == "#" for c in r] for r in rows]


def load_pcf(pattern, size):
    """The PCF bitmap font for SIZE (PATTERN % size, gzipped or not), or
    None."""
    import gzip
    import io
    from PIL import PcfFontFile
    if not pattern:
        return None
    path = pattern % size
    if not os.path.exists(path):
        return None
    data = open(path, "rb").read()
    if path.endswith(".gz"):
        data = gzip.decompress(data)

    class Pcf(PcfFontFile.PcfFontFile):
        # PIL 10's _load_encoding indexes the offsets by the character
        # code, not by code - first column: a font whose table starts at
        # 32 (Adobe's Symbol) came out shifted by 32. Corrected here for
        # codes 0-255: row 0 of a 16-bit table (the ISO 10646 fonts), or
        # the only row of an 8-bit one; own code.
        def _load_encoding(self):
            fp, _, i16, _ = self._getformat(PcfFontFile.PCF_BDF_ENCODINGS)
            first_col, last_col = i16(fp.read(2)), i16(fp.read(2))
            first_row, last_row = i16(fp.read(2)), i16(fp.read(2))
            i16(fp.read(2))                         # (the default character)
            cols = last_col - first_col + 1
            n = cols * (last_row - first_row + 1)
            offsets = [i16(fp.read(2)) for _ in range(n)]
            encoding = [None] * 256
            row = 0 if first_row <= 0 <= last_row else first_row
            for code in range(first_col, min(last_col, 255) + 1):
                off = offsets[(row - first_row) * cols + code - first_col]
                if off != 0xFFFF:
                    encoding[code] = off
            return encoding

    return Pcf(io.BytesIO(data))


PLACE = "centre"                                # (or "left": tests)


def render_pcf(pf, size, widths):
    """Glyph images (SIZE rows, the cell widths WIDTHS) from the bitmap
    font PF; baseline; the characters that did not fit."""
    def glyph(c):
        return pf.glyph[c] if c < len(pf.glyph) else None
    tops = [-glyph(ord(c))[1][1] for c in "Hbdfhkl" if glyph(ord(c))]
    caprows = max(2, min(size, max(tops) if tops else size * 2 // 3))
    clipped = []
    images = []
    for i, code in enumerate(range(FIRST, LAST + 1)):
        w = widths[i]
        cell = Image.new("1", (max(w, 1), size), 0)
        g = glyph(code)
        if w and g and g[3] is not None:
            (dx, _), (x0, y0, x1, y1), _, im = g
            x = ((w - dx) // 2 if PLACE == "centre" else 0) + x0
            left, right = x, x + (x1 - x0)
            if right > w:
                x -= min(right - w, max(left, 0))
            elif left < 0:
                x += min(-left, max(w - right, 0))
            top = caprows + y0
            for yy in range(y1 - y0):
                for xx in range(x1 - x0):
                    if im.getpixel((xx, yy)):
                        px, py = x + xx, top + yy
                        if 0 <= px < w and 0 <= py < size:
                            cell.putpixel((px, py), 1)
                        elif chr(code) not in clipped:
                            clipped.append(chr(code))
        images.append(cell)
    return images, caprows - 1, clipped


def render(path, size, fixes=None, pcf=None):
    """Font image for point SIZE: (record bytes, widths, baseline, the
    characters clipped); FIXES the hand-drawn glyphs for this size (char:
    drawing); PCF a bitmap font for the shapes (load_pcf)."""
    fixes = fixes or {}
    if path == "-":
        if not pcf:
            raise SystemExit("mkgeosfont.py: no outline font and no bitmap for size %d" % size)
        widths = []
        for code in range(FIRST, LAST + 1):
            g = pcf.glyph[code] if code < len(pcf.glyph) else None
            widths.append(max(1, g[0][0]) if g and code < LAST else 0)
        glyphs, baseline, clipped = render_pcf(pcf, size, widths)
        return finish(size, widths, glyphs, baseline, fixes) + (clipped,)
    font = ImageFont.truetype(path, size)
    design = ImageFont.truetype(path, 1000)         # advances in 1/1000 em
    ascent, _ = font.getmetrics()
    # The rows above the baseline: the tallest of "H" and the ascenders.
    probe = Image.new("1", (size * 12, size * 3), 0)
    ImageDraw.Draw(probe).text((size, size * 2), "Hbdfhkl", font=font, fill=1, anchor="ls")
    box = probe.getbbox()
    caprows = (size * 2 - box[1]) if box else ascent
    caprows = max(2, min(size, caprows))
    baseline = caprows - 1                           # the capitals' last row
    widths = []
    glyphs = []
    for code in range(FIRST, LAST + 1):
        ch = chr(code)
        w = max(1, int(round(design.getlength(ch) * size / 1000))) if code < LAST else 0
        pad = size
        img = Image.new("1", (max(w, 1) + 2 * pad, size + 2 * pad), 0)
        if w:
            ImageDraw.Draw(img).text((pad, pad + caprows), ch, font=font, fill=1, anchor="ls")
            box = img.getbbox()
            if box:                                 # ink past the cell: moved in
                left, right = box[0] - pad, box[2] - pad
                shift = 0
                if right > w:
                    shift = -min(right - w, max(left, 0))
                elif left < 0:
                    shift = min(-left, max(w - right, 0))
                if shift:
                    img = Image.new("1", img.size, 0)
                    ImageDraw.Draw(img).text((pad + shift, pad + caprows), ch, font=font,
                                             fill=1, anchor="ls")
        glyph = img.crop((pad, pad, pad + max(w, 1), pad + size))
        widths.append(w)
        glyphs.append(glyph)
    clipped = []
    if pcf:                                         # the bitmaps' shapes
        glyphs, baseline, clipped = render_pcf(pcf, size, widths)
    return finish(size, widths, glyphs, baseline, fixes) + (clipped,)


def finish(size, widths, glyphs, baseline, fixes):
    """The font image's bytes from the glyph cells (hand fixes applied):
    (record, widths, baseline)."""
    offsets = [0]
    for w in widths:
        offsets.append(offsets[-1] + w)
    set_width = (offsets[-1] + 7) // 8
    bits = [[0] * (set_width * 8) for _ in range(size)]
    for i, g in enumerate(glyphs):
        ch = chr(FIRST + i)
        fixed = drawing(fixes[ch], widths[i], size, "%r at %d" % (ch, size)) if ch in fixes else None
        for y in range(size):
            for x in range(widths[i]):
                if (fixed[y][x] if fixed else g.getpixel((x, y))):
                    bits[y][offsets[i] + x] = 1
    index_at = 8
    bits_at = index_at + 2 * len(offsets)
    rec = bytearray([baseline, set_width & 0xFF, set_width >> 8, size,
                     index_at & 0xFF, index_at >> 8, bits_at & 0xFF, bits_at >> 8])
    for o in offsets:
        rec += bytes([o & 0xFF, o >> 8])
    for row in bits:
        for b in range(set_width):
            v = 0
            for x in range(8):
                v = v << 1 | row[b * 8 + x]
            rec.append(v)
    return bytes(rec), widths, baseline


def header(name, fid, sizes, lengths, info):
    """The file header block's 256 bytes (as on disk; the CVT keeps 2-255)."""
    h = bytearray(256)
    h[0:2] = b"\x00\xff"
    h[2], h[3], h[4] = 3, 21, 0xBF
    h[5:5 + 63] = icon_bytes()
    h[0x44], h[0x45], h[0x46] = 0x83, 8, 1          # USR, FONT, VLIR
    h[0x47:0x49] = b"\x00\x00"
    h[0x49:0x4B] = b"\xff\xff"
    h[0x4B:0x4D] = b"\x00\x00"
    cls = ("%-12s" % name[:12] + "V1.0").encode("latin1")
    h[0x4D:0x4D + len(cls)] = cls
    for i, n in enumerate(lengths):
        h[0x61 + 2 * i:0x63 + 2 * i] = n.to_bytes(2, "little")
    h[0x80:0x82] = fid.to_bytes(2, "little")
    for i, s in enumerate(sizes):
        h[0x82 + 2 * i:0x84 + 2 * i] = (fid << 6 | s).to_bytes(2, "little")
    t = info.encode("latin1")[:95]
    h[0xA0:0xA0 + len(t)] = t
    return h


def cvt(name, h, records):
    """A VLIR CVT: the signature block (directory entry), the header, the
    record table, the records padded to whole blocks."""
    entry = bytearray(30)
    entry[0] = 0x83
    nm = name.encode("latin1")[:16]
    entry[3:19] = nm + b"\xa0" * (16 - len(nm))
    entry[19:21] = b"\x00\x00"                      # (header block: set by the writer)
    entry[21] = 1                                   # VLIR
    entry[22] = 8                                   # FONT
    table = bytearray(BLOCK)
    data = b""
    blocks = 2                                      # header and index blocks
    last = max(records)
    for n in range(last + 1):
        r = records.get(n)
        if not r:
            table[2 * n:2 * n + 2] = b"\x00\xff"
            continue
        k = (len(r) + BLOCK - 1) // BLOCK
        table[2 * n] = k
        table[2 * n + 1] = len(r) - (k - 1) * BLOCK + 1
        data += r + bytes(k * BLOCK - len(r))
        blocks += k
    entry[28:30] = blocks.to_bytes(2, "little")
    sig = bytearray(BLOCK)
    sig[0:30] = entry
    sig[30:58] = b"PRG formatted GEOS file V1.0"
    return bytes(sig) + bytes(h[2:]) + bytes(table) + data


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("font")
    ap.add_argument("id", type=int)
    ap.add_argument("name")
    ap.add_argument("sizes")
    ap.add_argument("out")
    ap.add_argument("--info", default="")
    ap.add_argument("--widths", help="write each size's widths to this file (tests)")
    ap.add_argument("--fix", help="hand-fixed glyphs (FIXES = {size: {char: drawing}})")
    ap.add_argument("--pcf", help="bitmap font per size for the shapes (\"%%d\": the size)")
    ap.add_argument("--pcf-sizes", help="the sizes the bitmaps are used for (default: all)")
    ap.add_argument("--place", choices=("centre", "left"), default="centre")
    a = ap.parse_args()
    if not 0 < a.id < 1024:
        raise SystemExit("mkgeosfont.py: a font ID is 1-1023")
    sizes = sorted(int(s) for s in a.sizes.split(","))
    if any(not 4 <= s <= 63 for s in sizes) or len(sizes) > 15:
        raise SystemExit("mkgeosfont.py: sizes 4-63, at most 15")
    fixes = {}
    if a.fix:
        scope = {}
        exec(compile(open(a.fix).read(), a.fix, "exec"), scope)
        fixes = scope["FIXES"]
    records, lengths, table = {}, [], []
    global PLACE
    PLACE = a.place
    pcf_sizes = {int(x) for x in a.pcf_sizes.split(",")} if a.pcf_sizes else None
    for s in sizes:
        use = a.pcf if (pcf_sizes is None or s in pcf_sizes) else None
        rec, widths, base, clipped = render(a.font, s, fixes.get(s), load_pcf(use, s))
        clipped = [c for c in clipped if c not in fixes.get(s, {})]
        if clipped:
            print("  size %d: cut off (a hand fix?): %s" % (s, "".join(clipped)))
        if len(rec) > 0xFFFF:
            raise SystemExit("mkgeosfont.py: size %d too large" % s)
        records[s] = rec
        lengths.append(len(rec))
        table.append("%d: baseline %d widths %s" % (s, base, " ".join(map(str, widths))))
    h = header(a.name, a.id, sizes, lengths, a.info)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(cvt(a.name, h, records))
    if a.widths:
        open(a.widths, "w").write("\n".join(table) + "\n")
    print("%s: %s, ID %d, sizes %s, %d bytes" % (a.out, a.name, a.id, ",".join(map(str, sizes)),
                                                   sum(lengths)))


if __name__ == "__main__":
    main()
