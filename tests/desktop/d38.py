#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: a new folder with two panes (the user's
hand test, 2026-11-21: "making a new folder in the right pane only
refreshes the view of the left pane"). Both panes in /b, the right one
active, C=N "nf1": the right pane lists it, and so does the left one
(the same folder). Then the left pane in /a, the right in /b, C=N "nf2"
in the right: it lists nf2, the left pane /a as it was.
Screens: build/harness/gush/desktop-d38*.png.
Usage: tests/desktop/d38.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

KEY_DOWN, KEY_HOME = 17, 18
VIEW_LIST, VIEW_ICONS = 0, 1
CELL_W, CELL_H, STRIP_LEFT = 40, 32, 312


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for i in range(30):
        path = os.path.join(OUT, "i%02d" % i)
        open(path, "wb").write(b"file %d\r" % i)
        files.append(path)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    files = []
    for name in ("f1", "f2"):
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"pane %s\r" % name.encode())
        files.append(path)
    g = Gush("desktop-d38", 6665, files)
    check = g.check
    v = g.v

    def byte(name):
        return v.mem_get(k[name], k[name])[0]

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):                                # (a monitor command stops
        v.resume()                                  # VICE until the next resume:
        time.sleep(s)                               # run it while waiting)
        v.ping()

    def call(routine, a, s=6):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def press(x, y, s=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
        v.resume()
        settle(s)

    def here():
        return bytes(v.mem_get(k["path"], k["path"] + 15)).split(b"\0")[0].decode("latin1")
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
        def names():
            out = []
            for i in range(word("count")):
                call(k["Fetch"], i, s=0.7)
                out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0].decode("latin1"))
            return out

        def switch():
            g.keys([0x80 | ord(" ")], settle=1)
            settle(3)

        def newfolder(name):
            g.keys([0x80 | ord("n")], settle=2)
            settle(2)
            g.keys(name + "\r", settle=0.3)
            settle(25)                                     # (both panes read again)

        call(k["TwoPanes"], 0, s=8)                            # left /b (the start)
        switch()                                               # right: "/"
        g.keys([KEY_HOME, KEY_DOWN, 13], settle=0.5)           # b
        settle(5)
        check("both panes in /b, the right active", (byte("active"), here()), (1, "/b"))
        newfolder("nf1")
        g.png("desktop-d38")
        check("the right pane lists nf1", "nf1" in names(), True)
        switch()
        check("the left pane (also /b) lists nf1", (here(), "nf1" in names()), ("/b", True))
        g.keys([8], settle=0.5)                                # left: up to /
        settle(4)
        g.keys([KEY_HOME, 13], settle=0.5)                     # a
        settle(20)                                             # (a D81: read, sorted)
        before = word("count")
        switch()
        check("the left pane in /a, the right one active in /b", (byte("active"), here()), (1, "/b"))
        newfolder("nf2")
        g.png("desktop-d38-b")
        check("the right pane (/b) lists nf2", (here(), "nf2" in names()), ("/b", True))
        switch()
        check("the left pane /a as it was", (here(), word("count")), ("/a", before))
    finally:
        g.stop()
    print("d38: %s" % ("all passed" if g.ok else "FAILED"))
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
