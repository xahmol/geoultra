"""gwps.py - a geoWrite 2.x document as PostScript, for gwtool.py's `ps`
command (docs/GWTOOL_MANUAL.md, "PostScript"; docs/DESIGN.md "PostScript
writer": the user's decisions of 2026-11-15 and 2026-11-19). It is the
reference for the C64 writer: both lay a page out as geoWrite does, and
tests/print compare them with geoWrite's own printout. No packages
needed.

Layout, as geoWrite measures lines (Michael Steil, "Inside geoWrite - 7:
File Format and Pagination", pagetable.com; behaviour only): each page
record is a page (geoWrite paginated it); a line's room is from the left
margin (the paragraph margin on a paragraph's first line) to the right
margin; character widths of the current font and style are added up
(GetRealSize: bold +1, outline +2), the line ends when the text passes
the right margin, after its last space (a space that overflows ends
the line itself; a word longer than the line is cut at the character), at a line break or a page break; a TAB goes to
the next tab stop past the text (a decimal stop lines up the text up to
the next full stop on it); the line's height and baseline are the
largest of its fonts' (outline 2 more, GetRealSize), and 2 dots of
leading under it; a picture (graphics escape) is a line of its own,
its height the picture's, centred between the margins (on a card). Line spacing 1.5 and 2 multiply the height with its leading, the room
added above the text. (The
leading, picture placement and the end at an overflowing space come
from geoWrite's own printout: tests/print/psref.py.)
Alignment left, centred, right, justified (the spaces widened, not on a
paragraph's last line).

Drawing: one PostScript unit is one geoWrite dot (1/80", 0.9 points),
y downwards from the page's top; the page (640 dots wide when a ruler
reaches past 480 in a V2.1 document, else 480; a "Write Image V2.0"
document is always 480, as geoWrite 2.1 prints it; the file header's
page height) centred on A4 or Letter. The header at the top, the body
below the header height the file header keeps, the footer above the
page's end by the footer height kept there. Fonts: IDs 27-37
(the LW fonts, GeoUltra's GU fonts) are the LaserWriter's built-in fonts
as real text at the GEOS size (their widths are the LaserWriter's;
each word placed where geoWrite has it and scaled to geoWrite's width
for it, a few percent at most); every other font is a Type 3
font made from its own bitmap glyphs, drawn as GeoUltra's kernal draws
them (src/kernal/text.s: bold, underline, reverse; italic and outline
plain, as the kernal); ID 0 and 128 (BSW, BSW128) are GeoUltra's own
system font (tools/fonts/system9.py). Pictures as image masks.
Own code (GeoUltra, 2026).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "fonts"))

ESC_GRAPHICS, ESC_RULER, ESC_NEWCARDSET = 0x10, 0x11, 0x17
TAB, PAGE_BREAK, CR = 0x09, 0x0C, 0x0D
UNDERLINE, BOLD, REVERSE, ITALIC, OUTLINE, SUPER, SUB = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02
PAPER = {"a4": (59528, 84189), "letter": (61200, 79200)}   # hundredths of a point
DOT = 0.9                               # points per dot (90 hundredths)
# IDs 27-37 (geoLaser's table: ID - 27 is the family; docs/DESIGN.md
# "Fonts"): the LaserWriter's fonts, (plain, bold, italic, bold italic).
PS_FONTS = {
    27: ("Times-Roman", "Times-Bold", "Times-Italic", "Times-BoldItalic"),
    28: ("Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique"),
    29: ("Symbol",) * 4,
    30: ("Courier", "Courier-Bold", "Courier-Oblique", "Courier-BoldOblique"),
    31: ("AvantGarde-Book", "AvantGarde-Demi", "AvantGarde-BookOblique", "AvantGarde-DemiOblique"),
    32: ("Bookman-Light", "Bookman-Demi", "Bookman-LightItalic", "Bookman-DemiItalic"),
    33: ("Helvetica-Narrow", "Helvetica-Narrow-Bold", "Helvetica-Narrow-Oblique",
         "Helvetica-Narrow-BoldOblique"),
    34: ("NewCenturySchlbk-Roman", "NewCenturySchlbk-Bold", "NewCenturySchlbk-Italic",
         "NewCenturySchlbk-BoldItalic"),
    35: ("Palatino-Roman", "Palatino-Bold", "Palatino-Italic", "Palatino-BoldItalic"),
    36: ("ZapfChancery-MediumItalic",) * 4,
    37: ("ZapfDingbats",) * 4,
}
SYSTEM_IDS = (0, 128)
PIC_DOWN = -2                           # a picture 2 rows above its line's top: over
                                        # the line above's leading (geoWrite's printout)
LEADING = 2                             # dots under each line (geoWrite's printout:
                                        # 11-dot lines in the 9-dot system font)                   # BSW, BSW128: GeoUltra's system font


class Font:
    """A GEOS font image (one point size; HG2G "Fonts"): baseline offset,
    set width, height, the index table (characters 32-127 and the end),
    the bit rows."""
    def __init__(self, rec):
        self.base, self.setw, self.height = rec[0], rec[1] | rec[2] << 8, rec[3]
        ix, bits = rec[4] | rec[5] << 8, rec[6] | rec[7] << 8
        n = (bits - ix) // 2
        self.offsets = [rec[ix + 2 * i] | rec[ix + 2 * i + 1] << 8 for i in range(n)]
        self.rows = [rec[bits + r * self.setw:bits + (r + 1) * self.setw] for r in range(self.height)]

    def width(self, c):
        k = c - 32
        if not 0 <= k < len(self.offsets) - 1:
            return 0
        return self.offsets[k + 1] - self.offsets[k]

    def real(self, c, style):
        """GetRealSize's width."""
        return self.width(c) + (1 if style & BOLD else 0) + (2 if style & OUTLINE else 0)

    def bit(self, c, row, col):
        o = self.offsets[c - 32] + col
        return self.rows[row][o >> 3] >> (7 - (o & 7)) & 1

    def cell(self, c, style):
        """The character's cell as the kernal draws it (text.s DrawChar):
        (width, rows of 0/1)."""
        w = self.width(c)
        cw = w + (1 if style & BOLD else 0)
        out = []
        pad = 2 if style & OUTLINE else 0       # (drawn plain, as the kernal; its
                                                # advance GetRealSize's)
        for r in range(self.height):
            row, prev = [], 0
            for col in range(cw):
                b = self.bit(c, r, col) if col < w else 0
                if style & BOLD:
                    b, prev = b | prev, b
                if style & UNDERLINE and r == self.base + 1:   # (the row is the
                    b = 1 if col + (1 if style & BOLD else 2) <= cw else 0   # line only)
                if style & REVERSE:
                    b ^= 1
                row.append(b)
            out.append(row + [0] * pad)
        return cw + pad, out


def system_font():
    import mkfont
    import system9
    return Font(mkfont.build(system9))


class Fonts:
    """Fonts by GEOS font ID word (family << 6 | size): from font files
    (GeoFile, GEOS type FONT: record n is the n-point size), the system
    font for 0 and 128, and the system font for a font not found (as
    geoWrite does without the file)."""
    def __init__(self, files=()):
        self.files = {}
        for gf in files:
            fam = gf.header[0x80] | gf.header[0x81] << 8
            self.files.setdefault(fam, gf)
        self.cache = {}
        self.sys = system_font()
        self.missing = set()

    def get(self, fid):
        fam, size = fid >> 6, fid & 63
        if fam in SYSTEM_IDS:
            return self.sys
        if fid not in self.cache:
            gf = self.files.get(fam)
            rec = gf.records[size] if gf and size < len(gf.records) else None
            if rec in (None, "end"):
                self.missing.add(fid)
                self.cache[fid] = self.sys
            else:
                self.cache[fid] = Font(rec)
        return self.cache[fid]


class Ruler:
    def __init__(self, data):
        w = lambda o: data[o] | data[o + 1] << 8
        self.left, self.right = w(1), w(3)
        self.tabs = [w(5 + 2 * i) for i in range(8)]
        self.para = w(21)
        self.align = data[23] & 3
        self.spacing = (data[23] >> 2) & 3


def tokens(rec):
    """A page record as tokens: ("c", code), ("tab",), ("cr",), ("pb",),
    ("ruler", Ruler), ("font", fid, style), ("pic", width cards, height,
    record)."""
    i = 0
    while i < len(rec):
        b = rec[i]
        if b == ESC_RULER:
            yield ("ruler", Ruler(rec[i:i + 27]))
            i += 27
        elif b == ESC_NEWCARDSET:
            yield ("font", rec[i + 1] | rec[i + 2] << 8, rec[i + 3])
            i += 4
        elif b == ESC_GRAPHICS:
            yield ("pic", rec[i + 1], rec[i + 2] | rec[i + 3] << 8, rec[i + 4])
            i += 5
        elif b == 0:
            return
        else:
            if b == TAB:
                yield ("tab",)
            elif b == CR:
                yield ("cr",)
            elif b == PAGE_BREAK:
                yield ("pb",)
            elif 0x20 <= b < 0x80:
                yield ("c", b)
            i += 1


class Line:
    """A laid-out line: its pieces [(x, fid, style, text)] or a picture,
    its height and baseline (from its top)."""
    def __init__(self):
        self.pieces, self.pic, self.height, self.base = [], None, 0, 0
        self.rules = []                 # (x0, x1, y offset): underlines of real text


def layout(rec, fonts, state):
    """The lines of one page record. state: the ruler, font and style
    carried over (each page record starts with its own)."""
    toks = list(tokens(rec))
    lines = []
    i = 0
    first = True                        # the paragraph's first line
    while i < len(toks):
        t = toks[i]
        if t[0] == "ruler":             # (here, so a ruler before a picture
            state["ruler"] = t[1]       # makes no empty line)
            i += 1
            continue
        if t[0] == "pic":
            ln = Line()
            r = state["ruler"]          # centred between the margins, on a card
            left, right = (r.left, r.right) if r else (0, 480)       # (geoWrite's
            ln.pic = ((left + right - 8 * t[1]) // 2 // 8 * 8, t[1], t[2], t[3])   # printout)
            ln.height = t[2]
            lines.append(ln)
            i += 1
            first = True
            continue
        i, ln, ended = measure(toks, i, fonts, state, first)
        lines.append(ln)
        first = ended
    return lines


def measure(toks, i, fonts, state, first):
    """One line from token i: (next token, Line, paragraph ended)."""
    while i < len(toks) and toks[i][0] == "ruler":     # (a paragraph's own
        state["ruler"] = toks[i][1]                     # ruler: its margins
        i += 1                                          # from the first line)
    ruler = state["ruler"]
    left = (ruler.para if first else ruler.left) if ruler else 0
    right = ruler.right if ruler else 480
    f = fonts.get(state["fid"])
    x = left
    chars = []                          # (x, width, code, fid, style) or tab marks
    space_at = None                     # (token index after the space, chars kept)
    ended = False
    j = i
    while j < len(toks):
        t = toks[j]
        kind = t[0]
        if kind == "ruler":
            state["ruler"] = ruler = t[1]
            right = ruler.right
            j += 1
            continue
        if kind == "font":
            state["fid"], state["style"] = t[1], t[2]
            f = fonts.get(t[1])
            j += 1
            continue
        if kind in ("cr", "pb"):
            j += 1
            ended = True
            break
        if kind == "pic":
            ended = True
            break
        if kind == "tab":
            x = tab_to(x, toks, j + 1, fonts, state, ruler)
            chars.append((x, 0, None, state["fid"], state["style"]))
            j += 1
            continue
        c = t[1]
        w = f.real(c, state["style"])
        if x + w > right and chars:
            if c == 0x20:               # the space itself overflows: the line
                j += 1                  # ends there, its word kept (geoWrite's
                break                   # printout)
            if space_at:
                j, keep, saved = space_at
                del chars[keep:]
                state.update(saved)     # (fonts or rulers read past the space)
            break
        chars.append((x, w, c, state["fid"], state["style"]))
        x += w
        j += 1
        if c == 0x20:
            space_at = (j, len(chars), dict(state))
    # the height and baseline: the largest of the fonts with characters on
    # the line (outline 2 more: GetRealSize); a line without any: the font
    # in effect (geoWrite's printout: a font changed at a line's start
    # does not count the one before)
    used = {(fid, style) for _, _, _, fid, style in chars} or {(state["fid"], state["style"])}
    hi = max(fonts.get(fid).height + (2 if style & OUTLINE else 0) for fid, style in used)
    base = max(fonts.get(fid).base + (2 if style & OUTLINE else 0) for fid, style in used)
    ln = Line()
    sp = {1: 3, 2: 4}.get(ruler.spacing if ruler else 0, 2)
    ln.height = (hi + LEADING) * sp // 2
    ln.base = base + ln.height - (hi + LEADING)     # (1.5 and 2: the room above
                                                    # the text, geoWrite's printout)
    # alignment: the line's width without its trailing spaces
    text = [ch for ch in chars if ch[2] is not None]
    while text and text[-1][2] == 0x20:
        text.pop()
    end = text[-1][0] + text[-1][1] if text else left
    shift, extra = 0, []
    align = ruler.align if ruler else 0
    if align == 1:
        shift = (right - end) // 2
    elif align == 2:
        shift = right - end
    elif align == 3 and not ended:
        gaps = [k for k, ch in enumerate(text) if ch[2] == 0x20]
        room = right - end
        if gaps and room > 0:
            per, more = divmod(room, len(gaps))
            add = 0
            adds = {}
            for n, k in enumerate(gaps):
                add += per + (1 if n < more else 0)
                adds[k] = add
            acc = 0
            for k in range(len(text)):
                extra.append(acc)
                if k in adds:
                    acc = adds[k]
    pieces = []
    for k, (cx, w, c, fid, style) in enumerate(chars):
        if c is None or c == 0x20 and k >= len(text):
            continue
        dx = shift + (extra[k] if k < len(extra) else 0)
        pieces.append((cx + dx, w, c, fid, style))
    ln.pieces = pieces
    return j, ln, ended


def tab_to(x, toks, j, fonts, state, ruler):
    """The x a TAB at x goes to: the next stop past x (stops at or past
    the right margin unused); a decimal stop less the text's width up
    to its next full stop. No stop left: x."""
    if not ruler:
        return x
    for stop in ruler.tabs:
        pos = stop & 0x7FFF
        if pos >= ruler.right or pos <= x:
            continue
        if stop & 0x8000:
            f, style, w = fonts.get(state["fid"]), state["style"], 0
            for t in toks[j:]:
                if t[0] == "font":
                    f, style = fonts.get(t[1]), t[2]
                elif t[0] == "c" and t[1] != 0x2E:
                    w += f.real(t[1], style)
                else:
                    break
            return max(x, pos - w)
        return pos
    return x


def ps_string(codes):
    out = []
    for c in codes:
        ch = chr(c)
        out.append("\\" + ch if ch in "()\\" else ch)
    return "(" + "".join(out) + ")"


class Writer:
    def __init__(self, fonts, paper, width, height):
        self.fonts = fonts
        self.paper = paper
        self.width, self.height = width, height
        self.type3 = {}                 # (fid, style) -> name; glyphs used
        self.glyphs = {}                # name -> {code: (width, rows)}
        self.pages = []

    def type3_font(self, fid, style):
        key = (fid if fid >> 6 not in SYSTEM_IDS else 9, style & (BOLD | UNDERLINE | REVERSE | OUTLINE))
        if key not in self.type3:
            name = "G%d_%d_%d" % (key[0] >> 6, key[0] & 63, key[1])
            self.type3[key] = name
            self.glyphs[name] = {}
        return self.type3[key], key[1]

    def prescan(self, records):
        """The bitmap fonts and their glyphs, as the C64 writer's first
        pass finds them: every character in each record (header, footer,
        then the pages) under its font and style, the fonts in the order
        first met (real-text fonts left out)."""
        for rec in records:
            fid, style = 0, 0
            for t in tokens(rec):
                if t[0] == "font":
                    fid, style = t[1], t[2]
                elif t[0] == "c" and not (fid >> 6 in PS_FONTS and self.real):
                    name, st = self.type3_font(fid, style)
                    c = t[1]
                    if c not in self.glyphs[name]:
                        f = self.fonts.get(fid)
                        cs = st & ~REVERSE if c == 0x20 else st
                        self.glyphs[name][c] = (f.cell(c, cs), f.base)

    def piece_ops(self, ln, top):
        """PostScript for a line's text: each run of characters of one
        font and style, unbroken by a jump, placed at its x."""
        ops = []
        runs = []
        for x, w, c, fid, style in ln.pieces:
            if runs and runs[-1]["fid"] == fid and runs[-1]["style"] == style and runs[-1]["end"] == x:
                runs[-1]["codes"].append(c)
                runs[-1]["end"] = x + w
            else:
                runs.append({"x": x, "fid": fid, "style": style, "codes": [c], "end": x + w})
        y = top + ln.base
        for r in runs:
            fam = r["fid"] >> 6
            if fam in PS_FONTS and self.real:
                ops += self.real_text(r, y)
            else:
                name, st = self.type3_font(r["fid"], r["style"])
                f = self.fonts.get(r["fid"])
                for c in r["codes"]:
                    if c not in self.glyphs[name]:  # (a space without reverse:
                        cs = st & ~REVERSE if c == 0x20 else st     # geoWrite's
                        self.glyphs[name][c] = (f.cell(c, cs), f.base)  # printout)
                ops.append("/%s 1 SF %d %d M %s S" % (name, r["x"], y, ps_string(r["codes"])))
        return ops

    def real_text(self, r, y):
        """A run in a LaserWriter font: each word at geoWrite's x (the
        bitmap widths decide the layout), underline and reverse drawn."""
        fam, size, style = r["fid"] >> 6, r["fid"] & 63, r["style"]
        name = PS_FONTS[fam][(1 if style & BOLD else 0) + (2 if style & ITALIC else 0)]
        f = self.fonts.get(r["fid"])
        ops = []
        if style & REVERSE:
            ops.append("%d %d %d %d BOX" % (r["x"], y - f.base, r["end"] - r["x"], f.height))
            ops.append("1 setgray")
        ops.append("/%s %d SF" % (name, size))
        x = r["x"]
        word = []
        for c in r["codes"] + [None]:
            if c in (0x20, None):
                if word:                # (scaled to geoWrite's width: W, OW)
                    ww = sum(word_w for _, word_w in word)
                    ops.append("%d %d M %s %d %s" % (x - ww, y, ps_string([k for k, _ in word]), ww,
                                                    "OW" if style & OUTLINE else "W"))
                    word = []
                if c is None:
                    break
                x += f.real(c, style)
                continue
            w = f.real(c, style)
            word.append((c, w))
            x += w
        if style & UNDERLINE:
            ops.append("%d %d %d 1 BOX" % (r["x"], y + 1, r["end"] - r["x"]))
        if style & REVERSE:
            ops.append("0 setgray")
        return ops

    def page(self, lines, header, footer, head_h=None, foot_h=None):
        """A page: the header at the top, the body below the header's
        height, the footer above the page's end (the heights the file
        header keeps, as geoWrite uses them; measured when it has none)."""
        ops = []
        y = 0
        for part, at, kept in ((header, 0, head_h), (footer, None, foot_h)):
            if not part:
                continue
            h = kept or sum(ln.height for ln in part)
            yy = at if at is not None else self.height - h
            for ln in part:
                ops += self.piece_ops(ln, yy)
                yy += ln.height
            if at is not None:
                y = h
        for ln in lines:
            if ln.pic:
                ops.append(self.picture(ln.pic, y))
            else:
                ops += self.piece_ops(ln, y)
            y += ln.height
        self.pages.append(ops)

    def picture(self, pic, y):
        x, wc, h, rec = pic
        data = self.pics.get(rec)
        if not data:
            return ""
        import gwdocx
        wc, h = data[0], data[1] | data[2] << 8
        bits = gwdocx.decompact(data[3:], wc * h)
        return "<%s> %d %d %d %d PIC" % (bits.hex(), x, y + PIC_DOWN, wc * 8, h)

    def write(self, path, title):
        # in whole hundredths of a point, rounded half up: the C64 writer
        # computes the same with integers, so both write the same text
        pw, ph = PAPER.get(self.paper) or (self.width * 90, self.height * 90)    # ("page":
                                        # the page itself, for tests: a dot a pixel at 80 dpi)
        x0 = (pw - self.width * 90 + 1) // 2
        y0 = (ph + self.height * 90 + 1) // 2
        hund = lambda v: "%d.%02d" % divmod(v, 100)
        out = ["%!PS-Adobe-3.0",
               "%%%%Title: %s" % title,
               "%%Creator: GeoUltra gwtool ps",
               "%%%%Pages: %d" % len(self.pages),
               "%%%%BoundingBox: 0 0 %d %d" % ((pw + 50) // 100, (ph + 50) // 100),
               "%%EndComments",
               "%%BeginProlog",
               "/M {moveto} bind def /S {show} bind def",
               "/W {/ww exch def /st exch def gsave currentpoint translate st stringwidth pop dup 0 gt",
               " {ww exch div} {pop 1} ifelse 1 scale 0 0 moveto st show grestore} bind def",
               "/OW {/ww exch def /st exch def gsave currentpoint translate st stringwidth pop dup 0 gt",
               " {ww exch div} {pop 1} ifelse 1 scale 0 0 moveto st true charpath 0.5 setlinewidth stroke",
               " grestore} bind def",
               "/SF {/sz exch def findfont [sz 0 0 sz neg 0 0] makefont setfont} bind def",
               "/BOX {4 2 roll moveto dup 0 exch rlineto exch 0 rlineto neg 0 exch rlineto closepath fill} bind def",
               "/PIC {/h exch def /w exch def /y exch def /x exch def /d exch def gsave x y translate w h scale "
               "w h true [w 0 0 h 0 0] {d} imagemask grestore} bind def"]
        for name, glyphs in self.glyphs.items():
            out += self.type3_def(name, glyphs)
        out.append("%%EndProlog")
        out.append("%%BeginSetup")
        out.append("<< /PageSize [%s %s] >> setpagedevice" % (hund(pw), hund(ph)))
        out.append("%%EndSetup")
        for n, ops in enumerate(self.pages, 1):
            out.append("%%%%Page: %d %d" % (n, n))
            out.append("gsave %s %s translate 0.9 -0.9 scale" % (hund(x0), hund(y0)))
            out += [o for o in ops if o]
            out.append("grestore showpage")
        out.append("%%EOF")
        open(path, "w", newline="\n").write("\n".join(out) + "\n")

    def type3_def(self, name, glyphs):
        """A Type 3 font of bitmap glyphs: units are dots, y downwards
        (the page's own space: FontMatrix identity under SF's flip, which
        a size of -1 undoes), the origin on the baseline."""
        lines = ["/%s 9 dict dup begin" % name,
                 "/FontType 3 def /FontMatrix [1 0 0 -1 0 0] def /FontBBox [0 -64 640 64] def",
                 "/Encoding 256 array def 0 1 255 {Encoding exch /.notdef put} for",
                 "/Glyphs %d dict def" % (len(glyphs) + 1),
                 "Glyphs /.notdef [0 0 0 <>] put"]
        for c, ((w, rows), base) in sorted(glyphs.items()):
            gname = "g%d" % c
            lines.append("Encoding %d /%s put" % (c, gname))
            stride = (w + 7) // 8
            data = bytearray()
            for row in rows:
                v = 0
                bits = row + [0] * (stride * 8 - len(row))
                for k, b in enumerate(bits):
                    v = v << 1 | b
                    if k % 8 == 7:
                        data.append(v)
                        v = 0
            lines.append("Glyphs /%s [%d %d %d <%s>] put" % (gname, w, base, len(rows), data.hex()))
        lines += ["/BuildGlyph {exch /Glyphs get exch get aload pop /d exch def /h exch def /b exch def /w exch def",
                  " w 0 0 b neg w h b sub setcachedevice",
                  " w 0 gt h 0 gt and {gsave 0 b neg translate w h scale",
                  " w h true [w 0 0 h 0 0] {d} imagemask grestore} if} bind def",
                  "/BuildChar {1 index /Encoding get exch get 1 index /BuildGlyph get exec} bind def",
                  "end definefont pop"]
        return lines


def write(path, pages_, header, footer, pics, fonts, paper="a4", page_height=752, title_page=False,
          title="geoWrite document", real=True, head_h=None, foot_h=None, version=b"V2.1"):
    """pages_: page records (2.x); header, footer: records or None; pics:
    {record: data}; fonts: a Fonts. Returns the fonts not found (drawn
    in the system font)."""
    width = 640 if version != b"V2.0" and any(p[:1] == b"\x11" and (p[3] | p[4] << 8) > 480
                                              for p in pages_) else 480     # (geoWrite 2.1
    # prints a V2.0 document as a 480-dot page whatever its margins: psref.py)
    w = Writer(fonts, paper, width, page_height)
    w.pics = pics
    w.real = real                       # False: every font from its bitmaps
    w.prescan([r for r in (header, footer) if r] + list(pages_))
    state = {"ruler": None, "fid": 0, "style": 0}
    head = layout(header, fonts, dict(state)) if header else None
    foot = layout(footer, fonts, dict(state)) if footer else None
    for n, rec in enumerate(pages_):
        lines = layout(rec, fonts, state)
        show = not (title_page and n == 0)
        w.page(lines, head if show else None, foot if show else None, head_h, foot_h)
    w.write(path, title)
    return sorted(fonts.missing)
