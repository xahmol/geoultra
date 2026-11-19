#!/usr/bin/env python3
"""tools/docxgw.py on a Word document made here the way Word writes one
(docs/manuals/TOOLS_MANUAL.md, "From Word"): the font through the theme
(minorHAnsi, Calibri), sizes and paragraph spacing in docDefaults and the
Normal style, a heading style based on Normal, a numbered and a bulleted
list (numbering.xml), a table, accents and typographic quotes, a right
tab, a page break and a picture (PNG). Checks the geoWrite records: the
fonts and sizes (GU Sans at 12 for 11 points, 18 bold for the 16-point
heading), the list prefixes, the table row with tabs, the ASCII text,
the page break, the picture record and its graphics escape; through
gwtool into an image, no index entry 00 00 (geoWrite 2.x needs all 127).
No VICE.
Usage: tests/tools/docxgw_test.py
"""
import io
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import docxgw  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "tools")
WNS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
NS = (WNS + ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
      ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"'
      ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
      ' xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"')


def p(text, style=None, num=None, extra=""):
    ppr = ""
    if style or num:
        ppr = "<w:pPr>%s%s</w:pPr>" % ('<w:pStyle w:val="%s"/>' % style if style else "",
                                      '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="%d"/></w:numPr>' % num
                                      if num else "")
    return '<w:p>%s<w:r><w:t xml:space="preserve">%s</w:t></w:r>%s</w:p>' % (ppr, text, extra)


def make(path):
    from PIL import Image, ImageDraw
    im = Image.new("L", (160, 80), 255)
    d = ImageDraw.Draw(im)
    d.ellipse((10, 10, 150, 70), outline=0, width=4)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    pic = ('<w:p><w:r><w:drawing><wp:inline><wp:extent cx="1828800" cy="914400"/><wp:docPr id="1" name="P"/>'
           '<a:graphic><a:graphicData><pic:pic><pic:blipFill><a:blip r:embed="rId9"/></pic:blipFill>'
           '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>')
    body = (p("Een kop", "Heading1")
            + p("Gewóne tekst met “aanhalingstekens” en een – streep.")
            + '<w:p><w:pPr><w:tabs><w:tab w:val="right" w:pos="4320"/></w:tabs></w:pPr><w:r><w:t>Links</w:t>'
              '</w:r><w:r><w:tab/></w:r><w:r><w:t>Rechts</w:t></w:r></w:p>'
            + p("Eerste", num=1) + p("Tweede", num=1) + p("Punt", num=2)
            + '<w:tbl><w:tr><w:tc>%s</w:tc><w:tc>%s</w:tc><w:tc>%s</w:tc></w:tr></w:tbl>' % (p("a"), p("b"), p("c"))
            + '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
            + p("Na de pagina") + pic)
    doc = '<?xml version="1.0" encoding="UTF-8"?><w:document %s><w:body>%s<w:sectPr/></w:body></w:document>' % (NS, body)
    styles = ('<?xml version="1.0" encoding="UTF-8"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr>'
              '<w:rFonts w:asciiTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi"/><w:sz w:val="22"/></w:rPr>'
              '</w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/>'
              '</w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
              '<w:style w:type="paragraph" w:styleId="Heading1"><w:basedOn w:val="Normal"/><w:rPr><w:b/>'
              '<w:sz w:val="32"/></w:rPr></w:style></w:styles>' % WNS)
    theme = ('<?xml version="1.0"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
             '<a:themeElements><a:fontScheme><a:majorFont><a:latin typeface="Calibri Light"/></a:majorFont>'
             '<a:minorFont><a:latin typeface="Calibri"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>')
    numbering = ('<?xml version="1.0"?><w:numbering %s><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
                 '<w:numFmt w:val="decimal"/></w:lvl></w:abstractNum><w:abstractNum w:abstractNumId="1">'
                 '<w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>'
                 '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
                 '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num></w:numbering>' % WNS)
    rels = ('<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId9" Type="image" Target="media/image1.png"/></Relationships>')
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("word/document.xml", doc)
        z.writestr("word/styles.xml", styles)
        z.writestr("word/theme/theme1.xml", theme)
        z.writestr("word/numbering.xml", numbering)
        z.writestr("word/_rels/document.xml.rels", rels)
        z.writestr("word/media/image1.png", buf.getvalue())


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "wordtest.docx")
    make(path)
    pages, header, footer, pics, warns = docxgw.convert(path)
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    text = b"".join(pages)
    cards = {(text[i + 1] | text[i + 2] << 8, text[i + 3]) for i in range(len(text) - 3) if text[i] == 0x17}
    check("Normal: GU Sans (28) at 12 dots for 11 points", (28 << 6 | 12, 0) in cards, cards)
    check("the heading: GU Sans 18, bold", (28 << 6 | 18, 0x40) in cards, cards)
    check("accents and quotes as ASCII", b'Gewone tekst met "aanhalingstekens" en een - streep.' in text,
          text[:200])
    check("the right tab as a tab", b"Links\tRechts" in text)
    check("numbered and bulleted list items", b"1. Eerste" in text and b"2. Tweede" in text
          and b"- Punt" in text)
    check("the table row: cells at tabs", b"a\tb\tc" in text)
    check("the page break: a new record after $0C", any(pg.endswith(b"\x0c") for pg in pages[:-1])
          and any(b"Na de pagina" in pg for pg in pages[1:]))
    check("Normal's space after: an empty line", b"\r\r" in text)
    rec = pics.get(64)
    check("the picture: record 64, 2 inches = 160 dots (20 cards), 80 high",
          rec is not None and rec[0] == 20 and rec[1] | rec[2] << 8 == 80, rec[:3] if rec else None)
    check("its graphics escape in the text", bytes([0x10, 20, 80, 0, 64]) in text)
    check("every page starts with a ruler and a font", all(pg[0] == 0x11 and pg[27] == 0x17 for pg in pages))
    check("no warnings", not warns, warns)
    img = os.path.join(OUT, "wordtest.d64")                # through gwtool into an image:
    if os.path.exists(img):                                 # every one of the 127 index
        os.remove(img)                                      # entries used or 00 FF, none
    import subprocess                                       # 00 00 (gwtool.py EMPTY:
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gwtool.py"), "fromdocx", path, img,  # geoWrite
                    "Word test"], check=True, capture_output=True)                                    # 2.x: 1:08)
    from mkappsdnp import Image
    im = Image(img)
    en = im.find("Word test")
    idx = im.block(en[1], en[2])
    pairs = [(idx[2 + 2 * k], idx[3 + 2 * k]) for k in range(127)]
    check("gwtool fromdocx: all 127 index entries exist (none 00 00)", (0, 0) not in pairs,
          [k for k, x in enumerate(pairs) if x == (0, 0)][:5])
    print("docxgw_test: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
