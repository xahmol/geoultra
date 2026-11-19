#!/usr/bin/env python3
"""The desktop's tasks in VICE (docs/design/DESIGN.md "Task switcher";
src/desktop/list.s TaskWords, TaskPress; side.s TaskOpen; actions.s
OpenTask, TaskTake; src/kernal/task.s FE_TASK): the status line shows
"1 task" at its right end; "open in new task" on GU Settings (cursor
on it, OpenTask) starts a task that runs Settings; back in task 0 the
status line says "2 tasks"; a click on it opens the popup; task 1
closed from there. Screens: build/harness/gush/desktop-d24*.png.
Usage: tests/desktop/d24.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

KEY_UP, KEY_DOWN, CR, KEY_STOP = 16, 17, 13, 22
P_COUNT, P_ITEMS = 0x9FF0, 0x9FF5
SIZES = {"a": 1, "bb": 5, "ccc": 3}                 # blocks (254 bytes each)


def main():
    os.makedirs(OUT, exist_ok=True)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    files = [os.path.join(ROOT, "build", "settings", "settings.cvt")]   # a VLIR file
    for name, blocks in SIZES.items():
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"x" * (254 * blocks - 10))
        files.append(path)
    g = Gush("desktop-d24", 6725, files)
    check = g.check
    v = g.v

    def byte(name):
        return v.mem_get(k[name], k[name])[0]

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

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

    def press(x, y, s=5):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(s)

    def names():
        """The list's names in order, through the desktop's Fetch (A/X =
        the entry), called from appMain as ClockTick's stand-in."""
        out = []
        tick, fetch = k["ClockTick"], k["Fetch"]
        for i in range(word("count")):
            v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                       0x84, 0xA9, i & 0xFF, 0xA2, i >> 8, 0x4C, fetch & 0xFF, fetch >> 8]))
            v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            v.resume()
            settle(0.6)
            out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0].decode("latin1"))
        return out

    def mine():
        return [n for n in names() if n.lower() in SIZES]

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

        def kbyte(name):
            return v.mem_get(kern[name], kern[name])[0]

        def dword(name):
            return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

        def key(c, s=1.5):
            head = kbyte("qHead")
            v.mem_set(kern["keyQueue"] + head, bytes([c]))
            v.mem_set(kern["qHead"], bytes([(head + 1) & 15]))
            pf = v.mem_get(0x39, 0x39)[0]
            v.mem_set(0x39, bytes([pf | 0x80]))
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

        def name_at(i):
            fetch = k["Fetch"]
            v.mem_set(0x5F80, bytes([0xA9, i & 0xFF, 0xA2, i >> 8, 0x20, fetch & 0xFF, fetch >> 8, 0x60]))
            call(0x5F80, 0, s=1)
            return bytes(v.mem_get(k["entryName"], k["entryName"] + 20)).split(b"\0")[0]

        v.mem_set(0x3A, bytes([200, 0, 60]))                # the context menu
        call(k["Popup"], 0, s=3)
        g.png("desktop-d24-ctx")
        key(27, s=2)
        press(40, 6, s=3)                                   # the file menu
        g.png("desktop-d24-file")
        key(27, s=2)
        press(300, 100, s=2)
        g.png("desktop-d24-one")
        check("one task: the indicator shown", dword("taskX") != 0xFFFF, True)
        n = dword("count")
        idx = [i for i in range(n) if name_at(i) == b"GU Settings"]
        check("GU Settings in /b", len(idx), 1)
        v.mem_set(k["cur"], bytes([idx[0], 0]))
        call(k["OpenTask"], 0, s=14)
        check("open in new task: task 1 runs Settings",
              (kbyte("taskCur"), bytes(v.mem_get(kern["taskName"], kern["taskName"] + 10)).split(b"\0")[0][:11]),
              (1, b"GU Settings"))
        g.png("desktop-d24-settings")
        v.mem_set(kern["taskReq"], b"\x80")
        v.resume()
        settle(3)
        key(KEY_UP)
        key(CR, s=8)
        check("back in task 0: the desktop", kbyte("taskCur"), 0)
        g.png("desktop-d24-two")
        x = dword("taskX")
        check("the indicator placed", x < 320, True)
        press(x + 3, 196, s=4)
        check("a click on it: the popup with two tasks", v.mem_get(P_COUNT, P_COUNT)[0], 4)
        g.png("desktop-d24-popup")
        key(KEY_DOWN)
        key(CR, s=8)                                        # to task 1
        v.mem_set(kern["taskReq"], b"\x80")
        v.resume()
        settle(3)
        key(KEY_DOWN)
        key(KEY_DOWN)
        key(CR, s=8)                                        # close task 1
        check("task 1 closed: task 0", kbyte("taskCur"), 0)
        g.png("desktop-d24-closed")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
