#!/usr/bin/env python3
"""The print queue through hibernation on the U64 (docs/DESIGN.md "Print
spooler"; src/kernal/hibernate.s module 115): a paused queue with
records is written straight into the REU (its header in bank 1, marked
data in bank 27 and in the first extra bank: SETTINGS.INI [system]
spool=256 for the test, the user's file kept and put back); a suspend: the file has banks 27-28 and the extra
banks too. The REU's copies wiped, a reboot: the session resumes with
the header and the data as they were. Paused, nothing is played. At
the end an empty queue is left. The user's HIBERNAT.BIN is set aside
first and put back, as is SETTINGS.INI.
Usage: tests/spool/hibspoolu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402

KEY_STUB = 0xC0A0
HOME = "/USB0/GEOULTRA/"
RUN, HDR, PAT, OUT, ZERO = 0x7F40, 0x7FE0, 0x7A00, 0x7B00, 0x7D00
# a paused queue: "GUS2", head $00:4100, tail $00:4000, one job, paused
HEADER = b"GUS2" + bytes([0, 0x41, 0, 0, 0x40, 0, 1, 0, 0x80, 0, 0, 0, 0, 0, 0])
EMPTY = b"GUS2" + bytes([0, 0x40, 0, 0, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
PATTERN = bytes((i * 11 + 7) & 0xFF for i in range(256))


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

    def call(routine, t=10):
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(t)

    def op(c64, reu, length, bank, cmd):
        """SysRAMOp: r0 C64, r1 REU, r2 length, r3L bank, Y the command."""
        sys_op = kern["SysRAMOp"]
        return ([0xA9, c64 & 0xFF, 0x85, 0x02, 0xA9, c64 >> 8, 0x85, 0x03,
                 0xA9, reu & 0xFF, 0x85, 0x04, 0xA9, reu >> 8, 0x85, 0x05,
                 0xA9, length & 0xFF, 0x85, 0x06, 0xA9, length >> 8, 0x85, 0x07,
                 0xA9, bank, 0x85, 0x08, 0xA0, cmd, 0x20, sys_op & 0xFF, sys_op >> 8])

    def run(ops, t=4):
        code = sum(ops, []) + [0x60]
        assert RUN + len(code) <= HDR, len(code)
        u.write(RUN, bytes(code))
        call(RUN, t)

    keep = get("HIBERNAT.BIN")
    keep_ini = get("SETTINGS.INI")
    ini = (keep_ini or b"").replace(b"\r\n", b"\n").split(b"\n")
    ini = [l for l in ini if not l.startswith(b"spool=")]
    if b"[system]" not in ini:
        ini.append(b"[system]")
    ini.insert(ini.index(b"[system]") + 1, b"spool=256")
    try:
        put("HIBERNAT.BIN", None)
        put("SETTINGS.INI", b"\r\n".join(ini))
        u.boot(crt)
        time.sleep(20)
        extra = u.read(kern["spoolExtra"], 1)[0]
        base = u.read(kern["spoolBase"], 1)[0]
        legacy = u.read(0x88C3, 1)[0]
        check("spool=256: two extra banks", extra, 2)
        u.write(HDR, HEADER)
        u.write(PAT, PATTERN)
        u.write(ZERO, bytes(256))
        put_ops = [op(HDR, 0xE700, 19, 1, 0x90), op(PAT, 0x4000, 256, 27, 0x90)]
        if extra:
            put_ops.append(op(PAT, 0x0100, 256, base, 0x90))
        run(put_ops)
        call(kern["HibSuspend"], t=30)
        check("the file: system, scrap store, a task bank, swap, a legacy area, the queue's banks",
              size("HIBERNAT.BIN"), (1 + 2 + 1 + 1 + legacy + 2 + extra) * 65536)
        wipe = [op(ZERO, 0x4000, 256, 27, 0x90)]
        if extra:
            wipe.append(op(ZERO, 0x0100, 256, base, 0x90))
        run(wipe)
        u.boot()
        time.sleep(30)
        check("the file used once: gone", size("HIBERNAT.BIN"), None)
        u.write(OUT, bytes(512))
        get_ops = [op(OUT + 0x200, 0xE700, 19, 1, 0x91), op(OUT, 0x4000, 256, 27, 0x91)]
        if extra:
            get_ops.append(op(OUT + 0x100, 0x0100, 256, base, 0x91))
        run(get_ops)
        check("resumed: the queue's header (paused, its records)", u.read(OUT + 0x200, 19), HEADER)
        check("resumed: bank 27's data", u.read(OUT, 256), PATTERN)
        if extra:
            check("resumed: the first extra bank's data", u.read(OUT + 0x100, 256), PATTERN)
    finally:
        try:
            u.write(HDR, EMPTY)                         # an empty queue left
            run([op(HDR, 0xE700, 19, 1, 0x90)])
        finally:
            put("HIBERNAT.BIN", keep)
            put("SETTINGS.INI", keep_ini)
    print("hibspoolu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
