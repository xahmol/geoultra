#!/usr/bin/env python3
"""tools/gwps.py (gwtool ps) without VICE: geoWrite's line rules on made
pages in the system font (its widths: tools/fonts/system9.py) and the
PostScript ghostscript reads. tests/print/psref.py checks whole pages
against geoWrite itself.
Usage: tests/tools/gwps_test.py
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gwps                                      # noqa: E402

ok = True


def check(title, got, want):
    global ok
    good = got == want
    ok = ok and good
    print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))


def ruler(left, right, para=None, align=0, spacing=0, tabs=()):
    t = list(tabs) + [right] * (8 - len(tabs))
    b = bytearray([0x11]) + left.to_bytes(2, "little") + right.to_bytes(2, "little")
    for x in t:
        b += x.to_bytes(2, "little")
    b += (left if para is None else para).to_bytes(2, "little") + bytes([align | spacing << 2, 0, 0, 0])
    return bytes(b)


def card(fid=9, style=0):
    return bytes([0x17, fid & 0xFF, fid >> 8, style])


def lines(rec, fonts):
    return gwps.layout(rec, fonts, {"ruler": None, "fid": 9, "style": 0})


def text(ln):
    return "".join(chr(p[2]) for p in ln.pieces)


def main():
    fonts = gwps.Fonts([])
    f = fonts.sys
    w = lambda s: sum(f.width(ord(c)) for c in s)
    words = "aaaa bbbb cccc dddd"
    right = 10 + w("aaaa bbbb c")               # "cccc" does not fit
    ls = lines(ruler(10, right) + card() + words.encode() + b"\r", fonts)
    check("break after the last space", [text(ln) for ln in ls], ["aaaa bbbb", "cccc dddd"])
    check("the next line at the left margin", ls[1].pieces[0][0], 10)
    ls = lines(ruler(10, 10 + w("abc")) + card() + b"abcdefg\r", fonts)
    check("a word longer than the line: cut at the character", [text(ln) for ln in ls], ["abc", "def", "g"])
    ls = lines(ruler(10, 400, para=30) + card() + b"one two\r", fonts)
    check("a paragraph's first line at the paragraph margin", ls[0].pieces[0][0], 30)
    ls = lines(ruler(10, 400, tabs=(100,)) + card() + b"a\tb\r", fonts)
    check("TAB to the stop", ls[0].pieces[1][0], 100)
    ls = lines(ruler(10, 400, tabs=(100 | 0x8000,)) + card() + b"a\t12.5\r", fonts)
    check("decimal stop: the full stop at the stop", ls[0].pieces[1][0] + w("12"), 100)
    ls = lines(ruler(0, 200, align=1) + card() + b"ab\r", fonts)
    check("centred", ls[0].pieces[0][0], (200 - w("ab")) // 2)
    ls = lines(ruler(0, 200, align=2) + card() + b"ab\r", fonts)
    check("right", ls[0].pieces[-1][0] + ls[0].pieces[-1][1], 200)
    right = w("aaaa bbbb c")
    ls = lines(ruler(0, right, align=3) + card() + b"aaaa bbbb cccc\r", fonts)
    check("justified: the line to the right margin", ls[0].pieces[-1][0] + ls[0].pieces[-1][1], right)
    check("justified: not the paragraph's last line", ls[1].pieces[0][0], 0)
    ls = lines(ruler(0, 400, spacing=2) + card() + b"x\r", fonts)
    check("double spacing: twice the height and its leading", ls[0].height, 2 * (f.height + gwps.LEADING))
    ls = lines(ruler(0, 400) + card(style=gwps.BOLD) + b"ab\r", fonts)
    check("bold: one dot wider a character", ls[0].pieces[1][0], w("a") + 1)
    width, rows = f.cell(ord("m"), gwps.UNDERLINE)
    check("underline: the row below the baseline, the cell but its last column",
          rows[f.base + 1], [1] * (width - 1) + [0])
    with tempfile.TemporaryDirectory() as d:
        page = (ruler(80, 560) + card() + b"Plain " + card(style=gwps.BOLD) + b"bold\r"
                + card(27 << 6 | 12) + b"Times text\r")
        ps = os.path.join(d, "t.ps")
        gwps.write(ps, [page], None, None, {}, gwps.Fonts([]))
        src = open(ps).read()
        check("ID 27 as Times-Roman, real text", "/Times-Roman 12 SF" in src, True)
        check("the system font as a Type 3 font", "/G0_9_0 1 SF" in src and "/G0_9_64 1 SF" in src, True)
        r = subprocess.run(["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=nullpage", ps],
                           capture_output=True, text=True)
        check("ghostscript reads it without an error", (r.returncode, r.stdout + r.stderr), (0, ""))
    print("gwps_test: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
