#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the refusal notice (docs/DESIGN.md "Serial
number", step S5; the user's decisions of 2026-11-19). An application
"geoWrite" shows geoWrite 2.1's refusal box ("Please reboot your
system..." through DBVARSTR, as its showError; mist64/geowrite): the
kernal notes its class (serials.s module 127). The desktop started
then asks at its first tick "geoWrite refused to run (its serial). Set
it in Settings?"; YES starts GU Settings from drive E on its Serials
page, which asks "Serial for geoWrite (4 hex):"; 58B5 typed: [serials]
geoWrite=58B5 in its text (VICE: not saved). Screens:
build/harness/gush/desktop-d35-*.png.
Usage: tests/desktop/d35.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

DLG_X, DLG_Y = 64, 32           # GEOS's default box position
SETTINGS_PAGE_SERIALS = 9


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    s = labels(os.path.join(ROOT, "build", "settings", "settings.lbl"))
    jt = harness.jumptab()
    g = Gush("desktop-d35", 6735, [])
    check, v = g.check, g.v

    def settle(t):
        time.sleep(t)
        v.ping()

    def press(x, y, t=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(0.5)
        v.mem_set(0x8505, b"\x80")
        v.resume()
        settle(t)

    def settings_text():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

    try:
        v.resume()
        settle(5)
        jtc = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jtc[1] | jtc[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        # "geoWrite" refuses: its box (left open; the CPU stopped)
        v.mem_set(kern["taskName"], b"geoWrite".ljust(12, b" ") + b"\0")
        v.mem_set(0x4F00, b"\x18Please reboot your system\x16\x50\x00\x40using the same GEOS disk\0")
        v.mem_set(0x4E80, bytes([0x81, 12, 16, 16, 0x0C, 1, 17, 72, 0]))
        dlg = jt["DoDlgBox"]
        start = harness.TRAMPOLINE
        v.mem_set(start, bytes([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x00, 0x85, 0x0C, 0xA9, 0x4F, 0x85, 0x0D,
                                0xA9, 0x80, 0x85, 0x02, 0xA9, 0x4E, 0x85, 0x03, 0x20, dlg & 0xFF, dlg >> 8,
                                0x4C, 0, 0]))
        v.regs_set({"PC": start})
        v.resume()
        settle(3)
        g.png("desktop-d35-refusal")
        # the application gone, the desktop started (as s9: FE_RUNSYS)
        fe = kern["ExtTable"] + 30
        desk = 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8]
        end = start + len(code)
        v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(12)
        g.png("desktop-d35-question")
        press(DLG_X + 8 + 20, DLG_Y + 72 + 8, t=15)      # YES: GU Settings
        g.png("desktop-d35-settings")
        page = v.mem_get(s["page"], s["page"])[0]
        check("GU Settings on its Serials page", page, SETTINGS_PAGE_SERIALS)
        g.queue("58B5\r", settle=4)
        g.png("desktop-d35-added")
        check("[serials] geoWrite=58B5 in its text", b"geoWrite=58B5\r\n" in settings_text(), True)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
