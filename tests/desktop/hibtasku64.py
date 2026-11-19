#!/usr/bin/env python3
"""Hibernation with two tasks on the U64 (docs/design/DESIGN.md "Task switcher",
src/kernal/hibernate.s, hibresume.s, task.s): task 0 marks a RAM
byte ($0334) $AA, a new task (1) marks it $BB and suspends (HibSuspend):
the file holds the system bank, both task banks, the swap bank and both
legacy REU areas, the print queue's banks 27-28 (its queue empty: not its
extra banks). After a reboot the session resumes in task 1 ($BB,
two tasks in the popup); a switch to task 0 finds $AA. Then task 1
closed and the same with the one task left. The user's
HIBERNAT.BIN is set aside first and put back.
Usage: tests/desktop/hibtasku64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402

KEY_UP, KEY_DOWN, CR, KEY_STOP = 16, 17, 13, 22
P_COUNT = 0x9FF0
MARK = 0x0334
KEY_STUB = 0xC0A0
HOME = "/USB0/GEOULTRA/"


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    u = U64()
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def get(name):
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + HOME + name, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def size(name):
        f = ftp()
        try:
            return f.size(HOME + name)
        except ftplib.error_perm:
            return None
        finally:
            f.quit()

    def put(name, data):
        f = ftp()
        if data is None:
            try:
                f.delete(HOME + name)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + HOME + name, io.BytesIO(data))
        f.quit()

    def kbyte(name):
        return u.read(kern[name], 1)[0]

    def popup(t=3):
        u.write(kern["taskReq"], b"\x80")
        time.sleep(t)

    def key(c, t=1.5):
        head = kbyte("qHead")
        u.write(kern["keyQueue"] + head, bytes([c]))
        u.write(kern["qHead"], bytes([(head + 1) & 15]))
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x80]))
        time.sleep(t)

    def call(routine, t=10):
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(t)

    keep = get("HIBERNAT.BIN")
    try:
        put("HIBERNAT.BIN", None)
        u.boot(crt)
        time.sleep(20)
        u.write(MARK, b"\xAA")
        popup()
        key(KEY_DOWN)
        key(CR, t=12)
        check("new task: slot 1", kbyte("taskCur"), 1)
        u.write(MARK, b"\xBB")
        legacy = u.read(0x88C3, 1)[0]
        call(kern["HibSuspend"], t=25)
        check("the file: system, scrap store, 2 task banks, swap, 2 legacy areas, print queue",
              size("HIBERNAT.BIN"), (1 + 2 + 2 + 1 + 2 * legacy + 2) * 65536)
        u.boot()
        time.sleep(25)
        check("resumed in task 1, its RAM", (kbyte("taskCur"), u.read(MARK, 1)[0]), (1, 0xBB))
        check("the file used once: gone", size("HIBERNAT.BIN"), None)
        popup()
        check("the popup: two tasks", u.read(P_COUNT, 1)[0], 4)
        key(KEY_UP)
        key(CR, t=6)
        check("task 0 back from the file: its RAM, its legacy area",
              (kbyte("taskCur"), u.read(MARK, 1)[0], kbyte("legacyBase")), (0, 0xAA, 192))
        popup()
        key(KEY_DOWN)
        key(CR, t=6)
        popup()
        key(KEY_DOWN)
        key(KEY_DOWN)
        key(CR, t=6)
        check("task 1 closed: task 0", kbyte("taskCur"), 0)
        u.write(MARK, b"\xCC")                          # one task: as before
        call(kern["HibSuspend"], t=20)
        check("one task: system, scrap store, 1 task bank, swap, 1 legacy area, print queue",
              size("HIBERNAT.BIN"), (1 + 2 + 1 + 1 + legacy + 2) * 65536)
        u.boot()
        time.sleep(25)
        check("resumed: task 0, its RAM", (kbyte("taskCur"), u.read(MARK, 1)[0]), (0, 0xCC))
    finally:
        put("HIBERNAT.BIN", keep)
    print("hibtasku64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
