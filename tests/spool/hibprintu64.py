#!/usr/bin/env python3
"""Printing and the automatic hibernation save on the U64 (docs/design/DESIGN.md
"Print spooler", "Hibernation"; writeback.s, spool.s module 120): a
three-page job for GU PDF A4 is recorded through the spooler (StartPrint,
94 bands, StopPrint per page; the queue paused meanwhile), played, and
an automatic save made due at once (as after 30 s without input). The
save waits while the queue plays (a snapshot taken mid-print, resumed
later, printed the rest again: pages twice, a PDF with wrong offsets);
after the queue ran empty the session is saved, and a reboot resumes it
without printing anything again. Checks: no HIBERNAT.BIN while it plays;
the queue empties; then the file; after the reboot the queue empty and
one new PDF with three pages (mutool, no repair). The PDF is taken away again; the user's HIBERNAT.BIN
and SETTINGS.INI are set aside and put back.
Usage: tests/spool/hibprintu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tests", "print"))
from feu64 import U64, APP_MAIN  # noqa: E402
from prnu64 import page, cards  # noqa: E402

HOME = "/USB0/GEOULTRA/"
KEY_STUB = 0xC0A0
STUB, BAND, WORK, NAME, RES, DONE = 0x5000, 0x5200, 0x5500, 0x50C0, 0x50E0, 0x50FF
PAGES = 3


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

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + str(detail)), flush=True)

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def get(path):
        b = io.BytesIO()
        f = ftp()
        try:
            f.retrbinary("RETR " + path, b.write)
        except ftplib.error_perm:
            return None
        finally:
            f.quit()
        return b.getvalue()

    def put(path, data):
        f = ftp()
        if data is None:
            try:
                f.delete(path)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + path, io.BytesIO(data))
        f.quit()

    def pdfs():
        f = ftp()
        try:
            return set(n.split("/")[-1] for n in f.nlst(HOME + "print") if n.endswith(".pdf"))
        except ftplib.error_perm:
            return set()
        finally:
            f.quit()

    def run(code, timeout=60):
        """CODE once from MainLoop (appMain), then the done flag; X at RES."""
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8,
                0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8] + code
        code += [0x8E, RES & 0xFF, RES >> 8, 0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        u.write(STUB, code)
        u.write(DONE, [0])
        u.write(APP_MAIN, [STUB & 0xFF, STUB >> 8])
        end = time.time() + timeout
        while u.read(DONE, 1)[0] != 1:
            if time.time() > end:
                raise TimeoutError("the call did not return")
            time.sleep(0.2)
        return u.read(RES, 1)[0]

    def r(reg, val):
        return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]

    def jsr(a):
        return [0x20, a & 0xFF, a >> 8]

    def queue():
        """(jobs in the queue, paused) from FE_SPOOL 0."""
        x, a, rr = u.fe(33, y=0)
        return rr[0] & 0xFF, bool(rr[0] & 0x8000)

    jt = {}
    names = [l.split("#")[0].split("=")[0].strip() for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
    for i, n in enumerate(x for x in names if x):
        jt[n] = 0xC100 + 3 * i
    keep = {n: get(HOME + n) for n in ("SETTINGS.INI", "HIBERNAT.BIN")}
    new = []
    try:
        put(HOME + "HIBERNAT.BIN", None)
        u.boot(crt)
        time.sleep(15)
        before = pdfs()
        u.write(NAME, b"GU PDF A4\0")
        x = run(r(0x0E, NAME) + [0xA9, 0, 0x85, 0x02] + jsr(jt["GetFile"]))
        check("GU PDF A4 loaded from drive E", x == 0, "X=%02X" % x)
        run(jsr(0x7900))
        u.fe(33, y=1)                                           # page 1 recorded paused (three
        for p in range(PAGES):                                  # pages do not fit a paused
            img, _ = page(640, 94, "Hibernation test, page %d of %d" % (p + 1, PAGES), False)
            run(r(0x04, WORK) + jsr(0x7903))                    # queue of 112 KB), then
            for band in range(img.height // 8):                 # played, a save made due
                u.write(BAND, cards(img, band))                 # at once (as after 30 s
                run(r(0x02, BAND) + r(0x04, WORK) + r(0x06, 0) + jsr(0x7906), timeout=600)
            run(r(0x02, BAND) + r(0x04, WORK) + jsr(0x7909), timeout=600)   # without input)
            if p == 0:
                u.fe(33, y=2)
                time.sleep(2)
                jobs, paused = queue()
                check("playing: the queue has work, not paused", jobs >= 1 and not paused, (jobs, paused))
                u.write(kern["hibState"], [0xC0])
                u.write(kern["wbPending"], [0x80])
                time.sleep(8)
                check("no save while the queue plays", get(HOME + "HIBERNAT.BIN") is None)
        end = time.time() + 900
        state = None
        while time.time() < end:
            state = queue()
            if state[0] == 0:
                break
            time.sleep(10)
        check("the queue played to the end", state is not None and state[0] == 0, state)
        end = time.time() + 120                                 # then saved (30 s quiet)
        while time.time() < end and get(HOME + "HIBERNAT.BIN") is None:
            time.sleep(10)
        check("then the session saved", get(HOME + "HIBERNAT.BIN") is not None)
        u.boot()                                                # power cycle: resumed
        time.sleep(40)
        state = queue()
        check("resumed: the queue empty, nothing played again", state is not None and state[0] == 0, state)
        time.sleep(10)
        new = sorted(pdfs() - before)
        check("one new PDF", len(new) == 1, new)
        if new:
            local = os.path.join(ROOT, "build", "harness", "print", "hib-" + new[0])
            os.makedirs(os.path.dirname(local), exist_ok=True)
            open(local, "wb").write(get(HOME + "print/" + new[0]) or b"")
            r2 = subprocess.run(["mutool", "info", local], capture_output=True)
            check("its %d pages, no repair" % PAGES, r2.returncode == 0 and b"Pages: %d" % PAGES in r2.stdout
                  and b"repair" not in r2.stderr, (r2.stdout[-200:], r2.stderr[:200]))
            print("  " + local)
    finally:
        for n in new:
            put(HOME + "print/" + n, None)
        for n, d in keep.items():
            put(HOME + n, d)
        check("the user's files back as they were", all(get(HOME + n) == d for n, d in keep.items()))
    print("hibprintu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
