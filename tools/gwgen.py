#!/usr/bin/env python3
"""gwgen.py - a geoWrite 2.1 document generated from a description.

    gwgen.py DESCRIPTION.toml OUT [--ps=FILE.ps] [--letter]

Made for GeoUltra's sample brochure and quick start guide (the user's
decision of 2026-11-19: generated directly, with full control of the
layout, not through Word). OUT is a new .d64 or .d81 image, or a folder
that gets a CVT (as gwtool's). --ps also writes the document as
PostScript through gwps (gwtool ps's writer), to check it or make a PDF.

The description (TOML; paths relative to it):

    [document]
    name = "GeoUltra"          # the document's name (16 characters at most)
    width = 480                # 480 (6 inches) or 640 (8 inches)
    font = "GU Sans"           # the default font and size for blocks
    size = 12
    info = "..."               # the file's info text
    header = "..."             # optional: one line on every page
    footer = "..."             # (font, size and alignment: header_font ...)

    [[block]]                  # a paragraph
    text = "Plain, **bold**, *italic*, __underlined__, ^^outline^^."
    font = "GU Serif"          # any GU family; size 9, 10, 12, 14, 18, 24
    size = 24
    align = "center"           # left, center, right, justify
    spacing = 1                # 1, 1.5, 2
    left = 0                   # margins in dots (80 an inch), from the
    right = 0                  # text area's edges; indent: the first
    indent = 0                 # line's, from the left margin
    tabs = [120, 240]          # tab stops (dots from the left edge)
    after = 1                  # empty lines after it
    keep = true                # keep it on the page of the next block

    [[block]]                  # a picture: PNG, JPEG ...
    picture = "shot.png"
    width = 320                # dots (a multiple of 8); height in proportion
    threshold = 140            # black below it (0-255); or dither = true
    invert = false
    crop = [0, 0, 640, 336]    # a part of the source picture (x, y, w, h)
    scale = 0.5                # instead of width: pixel for pixel (1), or
                               # 0.5 for docs/images' doubled screenshots
    colour = true              # one colour byte a card from the picture
                               # (a C64 screen's crop on card boundaries:
                               # its exact colours); its darker colour as
                               # the set pixels. At most 144 lines high:
                               # geoWrite's limit; taller ones scaled down

    [[block]]
    pagebreak = true

"\\t" in a text is a TAB, "\\n" a line break (a new paragraph with the
same ruler). Text is ASCII (geoWrite's fonts have no other characters).

Pages: geoWrite keeps a page per record. gwgen lays each page out as
geoWrite does (gwps.layout, with GeoUltra's GU fonts from build/fonts)
and starts a new record when the next block would pass the page's end
(the page height less the header and the footer), so the document opens
as laid out, without "update". A block that does not fit on a page of
its own is cut between words. Rulers, font changes and pictures are
written as docxgw.py writes them (Michael Steil, "Inside geoWrite - 7:
File Format and Pagination", pagetable.com; HG2G for the compacted
bitmaps). Own code (GeoUltra, 2026).
"""
import glob
import os
import re
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import docxgw                                                   # noqa: E402
import gwps                                                     # noqa: E402
import gwtool                                                   # noqa: E402
from mkappsdnp import read_cvt                                  # noqa: E402

ROOT = os.path.dirname(HERE)
FAMILIES = {"gu serif": 27, "gu sans": 28, "gu symbol": 29, "gu mono": 30, "gu geometric": 31,
            "gu book": 32, "gu narrow": 33, "gu school": 34, "gu classic": 35, "gu script": 36}
SIZES = (9, 10, 12, 14, 18, 24)
ALIGN = {"left": 0, "center": 1, "centre": 1, "right": 2, "justify": 3}
SPACING = {1: 0, 1.5: 1, 2: 2}
STYLE = {"**": 0x40, "*": 0x10, "__": 0x80, "^^": 0x08}
PAGE_RECORD_MAX = 6500          # geoWrite's page buffer is 7000 bytes
LINE_H = 13                     # gwtool.save_new's header and footer line height


def die(msg):
    sys.exit("gwgen: " + msg)


def card(fid, size, style):
    w = fid << 6 | size
    return bytes([docxgw.ESC_NEWCARDSET, w & 0xFF, w >> 8, style])


def font_of(spec, default):
    name = str(spec.get("font", default["font"])).lower()
    if name not in FAMILIES:
        die("unknown font %r (GU families: %s)" % (name, ", ".join(sorted(FAMILIES))))
    size = int(spec.get("size", default["size"]))
    if size not in SIZES:
        die("size %d: the GU fonts have %s" % (size, SIZES))
    return FAMILIES[name], size


def ruler(spec, width):
    """A 27-byte ruler escape from a block's margins, tabs, alignment and
    spacing (the layout of docxgw.ruler)."""
    left = int(spec.get("left", 0))
    right = width - 1 - int(spec.get("right", 0))
    para = left + int(spec.get("indent", 0))
    if not 0 <= left < right - 40 or not 0 <= para < right:
        die("margins out of the page: %r" % spec)
    tabs = sorted(t for t in spec.get("tabs", []) if left < t < right)[:8]
    words = tabs + [right] * (8 - len(tabs))
    align = ALIGN[spec.get("align", "left")]
    spacing = SPACING[spec.get("spacing", 1)]
    data = bytes([docxgw.ESC_RULER]) + left.to_bytes(2, "little") + right.to_bytes(2, "little")
    data += b"".join(w.to_bytes(2, "little") for w in words) + para.to_bytes(2, "little")
    return data + bytes([align | spacing << 2, 0, 0, 0])


def runs(text, fid, size):
    """The text with its style markup as bytes: a card set wherever the
    style changes, TAB and CR for \\t and \\n."""
    out = bytearray(card(fid, size, 0))
    style = 0
    for part in re.split(r"(\*\*|__|\^\^|\*)", text):
        if part in STYLE:
            style ^= STYLE[part]
            out += card(fid, size, style)
            continue
        for ch in part:
            if ch == "\t":
                out.append(0x09)
            elif ch == "\n":
                out.append(0x0D)
            elif 0x20 <= ord(ch) < 0x7F:
                out.append(ord(ch))
            else:
                die("not ASCII: %r in %r" % (ch, text[:40]))
    if style:
        die("unclosed style markup in %r" % text[:40])
    return bytes(out)


def picture(path, spec, width):
    """(cards wide, height, record) of a picture block. Keys: width (dots,
    scaled with its proportions, at most PIC_MAX_H lines), or scale (1:
    pixel for pixel, 0.5 for docs/images' doubled shots; nearest pixel,
    nothing blurred), crop = [x, y, w, h] (of the source, first),
    threshold / dither / invert (black and white), colour = true (one
    colour byte a card from the picture: for a crop of a C64 screen at
    its own size, on card boundaries, its exact colours; the darker colour
    of a card is its set pixels, so it prints and shows in black and white
    as it should)."""
    from PIL import Image, ImageOps
    im = Image.open(path).convert("RGB")
    if "crop" in spec:
        x, y, cw, ch = (int(v) for v in spec["crop"])
        im = im.crop((x, y, x + cw, y + ch))
    if "scale" in spec:
        f = float(spec["scale"])
        w, h = round(im.width * f) // 8 * 8, max(1, round(im.height * f))
        if w > width or h > docxgw.PIC_MAX_H:
            die("%s: %d x %d at scale %s: more than %d dots wide or %d lines high"
                % (path, w, h, spec["scale"], width, docxgw.PIC_MAX_H))
        im = im.resize((w, h), Image.NEAREST)
    else:
        w = int(spec.get("width", min(width, im.width))) // 8 * 8
        w = max(8, min(w, width))
        h = max(1, round(im.height * w / im.width))
        w, h = docxgw.fit_height(w, h)      # (geoWrite's limit: PIC_MAX_H lines)
        im = im.resize((w, h), Image.LANCZOS)
    if spec.get("colour") or spec.get("color"):
        return colour_picture(im, w, h)
    grey = im.convert("L")
    if spec.get("invert"):
        grey = ImageOps.invert(grey)
    if spec.get("dither"):
        bw = grey.convert("1")
    else:
        t = int(spec.get("threshold", 128))
        bw = grey.point(lambda v: 255 if v >= t else 0).convert("1", dither=Image.NONE)
    rows = bytearray()
    for y in range(h):
        for xc in range(w // 8):
            b = 0
            for bit in range(8):
                if bw.getpixel((xc * 8 + bit, y)) == 0:
                    b |= 0x80 >> bit
            rows.append(b)
    return w // 8, h, docxgw.picture_record(w // 8, h, bytes(rows))


def colour_picture(im, w, h):
    """A picture in its colours: each 8 x 8 card its two most frequent C64
    colours (the darker the ink, its pixels set), as on the C64's screen."""
    import gptool
    px = im.load()
    index = {}

    def colour(x, y):
        p = px[x, y]
        if p not in index:
            index[p] = gptool.nearest(p, range(16))
        return index[p]
    lum = lambda k: sum(gptool.PALETTE[k])
    wc = w // 8
    rows = bytearray(wc * h)
    colours = bytearray()
    for cy in range(0, h, 8):
        for cx in range(wc):
            cells = [(x, y, colour(x, y)) for y in range(cy, min(h, cy + 8))
                     for x in range(cx * 8, cx * 8 + 8)]
            counts = {}
            for _, _, k in cells:
                counts[k] = counts.get(k, 0) + 1
            order = sorted(counts, key=lambda k: -counts[k])
            if len(order) == 1:                 # one colour: dark ones as ink
                k = order[0]
                ink, paper = (k, k) if lum(k) < 384 else (0, k)
            else:
                a, b = order[0], order[1]
                ink, paper = (a, b) if lum(a) < lum(b) else (b, a)
            for x, y, k in cells:
                if k == ink or (k != paper and gptool.nearest(gptool.PALETTE[k], (ink, paper)) == ink):
                    rows[y * wc + cx] |= 0x80 >> (x - cx * 8)
            colours.append(ink << 4 | paper)
    return wc, h, docxgw.picture_record(wc, h, bytes(rows), bytes(colours))


def fonts():
    files = [read_cvt(f) for f in sorted(glob.glob(os.path.join(ROOT, "build", "fonts", "*.cvt")))]
    if not files:
        die("no GU fonts in build/fonts: make fonts first")
    return gwps.Fonts(files)


def height(rec, fts):
    state = {"ruler": None, "fid": 0, "style": 0}
    return sum(ln.height for ln in gwps.layout(rec, fts, state))


def side(text, spec, doc, kind, width):
    if not text:
        return None
    fid, size = font_of({"font": doc.get(kind + "_font", doc["font"]),
                         "size": doc.get(kind + "_size", 10)}, doc)
    rl = ruler({"align": doc.get(kind + "_align", "center")}, width)
    return rl + runs(text, fid, size) + b"\r"


def build(desc_path):
    base = os.path.dirname(os.path.abspath(desc_path))
    with open(desc_path, "rb") as f:
        d = tomllib.load(f)
    doc = d.get("document", {})
    doc.setdefault("font", "GU Sans")
    doc.setdefault("size", 12)
    width = int(doc.get("width", 480))
    if width not in (480, 640):
        die("width: 480 or 640")
    head = side(doc.get("header"), doc, doc, "header", width)
    foot = side(doc.get("footer"), doc, doc, "footer", width)
    head_h = head.count(b"\r") * LINE_H if head else 0
    foot_h = foot.count(b"\r") * LINE_H if foot else 0
    room = gwtool.PAGE_HEIGHT - head_h - foot_h
    fts = fonts()
    items = []                      # (kind, bytes, keep)
    pics = {}
    for n, b in enumerate(d.get("block", [])):
        if b.get("pagebreak"):
            items.append(("pb", b"", False))
            continue
        if "picture" in b:
            wc, h, rec = picture(os.path.join(base, b["picture"]), b, width)
            r = docxgw.PIC_FIRST + len(pics)
            if r > docxgw.PIC_LAST:
                die("more than 63 pictures")
            pics[r] = rec
            pic = bytes([docxgw.ESC_GRAPHICS, wc, h & 0xFF, h >> 8, r])
            items.append(("pic", ruler(b, width) + pic, b.get("keep", False)))
            continue
        fid, size = font_of(b, doc)
        text = runs(b.get("text", ""), fid, size) + b"\r"
        text += (card(fid, size, 0) + b"\r") * int(b.get("after", 0))
        items.append(("para", ruler(b, width) + text, b.get("keep", False)))
    pages = []
    page = bytearray()

    def fits(rec):
        return height(bytes(rec), fts) <= room and len(rec) <= PAGE_RECORD_MAX

    def close():
        nonlocal page
        if page:
            pages.append(bytes(page))
        page = bytearray()
    k = 0
    while k < len(items):
        kind, data, keep = items[k]
        if kind == "pb":
            if page:
                page.append(gwps.PAGE_BREAK)
            close()
            k += 1
            continue
        group = [data]                  # a block kept with the ones after it
        j = k
        while items[j][2] and j + 1 < len(items) and items[j + 1][0] != "pb":
            j += 1
            group.append(items[j][1])
        chunk = b"".join(group)
        if fits(page + chunk):
            page += chunk
            k = j + 1
            continue
        if page:                        # to the next page
            close()
            continue
        if fits(chunk):                 # (cannot happen: an empty page)
            page += chunk
            k = j + 1
            continue
        if kind != "para" or len(group) > 1:
            if len(group) > 1:          # a kept group larger than a page: by
                items[k] = (kind, data, False)      # itself, then
                continue
            die("block %d does not fit on a page" % k)
        cut = split(data, fts, room)   # a paragraph longer than a page
        page += cut[0]
        close()
        items[k] = ("para", cut[1], keep)
    close()
    if len(pages) > docxgw.PAGES:
        die("more than 61 pages")
    return doc, pages, head, foot, pics, fts


def split(data, fts, room):
    """A paragraph record cut between words: (the part that fits, the rest
    with the ruler and card set repeated)."""
    rl = data[:27]
    body = data[27:]
    lead = body[:4]                     # its first card set
    spaces = [i for i, c in enumerate(body) if c == 0x20]
    best = None
    lo, hi = 0, len(spaces) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        part = rl + body[:spaces[mid] + 1]
        if height(part, fts) <= room:
            best = mid
            lo = mid + 1
        else:
            hi = mid - 1
    if best is None:
        die("a word longer than a page")
    at = spaces[best] + 1
    cs = lead                           # the card set in effect at the cut
    i = 0
    while i < at:
        if body[i] == docxgw.ESC_NEWCARDSET:
            cs = body[i:i + 4]
            i += 4
        else:
            i += 1
    return rl + body[:at], rl + cs + body[at:]


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__.split("\n\n")[1])
    doc, pages, head, foot, pics, fts = build(args[0])
    name = doc.get("name", os.path.splitext(os.path.basename(args[0]))[0])[:16]
    gwtool.save_new(args[1], name, pages, head, foot, pics,
                    doc.get("info", "Made by GeoUltra's gwgen.")[:95])
    ps = next((a[5:] for a in argv if a.startswith("--ps=")), None)
    if ps:
        missing = gwps.write(ps, pages, head, foot, pics, fts,
                             paper="letter" if "--letter" in argv else "a4",
                             page_height=gwtool.PAGE_HEIGHT, title=name, real=True,
                             version=b"V2.1" if int(doc.get("width", 480)) == 640 else b"V2.0",
                             head_h=head.count(b"\r") * LINE_H if head else 0,
                             foot_h=foot.count(b"\r") * LINE_H if foot else 0)
        for fid in sorted(missing or ()):
            print("warning: font %d (size %d) not found" % (fid >> 6, fid & 63))
        print(ps)


if __name__ == "__main__":
    main(sys.argv)
