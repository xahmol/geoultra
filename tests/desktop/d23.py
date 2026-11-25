#!/usr/bin/env python3
"""Task switching in VICE (docs/design/DESIGN.md "Task switcher"; src/kernal/
task.s): the desktop in /b; a request (taskReq, as C= + RUN/STOP sets
it) opens the popup: the desktop, new task, close task. "new task": a
fresh desktop in slot 1, moved to /a there; the popup again: back to
task 0, its desktop still in /b (its own RAM); to task 1 again: /a;
"close task" in task 1: back in task 0, the popup's list one shorter;
with tasks=1 "new task" is refused. Each task's legacy REU area checked;
a VLIR file open in task 0 cannot be deleted, renamed or opened in task 1
until task 0 closes it.
Keys go straight into the kernal's key queue (the popup has its own
loop). Screens: build/harness/gush/desktop-d23*.png.
Usage: tests/desktop/d23.py
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
    g = Gush("desktop-d23", 6724, files)
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

        def here():
            return bytes(v.mem_get(k["path"], k["path"] + 20)).split(b"\0")[0].decode("latin1")

        def popup(s=3):
            v.mem_set(kern["taskReq"], b"\x80")
            v.resume()
            settle(s)

        def key(c, s=1.5):
            head = kbyte("qHead")
            v.mem_set(kern["keyQueue"] + head, bytes([c]))
            v.mem_set(kern["qHead"], bytes([(head + 1) & 15]))
            pf = v.mem_get(0x39, 0x39)[0]
            v.mem_set(0x39, bytes([pf | 0x80]))
            v.resume()
            settle(s)

        def run(code, s=4):
            """CODE at $4F40 run from MainLoop (as call()); its result
            byte at $4F3F."""
            v.mem_set(0x4F3F, b"\xEE")
            v.mem_set(0x4F40, bytes(code + [0x60]))
            call(0x4F40, 0, s=s)
            return v.mem_get(0x4F3F, 0x4F3F)[0]

        def r0(addr):
            return [0xA9, addr & 0xFF, 0x85, 0x02, 0xA9, addr >> 8, 0x85, 0x03]

        def r1(addr):
            return [0xA9, addr & 0xFF, 0x85, 0x04, 0xA9, addr >> 8, 0x85, 0x05]

        FE = kern["ExtTable"] + 30
        STX = [0x8E, 0x3F, 0x4F]
        VNAME, VPATH, NEWN, BPATH = 0x7F40, 0x7F60, 0x7F80, 0x7F90   # (free above GEOS's background screen; the desktop's own variables reach $4Fxx)
        v.mem_set(VNAME, b"GU Settings\0")
        v.mem_set(VPATH, b"/b/GU Settings\0")
        v.mem_set(NEWN, b"renamed\0")
        v.mem_set(BPATH, b"/b\0")
        cd_b = r0(VPATH) + [0xA9, 21, 0x20, FE & 0xFF, FE >> 8]    # FE_SELECT: its drive current
        open_v = cd_b + r0(VNAME) + [0x20, 0x74, 0xC2] + STX       # OpenRecordFile
        close_v = [0x20, 0x77, 0xC2] + STX                          # CloseRecordFile
        delete_v = r0(VPATH) + [0xA9, 7, 0x20, FE & 0xFF, FE >> 8] + STX
        rename_v = r0(VPATH) + r1(NEWN) + [0xA9, 10, 0x20, FE & 0xFF, FE >> 8] + STX

        check("task 0, the desktop in /b", (kbyte("taskCur"), here()), (0, "/b"))
        check("task 0 opens the VLIR file", run(open_v), 0)
        popup()
        g.png("desktop-d23-popup")
        check("the popup: the desktop, new task, close task",
              (v.mem_get(P_COUNT, P_COUNT)[0], list(v.mem_get(P_ITEMS, P_ITEMS + 2))), (3, [0, 0x80, 0x81]))
        key(KEY_DOWN)
        key(CR, s=12)                                       # new task
        check("new task: slot 1, a fresh desktop", kbyte("taskCur"), 1)
        size = v.mem_get(0x88C3, 0x88C3)[0]
        check("its own legacy REU area: 192 + size", kbyte("legacyBase"), 192 + size)
        check("task 1: the file open in task 0: delete refused", run(delete_v), 0x52)
        check("rename refused", run(rename_v), 0x52)
        check("OpenRecordFile refused", run(open_v), 0x52)
        v.mem_set(0x4F00, b"/a\0")
        tick, routine = k["ClockTick"], k["Into"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                   0xA9, 0x00, 0xA2, 0x4F, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(6)
        check("task 1 in /a", here(), "/a")
        popup()
        check("the popup: two tasks now", v.mem_get(P_COUNT, P_COUNT)[0], 4)
        key(KEY_UP)
        key(CR, s=8)                                        # to task 0
        g.png("desktop-d23-task0")
        check("back in task 0: still /b, legacy area 192", (kbyte("taskCur"), here(), kbyte("legacyBase")), (0, "/b", 192))
        check("task 0's file still open; closed", (kbyte("indexTS") != 0, run(close_v)), (True, 0))
        popup()
        key(KEY_DOWN)
        key(CR, s=8)                                        # to task 1
        check("to task 1 again: /a", (kbyte("taskCur"), here()), (1, "/a"))
        check("closed in task 0: task 1 opens it", run(open_v), 0)
        run(close_v)
        popup()
        key(KEY_DOWN)
        key(KEY_DOWN)
        key(CR, s=8)                                        # close task (task 1)
        check("close task: back in task 0 (/b)", (kbyte("taskCur"), here()), (0, "/b"))
        popup()
        check("one task left", v.mem_get(P_COUNT, P_COUNT)[0], 3)
        key(KEY_STOP, s=3)
        v.mem_set(kern["taskSlots"], b"\x01")             # tasks=1: no room
        popup()
        key(KEY_DOWN)
        key(CR, s=6)
        check("tasks=1: new task refused, still task 0", (kbyte("taskCur"), here()), (0, "/b"))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
