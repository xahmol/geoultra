#!/usr/bin/env python3
"""GeoUltra's desktop in VICE (docs/design/DESKTOP.md): favourites.
C=F adds the current folder (/b), not twice; a selected folder (a new
one, the cursor on it) is added as itself; the fifth favourite drops the
first; the sidebar shows them ("FAVOURITES", codes $80-$83) and a click
on one goes there. Without an Ultimate the lists are not saved (the
U64 test, du64.py, checks SETTINGS.INI and RECENT.INI). Screen:
build/harness/gush/desktop-d5.png.
Usage: tests/desktop/d5.py
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
JOY_IDLE, JOY_UP = 0xFF, 0xFE   # port 1's lines (active low; all eight, or the
                                # keyboard scan sees a joystick): the 1351's
                                # right button is "up"


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
    g = Gush("desktop-d5", 6641, files, extra=["-controlport1device", "37"])
    check = g.check
    v = g.v
    v.joyport_set(0, JOY_IDLE)                          # (the simulation: lines
                                                        # as set, so idle first)

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
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
        v.resume()
        settle(s)
    def favs():
        n = v.mem_get(k["counts"], k["counts"])[0]
        out = []
        for i in range(n):
            a = k["favs"] + 64 * i
            out.append(bytes(v.mem_get(a, a + 63)).split(b"\0")[0].decode("latin1"))
        return out

    def side(code):
        """Press on the sidebar line with this code."""
        n = v.mem_get(k["sideCount"], k["sideCount"])[0]
        codes = bytes(v.mem_get(k["sideLetters"], k["sideLetters"] + n - 1))
        top = v.mem_get(k["sideTops"] + codes.index(bytes([code])), k["sideTops"] + codes.index(bytes([code])))[0]
        press(20, top + 4, s=5)

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
        check("no favourites at the start", favs(), [])
        g.keys([C | ord("f")], settle=1)
        settle(3)
        check("C=F: /b", favs(), ["/b"])
        g.keys([C | ord("f")], settle=1)
        settle(3)
        check("C=F again: not twice", favs(), ["/b"])
        g.keys([C | ord("n")], settle=2)                    # a new folder,
        settle(2)                                           # the cursor on it
        g.keys("dir1\r", settle=0.3)
        settle(4)
        g.keys([KEY_HOME, KEY_DOWN], settle=0.3)            # dir1 (sorted: after "..")
        settle(1)
        g.keys([C | ord("f")], settle=1)
        settle(3)
        check("C=F on the selected folder: /b/dir1", favs(), ["/b", "/b/dir1"])
        side(ord("a"))
        check("drive A", here(), "/a")
        g.keys([C | ord("f")], settle=1)
        settle(3)
        side(ord("e"))
        g.keys([C | ord("f")], settle=1)
        settle(3)
        check("four: /b, /b/dir1, /a, /e", favs(), ["/b", "/b/dir1", "/a", "/e"])
        side(ord("b"))
        n = word("count")
        g.keys([KEY_HOME, C | ord("f")], settle=1)          # the cursor on "..":
        settle(3)                                           # /b already there
        g.keys([C | ord("n")], settle=2)
        settle(2)
        g.keys("dir2\r", settle=0.3)
        settle(4)
        g.keys([KEY_HOME, KEY_DOWN, KEY_DOWN], settle=0.3)  # dir2 (after "..", dir1)
        settle(1)
        g.keys([C | ord("f")], settle=1)
        settle(3)
        check("no file written without an Ultimate", word("count"), n + 1)
        check("a fifth drops the first", favs(), ["/b/dir1", "/a", "/e", "/b/dir2"])
        n = v.mem_get(k["sideCount"], k["sideCount"])[0]
        codes = bytes(v.mem_get(k["sideLetters"], k["sideLetters"] + n - 1))
        check("the sidebar's favourite lines", [c for c in codes if c & 0x80], [0x80, 0x81, 0x82, 0x83])
        side(0x80)
        check("a click on the first: there", here(), "/b/dir1")
        g.png("desktop-d5")
        # The toolbar (two lines, the default): a press on a button's middle
        # (its cards from x 8, 16 px apart, 8 px between the groups).
        def button(card):
            press(card * 8 + 8, 23, s=4)
        button(5)                                           # up
        check("toolbar up: /b", here(), "/b")
        n = word("count")
        button(12)                                          # end
        check("toolbar end: the last entry", word("cur"), n - 1)
        button(10)                                          # top
        check("toolbar top: the first", word("cur"), 0)
        button(26)                                          # select all
        bits = bytes(v.mem_get(k["sel"], k["sel"] + 31))
        check("toolbar select all: all but \"..\"", sum(bin(b).count("1") for b in bits), n - 1)
        button(15)                                          # view: list ->
        check("toolbar view: icons", v.mem_get(k["viewMode"], k["viewMode"])[0], 1)
        button(15)                                          # icons -> detailed
        check("toolbar view again: detailed", v.mem_get(k["viewMode"], k["viewMode"])[0], 2)
        button(15)                                          # -> list
        check("toolbar view a third time: list", v.mem_get(k["viewMode"], k["viewMode"])[0], 0)
        button(7)                                           # root
        check("toolbar root: /", here(), "/")
        button(1)                                           # back
        check("toolbar back: /b", here(), "/b")
        button(1)
        check("toolbar back again: /b/dir1", here(), "/b/dir1")
        button(3)                                           # forward
        check("toolbar forward: /b", here(), "/b")
        button(3)
        check("toolbar forward again: /", here(), "/")
        button(3)
        check("toolbar forward at the end: still /", here(), "/")
        button(1)                                           # back to /b, then
        side(ord("a"))                                      # somewhere new:
        button(3)                                           # nothing ahead
        check("after back and a new place: forward does nothing", here(), "/a")
        button(1)
        check("back from there: /b", here(), "/b")
        for i in range(18):                                 # more than 16 places:
            side(ord("a") if i % 2 == 0 else ord("e"))      # the oldest dropped
        check("history full: 16 places, the last current",
              (v.mem_get(k["histLen"], k["histLen"])[0], v.mem_get(k["histPos"], k["histPos"])[0]), (16, 15))
        button(1)
        check("back in a full history: /a", here(), "/a")
        g.png("desktop-d5-toolbar")
        # view > toolbar > one line, off, two lines: the menu's routine
        # (A = the item) called once through appMain, as a menu click runs
        # it: the content's top and the sidebar's first line (under its
        # heading) follow.
        from gushvice import KEY_STUB
        for item, top in ((1, 24), (2, 16), (0, 32)):
            tb, tick = k["Toolbar"], k["ClockTick"]
            v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                       0xA9, item, 0x4C, tb & 0xFF, tb >> 8]))
            v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            v.resume()
            settle(5)
            check("toolbar %d: the content from y %d" % (item, top),
                  (v.mem_get(k["topY"], k["topY"])[0], v.mem_get(k["sideTops"], k["sideTops"])[0]),
                  (top, top + 10))
            if item == 1:
                g.png("desktop-d5-oneline")
        # The clock's longest text (12-hour, "Wed 11 Nov 2026  12:42 pm",
        # 25 characters and its zero) stays in clockText: before the eighth
        # sweep it ran 2 bytes into curName, the theme in use.
        name = bytes(v.mem_get(k["curName"], k["curName"] + 14))
        v.mem_set(0x8516, bytes([26, 11, 11, 12, 42]))     # year .. minutes
        v.mem_set(k["clockMode"], b"\x01")
        tramp = harness.TRAMPOLINE
        cd = k["ClockDraw"]
        v.mem_set(tramp, bytes([0x78, 0x20, cd & 0xFF, cd >> 8, 0x4C, (tramp + 4) & 0xFF, (tramp + 4) >> 8]))
        v.regs_set({"PC": tramp})
        v.resume()
        settle(2)
        text = bytes(v.mem_get(k["clockText"], k["clockText"] + 25)).split(b"\0")[0]
        check("the 12-hour clock's longest text", text, b"Wed 11 Nov 2026  12:42 pm")
        check("the theme's name untouched by it", bytes(v.mem_get(k["curName"], k["curName"] + 14)), name)
        # The right mouse button (the 1351's "up" line on port 1) reaches
        # only guMouse2 ($C0E6): bit 7 clear while held, bit 6 at a press.
        # A running desktop needed: the pointer's driver runs in its IRQ.
        v.mem_set(tramp, bytes([0x58, 0x4C, (tramp + 1) & 0xFF, (tramp + 1) >> 8]))
        v.regs_set({"PC": tramp})                           # (cli, a loop: the
                                                            # IRQ runs the driver)
        left = v.mem_get(0x8505, 0x8505)[0]
        v.mem_set(0xC0E6, b"\x80")                        # (a press seen at the
                                                            # boot, lines not set yet)
        check("guMouse2 at rest", v.mem_get(0xC0E6, 0xC0E6)[0], 0x80)
        v.joyport_set(0, JOY_UP)
        v.resume()
        settle(1)
        check("right button held: bits 7 clear, 6 set", v.mem_get(0xC0E6, 0xC0E6)[0], 0x40)
        v.joyport_set(0, JOY_IDLE)
        v.resume()
        settle(1)
        check("released: bit 7 set, the press kept", v.mem_get(0xC0E6, 0xC0E6)[0], 0xC0)
        check("GEOS's button untouched", v.mem_get(0x8505, 0x8505)[0], left)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
