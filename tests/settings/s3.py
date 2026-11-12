#!/usr/bin/env python3
"""GeoUltra Settings in VICE, step S3 (docs/SETTINGS.md): the System
page. Started from the desktop as in s1.py, with an empty INI text
(VICE): the defaults (full speed, step 15, hibernation 30 s); turbo
off, the stepper down a step (turbo=14), full speed again (the key
taken out); hibernation 1 min; an application added to the slow list
through the file dialog on drive A (its permanent name's start as a
slow= line) and removed again. Screens: build/harness/gush/settings-s3*.png.
Usage: tests/settings/s3.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_SYSTEM = 2
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
    g = Gush("settings-s3", 6693, [])
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
        settle(t)

    def ini():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

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
        press(20, SIDE_TOP + PAGE_SYSTEM * SIDE_ROW + 7)
        check("the System page", sbyte("page"), PAGE_SYSTEM)
        check("defaults: full speed, hibernation 30 s", (sbyte("sel", 0), sbyte("sel", 1)), (0, 2))
        g.png("settings-s3")
        press(216 + 3, ROW_Y - 3)                           # turbo: off
        check("turbo off: turbo=off", ini(), b"[system]\r\nturbo=off\r\n")
        press(150 + 7, STEP_Y - 3)                          # the stepper: -
        check("the stepper down: turbo=14, the row on step", (ini(), sbyte("sel", 0)),
              (b"[system]\r\nturbo=14\r\n", 2))
        press(150 + 3, ROW_Y - 3)                           # full speed
        check("full speed: the key taken out", ini(), b"[system]\r\n")
        press(238 + 3, HIB_Y - 3)                           # hibernation: 1 min
        check("hibernation 1 min: hibernate=60", ini(), b"[system]\r\nhibernate=60\r\n")
        press(BTN_X + 20, LIST_TOP + 6, t=6)                # add...
        g.png("settings-s3-pick")
        press(*OPEN_XY, t=8)                                # Open (the first)
        text = ini()
        lines = text.split(b"\r\n")
        slow = [l for l in lines if l.startswith(b"slow=")]
        check("an application added: one slow= line, a name", (len(slow), len(slow[0]) > 5 if slow else 0),
              (1, True))
        print("  added:", slow)
        g.png("settings-s3-added")
        press(LIST_X + 20, LIST_TOP + 5)                    # its line selected
        press(BTN_X + 20, LIST_TOP + 16 + 6)                # remove
        check("removed again", ini(), b"[system]\r\nhibernate=60\r\n")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
