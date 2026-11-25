"""docxgw.py - a Word document (.docx) as a geoWrite 2.1 document, for
gwtool.py's `fromdocx` command (docs/manuals/TOOLS_MANUAL.md, "From Word"; the
user's request of 2026-11-18). Needs Pillow only for pictures.

The .docx (Office Open XML, ECMA-376) is read with the standard library:
word/document.xml, the styles (document defaults, paragraph and character
styles with their basedOn chains), the theme's fonts, numbering, the
default header and footer, the pictures. geoWrite 2.x (Michael Steil,
"Inside geoWrite - 7", pagetable.com) takes:
- text: ASCII $20-$7E; other characters by their plain form (accents
  dropped, typographic quotes and dashes as ASCII), else "?" (counted);
- paragraphs: a ruler escape when the paragraph's ruler differs from the
  one before: left and right margin, first line, up to 8 tab stops (left
  or decimal; Word's right and centre tabs become left ones), alignment,
  line spacing 1, 1.5 or 2 (Word's nearest);
- runs: a NewCardSet escape when font, size or style change: the font as
  one of GeoUltra's own families on drive E (GU Serif, Sans, Mono ...,
  IDs 27-36, FONTS below) at the nearest size it has (9-24 dots, 1.11
  times Word's points), bold, italic, underline, outline, superscript,
  subscript;
- tabs, line breaks (a new paragraph), page breaks; space after a
  paragraph of 6 points or more as an empty line; list items with "- "
  or their number; a table row as one paragraph, its cells at tab stops;
- pictures: dithered to black and white at 80 dpi, at most the text
  width and PIC_MAX_H high (scaled down to it), as GEOS compacted bitmaps in records 64-126;
- the default header and footer as records 61 and 62 (text only).
Pages: geoWrite keeps one page per record and repaginates on "update"
(and when printing for another page height): the text is cut into
records at paragraph ends, each filled to about FILL of a page by an
estimate, so geoWrite pulls the rest forward rather than overflowing its
7000-byte page buffer. Open the document once and use file > update.
Own code (GeoUltra, 2026).
"""
import io
import math
import unicodedata
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
WP = "{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}"
ESC_GRAPHICS, ESC_RULER, ESC_NEWCARDSET = 0x10, 0x11, 0x17
DOT_TWIPS = 18
EMU_DOT = 914400 // 80
PAGE_H = 752
FILL = 0.7
PAGE_BYTES = 5500
PIC_MAX_H = 144                     # lines: geoWrite 2.1 prints pictures of at
                                    # most 144 lines (its own photo scrap paste
                                    # limit): a taller one garbled the text after
                                    # it, and its next lines ran past the page
                                    # into the printer driver (the user's
                                    # brochure, 2026-11-25; 168 lines still
                                    # show on screen, 176 crash GEOS 2.0 when
                                    # scrolled back to); taller ones scaled down


def fit_height(w, h):
    """Width (a multiple of 8) and height of a picture w x h scaled down,
    proportions kept, to at most PIC_MAX_H lines."""
    if h <= PIC_MAX_H:
        return w, h
    nw = max(8, (w * PIC_MAX_H // h) // 8 * 8)
    return nw, max(1, min(PIC_MAX_H, round(h * nw / w)))
PAGES, HEADER_REC, FOOTER_REC, PIC_FIRST, PIC_LAST = 61, 61, 62, 64, 126

GU_SIZES = (9, 10, 12, 14, 18, 24)
# Word font names (lower case, a prefix is enough) -> GU family ID
FONTS = [("times", 27), ("cambria", 27), ("georgia", 27), ("garamond", 35), ("palatino", 35),
         ("book antiqua", 35), ("bookman", 32), ("century schoolbook", 34), ("century gothic", 31),
         ("avant", 31), ("futura", 31), ("arial narrow", 33), ("courier", 30), ("consolas", 30),
         ("lucida console", 30), ("symbol", 29), ("monotype corsiva", 36), ("zapf", 36),
         ("brush", 36), ("script", 36)]
GU_DEFAULT = 28                 # GU Sans (Arial, Calibri, Helvetica, Verdana ...)
PUNCT = {"‘": "'", "’": "'", "‚": "'", "“": '"', "”": '"', "„": '"',
         "–": "-", "—": "-", "…": "...", " ": " ", "•": "-", "·": "-",
         "«": '"', "»": '"', "−": "-", "­": ""}


def gu_font(name):
    n = (name or "").lower()
    for prefix, fid in FONTS:
        if n.startswith(prefix):
            return fid
    return GU_DEFAULT


def gu_size(pt):
    dots = pt * 80 / 72
    return min(GU_SIZES, key=lambda s: (abs(s - dots), s))


def ascii_text(s, bad):
    out = []
    for ch in s:
        if " " <= ch <= "~":
            out.append(ch)
            continue
        if ch in PUNCT:
            out.append(PUNCT[ch])
            continue
        plain = "".join(c for c in unicodedata.normalize("NFKD", ch) if not unicodedata.combining(c))
        if plain and all(" " <= c <= "~" for c in plain):
            out.append(plain)
        else:
            out.append("?")
            bad[0] += 1
    return "".join(out)


def on(el, tag):
    """A toggle property (w:b, w:i ...): None when absent, else its value."""
    e = el.find(W + tag) if el is not None else None
    if e is None:
        return None
    return e.get(W + "val", "true") not in ("0", "false", "off")


class Styles:
    def __init__(self, z):
        self.p, self.r, self.based = {}, {}, {}
        self.theme = {"minor": "Calibri", "major": "Calibri Light"}
        self.default_r, self.default_p = None, None
        self.para_default = None
        try:
            th = ET.fromstring(z.read("word/theme/theme1.xml"))
            for kind in ("minor", "major"):
                e = th.find(".//%s%sFont/%slatin" % (A, kind, A))
                if e is not None and e.get("typeface"):
                    self.theme[kind] = e.get("typeface")
        except KeyError:
            pass
        try:
            st = ET.fromstring(z.read("word/styles.xml"))
        except KeyError:
            return
        dd = st.find(W + "docDefaults")
        if dd is not None:
            self.default_r = dd.find("%srPrDefault/%srPr" % (W, W))
            self.default_p = dd.find("%spPrDefault/%spPr" % (W, W))
        for s in st.findall(W + "style"):
            sid = s.get(W + "styleId")
            b = s.find(W + "basedOn")
            self.based[sid] = b.get(W + "val") if b is not None else None
            self.p[sid], self.r[sid] = s.find(W + "pPr"), s.find(W + "rPr")
            if s.get(W + "type") == "paragraph" and s.get(W + "default") in ("1", "true"):
                self.para_default = sid

    def chain(self, sid):
        out, seen = [], set()
        while sid and sid not in seen:
            seen.add(sid)
            out.append(sid)
            sid = self.based.get(sid)
        return list(reversed(out))


class Props:
    """Effective properties, from the most general to the most direct."""

    def __init__(self, styles):
        self.s = styles

    def para(self, ppr):
        sid = None
        if ppr is not None and ppr.find(W + "pStyle") is not None:
            sid = ppr.find(W + "pStyle").get(W + "val")
        sid = sid or self.s.para_default
        layers = [self.s.default_p] + [self.s.p.get(x) for x in self.s.chain(sid)] + [ppr]
        rlayers = [self.s.default_r] + [self.s.r.get(x) for x in self.s.chain(sid)]
        return [x for x in layers if x is not None], [x for x in rlayers if x is not None]

    def run(self, plr, rpr):
        layers = list(plr)
        if rpr is not None and rpr.find(W + "rStyle") is not None:
            layers += [self.s.r.get(x) for x in self.s.chain(rpr.find(W + "rStyle").get(W + "val"))]
        layers.append(rpr)
        f = {"font": "Calibri", "pt": 10.0, "b": False, "i": False, "u": False, "outline": False,
             "va": None}
        for el in layers:
            if el is None:
                continue
            rf = el.find(W + "rFonts")
            if rf is not None:
                if rf.get(W + "ascii"):
                    f["font"] = rf.get(W + "ascii")
                elif rf.get(W + "asciiTheme"):
                    f["font"] = self.s.theme["major" if "major" in rf.get(W + "asciiTheme") else "minor"]
            sz = el.find(W + "sz")
            if sz is not None and sz.get(W + "val"):
                f["pt"] = int(sz.get(W + "val")) / 2
            for tag, key in (("b", "b"), ("i", "i"), ("outline", "outline")):
                v = on(el, tag)
                if v is not None:
                    f[key] = v
            u = el.find(W + "u")
            if u is not None:
                f["u"] = u.get(W + "val", "single") != "none"
            va = el.find(W + "vertAlign")
            if va is not None:
                f["va"] = va.get(W + "val")
        return f

    @staticmethod
    def get(layers, path, attr, conv=lambda x: x, default=None):
        val = default
        for el in layers:
            e = el.find(path)
            if e is not None and e.get(attr) is not None:
                val = conv(e.get(attr))
        return val


def card_set(f):
    fid = gu_font(f["font"]) << 6 | gu_size(f["pt"])
    style = (0x80 if f["u"] else 0) | (0x40 if f["b"] else 0) | (0x10 if f["i"] else 0) \
        | (0x08 if f["outline"] else 0) | (0x04 if f["va"] == "superscript" else 0) \
        | (0x02 if f["va"] == "subscript" else 0)
    return bytes([ESC_NEWCARDSET, fid & 0xFF, fid >> 8, style])


def ruler(layers, width, tabs_extra=None):
    tw = lambda v: int(round(int(v) / DOT_TWIPS))
    left = Props.get(layers, W + "ind", W + "left", tw, 0)
    left = Props.get(layers, W + "ind", W + "start", tw, left)
    right = Props.get(layers, W + "ind", W + "right", tw, 0)
    right = Props.get(layers, W + "ind", W + "end", tw, right)
    first = Props.get(layers, W + "ind", W + "firstLine", tw, 0)
    hang = Props.get(layers, W + "ind", W + "hanging", tw, 0)
    jc = Props.get(layers, W + "jc", W + "val", default="left")
    line = Props.get(layers, W + "spacing", W + "line", int, 240)
    rule = Props.get(layers, W + "spacing", W + "lineRule", default="auto")
    left = max(0, min(left, width - 40))
    rmargin = max(left + 40, min(width - 1, width - 1 - right))
    para = max(0, min(rmargin - 8, left + first - hang))
    tabs = []
    for el in layers:
        t = el.find(W + "tabs")
        if t is None:
            continue
        for tab in t.findall(W + "tab"):
            pos = tw(tab.get(W + "pos", "0"))
            if tab.get(W + "val") == "clear":
                tabs = [x for x in tabs if x[0] != pos]
            else:
                tabs.append((pos, tab.get(W + "val") == "decimal"))
    if tabs_extra:
        tabs = [(p, False) for p in tabs_extra]
    tabs = sorted({p: d for p, d in tabs if left < p < rmargin}.items())[:8]
    words = [(p | (0x8000 if d else 0)) for p, d in tabs] + [rmargin] * (8 - len(tabs))
    spacing = 0 if rule != "auto" or line < 300 else 1 if line < 420 else 2
    flags = {"left": 0, "start": 0, "center": 1, "right": 2, "end": 2, "both": 3,
             "distribute": 3}.get(jc, 0) | spacing << 2
    data = bytes([ESC_RULER]) + left.to_bytes(2, "little") + rmargin.to_bytes(2, "little")
    data += b"".join(w.to_bytes(2, "little") for w in words) + para.to_bytes(2, "little")
    return data + bytes([flags, 0, 0, 0]), spacing


def compact(data):
    """GEOS compacted bitmap packets (repeats of 3 and more, else unique
    runs of up to 91 bytes)."""
    out, i, n = bytearray(), 0, len(data)
    while i < n:
        j = i
        while j < n and j - i < 127 and data[j] == data[i]:
            j += 1
        if j - i >= 3:
            out += bytes([j - i, data[i]])
            i = j
            continue
        j = i
        while j < n and j - i < 91 and not (j + 2 < n and data[j] == data[j + 1] == data[j + 2]):
            j += 1
        out += bytes([128 + j - i]) + data[i:j]
        i = j
    return bytes(out)


PIC_COLOUR = 0xBF                   # dark grey on light grey, GEOS's own colours


def picture_record(wc, h, rows, colours=None):
    """A geoWrite picture record: width in cards, height, the compacted
    bitmap, then the compacted colours, one byte per card (wc x h/8,
    rounded up, row by row; ink in the high half), as geoWrite 2.x writes
    its pictures: it reads the colours after the bitmap, and without them
    it reads on into whatever follows (a crash in genuine GEOS 2.0 when
    such a picture is drawn again). COLOURS: those bytes; else PIC_COLOUR."""
    cards = wc * ((h + 7) // 8)
    if colours is None:
        colours = bytes([PIC_COLOUR]) * cards
    assert len(colours) == cards
    return bytes([wc, h & 0xFF, h >> 8]) + compact(rows) + compact(bytes(colours))


def picture(blob, cx, cy, width):
    from PIL import Image
    im = Image.open(io.BytesIO(blob)).convert("L")
    w = max(8, min(width, int(round(cx / EMU_DOT)))) if cx else min(width, im.width)
    h = int(round(cy / EMU_DOT)) if cy else im.height * w // im.width
    w = w // 8 * 8
    w, h = fit_height(w, max(1, h))
    bw = im.resize((w, h)).convert("1")             # (Floyd-Steinberg)
    rows = bytearray()
    for y in range(h):
        for xc in range(w // 8):
            b = 0
            for bit in range(8):
                if bw.getpixel((xc * 8 + bit, y)) == 0:
                    b |= 0x80 >> bit
            rows.append(b)
    return w // 8, h, picture_record(w // 8, h, bytes(rows))


class Reader:
    def __init__(self, path, width):
        self.z = zipfile.ZipFile(path)
        self.width = width
        self.s = Styles(self.z)
        self.props = Props(self.s)
        self.bad = [0]
        self.rels = {}
        try:
            for rel in ET.fromstring(self.z.read("word/_rels/document.xml.rels")):
                self.rels[rel.get("Id")] = rel.get("Target")
        except KeyError:
            pass
        self.numfmt = {}
        try:
            nb = ET.fromstring(self.z.read("word/numbering.xml"))
            absfmt = {}
            for an in nb.findall(W + "abstractNum"):
                absfmt[an.get(W + "abstractNumId")] = {
                    lv.get(W + "ilvl"): (lv.find(W + "numFmt").get(W + "val") if lv.find(W + "numFmt") is not None
                                         else "bullet") for lv in an.findall(W + "lvl")}
            for n in nb.findall(W + "num"):
                a = n.find(W + "abstractNumId")
                if a is not None:
                    self.numfmt[n.get(W + "numId")] = absfmt.get(a.get(W + "val"), {})
        except KeyError:
            pass
        self.counters = {}
        self.pics = []                  # picture records
        self.warnings = []

    def blocks(self, body):
        """(kind, data) items: ("para", (ruler, spacing, pieces, after)),
        ("pagebreak", None), ("pic", (wc, h, rec))."""
        for el in body:
            if el.tag == W + "p":
                yield from self.para(el)
            elif el.tag == W + "tbl":
                for tr in el.findall(W + "tr"):
                    cells = tr.findall(W + "tc")
                    step = self.width // max(1, len(cells))
                    pieces = []
                    first = None
                    for k, tc in enumerate(cells):
                        if k:
                            pieces.append(("tab", None))
                        for p in tc.findall(W + "p"):
                            for kind, data in self.para(p):
                                if kind == "para":
                                    first = first or data
                                    pieces += data[2]
                    if first:
                        rl, sp = ruler(self.props.para(None)[0], self.width,
                                       [step * k for k in range(1, len(cells))])
                        yield "para", (rl, sp, pieces, False)
            elif el.tag == W + "sectPr":
                pass

    def para(self, p):
        ppr = p.find(W + "pPr")
        layers, rlayers = self.props.para(ppr)
        rl, sp = ruler(layers, self.width)
        after = Props.get(layers, W + "spacing", W + "after", int, 0) or 0
        pieces = []
        num = ppr.find(W + "numPr") if ppr is not None else None
        if num is not None and num.find(W + "numId") is not None:
            nid = num.find(W + "numId").get(W + "val")
            lvl = num.find(W + "ilvl").get(W + "val") if num.find(W + "ilvl") is not None else "0"
            fmt = self.numfmt.get(nid, {}).get(lvl, "bullet")
            if fmt == "bullet":
                prefix = "- "
            else:
                key = (nid, lvl)
                self.counters[key] = self.counters.get(key, 0) + 1
                for k in list(self.counters):
                    if k[0] == nid and k[1] > lvl:
                        del self.counters[k]
                prefix = "%d. " % self.counters[key]
            pieces.append(("text", (self.props.run(rlayers, None), prefix)))
        out = []
        for r in p.iter():
            if r.tag != W + "r":
                continue
            f = self.props.run(rlayers, r.find(W + "rPr"))
            for c in r:
                if c.tag == W + "t":
                    pieces.append(("text", (f, ascii_text(c.text or "", self.bad))))
                elif c.tag == W + "tab":
                    pieces.append(("tab", None))
                elif c.tag in (W + "br", W + "cr"):
                    if c.get(W + "type") == "page":
                        out.append(("para", (rl, sp, pieces, False)))
                        out.append(("pagebreak", None))
                        pieces = []
                    else:
                        out.append(("para", (rl, sp, pieces, False)))
                        pieces = []
                elif c.tag == W + "drawing":
                    blip = c.find(".//%sblip" % A)
                    ext = c.find(".//%sextent" % WP)
                    if blip is None:
                        continue
                    target = self.rels.get(blip.get(R + "embed"))
                    if not target:
                        continue
                    try:
                        blob = self.z.read("word/" + target.lstrip("/").replace("word/", ""))
                        wc, h, rec = picture(blob, int(ext.get("cx")) if ext is not None else 0,
                                             int(ext.get("cy")) if ext is not None else 0, self.width)
                    except Exception as e:      # (Pillow missing, an odd format)
                        self.warnings.append("a picture not converted: %s" % e)
                        continue
                    if pieces:
                        out.append(("para", (rl, sp, pieces, False)))
                        pieces = []
                    out.append(("pic", (wc, h, rec)))
        out.append(("para", (rl, sp, pieces, after >= 120)))
        return out

    def part(self, name):
        try:
            return ET.fromstring(self.z.read(name))
        except KeyError:
            return None


def estimate(pieces, ruler_bytes, spacing):
    """A paragraph's height in dots, roughly (average character width
    half its size, line height 1.25 times it)."""
    left = ruler_bytes[1] | ruler_bytes[2] << 8
    right = ruler_bytes[3] | ruler_bytes[4] << 8
    avail = max(40, right - left)
    size, width = 10, 0
    for kind, data in pieces:
        if kind == "text":
            f, s = data
            size = max(size, gu_size(f["pt"]))
            width += len(s) * gu_size(f["pt"]) * 0.5
        elif kind == "tab":
            width += 30
    lines = max(1, math.ceil(width / avail))
    return lines * size * 1.25 * (1, 1.5, 2)[spacing]


def paginate(items, width, warnings):
    """Reader items (("para", (ruler, spacing, pieces, after)),
    ("pagebreak", None), ("pic", (wc, h, rec))) as geoWrite page records:
    (pages, pictures {record: data}, text), text(pieces) giving a
    paragraph's bytes (NewCardSets where the font changes). Shared by the
    Word and the Markdown reader (mdgw.py)."""
    pages, pics = [], {}
    state = {"ruler": None, "card": None, "page": bytearray(), "height": 0}

    def new_page():
        if state["page"]:
            pages.append(bytes(state["page"]))
        state["page"] = bytearray(state["ruler"] or ruler([], width)[0])
        state["page"] += state["card"] or card_set({"font": "", "pt": 10, "b": 0, "i": 0, "u": 0,
                                                     "outline": 0, "va": None})
        state["height"] = 0

    def text(pieces):
        out = bytearray()
        for kind, data in pieces:
            if kind == "tab":
                out.append(0x09)
                continue
            f, s = data
            cs = card_set(f)
            if cs != state["card"]:
                out += cs
                state["card"] = cs
            out += s.encode("ascii")
        return out
    for kind, data in items:
        if kind == "pagebreak":
            if state["page"]:
                state["page"].append(0x0C)
            new_page()
            continue
        if kind == "pic":
            wc, h, rec = data
            if len(pics) >= PIC_LAST - PIC_FIRST + 1:
                warnings.append("more than 63 pictures: the rest left out")
                continue
            r = PIC_FIRST + len(pics)
            pics[r] = rec
            if not state["page"] or state["height"] + h > PAGE_H * FILL:
                new_page()
            state["page"] += bytes([ESC_GRAPHICS, wc, h & 0xFF, h >> 8, r])
            state["height"] += h
            continue
        rl, sp, pieces, after = data
        est = estimate(pieces, rl, sp) + (12 if after else 0)
        if not state["page"]:
            state["ruler"] = rl
            new_page()
        elif (state["height"] + est > PAGE_H * FILL or len(state["page"]) > PAGE_BYTES) and state["height"]:
            state["ruler"] = rl
            new_page()
        if rl != state["ruler"]:
            state["page"] += rl
            state["ruler"] = rl
        state["page"] += text(pieces) + b"\r"
        if after:
            state["page"] += b"\r"
        state["height"] += est
    if state["page"]:
        pages.append(bytes(state["page"]))
    if len(pages) > PAGES:
        warnings.append("more than 61 pages: the rest left out")
        pages = pages[:PAGES]
    return pages, pics, text


def convert(path, width=480):
    """(pages, header, footer, pictures {record: data}, warnings)."""
    rd = Reader(path, width)
    doc = ET.fromstring(rd.z.read("word/document.xml"))
    body = doc.find(W + "body")
    pages, pics, text = paginate(list(rd.blocks(body)), width, rd.warnings)

    def side(kind):
        sect = body.find(W + "sectPr")
        if sect is None:
            return None
        for ref in sect.findall("%s%sReference" % (W, kind)):
            if ref.get(W + "type", "default") == "default":
                target = rd.rels.get(ref.get(R + "id"))
                el = rd.part("word/" + target) if target else None
                if el is None:
                    return None
                head = None
                out = bytearray()
                for k, (kd, d) in enumerate(rd.blocks(el)):
                    if kd != "para":
                        continue
                    if head is None:
                        head = d[0] + card_set({"font": "", "pt": 10, "b": 0, "i": 0, "u": 0,
                                                "outline": 0, "va": None})
                    out += text(d[2]) + b"\r"
                return bytes(head + out) if head else None
        return None
    header, footer = side("header"), side("footer")
    if rd.bad[0]:
        rd.warnings.append("%d character(s) without an ASCII form became '?'" % rd.bad[0])
    return pages, header, footer, pics, rd.warnings
