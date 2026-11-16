#!/usr/bin/env python3
"""tools/mkgeosfont.py (docs/DESIGN.md "Fonts"): GU Serif built from TeX
Gyre Termes (the system's fonts-texgyre) with a hand fix file: the CVT's
header (FONT, VLIR, ID 27, the (ID << 6 | size) list, the records'
sizes), a font image per size with height = size, the widths from the
metrics (design advance x size / 1000, rounded), and a hand-fixed glyph
in place. With --pcf when the X11 75-dpi Adobe bitmaps are given in
GU_PCF (a "%d" pattern), else the outline only.
Usage: tests/fonts/mkgeosfont_test.py
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TERMES = "/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyretermes-regular.otf"
SIZES = [9, 10, 12, 14, 18, 24]
B = 254


def main():
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    if not os.path.exists(TERMES):
        print("skip: TeX Gyre Termes not installed (fonts-texgyre)")
        sys.exit(0)
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "f.cvt")
        args = [sys.executable, os.path.join(ROOT, "tools", "mkgeosfont.py"), TERMES, "27", "GU Serif",
                ",".join(map(str, SIZES)), out, "--fix", os.path.join(ROOT, "tools", "fonts", "guserif_fix.py")]
        if os.environ.get("GU_PCF"):
            args += ["--pcf", os.environ["GU_PCF"], "--pcf-sizes", "10,12,14"]
        subprocess.run(args, check=True, capture_output=True)
        c = open(out, "rb").read()
        hdr = b"\0\0" + c[B:2 * B]                  # (the CVT keeps bytes 2-255)
        table = c[2 * B:3 * B]
        check("signature: a VLIR CVT", c[30:58], b"PRG formatted GEOS file V1.0")
        check("header: USR, FONT, VLIR", tuple(hdr[0x44:0x47]), (0x83, 8, 1))
        check("header: font ID 27", hdr[0x80] | hdr[0x81] << 8, 27)
        ids = [hdr[0x82 + 2 * i] | hdr[0x83 + 2 * i] << 8 for i in range(len(SIZES))]
        check("header: the (ID << 6 | size) list", ids, [27 << 6 | s for s in SIZES])
        pos, recs = 3 * B, {}
        for n in range(127):
            k, last = table[2 * n], table[2 * n + 1]
            if k:
                ln = (k - 1) * B + last - 1
                recs[n] = c[pos:pos + ln]
                pos += k * B
        check("records: one per size, numbered by size", sorted(recs), SIZES)
        lens = [hdr[0x61 + 2 * i] | hdr[0x62 + 2 * i] << 8 for i in range(len(SIZES))]
        check("header: the records' sizes", lens, [len(recs[s]) for s in SIZES])
        from PIL import ImageFont
        design = ImageFont.truetype(TERMES, 1000)
        for s in SIZES:
            r = recs[s]
            io_ = r[4] | r[5] << 8
            ix = [r[io_ + 2 * i] | r[io_ + 2 * i + 1] << 8 for i in range(97)]
            widths = [ix[i + 1] - ix[i] for i in range(95)]
            want = [max(1, round(design.getlength(chr(32 + i)) * s / 1000)) for i in range(95)]
            check("size %d: height, widths from the metrics" % s, (r[3], widths == want), (s, True))
        r = recs[10]                                # the hand-fixed "t" at 10
        io_, bo, sw = r[4] | r[5] << 8, r[6] | r[7] << 8, r[1] | r[2] << 8
        x0 = r[io_ + 2 * (ord("t") - 32)] | r[io_ + 2 * (ord("t") - 32) + 1] << 8
        row2 = "".join("#" if r[bo + 2 * sw + ((x0 + x) >> 3)] >> (7 - ((x0 + x) & 7)) & 1 else "."
                       for x in range(3))
        check("size 10: the hand-fixed \"t\"'s crossbar", row2, "###")
    print("mkgeosfont: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
