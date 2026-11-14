#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: copy=newer with dated GEOS files (tree.s
Newer; the user's list, 2026-11-13: d8.py had only plain files, which
have no date). Four GEOS files made from build/cmds/wc.cvt with their
directory dates set: DOC (2020) and DOX (2025) at /b's root; gush puts
DOCNEW (2025) into NEWT as DOC and DOXOLD (2020) into OLDT as DOX (1581
partitions). With copy=newer: DOC (older) cut and pasted into NEWT is
left out (still in /b); DOX (newer) cut and pasted into OLDT replaces
the one there (gone from /b). Checked through the desktop's names.
Usage: tests/desktop/d21.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT  # noqa: E402

KEY_DOWN, KEY_HOME, KEY_LEFT, CR = 17, 18, 8, 13
C = 0x80
COPY_NEWER = 3                  # deskPrefs' copy= (d8.py)


def cvt(name, year):
    """wc.cvt as a GEOS file NAME dated YEAR-06-01 12:00 (its directory
    entry: the name at 3, the date at 23)."""
    d = bytearray(open(os.path.join(ROOT, "build", "cmds", "wc.cvt"), "rb").read())
    d[3:19] = name.encode().ljust(16, b"\xA0")
    d[23:28] = bytes([year % 100, 6, 1, 12, 0])
    path = os.path.join(OUT, name.lower() + ".cvt")
    open(path, "wb").write(bytes(d))
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    files = [cvt("DOC", 2020), cvt("DOCNEW", 2025), cvt("DOX", 2025), cvt("DOXOLD", 2020)]
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d21", 6721, files)
    check = g.check
    v = g.v

    def settle(s=3):
        time.sleep(s)
        v.ping()

    def count():
        return v.mem_get(k["count"], k["count"])[0]

    def path():
        return bytes(v.mem_get(k["path"], k["path"] + 31)).split(b"\0")[0].decode("latin1")

    def press(xy, s=4):
        v.mem_set(0x3A, bytes([xy[0] & 0xFF, xy[0] >> 8, xy[1]]))
        v.mem_set(0x8505, b"\x00")
        v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
        v.resume()
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
        v.resume()
        settle(s)

    def names():
        """The listed names (each read back through C=C: copied)."""
        out = []
        for i in range(count()):
            g.keys([KEY_HOME] + [KEY_DOWN] * i + [C | ord("c")], settle=0.3)
            settle(0.5)
            out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 20)).split(b"\0")[0].decode("latin1"))
        return out

    def cursor_to(name, listed=None):
        """The cursor on the entry of that name (any case); its index. The
        names read here go through C=C (the clipboard): between a copy and
        its paste, pass the list read before."""
        listed = [n.lower() for n in (listed or names())]
        i = listed.index(name.lower())
        g.keys([KEY_HOME] + [KEY_DOWN] * i, settle=0.3)
        settle(0.5)
        return i
    def move(name, folder):
        """NAME cut in /b and pasted into FOLDER; (FOLDER's names, NAME
        still in /b)."""
        here = names()
        cursor_to(name, here)
        g.keys([C | ord("x")], settle=0.5)
        cursor_to(folder, here)
        g.keys([CR], settle=0.5)
        settle(3)
        g.keys([C | ord("v")], settle=0.5)
        settle(10)
        inside = sorted(n.lower() for n in names())
        g.keys([KEY_LEFT], settle=0.5)
        settle(3)
        return inside, name.lower() in [n.lower() for n in names()]
    try:
        g.start()
        for line in ("cd /b", "mkdir -t 8 NEWT", "mkdir -t 8 OLDT", "mv DOCNEW NEWT/DOC",
                     "mv DOXOLD OLDT/DOX"):
            g.run(line, settle=2)
        check("the desktop started", g.runsys("GeoUltra Desktop", wait=12), None)
        if path() == "/":
            g.keys([KEY_HOME, KEY_DOWN, CR], settle=0.5)
            settle(3)
        check("in /b", path(), "/b")
        v.mem_set(k["deskPrefs"], bytes([COPY_NEWER]))
        check("copy=newer: DOC (2020) onto NEWT's DOC (2025): left out, still in /b",
              move("DOC", "NEWT"), (["..", "doc"], True))
        check("copy=newer: DOX (2025) onto OLDT's DOX (2020): replaced, gone from /b",
              move("DOX", "OLDT"), (["..", "dox"], False))
        v.mem_set(k["deskPrefs"], b"\x00")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
