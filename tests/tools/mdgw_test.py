#!/usr/bin/env python3
"""tools/mdgw.py and tools/gwmd.py through gwtool (docs/GWTOOL_MANUAL.md,
"Markdown"): a Markdown text with headings (ATX and underlined), bold,
italic, code, a link, a bulleted and a numbered list, a block quote, a
code block, a table, a page break, a rule and a picture (PNG) made into
a geoWrite document in a D64 (`frommd`); its records checked (fonts and
sizes: GU Sans 24 bold for level 1, 12 for the body, GU Mono for code;
the list prefixes; the table row at tabs; the page break; the picture
record and escape; all 127 index entries); then written back as Markdown
(`md`): headings, emphasis, list, table, page break and picture link
back. No VICE.
Usage: tests/tools/mdgw_test.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from mkappsdnp import Image  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "tools", "md")
TOOL = [sys.executable, os.path.join(ROOT, "tools", "gwtool.py")]
TEXT = """---
title: front matter, skipped
---
# A heading

Plain text with **bold**, *italic*, `code` and a [link](https://example.org).
A second line of the same paragraph.

Second level
------------

- one
- two

1. first
2. second

> Quoted words.

```
10 PRINT "HELLO"
```

| Name | Size |
|------|-----:|
| a    | 1    |
| b    | 2    |

<!-- pagebreak -->

After the break.

***

![circle](pic.png)
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    from PIL import Image as PImage, ImageDraw
    im = PImage.new("L", (160, 80), 255)
    ImageDraw.Draw(im).ellipse((10, 10, 150, 70), outline=0, width=4)
    im.save(os.path.join(OUT, "pic.png"))
    src = os.path.join(OUT, "test.md")
    open(src, "w").write(TEXT)
    img = os.path.join(OUT, "test.d64")
    if os.path.exists(img):
        os.remove(img)
    r = subprocess.run(TOOL + ["frommd", src, img, "Md test"], capture_output=True, text=True)
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    check("frommd runs, no warnings", r.returncode == 0 and "warning" not in r.stdout, r.stdout + r.stderr)
    d = Image(img)
    en = d.find("Md test")
    gf = d.gfile(en)
    pages = [x for x in gf.records[:61] if x not in (None, "end")]
    text = b"".join(pages)
    cards = {(text[i + 1] | text[i + 2] << 8, text[i + 3]) for i in range(len(text) - 3) if text[i] == 0x17}
    check("heading 1: GU Sans 24, bold", (28 << 6 | 24, 0x40) in cards, cards)
    check("heading 2 (underlined form): GU Sans 18, bold", (28 << 6 | 18, 0x40) in cards, cards)
    check("body GU Sans 12; bold, italic", {(28 << 6 | 12, 0), (28 << 6 | 12, 0x40), (28 << 6 | 12, 0x10)} <= cards,
          cards)
    check("code in GU Mono", any(fid >> 6 == 30 for fid, _ in cards), cards)
    check("front matter skipped", b"front matter" not in text)
    check("paragraph lines joined, the link's address kept",
          b"link (https://example.org). A second line" in text, text[:300])
    check("list prefixes", b"- one" in text and b"1. first" in text and b"2. second" in text)
    check("table row at tabs", b"a\t1" in text and b"Name" in text)
    check("the code block's line", b'10 PRINT "HELLO"' in text)
    check("page break: a page ends with $0C", any(p.rstrip(b"\r").endswith(b"\x0c") for p in pages[:-1]))
    pic = gf.records[64] if len(gf.records) > 64 else None
    check("picture: record 64, 20 cards, 80 high", pic not in (None, "end") and pic[0] == 20
          and pic[1] | pic[2] << 8 == 80, pic[:3] if pic else None)
    idx = d.block(en[1], en[2])
    pairs = [(idx[2 + 2 * k], idx[3 + 2 * k]) for k in range(127)]
    check("all 127 index entries exist", (0, 0) not in pairs)
    back = os.path.join(OUT, "back.md")
    r = subprocess.run(TOOL + ["md", img, back, "Md test"], capture_output=True, text=True)
    md = open(back).read() if os.path.exists(back) else ""
    check("md runs", r.returncode == 0, r.stdout + r.stderr)
    check("back: headings", "# A heading" in md and "## Second level" in md, md[:400])
    check("back: bold, italic, code", "**bold**" in md and "*italic*" in md and "`code`" in md, md[:400])
    check("back: lists, apart", "- one\n- two\n\n1. first\n2. second" in md, md)
    check("back: code block, rule", '```\n10 PRINT "HELLO"\n```' in md and "\n***\n" in md, md)
    check("back: table", re.search(r"\| \*\*Name\*\* \| \*\*Size\*\* \|\n\|", md) is not None
          and "| a | 1 |" in md, md)
    check("back: page break", "<!-- pagebreak -->" in md)
    check("back: picture file and link", "![picture 1](back_files/picture1.png)" in md
          and os.path.exists(os.path.join(OUT, "back_files", "picture1.png")))
    print("mdgw_test: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
