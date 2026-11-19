#!/usr/bin/env python3
"""The screenshots of the sample brochure and quick start guide
(samples/*.toml, tools/gwgen.py), taken in VICE (headless) from the
current build: drive B a sample D81 made here (the sample letter, the
GeoUltra logo as a geoPaint picture), drive E GeoUltra's system drive.
Only GeoUltra's own content is shown (no Berkeley icons): drive A, the
user's GEOS disk the harness boots with, is not opened.
Writes samples/shots/*.png (the C64's 320 x 200, in its colours), which
are committed so the documents build without VICE.
Usage: samples/shots.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness, apprun, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402

SHOTS = os.path.join(ROOT, "samples", "shots")
BUILD = os.path.join(ROOT, "build", "samples")
VIEW_LIST, VIEW_ICONS = 0, 1
SIDE_TOP, SIDE_ROW = 16, 16             # (src/settings/settings.inc)
PAGE_THEME, PAGE_PRINTING = 0, 8


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def sample_disk():
    """build/samples/sample.d81 for drive B: the letter and the logo
    (samples/build.py)."""
    build.splash()
    if os.path.exists(build.CVT):
        import shutil
        shutil.rmtree(build.CVT)
    build.gwgen("letter")
    build.logo_picture()
    return build.disk(os.path.join(BUILD, "sample.d81"), ["Letter", "GeoUltra logo"])


def main():
    os.makedirs(SHOTS, exist_ok=True)
    disk = sample_disk()
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    g = Gush("samples", 6750, disk=disk)
    v = g.v

    def settle(t):
        time.sleep(t)
        v.ping()

    def call(routine, a=0, x=0, s=4):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0xA2, x, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def press(x, y, s=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(0.5)
        v.mem_set(0x8505, b"\x80")
        v.resume()
        settle(s)

    def shot(name):
        path = os.path.join(SHOTS, name + ".png")
        apprun.render(v.mem_get(0xA000, 0xBF3F), v.mem_get(0x8C00, 0x8FE7), path)
        from PIL import Image
        Image.open(path).resize((320, 200), Image.NEAREST).save(path)
        print(path)

    def entry(name):
        n = int.from_bytes(bytes(v.mem_get(k["count"], k["count"] + 1)), "little")
        for i in range(n):
            call(k["Fetch"], i & 0xFF, i >> 8, s=0.5)
            if bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0] == name:
                return i
        return None

    try:
        v.resume()
        settle(5)
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        fe = kern["ExtTable"] + 30                  # FE_CD /e, then the desktop
        start, nm, desk = harness.TRAMPOLINE, 0x4F00, 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, nm & 0xFF, 0x85, 0x02, 0xA9, nm >> 8, 0x85, 0x03,
                0xA9, 11, 0x20, fe & 0xFF, fe >> 8,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8]
        end = start + len(code)
        v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
        v.mem_set(nm, b"/e\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(10)
        call(k["Drive"], ord("e"))
        call(k["View"], VIEW_LIST)
        shot("desktop-list")
        call(k["View"], VIEW_ICONS, s=8)
        shot("desktop-icons")
        call(k["View"], VIEW_LIST)
        call(k["Drive"], ord("b"))
        call(k["TwoPanes"], 0, s=8)
        call(k["PaneSwitch"], 0, s=4)               # the right pane: drive E
        call(k["Drive"], ord("e"))
        call(k["PaneSwitch"], 0, s=4)
        shot("two-panes")
        call(k["TwoPanes"], 0, s=20)                # (one list: the desktop restarts)
        call(k["Gush"], 0, s=10)
        # a few short commands, so every prompt stays on the screen
        g.queue("cd /b\r", settle=4)
        g.queue("ls -l\r", settle=4)
        g.queue("df\r", settle=4)
        g.queue("free\r", settle=4)
        g.queue("date\r", settle=4)
        shot("gush")
        g.queue("exit\r", settle=10)
        call(k["Settings"], 0, s=10)
        shot("settings-desktop")
        press(20, SIDE_TOP + PAGE_THEME * SIDE_ROW + 7, s=5)
        shot("settings-theme")
        press(20, SIDE_TOP + PAGE_PRINTING * SIDE_ROW + 7, s=5)
        shot("settings-printing")
        press(190, 186, s=12)                       # OK: back to the desktop
        call(k["Drive"], ord("b"))
        at = entry(b"Letter")
        if at is not None:
            v.mem_set(k["cur"], bytes([at, 0]))
            v.mem_set(0x3A, bytes([200, 0, 60]))
            call(k["Popup"], 0, s=3)
            shot("context-menu")
            press(250, 170, s=2)                    # (closed: a click outside,
                                                    # in the list's empty part)
        v.mem_set(kern["taskReq"], b"\x80")
        v.resume()
        settle(3)
        shot("task-list")
    finally:
        g.stop()


if __name__ == "__main__":
    main()
