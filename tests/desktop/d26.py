#!/usr/bin/env python3
"""The desktop's print queue in VICE (docs/DESIGN.md "Print spooler",
src/desktop/spool.s; the user's decisions of 2026-11-15): from
the desktop, the queue paused (FE_SPOOL) and three jobs printed through
tests/spool/logdrv.s (a printer driver that logs its calls, from drive
B): the menu bar shows "print paused"; geos > print queue: three lines
(the desktop's jobs under its name, a page each, the first paused, the others
waiting); cancel on the second line: it shows cancelled; resume: the
jobs play while the window is open, which then shows "No print jobs."
(it follows the queue); the driver saw jobs 1 and 3 only; close: the
indicator gone. Screens: build/harness/gush/desktop-d26*.png.
Usage: tests/desktop/d26.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

FE_SPOOL = 33
WIN_L, WIN_TOP, ROW0, ROW_STEP, BTN_Y = 48, 24, 22, 18, 122


def logdrv():
    o, b, c = (os.path.join(OUT, "logdrv" + x) for x in (".o", ".bin", ".cvt"))
    subprocess.run(["ca65", "-o", o, os.path.join(ROOT, "tests", "spool", "logdrv.s")], check=True)
    subprocess.run(["ld65", "-C", os.path.join(ROOT, "tests", "spool", "logdrv.cfg"), "-o", b, o], check=True)
    subprocess.run([sys.executable, os.path.expanduser("~/git/geos-oscar64/tools/geosapp.py"),
                    os.path.join(ROOT, "tests", "spool", "logdrv.toml"), b, c], check=True, capture_output=True)
    return c


def main():
    os.makedirs(OUT, exist_ok=True)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d26", 6727, [logdrv()])
    check = g.check
    v = g.v
    jt = harness.jumptab()

    def settle(s=3):
        time.sleep(s)
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
        time.sleep(0.5)
        v.ping()
        v.mem_set(0x8505, b"\x80")
        v.resume()
        settle(s)

    def text(at, n=48):
        raw = bytes(v.mem_get(at, at + n)).split(b"\0\0")[0]
        out, i = bytearray(), 0                     # GOTOX x (3 bytes) as "|"
        while i < len(raw) and raw[i]:
            if raw[i] == 20:
                out += b"|"
                i += 3
            elif raw[i] < 32:
                i += 1
            else:
                out.append(raw[i])
                i += 1
        return bytes(out)

    def jsr(a):
        a = jt.get(a, a) if isinstance(a, str) else a
        return [0x20, a & 0xFF, a >> 8]

    def r(reg, val):
        return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]

    def fe(sub):
        return [0xA9, FE_SPOOL, 0xA0, sub] + jsr(kern["FileEngine"])

    try:
        fecd = kern["ExtTable"] + 30                        # FE_CD /b, the desktop
        start = harness.TRAMPOLINE
        nm, desk = 0x4F80, 0x4F90
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, nm & 0xFF, 0x85, 0x02, 0xA9, nm >> 8, 0x85, 0x03,
                0xA9, 11, 0x20, fecd & 0xFF, fecd >> 8,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fecd & 0xFF, fecd >> 8]
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.resume()
        settle(5)
        mj = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(mj[1] | mj[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        v.mem_set(start, bytes(code))
        v.mem_set(nm, b"/b\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)

        # from the desktop (appMain): the driver loaded, the queue paused,
        # three jobs of a page printed
        run, name = 0x7F40, 0x7FE0
        job = (jsr(0x7900) + r(0x04, 0x0400) + jsr(0x7903)
               + r(0x02, 0x0400) + r(0x04, 0x0400) + r(0x06, 0) + jsr(0x7906)
               + r(0x02, 0x0400) + r(0x04, 0x0400) + jsr(0x7909))
        head = ([0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
                + r(0x0E, name) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile") + [0x8E, 0xF0, 0x02]
                + fe(1) + [0xA9, 3, 0x8D, 0xF8, 0x02])        # three jobs: $02F8
        loop = run + len(head)
        prog = head + job + [0xCE, 0xF8, 0x02, 0xF0, 0x03, 0x4C, loop & 0xFF, loop >> 8, 0x60]
        assert run + len(prog) <= name, len(prog)
        v.mem_set(0x0280, bytes(0x70))
        v.mem_set(name, b"GU Logdrv\0")
        v.mem_set(run, bytes(prog))
        v.mem_set(0x2F0, b"\xEE")
        call(run, 0, s=6)
        check("the driver loaded (GetFile from the desktop)", v.mem_get(0x2F0, 0x2F0)[0], 0)
        check("paused: the driver called for nothing yet", v.mem_get(0x0280, 0x0280)[0], 0)
        settle(3)
        g.png("desktop-d26-paused")
        shown = (v.mem_get(k["spShown"], k["spShown"])[0], text(k["qText"], 16))
        check("the menu bar's indicator (the long form, or the short one when the date is wide)",
              shown in ((1, b"print paused"), (1, b"paused")), True)
        call(k["MQueue"], 0, s=5)
        g.png("desktop-d26-window")
        check("the window's title", text(k["title"], 32), b"Print queue|paused")
        rows = [text(k["rowText"] + 44 * i, 44) for i in range(3)]
        check("its lines: the jobs, a page each, paused, waiting", rows,
              [b"1|GU Desktop|1 page|paused", b"2|GU Desktop|1 page|waiting", b"3|GU Desktop|1 page|waiting"])
        press(WIN_L + 20, WIN_TOP + ROW0 + ROW_STEP + 8, s=6)        # cancel line 2
        g.png("desktop-d26-cancel")
        check("cancel on line 2: it shows cancelled", text(k["rowText"] + 44, 44), b"2|GU Desktop|1 page|cancelled")
        press(WIN_L + 24, WIN_TOP + BTN_Y + 8, s=10)                 # resume
        g.png("desktop-d26-resumed")
        check("resumed: the window follows the queue (empty)", v.mem_get(k["qCount"], k["qCount"])[0], 0)
        check("and the indicator with it (gone)", v.mem_get(k["spShown"], k["spShown"])[0], 0)
        log = v.mem_get(0x0280, 0x0288)
        check("the driver saw jobs 1 and 3 (init, start, a row, stop each)", log.hex(), "080102030401020304")
        press(WIN_L + 21 * 8 + 24, WIN_TOP + BTN_Y + 8, s=5)         # close
        settle(2)
        g.png("desktop-d26-closed")
        check("closed: the indicator gone", v.mem_get(k["spShown"], k["spShown"])[0], 0)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
