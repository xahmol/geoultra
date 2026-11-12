#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: folders copied, moved and deleted with
everything in them (src/desktop/tree.s; the user, 2026-11-11). gush
makes the tree on drive B (1581 partitions, as tests/gush/g8.py): SRC
with ONE, TWO and SUB/THREE, and an empty OUTER. Then the desktop:
SRC copied into OUTER (the whole tree there); pasted again: "Replace
it?" answered "Yes to all" (no second question, still the same tree);
OUTER deleted: "Delete everything in it?" answered Yes (gone); SRC cut
and pasted into a new folder MOVED (moved: gone from /b, its tree in
MOVED). Then copy= and delete= (the user, 2026-11-12): ONE moved into
a folder that has one, with skip, only newer (plain files: no date) and
replace; TWO deleted without the question. Checked through the
desktop's entry counts and names.
Usage: tests/desktop/d8.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT  # noqa: E402

KEY_DOWN, KEY_HOME, KEY_LEFT, CR, DEL = 17, 18, 8, 13, 29
C = 0x80
YES_XY = (90, 110)              # the question's left button
YES_ALL_XY = (150, 110)         # its "Yes to all" (cards 8-15 of the dialog)


def main():
    os.makedirs(OUT, exist_ok=True)
    paths = []
    for name, data in (("one", b"first\r"), ("two", b"second\r"), ("three", b"third\r")):
        path = os.path.join(OUT, name)
        open(path, "wb").write(data)
        paths.append(path)
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d8", 6643, paths)
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
    try:
        g.start()
        for line in ("cd /b", "mkdir -t 8 SRC", "cp ONE TWO SRC", "mkdir -t 3 SRC/SUB",
                     "cp THREE SRC/SUB", "mkdir -t 12 OUTER"):     # (as tests/gush/g8.py)
            g.run(line, settle=2)
        check("the desktop started", g.runsys("GeoUltra Desktop", wait=12), None)
        if path() == "/":                                    # ("/": a, b, e)
            g.keys([KEY_HOME, KEY_DOWN, CR], settle=0.5)
            settle(3)
        check("in /b", path(), "/b")
        here = names()
        cursor_to("SRC", here)                               # copy SRC
        g.keys([C | ord("c")], settle=0.5)
        cursor_to("OUTER", here)
        g.keys([CR], settle=0.5)
        settle(3)
        check("into OUTER", path(), "/b/OUTER")
        g.keys([C | ord("v")], settle=0.5)
        settle(15)
        check("SRC copied into OUTER", sorted(n.lower() for n in names()), ["..", "src"])
        cursor_to("SRC")
        g.keys([CR], settle=0.5)
        settle(3)
        check("its files and SUB", sorted(n.lower() for n in names()), ["..", "one", "sub", "two"])
        cursor_to("SUB")
        g.keys([CR], settle=0.5)
        settle(3)
        check("SUB's file", sorted(n.lower() for n in names()), ["..", "three"])
        for _ in range(3):                                   # up to /b, SRC copied
            g.keys([KEY_LEFT], settle=0.5)                   # again (the names read
            settle(3)                                        # went through C=C)
        here = names()
        cursor_to("SRC", here)
        g.keys([C | ord("c")], settle=0.5)
        cursor_to("OUTER", here)
        g.keys([CR], settle=0.5)
        settle(3)
        check("back in OUTER", path(), "/b/OUTER")
        g.keys([C | ord("v")], settle=0.5)                   # again: Replace it?
        settle(6)
        g.png("desktop-d8-replace")
        press(YES_ALL_XY, s=15)                              # Yes to all
        g.png("desktop-d8-after")
        check("pasted again, Yes to all: the same tree", sorted(n.lower() for n in names()), ["..", "src"])
        g.keys([KEY_LEFT], settle=0.5)                       # /b: delete OUTER
        settle(3)
        before = count()
        cursor_to("OUTER")
        g.keys([DEL], settle=0.5)
        settle(3)
        press(YES_XY, s=4)                                   # "Delete the selection?"
        g.png("desktop-d8-everything")
        press(YES_XY, s=15)                                  # "Delete everything in it?"
        check("OUTER deleted with its tree", (count(), "outer" in [n.lower() for n in names()]),
              (before - 1, False))
        g.keys([C | ord("n")], settle=1)                     # a folder MOVED
        settle(2)
        g.keys("MOVED", settle=0.3)
        g.keys("\r", settle=0.3)
        settle(4)
        here = names()
        cursor_to("SRC", here)                               # cut SRC, paste in MOVED
        g.keys([C | ord("x")], settle=0.5)
        cursor_to("MOVED", here)
        g.keys([CR], settle=0.5)
        settle(3)
        g.keys([C | ord("v")], settle=0.5)
        settle(20)
        check("SRC moved into MOVED", sorted(n.lower() for n in names()), ["..", "src"])
        g.keys([KEY_LEFT], settle=0.5)
        settle(3)
        check("SRC gone from /b", "src" in [n.lower() for n in names()], False)
        # copy= and delete= (deskPrefs; the user, 2026-11-12, after
        # GeoDesk64): ONE moved from /b into MOVED/SRC, which has a ONE.
        def move_one(prefs):
            v.mem_set(k["deskPrefs"], bytes([prefs]))
            here = names()
            cursor_to("ONE", here)
            g.keys([C | ord("x")], settle=0.5)
            cursor_to("MOVED", here)
            g.keys([CR], settle=0.5)
            settle(3)
            g.keys([KEY_HOME, KEY_DOWN, CR], settle=0.5)    # SRC (.., SRC: no
            settle(3)                                        # C=C before the paste)
            g.keys([C | ord("v")], settle=0.5)
            settle(10)
            inside = sorted(n.lower() for n in names())
            g.keys([KEY_LEFT], settle=0.5)
            settle(3)
            g.keys([KEY_LEFT], settle=0.5)
            settle(3)
            return inside, "one" in [n.lower() for n in names()]
        check("copy=skip: no question, ONE left in /b", move_one(2),
              (["..", "one", "sub", "two"], True))
        check("copy=newer: plain files have no date: left as well", move_one(3),
              (["..", "one", "sub", "two"], True))
        check("copy=replace: no question, ONE moved (gone from /b)", move_one(1),
              (["..", "one", "sub", "two"], False))
        v.mem_set(k["deskPrefs"], bytes([4]))               # delete=now
        before = count()
        cursor_to("TWO")
        g.keys([DEL], settle=0.5)
        settle(6)
        check("delete=now: TWO deleted without a question",
              (count(), "two" in [n.lower() for n in names()]), (before - 1, False))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
