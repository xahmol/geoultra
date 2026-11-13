#!/usr/bin/env python3
"""GeoUltra Settings in VICE, step S3b (docs/SETTINGS.md): the Time
page. Started from the desktop as in s1.py, with an empty INI text
(VICE): the defaults (no server, UTC+00:00, summer time off); the zone
four quarters up (offset=3600, UTC+01:00) and below UTC (offset=-900);
summer time EU (summer=eu); the server from the list (time.google.com)
and as custom, typed in the input dialog (ntp=); the date and time typed (GEOS's clock set), a wrong one
refused; "now" without a network (VICE): its failure said.
Screens: build/harness/gush/settings-s3b*.png.
Usage: tests/settings/s3b.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_TIME = 3
SERVER_Y, NOW_Y = 36, 45
LIST_Y = SERVER_Y + 4            # ptime.s LIST_TOP + 1: the first row's top
ZONE_Y, SUMMER_Y, DATE_Y = 80, 100, 124
MINUS_XY, PLUS_XY = (156, 76), (236, 76)
OK_XY = (90, 110)
KEY_DELETE = 29
ROW_Y, STEP_Y = 36, 54
HIB_Y = 171 - 8
LIST_TOP, LIST_X = 64, 150
BTN_X = 150 + 104 + 8
OPEN_XY = (224, 44)
SIDE_TOP, SIDE_ROW = 20, 14
Y0, DY, X1, X2 = 16 + 20, 18, 150, 212
CANCEL_XY = (27 * 8 + 24, 188)
YES_XY = (90, 110)


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    s = labels(os.path.join(ROOT, "build", "settings", "settings.lbl"))
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    g = Gush("settings-s3b", 6699, [])
    check = g.check
    v = g.v

    def sbyte(name, off=0):
        return v.mem_get(s[name] + off, s[name] + off)[0]

    def settle(t=3):
        time.sleep(t)
        v.ping()

    def call(routine, a, t=6):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(t)

    def press(x, y, t=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
        v.resume()
        settle(t)

    def ini():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

    def zone_text():
        return None

    try:
        fe = kern["ExtTable"] + 30                          # the desktop, as d13
        start = harness.TRAMPOLINE
        desk = 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
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
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)
        call(k["Settings"], 0, t=8)
        press(20, SIDE_TOP + PAGE_TIME * SIDE_ROW + 7)
        check("the Time page", sbyte("page"), PAGE_TIME)
        check("defaults: summer time off, an empty text", (sbyte("sel", 0), ini()), (1, b""))
        g.png("settings-s3b")
        v.mem_set(0x8516, bytes([26, 12, 31, 23, 30]))      # 2026-12-31 23:30: a year's end
        for _ in range(4):
            press(*PLUS_XY, t=2)
        check("the zone 4 quarters up: offset=3600", ini(), b"[time]\r\noffset=3600\r\n")
        check("the clock with it: an hour on, into the next year (2027-01-01; VICE's warp moves "
              "the minutes on meanwhile)", list(v.mem_get(0x8516, 0x8518)), [27, 1, 1])
        for _ in range(5):
            press(*MINUS_XY, t=2)
        check("5 down: below UTC, offset=-900", ini(), b"[time]\r\noffset=-900\r\n")
        check("5 quarters back: into 2026-12-31 again", list(v.mem_get(0x8516, 0x8518)), [26, 12, 31])
        g.png("settings-s3b-zone")
        press(150 + 3, SUMMER_Y - 3)
        check("summer time EU: summer=eu", ini(), b"[time]\r\noffset=-900\r\nsummer=eu\r\n")
        press(200, SERVER_Y - 3, t=3)                       # the server's box: the list
        g.png("settings-s3b-list")
        press(200, LIST_Y + 1 * 12 + 6, t=4)                # time.google.com
        check("the list: time.google.com picked: ntp=time.google.com", ini(),
              b"[time]\r\noffset=-900\r\nsummer=eu\r\nntp=time.google.com\r\n")
        press(200, SERVER_Y - 3, t=3)
        press(200, LIST_Y + 4 * 12 + 6, t=4)                # custom...: typed
        g.keys([KEY_DELETE] * 20, settle=0.1)
        g.keys("pool.ntp.org\r", settle=0.3)
        settle(3)
        check("custom: the server typed: ntp=pool.ntp.org", ini(),
              b"[time]\r\noffset=-900\r\nsummer=eu\r\nntp=pool.ntp.org\r\n")
        g.png("settings-s3b-server")
        press(270, DATE_Y - 3, t=4)                         # set...
        g.png("settings-s3b-ask")
        g.keys([KEY_DELETE] * 20, settle=0.1)
        g.keys("2027-01-02 03:04\r", settle=0.3)
        settle(3)
        check("the date typed: GEOS's clock 27-01-02 03:04",
              bytes(v.mem_get(0x8516, 0x851A)), bytes([27, 1, 2, 3, 4]))
        g.png("settings-s3b-date")
        press(270, DATE_Y - 3, t=4)
        g.keys([KEY_DELETE] * 20, settle=0.1)
        g.keys("2027-13-02 03:04\r", settle=0.3)
        settle(3)
        g.png("settings-s3b-baddate")
        check("a 13th month refused: the clock kept", bytes(v.mem_get(0x8516, 0x8518)), bytes([27, 1, 2]))
        press(*OK_XY, t=3)
        press(160, NOW_Y + 5, t=12)                         # now: no network
        g.png("settings-s3b-now")
        press(*OK_XY, t=3)
        check("now without a network: said, the page still there", sbyte("page"), PAGE_TIME)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
