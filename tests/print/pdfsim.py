#!/usr/bin/env python3
"""GU PDF (src/printer/pdf.s) on a 6502 emulator (py65), without VICE:
the driver and its scripts (pdfdata) as built, its file engine calls
answered here (FE_OPEN, FE_READ, FE_WRITE, FE_CLOSE, FE_HOME, FE_MKDIR,
FE_SPOOL 5): InitForPrint, then PAGES pages of BANDS bands of
pseudo-random dots each. Checks: the path, the calls, mutool reads the
PDF without a repair and finds the pages, each page's image is the rows
as sent with the rest blank. Fast (seconds), for working on the driver;
tests/print/pdf1.py runs it in VICE. docs/design/DESIGN.md "Printing".
Both drivers, GU PDF A4 and GU PDF Letter (their paper checked).
Usage: tests/print/pdfsim.py [PAGES] [BANDS]
"""
import os
import random
import re
import subprocess
import sys

from py65.devices.mpu6502 import MPU

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "print")
WORK, DATA, NAME = 0x4000, 0x5000, b"geoWrite    "
GUEXT, ENTRY = 0xC0E4, 0xC800          # the extension table's address and the engine
DORAMOP = 0xC2D4


def labels(paper="a4"):
    subprocess.run(["make", "-s", "build/printer/pdf%s.cvt" % paper, "build/printer/pdf%sdata.cvt" % paper],
                   cwd=ROOT, check=True, capture_output=True)
    obj = os.path.join(ROOT, "build", "printer", "pdf%s.o" % paper)
    lbl = os.path.join(OUT, "pdf.lbl")
    subprocess.run(["ld65", "-C", os.path.join(ROOT, "src", "printer", "printer.cfg"), "-o", os.devnull,
                    "-Ln", lbl, obj], check=True)
    out = {}
    for line in open(lbl):
        p = line.split()
        out[p[2].lstrip(".")] = int(p[1], 16)
    return out


class Machine:
    def __init__(self, paper="a4"):
        self.cpu = MPU()
        self.mem = self.cpu.memory
        self.paper = paper
        drv = open(os.path.join(ROOT, "build", "printer", "pdf%s.bin" % paper), "rb").read()
        self.mem[0x7900:0x7900 + len(drv)] = drv
        self.data = open(os.path.join(ROOT, "build", "printer", "pdf%sdata.bin" % paper), "rb").read()
        self.mem[GUEXT] = (ENTRY - 30) & 0xFF
        self.mem[GUEXT + 1] = (ENTRY - 30) >> 8
        self.mem[ENTRY] = 0x60                     # (rts: answered in Python)
        self.mem[DORAMOP] = 0x60                   # DoRAMOp, answered in Python
        self.reu = {}
        self.mem[0x8100:0x8500] = [(i * 7 + 3) & 0xFF for i in range(0x400)]  # the program's
        self.mem[0x8516:0x851C] = [26, 11, 16, 14, 5, 9]    # 2026-11-16 14:05:09
        self.files, self.handles, self.log = {}, {}, []

    def ramop(self):
        m, c = self.mem, self.cpu
        c64, reu, n, bank = self.word(2), self.word(4), self.word(6), m[8]
        a = (bank << 16) + reu
        if c.y == 0x90:
            for i in range(n):
                self.reu[a + i] = m[c64 + i]
        elif c.y == 0x91:
            for i in range(n):
                m[c64 + i] = self.reu.get(a + i, 0)
        self.log.append("ramop %02X %04X %02X:%04X %04X" % (c.y, c64, bank, reu, n))

    def kept(self):
        return list(self.mem[0x8100:0x8500]) == [(i * 7 + 3) & 0xFF for i in range(0x400)]

    def word(self, a):
        return self.mem[a] | self.mem[a + 1] << 8

    def string(self, a):
        s = bytearray()
        while self.mem[a]:
            s.append(self.mem[a])
            a += 1
        return s.decode("latin1")

    def engine(self):
        c, m = self.cpu, self.mem
        f, y = c.a, c.y
        r0, r1, r2 = self.word(2), self.word(4), self.word(6)
        x, a = 0, c.a
        if f == 13:                                # FE_OPEN
            path, mode = self.string(r0), m[6]
            self.log.append("open %s %d" % (path, mode))
            h = len(self.handles) + 1
            self.handles[h] = [path, 0]
            if mode == 1:
                self.files[path] = bytearray()
            elif path == {"a4": "/e/GU PDF A4 data",           # (drive E's names
                          "letter": "/e/GU PDF Ltr data"}[self.paper]:   # since 2026-11-26)
                self.files[path] = bytearray(self.data)
            a = h
        elif f == 14:                              # FE_READ
            path, at = self.handles[y]
            chunk = self.files[path][at:at + r2]
            m[r1:r1 + len(chunk)] = chunk
            self.handles[y][1] += len(chunk)
            m[6], m[7] = len(chunk) & 0xFF, len(chunk) >> 8
        elif f == 15:                              # FE_WRITE
            self.files[self.handles[y][0]] += bytes(m[r1:r1 + r2])
        elif f == 4:                               # FE_CLOSE
            self.handles.pop(y, None)
        elif f == 26:                              # FE_HOME
            home = b"/USB0/GEOULTRA/\0"
            m[r1:r1 + len(home)] = home
        elif f == 8:                               # FE_MKDIR
            self.log.append("mkdir " + self.string(r0))
        elif f == 33 and y == 5:                   # FE_SPOOL 5
            m[r0:r0 + 13] = NAME + bytes(13 - len(NAME))
        else:
            raise RuntimeError("engine %d" % f)
        for i in range(2, 0x22):                   # (the engine destroys r0-r15)
            if i not in (6, 7) or f != 14:
                m[i] = 0xEE
        c.a, c.x = a, x

    def call(self, addr, regs=None, limit=20000000):
        c, m = self.cpu, self.mem
        for k, v in (regs or {}).items():
            m[k], m[k + 1] = v & 0xFF, v >> 8
        c.sp = 0xFD
        m[0x1FF], m[0x1FE] = 0xFF, 0xFE           # rts to $FFFF: done
        c.pc = addr
        n = 0
        while c.pc != 0xFFFF:
            if c.pc == ENTRY:
                self.engine()
            elif c.pc == DORAMOP:
                self.ramop()
            c.step()
            n += 1
            if n > limit:
                raise RuntimeError("runaway at %04X" % c.pc)
        return c.x


def main():
    pages = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    bands = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    os.makedirs(OUT, exist_ok=True)
    ok = run("a4", pages, bands, "0 0 595 842")
    ok = run("letter", pages, bands, "0 0 612 792") and ok
    print("pdfsim: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


def run(paper, pages, bands, media):
    print("GU PDF %s:" % paper)
    labels(paper)
    m = Machine(paper)
    rnd = random.Random(94)
    data = bytes(rnd.getrandbits(8) for _ in range(bands * 640))
    m.mem[DATA:DATA + len(data)] = data
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + str(detail)))

    m.call(0x7900)
    xs = []
    for p in range(pages):
        xs.append(m.call(0x7903, {4: WORK}))
        for b in range(bands):
            m.call(0x7906, {2: DATA + b * 640, 4: WORK, 6: 0})
        xs.append(m.call(0x7909, {2: DATA, 4: WORK}))
    check("StartPrint and StopPrint X = 0", xs == [0] * (2 * pages), xs)
    outs = [p for p in m.files if p.startswith("/USB0")]
    path = outs[0] if outs else ""
    check("the file: GEOULTRA/print/geoWrite-20261116-140509.pdf",
          path == "/USB0/GEOULTRA/print/geoWrite-20261116-140509.pdf", outs)
    check("the folder made", "mkdir /USB0/GEOULTRA/print" in m.log, m.log[:4])
    modes = [l.split()[-1] for l in m.log if l.startswith("open /USB0")]
    check("made for page 1, appended to after", modes[:1] == ["1"] and set(modes[1:]) == {"2"}
          and len(modes) == pages * (2 + bands), modes[:6])
    pdf = os.path.join(OUT, "pdfsim-%s.pdf" % paper)
    open(pdf, "wb").write(m.files.get(path, b""))
    r = subprocess.run(["mutool", "info", pdf], capture_output=True)
    err = r.stderr.decode("latin1")
    check("mutool reads it without repairing", r.returncode == 0 and "repair" not in err and "error" not in err,
          err[:300])
    n = re.search(r"Pages: (\d+)", r.stdout.decode("latin1"))
    check("%d pages" % pages, n is not None and int(n.group(1)) == pages, r.stdout[:200])
    rows = bytearray()
    for band in range(bands):
        for row in range(8):
            rows += bytes(data[band * 640 + c * 8 + row] for c in range(80))
    want = bytes(rows) + bytes(752 * 80 - len(rows))
    for k in range(pages):
        got = subprocess.run(["mutool", "show", "-b", pdf, str(3 + 3 * k)], capture_output=True).stdout
        check("page %d's image: the rows as sent, the rest blank" % (k + 1), got == want, "%d bytes" % len(got))
    page = subprocess.run(["mutool", "show", pdf, "5"], capture_output=True).stdout.decode("latin1")
    check("the paper: /MediaBox %s" % media, media in page, page[:120])
    print("  %s: %d bytes" % (pdf, os.path.getsize(pdf)))
    return ok


if __name__ == "__main__":
    main()
