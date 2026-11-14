#!/usr/bin/env python3
"""File engine on the Ultimate 64: disk images gone into like folders
(docs/FILE_ENGINE.md "Disk images as folders"; engineimg.s, modules
88-90).

Only test copies are used: the test D64 (test/geopub.d64) is copied by
FTP to test/img/gutest.d64 and gone into there, and the build's
build/sysdrive-plain.dnp (8 tracks: room in the REU beside large mounted
drives) to test/img/gutest.dnp; test/GEOS64.D81 (mounted on A) must be
refused. The backup the first
write-back makes (GEOULTRA/BACKUP/gutest.d64) and test/img are removed
at the end; MOUNTS.INI is checked unchanged. Checked: a listing of the
image's files (its listing handle shows the image again for every
FE_READDIR), FE_STAT inside it, a file written into it and written
back into the image file, a copy within the image (the same image named
twice in one call), a copy out of it onto the Ultimate (which drops the
REU copy; the next listing loads the image again), a delete inside it,
a native image's listing and a folder in it, the mounted image refused (FE_MOUNTED), a
disk image as the last part of FE_STAT: the file itself.
Usage: tests/engine/imgu64.py [build/geoultra64.crt]
"""
import ftplib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402
from e2 import Image  # noqa: E402

FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE = 1, 2, 3, 4
FE_COPY, FE_DELETE, FE_OPEN, FE_WRITE = 5, 7, 13, 15
FO_WRITE = 1
FE_MOUNTED = 0x51
INFO, NAME, DATA = 0x5300, 0x5320, 0x6000
HOME = "/USB0/GEOULTRA"
TEST = HOME + "/test"
DIR = TEST + "/img"
IMG = DIR + "/gutest.d64"
UIMG = "/usb0/geoultra/test/img/gutest.d64"
DNP = DIR + "/gutest.dnp"                   # (build/sysdrive-plain.dnp: drive
UDNP = "/usb0/geoultra/test/img/gutest.dnp"  # E's files, unrelocated)
BACKUP = HOME + "/BACKUP/gutest.d64"
INI = HOME + "/MOUNTS.INI"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "engine")


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

    def ftp(self):
        f = ftplib.FTP(self.u.ip, timeout=60)
        f.login()
        return f

    def listing(self, path):
        x, h, _ = self.fe(FE_OPENDIR, s0=path, timeout=120)
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

    def image(self, name):
        return Image(self.get(IMG, name))

    def run(self):
        os.makedirs(OUT, exist_ok=True)
        ini = open(self.get(INI, "img-ini"), "rb").read()
        orig = self.get(TEST + "/geopub.d64", "img-orig.d64")
        f = self.ftp()
        try:
            f.mkd(DIR)
        except ftplib.error_perm:
            pass
        f.quit()
        self.u.ftp_put(orig, IMG)
        try:
            self.body(orig)
        finally:
            f = self.ftp()
            for p in (IMG, DNP, DIR + "/IMGTEST", BACKUP):
                try:
                    f.delete(p)
                except ftplib.error_perm:
                    pass
            try:
                f.rmd(DIR)
            except ftplib.error_perm:
                pass
            f.quit()
            self.check("MOUNTS.INI as it was", open(self.get(INI, "img-ini2"), "rb").read() == ini, True)

    def body(self, orig):
        fe, check = self.fe, self.check
        names = sorted(e[3:19].split(b"\xA0")[0].decode("latin1") for e in Image(orig).entries())
        check("the image listed as a folder (its files)", self.listing(UIMG), names)
        x = fe(FE_STAT, s0=UIMG + "/" + names[0], r1=INFO)[0]
        check("FE_STAT of a file inside it", x, 0)
        x = fe(FE_STAT, s0=UIMG, r1=INFO)[0]
        check("FE_STAT of the image itself: an Ultimate file (FE_K_UFILE)", (x, self.u.read(INFO, 1)[0]), (0, 5))
        x, h, _ = fe(FE_OPEN, s0=UIMG + "/IMGTEST", r2=FO_WRITE)
        self.u.write(DATA, b"inside\r")
        fe(FE_WRITE, y=h, r1=DATA, r2=7)
        fe(FE_CLOSE, y=h)
        img = self.image("img-1.d64")
        e = img.entry("IMGTEST")
        check("a file written inside: in the image file at once", (x, e is not None and img.contents(e)[0]),
              (0, b"inside\r"))
        x = fe(FE_COPY, s0=UIMG + "/IMGTEST", s1=UIMG + "/IMGTWO", timeout=120)[0]
        img = self.image("img-2.d64")
        e = img.entry("IMGTWO")
        check("a copy within the image", (x, e is not None and img.contents(e)[0]), (0, b"inside\r"))
        x = fe(FE_COPY, s0=UIMG + "/IMGTEST", s1="/usb0/geoultra/test/img/IMGTEST", timeout=120)[0]
        f = self.ftp()
        there = "IMGTEST" in [n.split("/")[-1] for n in f.nlst(DIR)]
        f.quit()
        check("a copy out of it onto the Ultimate", (x, there), (0, True))
        check("listed again (loaded again: the copy onto the Ultimate dropped it)",
              self.listing(UIMG), sorted(names + ["IMGTEST", "IMGTWO"]))
        x = fe(FE_DELETE, s0=UIMG + "/IMGTWO")[0]
        img = self.image("img-3.d64")
        check("a delete inside it", (x, img.entry("IMGTWO") is None, img.entry("IMGTEST") is not None),
              (0, True, True))
        self.u.ftp_put(os.path.join(ROOT, "build", "sysdrive-plain.dnp"), DNP)
        top = self.listing(UDNP)
        sub = self.listing(UDNP + "/bin")
        check("a native image (8 tracks) listed, and a folder in it",
              (isinstance(top, list) and "bin" in top, sub), (True, ["wc"]))
        check("the image mounted on A refused", self.listing("/usb0/geoultra/test/GEOS64.D81"), FE_MOUNTED)
        f = self.ftp()
        backup = "gutest.d64" in [n.split("/")[-1] for n in f.nlst(HOME + "/BACKUP")]
        f.quit()
        check("its backup made before the first write-back", backup, True)


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    t = Test(crt)
    t.run()
    print("imgu64: %s" % ("all passed" if t.ok else "FAILED"))
    sys.exit(0 if t.ok else 1)


if __name__ == "__main__":
    main()
