#!/usr/bin/env python3
"""GeoUltra's desktop in VICE, step D4 (docs/DESKTOP.md): the actions. In
/b (gush's test disk with the files f00-f02): new folder (C=N, a name
typed into the dialog), copy f00 (C=C) and paste it in the folder (C=V);
paste again: the question, YES replaces; cut f01 in /b and paste it in
the folder (moved: /b one entry less); rename it there (C=R, the name
deleted and typed anew); delete it (DEL, YES). Checked through the
desktop's entry count and the names it lists (its entry table read back
by moving the cursor). Screens: build/harness/gush/desktop-d4*.png.
Usage: tests/desktop/d4.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness  # noqa: E402

KEY_DOWN, KEY_UP, KEY_HOME, KEY_LEFT, CR, DEL = 17, 16, 18, 8, 13, 29
C = 0x80
YES_XY = (90, 110)              # the dialog's left icon (DBI_X_0, DBI_Y_2)


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for i in range(3):
        path = os.path.join(OUT, "f%02d" % i)
        open(path, "wb").write(b"text %d\r" % i)
        files.append(path)
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d4", 6639, files)
    check = g.check
    v = g.v

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):
        time.sleep(s)
        v.ping()

    def press(x, y, s=3):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(s)
    try:
        fe = kern["ExtTable"] + 30                          # FE_CD /b, the desktop
        start = harness.TRAMPOLINE
        nm, desk = 0x4F00, 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, nm & 0xFF, 0x85, 0x02, 0xA9, nm >> 8, 0x85, 0x03,
                0xA9, 11, 0x20, fe & 0xFF, fe >> 8,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8]
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.resume()
        settle(5)
        jt = v.mem_get(0xC1C3, 0xC1C5)
        from vicemon import RESP_CHECKPOINT
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        v.mem_set(start, bytes(code))
        v.mem_set(nm, b"/b\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)
        base = word("count")
        check("/b listed: gush and f00-f02", base, 4)
        g.keys([C | ord("n")], settle=2)                    # new folder
        settle(2)
        g.png("desktop-d4-new")
        g.keys("dir1", settle=0.3)
        settle(1)
        g.png("desktop-d4-typed")
        g.keys("\r", settle=0.3)
        settle(4)
        check("C=N dir1: one entry more", word("count"), base + 1)
        g.keys([KEY_HOME, KEY_DOWN], settle=0.3)            # f00 (after gush)
        g.keys([C | ord("c")], settle=1)
        settle(1)
        check("C=C: one name on the clipboard", word("clipCount"), 1)
        g.keys([KEY_HOME] + [KEY_DOWN] * base + [CR], settle=0.3)   # dir1: the last
        settle(4)
        check("into dir1", bytes(v.mem_get(k["path"], k["path"] + 7)), b"/b/dir1\0")
        g.keys([C | ord("v")], settle=1)
        settle(5)
        check("C=V: f00 copied into dir1", word("count"), 1)
        g.keys([C | ord("v")], settle=1)                    # again: replace?
        settle(3)
        g.png("desktop-d4-ask")
        press(*YES_XY, s=5)
        check("pasted again, YES: still one entry", word("count"), 1)
        g.keys([KEY_LEFT], settle=1)                        # /b: cut f01
        settle(3)
        g.keys([KEY_HOME, KEY_DOWN, KEY_DOWN, C | ord("x")], settle=0.5)
        settle(1)
        g.keys([KEY_HOME] + [KEY_DOWN] * base + [CR], settle=0.3)
        settle(4)
        g.keys([C | ord("v")], settle=1)
        settle(5)
        check("C=X, C=V: f01 moved into dir1", word("count"), 2)
        g.keys([KEY_LEFT], settle=1)
        settle(3)
        check("/b: one entry less (f01 gone, dir1 there)", word("count"), base)
        g.keys([KEY_HOME] + [KEY_DOWN] * (base - 1) + [CR], settle=0.3)   # dir1 again
        settle(4)
        g.keys([KEY_HOME, KEY_DOWN, C | ord("r")], settle=1)            # rename f01
        settle(2)
        g.keys([DEL] * 5, settle=0.2)
        g.keys("g01\r", settle=0.3)
        settle(4)
        g.keys([KEY_HOME, KEY_DOWN, C | ord("c")], settle=0.5)          # (its name read
        settle(1)                                                       # back: the clipboard)
        nm = bytes(v.mem_get(k["entryName"], k["entryName"] + 7)).split(b"\0")[0]
        check("C=R: f01 renamed g01", nm, b"g01")
        g.keys([KEY_HOME, KEY_DOWN, DEL], settle=1)                     # delete g01
        settle(3)
        press(*YES_XY, s=5)
        check("DEL, YES: one entry left", word("count"), 1)
        g.png("desktop-d4")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
