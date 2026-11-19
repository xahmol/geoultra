#!/usr/bin/env python3
"""GU PostScript started with a document (docs/PSW.md, "Use"; step P6)
in VICE, both ways, each file compared with gwtool ps's byte for byte:
- gush: `"/e/GU PostScript" "/b/GeoUTools UK"` (FE_RUNDOC: the application
  on drive E with the document of drive B);
- the desktop: in /b, the cursor on the document, the context menu's
  item 1 (list.s TaskOrMount: "make PostScript", ctxmenu.s MakePS).
GU PostScript finds the document's drive by its disk's name, shows its
options box (OK: A4, real text) and writes; the test answers the file
engine's calls for the Ultimate's paths (as psc64.py). Drive B: a D81
with gush and GeoUTools' manual (GEOUTOOLS_MANUAL).
Usage: tests/print/psent.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "print")
DOC = os.environ.get("GEOUTOOLS_MANUAL", os.path.expanduser("~/git/GeoUTools/docs/geowrite-manual-en.cvt"))
NAME = "GeoUTools UK"
HANDLE = 0x66


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def answer(v, raw):
    """The options box's OK pressed, then the file engine's calls for the
    Ultimate's paths answered until the file is closed: the bytes."""
    ext = v.mem_get(0xC0E4, 0xC0E5)
    entry = (ext[0] | ext[1] << 8) + 30
    v.mem_set(0x033F, b"\x60")
    cid = v.checkpoint(entry, temporary=False)

    def zp(n):
        b = v.mem_get(n, n + 1)
        return b[0] | b[1] << 8

    def string(a):
        return bytes(v.mem_get(a, a + 80)).split(b"\0")[0].decode("latin1")
    for _ in range(12):                         # (the box: up within some seconds)
        v.resume()
        time.sleep(1)
        v.ping()
    v.mem_set(0x3A, bytes([220, 0, 84]))        # OK: a press, run by the loop
    v.mem_set(0x8505, b"\x00")
    v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
    out, log = bytearray(), []
    while True:
        v.events.clear()
        v.resume()
        try:
            v.wait_event(RESP_CHECKPOINT, 90)
        except Exception:
            break
        r = v.regs_get()
        f, y = r["A"], r["Y"]
        ans = None
        if f == 26:
            v.mem_set(zp(4), b"/USB0/GEOULTRA/\0")
            ans = (0, 0)
        elif f == 8 and string(zp(2)).upper().startswith("/USB0"):
            ans = (0, 0)
        elif f == 13 and string(zp(2)).upper().startswith("/USB0"):
            log.append("open " + string(zp(2)))
            ans = (HANDLE, 0) if v.mem_get(6, 6)[0] == 1 else (5, 5)    # (SETTINGS.INI: none)
        elif f == 15 and y == HANDLE:
            n = zp(6)
            if n:
                a = zp(4)
                out += bytes(v.mem_get(a, a + n - 1))
            ans = (0, 0)
        elif f == 4 and y == HANDLE:
            ans = (0, 0)
        if ans:
            v.regs_set({"PC": 0x033F, "A": ans[0], "X": ans[1]})
        if f == 4 and y == HANDLE:
            break
    v.delete_checkpoint(cid)
    v.ping()
    open(raw, "wb").write(out)
    return log


def main():
    os.makedirs(OUT, exist_ok=True)
    subprocess.run(["make", "-s", "all"], cwd=ROOT, check=True, capture_output=True)
    pc = os.path.join(OUT, "psent-pc.ps")
    ok = True
    results = []
    for way in ("gush", "desktop"):
        g = Gush("psent-" + way, 6771 if way == "gush" else 6772, [DOC])
        raw = os.path.join(OUT, "psent-%s.ps" % way)
        try:
            if way == "gush":
                g.start()
                g.run('"/e/GU PostScript" "/b/%s"' % NAME, settle=2)
            else:
                k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
                kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
                v = g.v
                fe = kern["ExtTable"] + 30
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
                time.sleep(5)
                v.ping()
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
                time.sleep(8)
                v.ping()

                def call(routine, a=0, x=0, s=1.0):
                    tick = k["ClockTick"]
                    v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8,
                                               0x8D, 0x9C, 0x84, 0xA9, a, 0xA2, x, 0x4C,
                                               routine & 0xFF, routine >> 8]))
                    v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
                    v.resume()
                    time.sleep(s)
                    v.ping()
                n = int.from_bytes(bytes(v.mem_get(k["count"], k["count"] + 1)), "little")
                at = None
                for i in range(n):
                    call(k["Fetch"], i & 0xFF, i >> 8, s=0.6)
                    if bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0] == NAME.encode():
                        at = i
                ok = ok and at is not None
                print("%s the document in /b" % ("pass" if at is not None else "FAIL"))
                v.mem_set(k["cur"], bytes([at or 0, 0]))
                v.mem_set(0x3A, bytes([200, 0, 60]))
                call(k["Popup"], 0, s=3)                    # the menu: its item 1's text
                g.png("psent-menu")
                print("%s item 1 on the document: make PostScript" % ("pass" if v.mem_get(k["isWrite"], k["isWrite"])[0] == 0x80 else "FAIL"))
                ok = ok and v.mem_get(k["isWrite"], k["isWrite"])[0] == 0x80
                g.click(10, 190, settle=2)                  # (a click outside: the menu away)
                call(k["TaskOrMount"], s=0.2)               # item 1: make PostScript
            log = answer(g.v, raw)
            g.png("psent-" + way)
        finally:
            g.stop()
        disk = g.disk
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gwtool.py"), "ps", disk, pc, NAME],
                       check=True, capture_output=True)
        a = open(raw, "rb").read() if os.path.exists(raw) else b""
        b = open(pc, "rb").read()
        same = a == b and len(a) > 0
        ok = ok and same
        results.append(way)
        print("%s %s: GU PostScript's file and gwtool ps's: %d and %d bytes (%s)" % (
            "pass" if same else "FAIL", way, len(a), len(b), ", ".join(log)))
    print("psent: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
