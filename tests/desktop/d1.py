#!/usr/bin/env python3
"""GeoUltra's desktop in VICE (docs/design/DESKTOP.md): started from
drive E (FE_RUNSYS) on the gush test setup (drive A the GEOS 2.0 disk,
drive B a D81). Checked from its state in memory (build/desktop/
desktop.lbl): drawing on both screens, RecoverVector set, the path and
the entries of "/" listed, and the geos menu's desk accessories with
drive E's GU Folder among them. Then EnterDeskTop with the kernal's
ownDesk flag set (SETTINGS.INI [system] desktop=geoultra; set here
directly, VICE has no stick) starts it, not GEOS 2.0's deskTop.
Screens: build/harness/gush/desktop-d1*.png.
Usage: tests/desktop/d1.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    k = labels()
    g = Gush("desktop-d1", 6632)
    check = g.check
    try:
        check("started from drive E (FE_RUNSYS does not return)", g.runsys("GeoUltra Desktop", wait=6), None)
        v = g.v
        check("both screens drawn on", v.mem_get(0x2F, 0x2F)[0] & 0xC0, 0xC0)
        check("RecoverVector: the desktop's Recover (bitmap and colours)",
              bytes(v.mem_get(0x84B1, 0x84B2)), bytes([k["Recover"] & 0xFF, k["Recover"] >> 8]))
        check("the path: /", bytes(v.mem_get(k["path"], k["path"] + 1)), b"/\0")
        check("the entries of /: a, b, e", v.mem_get(k["count"], k["count"])[0], 3)
        g.png("desktop-d1")
        v.mem_set(0x3A, bytes([10, 0, 5]))                  # a press on "geos"
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        time.sleep(3)
        v.ping()
        n = v.mem_get(k["daCount"], k["daCount"])[0]
        names = [bytes(v.mem_get(k["daNames"] + 17 * i, k["daNames"] + 17 * i + 16)).split(b"\0")[0].decode("latin1")
                 for i in range(n)]
        check("the geos menu: drive E's GU Folder among the accessories", "GU Folder" in names, True)
        g.png("desktop-d1-geos")
    finally:
        g.stop()
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g2 = Gush("desktop-d1-enter", 6634)
    try:
        v = g2.v
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)                      # up to MainLoop
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        v.mem_set(kern["ownDesk"], b"\x80")
        v.regs_set({"PC": 0xC22C})                           # EnterDeskTop
        v.resume()
        time.sleep(15)
        v.ping()
        code = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:16]
        g2.check("EnterDeskTop with desktop=geoultra: GeoUltra's desktop", bytes(v.mem_get(0x0400, 0x040F)), code)
        g2.png("desktop-d1-enter")
    finally:
        g2.stop()
    g.ok = g.ok and g2.ok
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
