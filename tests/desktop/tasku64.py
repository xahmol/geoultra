#!/usr/bin/env python3
"""Task switching on the U64 (docs/DESIGN.md "Task switcher"; src/
kernal/task.s, modules 95-98): the desktop as task 0 marks a RAM byte
($0334) $AA; a request (taskReq, as C= + RUN/STOP sets it) opens the
popup; "new task": slot 1, a fresh desktop, the byte set to $BB there;
back to task 0: $AA again (its own 64 KB from the REU); to task 1: $BB;
"close task" in task 1: task 0 again, the popup's list one shorter.
Keys go straight into the kernal's key queue. The user's HIBERNAT.BIN
is set aside first (a fresh start) and put back.
Usage: tests/desktop/tasku64.py [build/geoultra64.crt]
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
HOME = "/USB0/GEOULTRA"


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    u = U64()
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

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

    f = ftplib.FTP(u.ip, timeout=60)
    f.login()
    hib = io.BytesIO()
    try:
        f.retrbinary("RETR " + HOME + "/HIBERNAT.BIN", hib.write)
        f.delete(HOME + "/HIBERNAT.BIN")
        hib = hib.getvalue()
    except ftplib.error_perm:
        hib = None
    f.quit()
    try:
        u.boot(crt)
        time.sleep(20)
        u.write(MARK, b"\xAA")
        check("task 0", kbyte("taskCur"), 0)
        popup()
        check("the popup: the desktop, new task, close task", u.read(P_COUNT, 1)[0], 3)
        key(KEY_DOWN)
        key(CR, t=12)
        check("new task: slot 1", kbyte("taskCur"), 1)
        u.write(MARK, b"\xBB")
        popup()
        check("the popup: two tasks", u.read(P_COUNT, 1)[0], 4)
        key(KEY_UP)
        key(CR, t=6)
        check("back to task 0: its own RAM", (kbyte("taskCur"), u.read(MARK, 1)[0]), (0, 0xAA))
        popup()
        key(KEY_DOWN)
        key(CR, t=6)
        check("to task 1: its own RAM", (kbyte("taskCur"), u.read(MARK, 1)[0]), (1, 0xBB))
        popup()
        key(KEY_DOWN)
        key(KEY_DOWN)
        key(CR, t=6)
        check("close task: task 0 again", (kbyte("taskCur"), u.read(MARK, 1)[0]), (0, 0xAA))
        popup()
        check("one task left", u.read(P_COUNT, 1)[0], 3)
        key(KEY_STOP, t=3)
    finally:
        if hib is not None:
            f = ftplib.FTP(u.ip, timeout=60)
            f.login()
            f.storbinary("STOR " + HOME + "/HIBERNAT.BIN", io.BytesIO(hib))
            f.quit()
    print("tasku64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
