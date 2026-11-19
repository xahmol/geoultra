"""gwdocx.py - a geoWrite 2.x document as a Word document (.docx), for
gwtool.py's `docx` command (docs/manuals/TOOLS_MANUAL.md, "Word"; the user's
request of 2026-11-18). No packages needed: the .docx (Office Open XML,
ECMA-376) is written as its few XML parts in a ZIP file, the pictures as
PNG files (own writer, zlib).

geoWrite's units are dots of 1/80 inch: 1 dot = 18 twips (1/1440 inch).
Its text area is 480 dots (6") or 640 dots (8") wide; the Word page is
A4 with that width centred. A GEOS font's "point size" is its height in
dots, so Word gets 0.9 times it in points (72 / 80). Mapped (the 2.x
format: Michael Steil, "Inside geoWrite - 7", pagetable.com):
- ruler: left margin, right margin, first line (paragraph margin), tab
  stops (bit 15: decimal; stops at or past the right margin are unused),
  alignment (left, centre, right, justified), line spacing (1, 1.5, 2);
- NewCardSet: font (by family number, the name from the font files on
  the image, then a Windows font that looks alike, FONT_MAP), size, and
  style bits: underline, bold, reverse (white on black), italic, outline,
  superscript, subscript;
- TAB, line break (a new paragraph), page break ($0C);
- pages 0-60 the body (a page break at each geoWrite page with
  page_breaks="records", else only the explicit ones), record 61 the
  header, 62 the footer, pictures (records 64-126, GEOS compacted
  bitmaps, as in BitmapUp) as inline PNG images at 80 dpi.
Own code (GeoUltra, 2026).
"""
import struct
import zipfile
import zlib
from xml.sax.saxutils import escape

DOT = 18                        # twips per dot
A4_W, A4_H = 11906, 16838       # twips
TOP_BOTTOM = 1134               # 2 cm
FAMILY = {0: "BSW", 1: "University", 2: "California", 3: "Roma", 4: "Dwinelle",
          5: "Cory", 6: "Tolkien", 7: "Bubble", 8: "Commodore"}
FONT_MAP = {"BSW": "Arial", "University": "Century Gothic", "California": "Arial",
            "Roma": "Times New Roman", "Dwinelle": "Old English Text MT",
            "Cory": "Courier New", "Commodore": "Courier New", "Tolkien": "Papyrus",
            "Bubble": "Comic Sans MS"}
ALIGN = ("left", "center", "right", "both")
SPACING = (240, 360, 480, 240)
ESC_GRAPHICS, ESC_RULER, ESC_NEWCARDSET = 0x10, 0x11, 0x17
EMU = 9525 * 96 // 80           # EMU per dot (914400 per inch / 80)


class Ruler:
    def __init__(self, data):
        w = lambda o: data[o] | data[o + 1] << 8
        self.left, self.right = w(1), w(3)
        self.tabs = [w(5 + 2 * i) for i in range(8)]
        self.para = w(21)
        self.flags = data[23]


def png(width, height, rows):
    """A 1-bit PNG (black on white) of rows (bytes, 8 dots each)."""
    raw = b"".join(b"\0" + bytes(255 - b for b in r) for r in rows)

    def chunk(kind, data):
        c = kind + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 1, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def decompact(data, nbytes):
    """GEOS compacted bitmap: 1-127 repeat the next byte, 129-219 copy
    COUNT-128 bytes, 221-255 repeat the next COUNT-220 bytes BIGCOUNT
    times (HG2G); the first nbytes of the stream."""
    out = bytearray()
    i = 0

    def packet(i, limit):
        c = data[i]
        if c < 128:
            out.extend([data[i + 1]] * c)
            return i + 2
        if c < 220:
            n = c - 128
            out.extend(data[i + 1:i + 1 + n])
            return i + 1 + n
        n, big = c - 220, data[i + 1]
        start = i + 2
        for _ in range(big):
            j = start
            while j < start + n:
                j = packet(j, None)
        return start + n
    while len(out) < nbytes and i < len(data):
        i = packet(i, None)
    return bytes(out[:nbytes])


def picture(rec):
    """A geoWrite picture record (a photo scrap: width in cards, height,
    compacted bitmap): (width, height, PNG)."""
    wc, h = rec[0], rec[1] | rec[2] << 8
    bits = decompact(rec[3:], wc * h)
    rows = [bits[y * wc:(y + 1) * wc] for y in range(h)]
    return wc * 8, h, png(wc * 8, h, rows)


class Writer:
    def __init__(self, fonts, width):
        self.fonts = fonts              # family number -> GEOS font name
        self.width = width
        self.media = []                 # (name, png bytes)

    def font(self, fid):
        name = self.fonts.get(fid >> 6) or FAMILY.get(fid >> 6, "BSW")
        return FONT_MAP.get(name, name), fid & 63

    def run_props(self, fid, style):
        name, size = self.font(fid)
        p = ['<w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/>' % ((escape(name),) * 3)]
        if style & 0x40:
            p.append("<w:b/>")
        if style & 0x10:
            p.append("<w:i/>")
        if style & 0x08:
            p.append("<w:outline/>")
        if style & 0x20:                # (CT_RPr's order: color, sz, u, shd,
            p.append('<w:color w:val="FFFFFF"/>')   # vertAlign: Word checks it)
        p.append('<w:sz w:val="%d"/>' % max(2, round(size * 1.8)))
        if style & 0x80:
            p.append('<w:u w:val="single"/>')
        if style & 0x20:
            p.append('<w:shd w:val="clear" w:color="auto" w:fill="000000"/>')
        if style & 0x04:
            p.append('<w:vertAlign w:val="superscript"/>')
        elif style & 0x02:
            p.append('<w:vertAlign w:val="subscript"/>')
        return "<w:rPr>%s</w:rPr>" % "".join(p)

    def para_props(self, ruler):
        p = []
        tabs = [t for t in ruler.tabs if (t & 0x7FFF) < ruler.right]
        if tabs:
            p.append("<w:tabs>%s</w:tabs>" % "".join(
                '<w:tab w:val="%s" w:pos="%d"/>' % ("decimal" if t & 0x8000 else "left",
                                                    (t & 0x7FFF) * DOT) for t in tabs))
        p.append('<w:spacing w:before="0" w:after="0" w:line="%d" w:lineRule="auto"/>'
                 % SPACING[(ruler.flags >> 2) & 3])
        first = ruler.para - ruler.left
        p.append('<w:ind w:left="%d" w:right="%d" %s/>' % (
            ruler.left * DOT, max(0, self.width - ruler.right) * DOT,
            'w:firstLine="%d"' % (first * DOT) if first >= 0 else 'w:hanging="%d"' % (-first * DOT)))
        p.append('<w:jc w:val="%s"/>' % ALIGN[ruler.flags & 3])
        return "<w:pPr>%s</w:pPr>" % "".join(p)

    def body(self, records, pics, page_breaks):
        """Paragraph XML of a list of page records (header, ruler and
        font at each record's start)."""
        out, runs, text = [], [], []
        state = {"ruler": None, "fid": 0, "style": 0, "pstart": None}

        def flush_text():
            if text:
                s = "".join(text)
                runs.append("<w:r>%s<w:t xml:space=\"preserve\">%s</w:t></w:r>"
                            % (self.run_props(state["fid"], state["style"]), escape(s)))
                text.clear()

        def end_para():
            flush_text()
            ruler = state["pstart"] or state["ruler"]
            out.append("<w:p>%s%s</w:p>" % (self.para_props(ruler) if ruler else "", "".join(runs)))
            runs.clear()
            state["pstart"] = None

        def raw(xml):
            flush_text()
            runs.append(xml)
        for k, rec in enumerate(records):
            if k and page_breaks == "records":
                raw('<w:r><w:br w:type="page"/></w:r>')
            i = 0
            while i < len(rec):
                b = rec[i]
                if b == ESC_RULER:
                    state["ruler"] = Ruler(rec[i:i + 27])
                    if not runs and not text:
                        state["pstart"] = state["ruler"]
                    i += 27
                elif b == ESC_NEWCARDSET:
                    flush_text()
                    state["fid"], state["style"] = rec[i + 1] | rec[i + 2] << 8, rec[i + 3]
                    i += 4
                elif b == ESC_GRAPHICS:
                    wc, h, r = rec[i + 1], rec[i + 2] | rec[i + 3] << 8, rec[i + 4]
                    if r in pics:
                        raw(self.image(pics[r]))
                    i += 5
                elif b == 0x0D:
                    end_para()
                    i += 1
                elif b == 0x0C:
                    raw('<w:r><w:br w:type="page"/></w:r>')
                    i += 1
                elif b == 0x09:
                    raw("<w:r>%s<w:tab/></w:r>" % self.run_props(state["fid"], state["style"]))
                    i += 1
                elif b == 0:
                    i = len(rec)
                else:
                    if 0x20 <= b < 0x7F:
                        text.append(chr(b))
                    i += 1
        if runs or text:
            end_para()
        return "".join(out)

    def image(self, rec):
        w, h, data = picture(rec)
        n = len(self.media) + 1
        self.media.append(("image%d.png" % n, data))
        cx, cy = w * EMU, h * EMU
        return ('<w:r><w:drawing><wp:inline><wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="Picture %d"/>'
                '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
                '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
                '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
                '<pic:nvPicPr><pic:cNvPr id="%d" name="image%d.png"/><pic:cNvPicPr/></pic:nvPicPr>'
                '<pic:blipFill><a:blip r:embed="rImg%d"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
                '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
                '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
                '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
                % (cx, cy, n, n, n, n, n, cx, cy))


NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"')


def write(path, pages_, header, footer, pics, fonts, start_page=1, page_breaks="explicit"):
    """pages_: page records (2.x); header, footer: records or None; pics:
    {record: data}; fonts: {family: GEOS name}."""
    width = 640 if any(Ruler(p[:27]).right > 480 for p in pages_ if p[:1] == b"\x11") else 480
    w = Writer(fonts, width)
    body = w.body(pages_, pics, page_breaks)
    side = (A4_W - width * DOT) // 2
    rels = ['<Relationship Id="rStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/styles" Target="styles.xml"/>']
    parts = {}
    refs = ""
    for kind, rec in (("header", header), ("footer", footer)):
        if rec:
            xml = w.body([rec], pics, "explicit")
            parts["word/%s1.xml" % kind] = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:%s %s>%s</w:%s>' % (
                "hdr" if kind == "header" else "ftr", NS, xml, "hdr" if kind == "header" else "ftr")
            rels.append('<Relationship Id="r%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                        'relationships/%s" Target="%s1.xml"/>' % (kind, kind, kind))
            refs += '<w:%sReference w:type="default" r:id="r%s"/>' % (kind, kind)
    for name, _ in w.media:
        n = name[5:-4]
        rels.append('<Relationship Id="rImg%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                    'relationships/image" Target="media/%s"/>' % (n, name))
    sect = ('<w:sectPr>%s<w:pgSz w:w="%d" w:h="%d"/><w:pgMar w:top="%d" w:right="%d" w:bottom="%d" '
            'w:left="%d" w:header="567" w:footer="567" w:gutter="0"/><w:pgNumType w:start="%d"/></w:sectPr>'
            % (refs, A4_W, A4_H, TOP_BOTTOM, side, TOP_BOTTOM, side, start_page))
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s'
                '</w:body></w:document>' % (NS, body, sect))
    styles = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults>'
              '<w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="20"/>'
              '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" '
              'w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>' % NS)
    types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             '<Default Extension="png" ContentType="image/png"/>'
             '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-'
             'officedocument.wordprocessingml.document.main+xml"/>'
             '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-'
             'officedocument.wordprocessingml.styles+xml"/>'
             + "".join('<Override PartName="/%s" ContentType="application/vnd.openxmlformats-officedocument.'
                       'wordprocessingml.%s+xml"/>' % (p, "header" if "header" in p else "footer")
                       for p in parts) + '</Types>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("_rels/.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rDoc" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                   'relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr("word/document.xml", document)
        z.writestr("word/styles.xml", styles)
        z.writestr("word/_rels/document.xml.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   + "".join(rels) + '</Relationships>')
        for name, data in parts.items():
            z.writestr(name, data)
        for name, data in w.media:
            z.writestr("word/media/" + name, data)
