#!/usr/bin/env python3
"""File engine step E3 on the Ultimate 64 (docs/FILE_ENGINE.md, "Tests").

GeoUltra from the U64's flash (feu64.py); the cartridge given on the
command line is put there first. Everything the test writes is in
/USB0/GEOULTRA/test/engine (made and removed by the test; the user's own
files are never touched). Checked: "/" lists the Ultimate's tops, FE_STAT
(files with size and date, folders, disk images as files), FE_OPENDIR /
FE_READDIR (folders, patterns), FE_CD / FE_PWD, FE_MKDIR, FE_RENAME,
FE_DELETE, FE_RMDIR with their errors.
Usage: tests/engine/e3u64.py [build/geoultra64.crt]
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from e2 import Image  # noqa: E402

(FE_VERSION, FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE, FE_COPY, FE_MOVE, FE_DELETE,
 FE_MKDIR, FE_RMDIR, FE_RENAME, FE_CD, FE_PWD, FE_OPEN, FE_READ, FE_WRITE, FE_DF) = range(17)
K_ROOT, K_DRIVE, K_FOLDER, K_GEOS, K_CBM, K_UFILE, K_UDIR = range(7)
FILE_NOT_FOUND, WR_PR_ON, FILE_EXISTS, DIR_NOT_EMPTY = 5, 0x26, 0x40, 0x41
END_OF_DIR, BAD_PATH, NOT_FOLDER, IS_FOLDER = 0x48, 0x49, 0x4A, 0x4B
INFO, NAME, PROG, DATA = 0x5300, 0x5320, 0x5400, 0x6000
HOME = "/usb0/geoultra/test/engine"
FC_OVERWRITE, FC_RAW = 1, 2
FO_READ, FO_WRITE = 0, 1
NOT_SUPPORTED, CANCELLED = 0x4E, 0x47
PAYLOAD = bytes((i * 13 + 7) & 0xFF for i in range(600))
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                   "build", "harness", "engine")


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

    def stat(self, path):
        x, _, _ = self.fe(FE_STAT, s0=path, r1=INFO)
        if x:
            return (x,)
        i = self.u.read(INFO, 16)
        return (0, i[0], int.from_bytes(i[4:8], "little"))

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
        return sorted(out) if x == END_OF_DIR else ("error %02x" % x, out)

    def make(self, path, data):
        """A CBM SEQ file on a GEOS drive (FE_OPEN, FE_WRITE)."""
        x, h, _ = self.fe(FE_OPEN, s0=path, r2=FO_WRITE)
        if x:
            return x
        if data:
            self.u.write(DATA, data)
            x = self.fe(FE_WRITE, y=h, r1=DATA, r2=len(data))[0]
        self.fe(FE_CLOSE, y=h)
        return x

    def read(self, path):
        """A GEOS file's bytes (FE_OPEN, FE_READ)."""
        x, h, _ = self.fe(FE_OPEN, s0=path, r2=FO_READ)
        if x:
            return x
        got = b""
        while True:
            x, _, r = self.fe(FE_READ, y=h, r1=DATA, r2=0x1000)
            if x:
                return ("error", x)
            got += self.u.read(DATA, r[2]) if r[2] else b""
            if r[2] < 0x1000:
                break
        self.fe(FE_CLOSE, y=h)
        return got

    def ftp(self, path):
        """A file on the Ultimate's stick, by FTP."""
        dest = os.path.join(OUT, "ftp.bin")
        if os.path.exists(dest):
            os.remove(dest)
        self.u.ftp_get(path.replace("/usb0", "/USB0", 1), dest)
        return open(dest, "rb").read() if os.path.exists(dest) else None

    def pwd(self):
        self.fe(FE_PWD, r0=NAME)
        return self.u.read(NAME, 128).split(b"\0")[0].decode("latin1")

    def run(self):
        fe, check, stat, listing = self.fe, self.check, self.stat, self.listing
        check("FE_VERSION", fe(FE_VERSION)[2][0], 3)
        root = listing("/")
        check("/ lists the drives and /usb0", "a" in root and "usb0" in root, True)
        check("FE_STAT /usb0", stat("/usb0"), (0, K_UDIR, 0))
        check("FE_STAT a file: its size", stat("/usb0/geoultra/MOUNTS.INI")[:2], (0, K_UFILE))
        check("FE_STAT a disk image is a file", stat("/usb0/geoultra/test/GEOS64.D81"), (0, K_UFILE, 819200))
        check("FE_STAT a missing file", stat("/usb0/geoultra/nope"), (FILE_NOT_FOUND,))
        check("FE_OPENDIR a pattern", listing("/usb0/geoultra/test/*.d64"), ["geopub.d64", "neos.d64"])
        if stat(HOME)[0] == 0:                  # left over from an aborted run
            for n in listing(HOME):
                fe(FE_DELETE, s0=HOME + "/" + n)
                fe(FE_RMDIR, s0=HOME + "/" + n)
            fe(FE_RMDIR, s0=HOME)
        check("FE_MKDIR", (fe(FE_MKDIR, s0=HOME)[0], stat(HOME)), (0, (0, K_UDIR, 0)))
        check("FE_MKDIR again", fe(FE_MKDIR, s0=HOME)[0], FILE_EXISTS)
        check("FE_CD and FE_PWD", (fe(FE_CD, s0=HOME)[0], self.pwd()), (0, HOME))
        check("FE_MKDIR relative", (fe(FE_MKDIR, s0="sub")[0], listing(".")), (0, ["sub"]))
        check("FE_CD into a missing folder", (fe(FE_CD, s0="nope")[0], self.pwd()), (FILE_NOT_FOUND, HOME))
        check("FE_RENAME a folder", (fe(FE_RENAME, s0="sub", s1="sub2")[0], listing(".")), (0, ["sub2"]))
        check("FE_RENAME a missing name", fe(FE_RENAME, s0="nope", s1="x")[0], FILE_NOT_FOUND)
        check("FE_RENAME with a /", fe(FE_RENAME, s0="sub2", s1="a/b")[0], BAD_PATH)
        check("FE_MKDIR inside", fe(FE_MKDIR, s0="sub2/inner")[0], 0)
        check("FE_RMDIR a folder with entries", fe(FE_RMDIR, s0="sub2")[0], DIR_NOT_EMPTY)
        check("FE_DELETE a folder", fe(FE_DELETE, s0="sub2/inner")[0], IS_FOLDER)
        check("FE_RMDIR", (fe(FE_RMDIR, s0="sub2/inner")[0], fe(FE_RMDIR, s0="sub2")[0], listing(".")),
              (0, 0, []))
        check("FE_DELETE a missing file", fe(FE_DELETE, s0="nope")[0], FILE_NOT_FOUND)
        check("FE_RMDIR a missing folder", fe(FE_RMDIR, s0="nope")[0], FILE_NOT_FOUND)
        check("FE_DELETE the top refused", fe(FE_DELETE, s0="/usb0")[0], BAD_PATH)
        check("FE_CD /", (fe(FE_CD, s0="/")[0], self.pwd()), (0, "/"))
        self.copies()
        check("FE_RMDIR the test folder", (fe(FE_RMDIR, s0=HOME)[0], stat(HOME)), (0, (FILE_NOT_FOUND,)))

    def copies(self):
        fe, check, stat, listing = self.fe, self.check, self.stat, self.listing
        os.makedirs(OUT, exist_ok=True)
        for n in ("XFER1", "XFER2", "XFER3", "EMPTY", "NEOS"):
            fe(FE_DELETE, s0="/a/" + n)
        fe(FE_DELETE, s0="/b/A:B")
        check("a test file on drive A", (self.make("/a/XFER1", PAYLOAD), stat("/a/XFER1")), (0, (0, K_CBM, 3)))
        check("FE_COPY A -> the Ultimate (into a folder: .seq)",
              (fe(FE_COPY, s0="/a/XFER1", s1=HOME)[0], stat(HOME + "/XFER1.seq")), (0, (0, K_UFILE, 600)))
        check("its bytes, by FTP", self.ftp(HOME + "/XFER1.seq") == PAYLOAD, True)
        check("FE_COPY again refused", fe(FE_COPY, s0="/a/XFER1", s1=HOME)[0], FILE_EXISTS)
        check("FE_COPY with overwrite", fe(FE_COPY, s0="/a/XFER1", s1=HOME, r2=FC_OVERWRITE)[0], 0)
        check("FE_COPY raw: no extension",
              (fe(FE_COPY, s0="/a/XFER1", s1=HOME, r2=FC_RAW)[0], stat(HOME + "/XFER1")), (0, (0, K_UFILE, 600)))
        check("FE_COPY to a new name", (fe(FE_COPY, s0="/a/XFER1", s1=HOME + "/other.txt")[0],
                                        self.ftp(HOME + "/other.txt") == PAYLOAD), (0, True))
        check("FE_COPY the Ultimate -> A",
              (fe(FE_COPY, s0=HOME + "/XFER1.seq", s1="/a/XFER2")[0], stat("/a/XFER2"), self.read("/a/XFER2")
               == PAYLOAD), (0, (0, K_CBM, 3), True))
        x, info = fe(FE_STAT, s0="/a/XFER2", r1=INFO)[0], self.u.read(INFO, 16)
        check("its type from the extension (SEQ)", (x, info[1]), (0, 0x81))
        check("FE_COPY into a folder: the name without .seq exists",
              fe(FE_COPY, s0=HOME + "/XFER1.seq", s1="/a")[0], FILE_EXISTS)
        check("FE_COPY with overwrite", fe(FE_COPY, s0=HOME + "/XFER1.seq", s1="/a", r2=FC_OVERWRITE)[0], 0)
        check("FE_COPY other.txt -> A: a PRG of that name",
              (fe(FE_COPY, s0=HOME + "/other.txt", s1="/a/")[0], fe(FE_STAT, s0="/a/other.txt", r1=INFO)[0],
               self.u.read(INFO + 1, 1)[0]), (0, 0, 0x82))
        fe(FE_DELETE, s0="/a/other.txt")
        check("an empty file there and back",
              (self.make("/a/EMPTY", b""), fe(FE_COPY, s0="/a/EMPTY", s1=HOME)[0], stat(HOME + "/EMPTY.seq"),
               fe(FE_DELETE, s0="/a/EMPTY")[0], fe(FE_COPY, s0=HOME + "/EMPTY.seq", s1="/a")[0],
               stat("/a/EMPTY"), self.read("/a/EMPTY")), (0, 0, (0, K_UFILE, 0), 0, 0, (0, K_CBM, 1), b""))
        check("a name with : and * there and back (%XX)",
              (self.make("/b/A:B*", b"xy"), fe(FE_COPY, s0="/b/A:B*", s1=HOME)[0],
               stat(HOME + "/A%3AB%2A.seq")[0], fe(FE_DELETE, s0="/b/A:B*")[0],
               fe(FE_COPY, s0=HOME + "/A%3AB%2A.seq", s1="/b")[0], self.read("/b/A:B*")),
              (0, 0, 0, 0, 0, b"xy"))
        fe(FE_DELETE, s0="/b/A:B*")
        check("FE_MOVE A -> the Ultimate", (fe(FE_MOVE, s0="/a/XFER2", s1=HOME + "/moved.seq")[0],
                                           stat("/a/XFER2"), stat(HOME + "/moved.seq")),
              (0, (FILE_NOT_FOUND,), (0, K_UFILE, 600)))
        check("FE_MOVE the Ultimate -> A", (fe(FE_MOVE, s0=HOME + "/moved.seq", s1="/a/XFER3")[0],
                                           stat(HOME + "/moved.seq"), self.read("/a/XFER3") == PAYLOAD),
              (0, (FILE_NOT_FOUND,), True))
        self.u.write(PROG, [0x38, 0x60])                 # sec; rts: stop
        check("a cancelled copy", (fe(FE_COPY, s0="/a/XFER3", s1=HOME + "/cancel", r3=PROG)[0],
                                   fe(FE_DELETE, s0=HOME + "/cancel")[0]), (CANCELLED, 0))
        check("FE_COPY a folder from the Ultimate", fe(FE_COPY, s0="/usb0/geoultra/test", s1="/a")[0],
              IS_FOLDER)
        check("FE_COPY the Ultimate -> the Ultimate", fe(FE_COPY, s0=HOME + "/XFER1", s1=HOME + "/x")[0],
              NOT_SUPPORTED)
        geos = [n for n in listing("/a") if stat("/a/" + n)[1:2] == (K_GEOS,)]
        check("FE_COPY a GEOS file without FC_RAW", fe(FE_COPY, s0="/a/" + geos[0], s1=HOME)[0], NOT_SUPPORTED)
        free = fe(FE_DF, s0="/a")[2][1]
        t = time.time()
        x = fe(FE_COPY, s0="/usb0/geoultra/test/neos.d64", s1="/a/NEOS", timeout=600)[0]
        check("neos.d64 (174848 bytes) onto drive A in %.0f s" % (time.time() - t),
              (x, stat("/a/NEOS"), free - fe(FE_DF, s0="/a")[2][1]), (0, (0, K_CBM, 689), 689))
        time.sleep(15)                                  # the write-back
        image = os.path.join(OUT, "hw-a.d81")
        self.u.ftp_get("/USB0/GEOULTRA/test/GEOS64.D81", image)
        img = Image(image)
        check("its bytes in drive A's image", img.contents(img.entry("NEOS"))[0]
              == self.ftp("/usb0/geoultra/test/neos.d64"), True)
        e = img.entry("NEOS")
        check("its date from the Ultimate's file (year 2000-2079: below 80)", 0 < e[23] < 80 and 1 <= e[24] <= 12,
              True)
        for n in ("XFER1", "XFER3", "NEOS"):
            fe(FE_DELETE, s0="/a/" + n)
        for n in listing(HOME):
            fe(FE_DELETE, s0=HOME + "/" + n)
        check("all cleaned up", (listing(HOME), stat("/a/XFER1")[0]), ([], FILE_NOT_FOUND))


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else None
    t = Test(crt)
    t.run()
    sys.exit(0 if t.ok else 1)


if __name__ == "__main__":
    main()
