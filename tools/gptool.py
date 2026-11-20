#!/usr/bin/env python3
"""gptool.py - geoPaint documents on a PC: list, to and from PNG, JPEG,
GIF, BMP (any format Pillow reads or writes).

    gptool.py list IMAGE
    gptool.py export IMAGE NAME OUT.png [--mono] [--crop] [--scale=N]
    gptool.py import IN.png OUT NAME [--colour] [--no-dither] [--fit]
                     [--ink=N] [--paper=N] [--threshold=N]

IMAGE is a D64, D71, D81 or DNP (a name may carry a DNP folder). OUT is
a new .d64 / .d81 image (made with VICE's c1541) or a folder that gets a
CVT file, as with gwtool.py.

`export` writes the document's 640 x 720 pixels in the C64's colours
(each 8 x 8 card its foreground and background colour); --mono in black
and white (set pixels black); --crop leaves out the empty border (the
colour of the page's bottom right corner around the drawing); --scale=N enlarges N times (pixels
stay square: a C64 screen pixel is about as wide as high).

`import` makes a geoPaint 2.0 document (V1.1 format) NAME: the picture
at the top left of the page; --fit scales it to fill the page's 640 x
720 keeping its proportions (else only a larger one is scaled down).
Black and white by default: Floyd-Steinberg dithering (--no-dither: a
threshold, --threshold=N, 0-255, 128 by default), ink and paper colours
--ink=N and --paper=N (C64 colour numbers, 0 black and 1 white by
default). --colour: each 8 x 8 card gets the two C64 colours (of the 16)
that fit its pixels best, each pixel the nearer of them; as on the C64
itself only two colours a card. The picture's most common colour is its
background: it fills the page around the picture and is the paper of
every card that has it, so solid shapes become set pixels in their own
colour (they also show in black and white, as geoPaint without colour
shows them).

The format (HG2G, appendix F "geoPaint"): a VLIR file of 45 records,
each two card rows: 2 x 80 cards of 8 bytes (top to bottom, bit 7 the
leftmost pixel, 1 the foreground), 8 zero bytes, then 160 colour bytes
(foreground << 4 | background), compressed as one stream: a command 0-63
takes that many bytes as they are, 65-127 repeats the next 8 bytes (a
card) command - 64 times, 129-255 repeats the next byte command - 128
times. An empty record ($00 $FF) is a blank strip. Own code (GeoUltra,
2026); the image reading from tools/mkappsdnp.py, the writing as in
tools/gwtool.py.
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkappsdnp import Image, GeoFile          # noqa: E402
import gwtool                                 # noqa: E402

W, H = 640, 720
CARDS, ROWS = 80, 90
RECORDS = 45
REC_BYTES = 2 * CARDS * 8 + 8 + 2 * CARDS     # 1448
CLASS = b"Paint Image V1.1"
# The C64's 16 colours (Pepto's measured palette, as VICE uses).
PALETTE = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
           (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
           (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
           (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95)]
BLANK_COLOUR = 0x01                            # a missing strip: black on white
ICON = [
    "########################",
    "#......................#",
    "#..####.......##.......#",
    "#.#....#.....#..#......#",
    "#.#....#....#....#.....#",
    "#..####.....######.....#",
    "#...........#....#.....#",
    "#..........#.....#.....#",
    "#.....#....#......#....#",
    "#....###..........#....#",
    "#...#####..........#...#",
    "#..#######.........#...#",
    "#...#####...###########.",
    "#....###....#.........#.",
    "#.....#.....#.........#.",
    "#...........#.........#.",
    "#...........#.........#.",
    "#...........###########.",
    "#......................#",
    "#......................#",
    "########################",
]


def die(msg):
    sys.exit("gptool: " + msg)


def decompress(data):
    """A record's stream as its 1448 bytes (short streams padded with 0)."""
    out = bytearray()
    i = 0
    while i < len(data) and len(out) < REC_BYTES:
        c = data[i]
        i += 1
        if c < 64:
            out += data[i:i + c]
            i += c
        elif 64 < c < 128:
            out += data[i:i + 8] * (c - 64)
            i += 8
        elif c > 128:
            out += bytes([data[i]]) * (c - 128) if i < len(data) else b""
            i += 1
        else:                                   # 64, 128: not used
            break
    return bytes(out[:REC_BYTES].ljust(REC_BYTES, b"\0"))


def compress(raw):
    """1448 bytes as a geoPaint stream (cards, bytes, else literal runs),
    ended by a 0 byte as geoPaint ends its own records. Each part of the
    strip (the two card rows, the 8 gap bytes, the colours) is packed on
    its own, so no run of cards crosses from one into the next: geoPaint's
    own files never do, and geoPaint draws such strips wrongly (the same
    stripes in every strip, measured in genuine GEOS 2.0 as in GeoUltra)."""
    parts = (raw[:CARDS * 8], raw[CARDS * 8:2 * CARDS * 8], raw[2 * CARDS * 8:2 * CARDS * 8 + 8],
             raw[2 * CARDS * 8 + 8:])
    return b"".join(pack(part) for part in parts) + b"\0"


def pack(raw):
    """One part of a strip as geoPaint packets (no end byte)."""
    out = bytearray()
    lit = bytearray()

    def flush():
        while lit:
            part = lit[:63]
            out.append(len(part))
            out.extend(part)
            del lit[:63]
    i, n = 0, len(raw)
    while i < n:
        card = raw[i:i + 8]
        k = 1
        if len(card) == 8:
            while k < 63 and raw[i + 8 * k:i + 8 * k + 8] == card:
                k += 1
        run = 1
        while i + run < n and run < 127 and raw[i + run] == raw[i]:
            run += 1
        if k >= 2 and 8 * k > run:
            flush()
            out.append(64 + k)
            out.extend(card)
            i += 8 * k
        elif run >= 3:
            flush()
            out += bytes([128 + run, raw[i]])
            i += run
        else:
            lit.append(raw[i])
            i += 1
    flush()
    return bytes(out)


def find(img, name):
    en = img.find(name)
    if en is None:
        die("%s: not on the image" % name)
    gf = img.gfile(en)
    if not gf.header or gf.header[0x4D:0x4D + 11] != b"Paint Image" or gf.records is None:
        die("%s: not a geoPaint document" % name)
    return gf


def cards_of(gf):
    """(bitmap 90 x 80 cards of 8 bytes, colours 90 x 80) of a document."""
    bits = [[bytes(8)] * CARDS for _ in range(ROWS)]
    cols = [[BLANK_COLOUR] * CARDS for _ in range(ROWS)]
    for r in range(RECORDS):
        rec = gf.records[r] if r < len(gf.records) else None
        if rec in (None, "end"):
            continue
        raw = decompress(rec)
        for half in range(2):
            row = 2 * r + half
            base = half * CARDS * 8
            bits[row] = [raw[base + c * 8:base + c * 8 + 8] for c in range(CARDS)]
            cbase = 2 * CARDS * 8 + 8 + half * CARDS
            cols[row] = list(raw[cbase:cbase + CARDS])
    return bits, cols


def export(gf, out, mono=False, crop=False, scale=1):
    from PIL import Image as PImage
    bits, cols = cards_of(gf)
    im = PImage.new("RGB", (W, H))
    px = im.load()
    for row in range(ROWS):
        for c in range(CARDS):
            fg, bg = cols[row][c] >> 4, cols[row][c] & 15
            ink = (0, 0, 0) if mono else PALETTE[fg]
            paper = (255, 255, 255) if mono else PALETTE[bg]
            card = bits[row][c]
            for y in range(8):
                b = card[y]
                for x in range(8):
                    px[c * 8 + x, row * 8 + y] = ink if b & (0x80 >> x) else paper
    if crop:
        bg = px[W - 1, H - 1]                   # (the page's empty end)
        box = None
        for y in range(H):
            for x in range(W):
                if px[x, y] != bg:
                    box = [x, y, x, y] if box is None else [min(box[0], x), min(box[1], y),
                                                             max(box[2], x), max(box[3], y)]
        if box:
            im = im.crop((box[0], box[1], box[2] + 1, box[3] + 1))
    if scale > 1:
        im = im.resize((im.width * scale, im.height * scale), PImage.NEAREST)
    im.save(out)
    return im.size


def nearest(rgb, choices):
    return min(choices, key=lambda k: sum((a - b) ** 2 for a, b in zip(rgb, PALETTE[k])))


def from_picture(path, colour=False, dither=True, fit=False, ink=0, paper=1, threshold=128):
    """(bits, cols) as cards_of gives, from a picture file."""
    from PIL import Image as PImage
    im = PImage.open(path)
    im = im.convert("RGBA")
    flat = PImage.new("RGBA", im.size, (255, 255, 255, 255))
    flat.alpha_composite(im)
    im = flat.convert("RGB")
    w, h = im.size
    if fit or w > W or h > H:
        f = min(W / w, H / h)
        im = im.resize((max(1, round(w * f)), max(1, round(h * f))), PImage.LANCZOS)
    back = paper
    if colour:                                  # the picture's most common colour:
        hist = {}                               # its background, also around it
        for p, n in ((p, n) for n, p in im.getcolors(1 << 20) or []):
            k = nearest(p, range(16))
            hist[k] = hist.get(k, 0) + n
        back = max(hist, key=hist.get) if hist else paper
    page = PImage.new("RGB", (W, H), PALETTE[back])
    page.paste(im, (0, 0))
    bits = [[None] * CARDS for _ in range(ROWS)]
    cols = [[0] * CARDS for _ in range(ROWS)]
    if not colour:
        grey = page.convert("L")
        if dither:
            bw = grey.convert("1")                       # Floyd-Steinberg
            on = lambda x, y: bw.getpixel((x, y)) == 0
        else:
            on = lambda x, y: grey.getpixel((x, y)) < threshold
        for row in range(ROWS):
            for c in range(CARDS):
                card = bytearray(8)
                for y in range(8):
                    b = 0
                    for x in range(8):
                        if on(c * 8 + x, row * 8 + y):
                            b |= 0x80 >> x
                    card[y] = b
                bits[row][c] = bytes(card)
                cols[row][c] = ink << 4 | paper
        return bits, cols
    px = page.load()
    index = {}                                  # each pixel colour's index, once
    lum = lambda k: sum(PALETTE[k])
    for row in range(ROWS):
        for c in range(CARDS):
            pixels = [px[c * 8 + x, row * 8 + y] for y in range(8) for x in range(8)]
            counts = {}
            for p in pixels:
                k = index.get(p)
                if k is None:
                    k = index[p] = nearest(p, range(16))
                counts[k] = counts.get(k, 0) + 1
            order = sorted(counts, key=lambda k: -counts[k])
            a = order[0]
            card = bytearray(8)
            # Paper is the picture's background where the card has it, so a
            # solid shape becomes set pixels in its own colour (it shows in
            # black and white too); else the lighter colour is the paper.
            if len(order) == 1:
                fg, bg = (ink, back) if a == back else (a, back)
            else:
                b = order[1]
                if back in (a, b):
                    fg, bg = (b if a == back else a), back
                else:
                    fg, bg = (a, b) if lum(a) < lum(b) else (b, a)
            for y in range(8):
                v = 0
                for x in range(8):
                    if nearest(pixels[y * 8 + x], (fg, bg)) == fg:
                        v |= 0x80 >> x
                card[y] = v
            bits[row][c] = bytes(card)
            cols[row][c] = fg << 4 | bg
    return bits, cols


def records_of(bits, cols):
    recs = []
    for r in range(RECORDS):
        raw = bytearray()
        for half in range(2):
            for c in range(CARDS):
                raw += bits[2 * r + half][c]
        raw += bytes(8)
        for half in range(2):
            raw += bytes(cols[2 * r + half])
        recs.append(compress(bytes(raw)))
    return recs + [None] * (127 - RECORDS)        # (all 127 entries: gwtool EMPTY)


def new_header(info):
    h = bytearray(256)
    h[1] = 0xFF
    h[2:5] = bytes([3, 21, 0x80 + 63])
    for y, row in enumerate(ICON):
        row = row[:24].ljust(24)
        for xc in range(3):
            b = 0
            for bit in range(8):
                if row[xc * 8 + bit] == "#":
                    b |= 0x80 >> bit
            h[5 + y * 3 + xc] = b
    h[0x44:0x4D] = bytes([0x83, 7, 1, 0, 0, 0xFF, 0xFF, 0, 0])
    h[0x4D:0x61] = CLASS.ljust(20, b"\0")
    h[0x75:0x89] = b"geoPaint    V2.0".ljust(20, b"\0")
    t = info.encode("ascii")[:95]
    h[0xA0:0xA0 + len(t)] = t
    return bytes(h)


def make(name, recs, info):
    entry = bytearray(30)
    entry[0] = 0x83
    entry[3:19] = name.encode("latin1")[:16].ljust(16, b"\xa0")
    entry[0x15], entry[0x16] = 1, 7
    now = datetime.datetime.now()
    entry[0x17:0x1C] = bytes([now.year % 100, now.month, now.day, now.hour, now.minute])
    return GeoFile(bytes(entry), new_header(info), None, recs)


def option(argv, key, default, conv=int):
    for a in argv:
        if a.startswith("--%s=" % key):
            return conv(a.split("=", 1)[1])
    return default


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    cmd = args[0] if args else ""
    if cmd == "list" and len(args) == 2:
        img = Image(args[1])
        for en in img.entries():
            gf = img.gfile(en)
            if gf.header and gf.header[0x4D:0x4D + 11] == b"Paint Image" and gf.records is not None:
                used = sum(1 for r in gf.records[:RECORDS] if r not in (None, "end"))
                print("%-24s %s  %d of 45 strips" % (gf.name, gf.header[0x4D:0x5D].decode("latin1"), used))
        return
    if cmd == "export" and len(args) == 4:
        gf = find(Image(args[1]), args[2])
        size = export(gf, args[3], "--mono" in argv, "--crop" in argv, option(argv, "scale", 1))
        print("%s: %d x %d" % (args[3], size[0], size[1]))
        return
    if cmd == "import" and len(args) == 4:
        bits, cols = from_picture(args[1], "--colour" in argv or "--color" in argv, "--no-dither" not in argv,
                                  "--fit" in argv, option(argv, "ink", 0), option(argv, "paper", 1),
                                  option(argv, "threshold", 128))
        gf = make(args[3], records_of(bits, cols), "From %s by GeoUltra's gptool." % os.path.basename(args[1]))
        gwtool.output([gf], args[2])
        return
    sys.exit(__doc__.strip().split("\n\n")[1])


if __name__ == "__main__":
    main(sys.argv)
