#!/usr/bin/env python3
"""File engine step E4 on the Ultimate 64: mounting while GEOS runs
(docs/FILE_ENGINE.md "Mount"; enginemount.s).

GeoUltra from the U64's flash (feu64.py); the cartridge given on the
command line is put there first. Only test copies in /USB0/GEOULTRA/test
are mounted; MOUNTS.INI and the images the test writes to are saved
first and put back at the end, whatever happens. Checked: FE_MOUNTINFO,
FE_MOUNT of a D64 and a DNP into empty drives (listings as the images'),
MOUNTS.INI written anew, a write to a mounted drive written back by
FE_UMOUNT, mounting over a mounted drive, the errors.
Usage: tests/engine/mntu64.py [build/geoultra64.crt]
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402
from e2 import Image  # noqa: E402

FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE = 1, 2, 3, 4
FE_DELETE, FE_OPEN, FE_WRITE = 7, 13, 15
FE_MOUNT, FE_UMOUNT, FE_MOUNTINFO = 17, 18, 23
FO_WRITE = 1
DEV_NOT_FOUND, BAD_PATH, NOT_SUPPORTED = 13, 0x49, 0x4E
INFO, NAME, BUF, DATA = 0x5300, 0x5320, 0x5400, 0x6000
TEST = "/USB0/GEOULTRA/test"
INI = "/USB0/GEOULTRA/MOUNTS.INI"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "engine")
D64, DNP = "geopub.d64", "ramapps.DNP"


class Test:
    def __init__(self, crt):
        self.u = U64()
        self.ok = True
        self.u.boot(crt)

    def fe(self, *a, **k):
        return self.u.fe(*a, **k)

    def check(self, title, got, want):
        good = got == want
        self.ok = self.ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def get(self, path, local):
        dest = os.path.join(OUT, local)
        if os.path.exists(dest):
            os.remove(dest)
        self.u.ftp_get(path, dest)
        return dest

    def info(self, drive):
        x, _, r = self.fe(FE_MOUNTINFO, s0=drive, r1=BUF)
        if x:
            return (x,)
        return (0, r[2] & 0xFF, self.u.read(BUF, 64).split(b"\0")[0].decode("latin1"))

    def listing(self, path):
        x, h, _ = self.fe(FE_OPENDIR, s0=path)
        if x:
            return x
        out = []
        while True:
            x, _, _ = self.fe(FE_READDIR, y=h, r1=INFO, r2=NAME)
            if x:
                break
            out.append(self.u.read(NAME, 64).split(b"\0")[0].decode("latin1"))
        self.fe(FE_CLOSE, y=h)
        return sorted(out)

    def ini(self):
        return open(self.get(INI, "mnt-ini"), "rb").read()

    def run(self):
        fe, check = self.fe, self.check
        os.makedirs(OUT, exist_ok=True)
        saved = {p: open(self.get(p, "mnt-save-" + os.path.basename(p)), "rb").read()
                 for p in (INI, TEST + "/" + D64)}
        try:
            self.body(saved)
        finally:
            for p, data in saved.items():
                path = os.path.join(OUT, "mnt-restore")
                open(path, "wb").write(data)
                self.u.ftp_put(path, p)
            check("MOUNTS.INI and %s as they were" % D64,
                  [open(self.get(p, "mnt-back"), "rb").read() == d for p, d in saved.items()], [True, True])

    def body(self, saved):
        fe, check, info = self.fe, self.check, self.info
        check("FE_MOUNTINFO /a, /c", (info("/a"), info("/c")),
              ((0, 3, TEST + "/GEOS64.D81"), (DEV_NOT_FOUND,)))
        check("errors: drive E, a file that is no image, /c empty",
              (fe(FE_MOUNT, s0="/e", s1=TEST + "/" + D64)[0], fe(FE_MOUNT, s0="/c", s1=INI)[0],
               fe(FE_UMOUNT, s0="/c")[0]), (BAD_PATH, NOT_SUPPORTED, DEV_NOT_FOUND))
        x = fe(FE_MOUNT, s0="/c", s1="/usb0/geoultra/test/" + D64, timeout=120)[0]
        check("FE_MOUNT %s into /c" % D64, (x, info("/c")), (0, (0, 1, "/usb0/geoultra/test/" + D64)))
        img = Image(os.path.join(OUT, "mnt-save-" + D64))
        names = sorted(e[3:19].split(b"\xA0")[0].decode("latin1") for e in img.entries())
        check("/c lists the image's files", self.listing("/c"), names)
        check("MOUNTS.INI written anew", self.ini(),
              saved[INI] + b"C=/usb0/geoultra/test/" + D64.encode() + b"\r\n")
        x, h, _ = fe(FE_OPEN, s0="/c/MNTTEST", r2=FO_WRITE)
        self.u.write(DATA, b"mounted\r")
        fe(FE_WRITE, y=h, r1=DATA, r2=8)
        fe(FE_CLOSE, y=h)
        check("a file written on /c", (x, fe(FE_STAT, s0="/c/MNTTEST", r1=INFO)[0]), (0, 0))
        check("FE_UMOUNT /c", (fe(FE_UMOUNT, s0="/c", timeout=120)[0], info("/c")), (0, (DEV_NOT_FOUND,)))
        img = Image(self.get(TEST + "/" + D64, "mnt-after.d64"))
        e = img.entry("MNTTEST")
        check("written back into the image", e is not None and img.contents(e)[0], b"mounted\r")
        check("MOUNTS.INI without /c again", self.ini(), saved[INI])
        x = fe(FE_MOUNT, s0="/d", s1=TEST + "/" + DNP, timeout=300)[0]
        i = info("/d")
        check("FE_MOUNT a DNP into /d (native)", (x, i[:2]), (0, (0, 4)))
        check("/d lists files", len(self.listing("/d")) > 0, True)
        x = fe(FE_MOUNT, s0="/d", s1=TEST + "/" + D64, timeout=120)[0]
        check("FE_MOUNT over it: the D64 in /d now", (x, info("/d")[:2]), (0, (0, 1)))
        check("FE_UMOUNT /d", fe(FE_UMOUNT, s0="/d", timeout=120)[0], 0)
        check("A and B as they were", (info("/a")[:2], info("/b")[:2], self.ini()),
              ((0, 3), (0, 1), saved[INI]))


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else None
    t = Test(crt)
    t.run()
    sys.exit(0 if t.ok else 1)


if __name__ == "__main__":
    main()
