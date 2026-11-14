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
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402
from e2 import Image  # noqa: E402

FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE = 1, 2, 3, 4
FE_COPY, FE_DELETE, FE_OPEN, FE_WRITE = 5, 7, 13, 15
FE_MOUNT, FE_UMOUNT, FE_MOUNTINFO, FE_MKIMG = 17, 18, 23, 24
FE_MKDIR, FE_RMDIR, FE_DF = 8, 9, 16
FILE_EXISTS = 0x40
MK = "/usb0/geoultra/test/mk"
FO_WRITE = 1
DEV_NOT_FOUND, BAD_PATH, NOT_SUPPORTED = 13, 0x49, 0x4E
INFO, NAME, BUF, DATA = 0x5300, 0x5320, 0x5400, 0x6000
TEST = "/USB0/GEOULTRA/test"
INI = "/USB0/GEOULTRA/MOUNTS.INI"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "engine")
D64, DNP = "geopub.d64", "gumnt.dnp"           # (DNP: build/sysdrive-plain.dnp, 8
                                                # tracks, put there and removed: room
                                                # in the REU beside an 8 MB drive C)
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")


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
        check("FE_MOUNTINFO /a, /d", (info("/a"), info("/d")),
              ((0, 3, TEST + "/GEOS64.D81"), (DEV_NOT_FOUND,)))
        check("errors: drive E, a file that is no image, /d empty",
              (fe(FE_MOUNT, s0="/e", s1=TEST + "/" + D64)[0], fe(FE_MOUNT, s0="/d", s1=INI)[0],
               fe(FE_UMOUNT, s0="/d")[0]), (BAD_PATH, NOT_SUPPORTED, DEV_NOT_FOUND))
        check("the image drive A has, onto /d: refused (FE_MOUNTED)",
              (fe(FE_MOUNT, s0="/d", s1="/usb0/geoultra/test/geos64.d81", timeout=60)[0], info("/d")),
              (0x51, (DEV_NOT_FOUND,)))
        x = fe(FE_MOUNT, s0="/d", s1="/usb0/geoultra/test/" + D64, timeout=120)[0]
        check("FE_MOUNT %s into /d" % D64, (x, info("/d")), (0, (0, 1, "/usb0/geoultra/test/" + D64)))
        img = Image(os.path.join(OUT, "mnt-save-" + D64))
        names = sorted(e[3:19].split(b"\xA0")[0].decode("latin1") for e in img.entries())
        check("/d lists the image's files", self.listing("/d"), names)
        check("MOUNTS.INI written anew", self.ini(),
              saved[INI] + b"D=/usb0/geoultra/test/" + D64.encode() + b"\r\n")
        x, h, _ = fe(FE_OPEN, s0="/d/MNTTEST", r2=FO_WRITE)
        self.u.write(DATA, b"mounted\r")
        fe(FE_WRITE, y=h, r1=DATA, r2=8)
        fe(FE_CLOSE, y=h)
        check("a file written on /d", (x, fe(FE_STAT, s0="/d/MNTTEST", r1=INFO)[0]), (0, 0))
        check("FE_UMOUNT /d", (fe(FE_UMOUNT, s0="/d", timeout=120)[0], info("/d")), (0, (DEV_NOT_FOUND,)))
        img = Image(self.get(TEST + "/" + D64, "mnt-after.d64"))
        e = img.entry("MNTTEST")
        check("written back into the image", e is not None and img.contents(e)[0], b"mounted\r")
        check("MOUNTS.INI without /d again", self.ini(), saved[INI])
        self.u.ftp_put(os.path.join(ROOT, "build", "sysdrive-plain.dnp"), TEST + "/" + DNP)
        x = fe(FE_MOUNT, s0="/d", s1=TEST + "/" + DNP, timeout=300)[0]
        i = info("/d")
        check("FE_MOUNT a DNP into /d (native)", (x, i[:2]), (0, (0, 4)))
        check("/d lists files", len(self.listing("/d")) > 0, True)
        x = fe(FE_MOUNT, s0="/d", s1=TEST + "/" + D64, timeout=120)[0]
        check("FE_MOUNT over it: the D64 in /d now", (x, info("/d")[:2]), (0, (0, 1)))
        check("FE_UMOUNT /d", fe(FE_UMOUNT, s0="/d", timeout=120)[0], 0)
        subprocess.run(["curl", "-s", "-Q", "DELE %s/%s" % (TEST, DNP), "ftp://%s/" % self.u.ip],
                       capture_output=True)
        check("A and B as they were", (info("/a")[:2], info("/b")[:2], self.ini()),
              ((0, 3), (0, 1), saved[INI]))
        self.mkimg(saved)

    def mkimg(self, saved):
        """FE_MKIMG: D64, D71, D81 as VICE's c1541 formats them; a DNP
        mounted, written to, unmounted."""
        fe, check, info = self.fe, self.check, self.info
        fe(FE_MKDIR, s0=MK)
        self.u.write(DATA, b"TEST DISK\0")
        for kind in ("d64", "d71", "d81"):
            x = fe(FE_MKIMG, s0="%s/new.%s" % (MK, kind), r1=DATA, timeout=120)[0]
            ours = open(self.get("/USB0/GEOULTRA/test/mk/new." + kind, "mk-ours." + kind), "rb").read()
            vice = os.path.join(OUT, "mk-vice." + kind)
            if os.path.exists(vice):
                os.remove(vice)
            subprocess.run([C1541, "-format", "test disk,gu", kind, vice], capture_output=True, check=True)
            want = open(vice, "rb").read()
            diff = [i for i in range(min(len(ours), len(want))) if ours[i] != want[i]]
            check("FE_MKIMG new.%s: as c1541 formats it" % kind, (x, len(ours), diff[:8]), (0, len(want), []))
        check("FE_MKIMG over an existing image", fe(FE_MKIMG, s0=MK + "/new.d64", r1=DATA)[0], FILE_EXISTS)
        check("FE_COPY onto an image's name: there already (not into it)",
              fe(FE_COPY, s0="/a/GEOS", s1=MK + "/new.d64")[0], FILE_EXISTS)
        x = fe(FE_MKIMG, s0=MK + "/new.dnp", r1=DATA, r2=4, timeout=120)[0]
        check("FE_MKIMG new.dnp (4 tracks)", (x, os.path.getsize(self.get("/USB0/GEOULTRA/test/mk/new.dnp",
                                                                         "mk-ours.dnp"))), (0, 4 * 65536))
        x = fe(FE_MOUNT, s0="/d", s1=MK + "/new.dnp", timeout=120)[0]
        df = fe(FE_DF, s0="/d")
        check("mounted: native, empty, %d blocks free" % (4 * 256 - 35), (x, info("/d")[:2], self.listing("/d"),
              df[0], df[2][1]), (0, (0, 4), [], 0, 4 * 256 - 35))
        x, h, _ = fe(FE_OPEN, s0="/d/NEWFILE", r2=FO_WRITE)
        self.u.write(DATA, b"native\r")                 # ($6000: as above; the deskTop
        fe(FE_WRITE, y=h, r1=DATA, r2=7)                # changes bytes further on)
        fe(FE_CLOSE, y=h)
        check("a file written there, unmounted", (x, fe(FE_UMOUNT, s0="/d", timeout=120)[0]), (0, 0))
        img = open(self.get("/USB0/GEOULTRA/test/mk/new.dnp", "mk-after.dnp"), "rb").read()
        check("its bytes in the DNP", b"native\r" in img, True)
        check("FE_DELETE of the images (files, though the firmware enters them)",
              [fe(FE_DELETE, s0=MK + "/" + n)[0] for n in ("new.d64", "new.d71", "new.d81", "new.dnp")],
              [0, 0, 0, 0])
        check("cleaned up", (fe(FE_RMDIR, s0=MK)[0], self.ini()), (0, saved[INI]))


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    t = Test(crt)
    t.run()
    sys.exit(0 if t.ok else 1)


if __name__ == "__main__":
    main()
