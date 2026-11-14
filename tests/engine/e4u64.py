#!/usr/bin/env python3
"""File engine step E4 on the Ultimate 64: CVT (docs/FILE_ENGINE.md,
"Copying"; enginecvt.s).

GeoUltra from the U64's flash (feu64.py); the cartridge given on the
command line is put there first. A sequential and a VLIR GEOS file from
drive A's test image (a copy, /USB0/GEOULTRA/test) are copied onto the
stick as CVT and checked against the originals' header and data or
records, and against VICE's c1541 (-geoswrite into an empty image);
then converted back onto drive A under a new name and compared again; a
CVT whose stick name differs only in case gets its GEOS name back; a
".cvt" that is none is copied as it is; FC_RAW still copies raw.
Everything is written in /USB0/GEOULTRA/test/e4 and on the test images,
and removed again.
Usage: tests/engine/e4u64.py [build/geoultra64.crt]
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402
from e2 import Image  # noqa: E402

(FE_VERSION, FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE, FE_COPY, FE_MOVE, FE_DELETE,
 FE_MKDIR, FE_RMDIR, FE_RENAME, FE_CD, FE_PWD, FE_OPEN, FE_READ, FE_WRITE) = range(16)
FO_READ, FO_WRITE, FO_APPEND = range(3)
IS_FOLDER, STRUCT_MISMAT = 0x4B, 10
DATA = 0x6000
assert FE_MKDIR == 8
FILE_NOT_FOUND = 5
FC_RAW = 2
INFO, NAME = 0x5300, 0x5320
HOME = "/usb0/geoultra/test/e4"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "engine")
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
IMAGE_A = "/USB0/GEOULTRA/test/GEOS64.D81"
IMAGE_B = "/USB0/GEOULTRA/test/neos.d64"
SAFE = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ")


def name_of(e):
    return e[3:19].split(b"\xA0")[0].decode("latin1")


def sound(img, e):
    """True when every chain of the file stays on the disk (a 1581's
    tracks 1-80, sectors 0-39)."""
    def chain(t, s):
        n = 0
        while t:
            if not (1 <= t <= 80 and s < 40) or n > 4000:
                return False
            t, s = img.block(t, s)[:2]
            n += 1
        return True
    if e[21] != 1:
        return chain(e[1], e[2])
    index = img.block(e[1], e[2])
    return all(chain(index[2 + 2 * r], index[3 + 2 * r]) for r in range(127) if index[2 + 2 * r])


def cvt_parts(data):
    """A CVT's directory entry and its parts as Image.contents gives
    them: the header block, then the data or each record."""
    entry, header = data[:30], data[254:508]
    if entry[21] != 1:
        return entry, [header, data[508:]]
    table, pos, parts = data[508:762], 762, [header]
    for r in range(127):
        n, last = table[2 * r], table[2 * r + 1]
        if n == 0:
            parts.append("none" if last == 0xFF else "empty")
            continue
        parts.append(data[pos:pos + 254 * (n - 1) + last - 1])
        pos += 254 * n
    return entry, parts


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
        self.u.ftp_get(path.replace("/usb0", "/USB0", 1), dest)
        return dest

    def image(self, path, local):
        time.sleep(15)                                  # the write-back
        return Image(self.get(path, local))

    def run(self):
        fe, check = self.fe, self.check
        os.makedirs(OUT, exist_ok=True)
        orig = Image(self.get(IMAGE_A, "e4-a.d81"))
        geos = [e for e in orig.entries() if e[19] and set(e[3:19].split(b"\xA0")[0]) <= SAFE]
        seq = min((e for e in geos if e[21] == 0), key=lambda e: e[28] | e[29] << 8)
        vlir = min((e for e in geos if e[21] == 1), key=lambda e: e[28] | e[29] << 8)
        big = max((e for e in geos if e[21] == 1 and sound(orig, e)), key=lambda e: e[28] | e[29] << 8)
        broken = [e for e in geos if not sound(orig, e)]
        fe(FE_MKDIR, s0=HOME)
        for e, kind in ((seq, "sequential"), (vlir, "VLIR"), (big, "large VLIR")):
            name = name_of(e)
            x = fe(FE_COPY, s0="/a/" + name, s1=HOME, timeout=300)[0]
            check("FE_COPY a %s GEOS file (%s, %d blocks) as CVT" % (kind, name, e[28] | e[29] << 8), x, 0)
            data = open(self.get(HOME + "/" + name + ".cvt", "e4-%s.cvt" % kind.replace(" ", "-")), "rb").read()
            entry, parts = cvt_parts(data)
            check("its signature", data[30:58], b"%s formatted GEOS file V1.0" % (b"SEQ" if kind == "sequential" else b"PRG"))
            check("its directory entry", entry, bytes(e))
            check("its header and data as the original's", parts == orig.contents(e), True)
            vice = os.path.join(OUT, "e4-vice.d81")
            if os.path.exists(vice):
                os.remove(vice)
            subprocess.run([C1541, "-format", "e4,e4", "d81", vice, "-geoswrite",
                            os.path.join(OUT, "e4-%s.cvt" % kind.replace(" ", "-"))], capture_output=True, check=True)
            img = Image(vice)
            got = [v for v in img.entries() if v[19]]
            back = img.contents(got[0]) if got else []
            want = orig.contents(e)
            if kind == "sequential" and len(back) == 2:     # (c1541 -geoswrite fills the last
                back[1] = back[1][:len(want[1])]            # block of a sequential file to 254)
            check("VICE's c1541 reads it back as the original", back == want, True)
        # a file with a broken chain: an error, and no file left on the stick
        for e in broken[:1]:
            name = name_of(e)
            x = fe(FE_COPY, s0="/a/" + name, s1=HOME, timeout=300)[0]
            check("%s (a broken chain on the test image): an error, no %s.cvt left" % (name, name),
                  (x != 0, fe(FE_STAT, s0="%s/%s.cvt" % (HOME, name), r1=INFO)[0]), (True, FILE_NOT_FOUND))
        self.streams(seq, vlir, orig)
        # back onto drive A under a new name
        for e, new in ((seq, "E4SEQ"), (vlir, "E4VLIR"), (big, "E4BIG")):
            x = fe(FE_COPY, s0="%s/%s.cvt" % (HOME, name_of(e)), s1="/a/" + new, timeout=300)[0]
            check("FE_COPY the CVT back as /a/%s" % new, x, 0)
        img = self.image(IMAGE_A, "e4-a2.d81")
        for e, new in ((seq, "E4SEQ"), (vlir, "E4VLIR"), (big, "E4BIG")):
            n = img.entry(new)
            check("/a/%s: header and data as the original's" % new,
                  n is not None and img.contents(n) == orig.contents(e), True)
            check("/a/%s: type, structure, GEOS type, date, size" % new,
                  n is not None and (n[0], n[21:28], n[28:30]), (e[0], e[21:28], e[28:30]))
            fe(FE_DELETE, s0="/a/" + new)
        # a CVT whose name differs in case: its GEOS name again
        name = name_of(seq)
        low = os.path.join(OUT, "e4-low.cvt")
        open(low, "wb").write(open(os.path.join(OUT, "e4-sequential.cvt"), "rb").read())
        self.u.ftp_put(low, "/USB0/GEOULTRA/test/e4/" + name.swapcase() + ".cvt")
        fe(FE_MKDIR, s0="/a/E4DIR", r2=3)                # (a new partition: nothing to clash)
        x = fe(FE_COPY, s0="%s/%s.cvt" % (HOME, name.swapcase()), s1="/a/E4DIR", timeout=300)[0]
        check("a CVT named %s.cvt into a folder: named %s" % (name.swapcase(), name),
              (x, fe(FE_STAT, s0="/a/E4DIR/" + name, r1=INFO)[0]), (0, 0))
        fe(FE_DELETE, s0="/a/E4DIR/" + name)
        fe(FE_RMDIR, s0="/a/E4DIR")
        # a .cvt that is none: as it is
        fake = bytes((i * 7 + 3) & 0xFF for i in range(600))
        path = os.path.join(OUT, "e4-fake.cvt")
        open(path, "wb").write(fake)
        self.u.ftp_put(path, "/USB0/GEOULTRA/test/e4/fake.cvt")
        check("drive B has no fake.cvt", fe(FE_STAT, s0="/b/fake.cvt", r1=INFO)[0], FILE_NOT_FOUND)
        check("a .cvt that is no CVT onto drive B", fe(FE_COPY, s0=HOME + "/fake.cvt", s1="/b")[0], 0)
        # FC_RAW: a sequential GEOS file's data
        check("FC_RAW: a sequential GEOS file raw", fe(FE_COPY, s0="/a/" + name, s1=HOME + "/raw",
                                                      r2=FC_RAW)[0], 0)
        check("its bytes", open(self.get(HOME + "/raw", "e4-raw"), "rb").read(), orig.contents(seq)[1])
        img = self.image(IMAGE_B, "e4-b.d64")
        f = img.entry("fake.cvt")
        check("the fake .cvt: its bytes", f is not None and img.contents(f)[0], fake)
        fe(FE_DELETE, s0="/b/fake.cvt")                 # (only what the test made)
        x, h, _ = fe(FE_OPENDIR, s0=HOME)
        names = []
        while not x:
            x, _, _ = fe(FE_READDIR, y=h, r1=INFO, r2=NAME)
            if not x:
                names.append(self.u.read(NAME, 64).split(b"\0")[0].decode("latin1"))
        fe(FE_CLOSE, y=h)
        for n in names:
            fe(FE_DELETE, s0=HOME + "/" + n)
        fe(FE_RMDIR, s0=HOME)
        check("cleaned up", [fe(FE_STAT, s0=p, r1=INFO)[0] for p in (HOME, "/a/E4SEQ", "/a/E4VLIR", "/a/E4BIG",
                                                                      "/a/E4DIR", "/b/fake.cvt")],
              [FILE_NOT_FOUND] * 6)


    def read_all(self, h, piece):
        out = b""
        while True:
            x, _, r = self.fe(FE_READ, y=h, r1=DATA, r2=piece)
            if x or r[2] == 0:
                return x, out
            out += self.u.read(DATA, r[2])
            self.fe(FE_STAT, s0=HOME, r1=INFO)              # (opens files of its own)

    def streams(self, seq, vlir, orig):
        """Streams on the Ultimate (modules 61-64)."""
        fe, check = self.fe, self.check
        path = HOME + "/stream.txt"
        x, h, _ = fe(FE_OPEN, s0=path, r2=FO_WRITE)
        data = bytes((i * 11 + 5) & 0xFF for i in range(600))
        self.u.write(DATA, data[:250])
        a = fe(FE_WRITE, y=h, r1=DATA, r2=250)[0]
        fe(FE_STAT, s0=HOME, r1=INFO)
        self.u.write(DATA, data[250:])
        b = fe(FE_WRITE, y=h, r1=DATA, r2=350)[0]
        fe(FE_CLOSE, y=h)
        check("FE_OPEN, FE_WRITE (250 + 350 bytes) on the Ultimate", (x, a, b), (0, 0, 0))
        check("its bytes on the stick", open(self.get(path, "e4-stream"), "rb").read(), data)
        x, h, _ = fe(FE_OPEN, s0=path, r2=FO_APPEND)
        self.u.write(DATA, b"tail")
        a = fe(FE_WRITE, y=h, r1=DATA, r2=4)[0]
        fe(FE_CLOSE, y=h)
        x, h, _ = fe(FE_OPEN, s0=path, r2=FO_READ)
        got = self.read_all(h, 257)
        fe(FE_CLOSE, y=h)
        check("FO_APPEND, then FE_READ in pieces of 257 (FE_STAT between)", (x, a, got), (0, 0, (0, data + b"tail")))
        x, h, _ = fe(FE_OPEN, s0="%s/%s.cvt" % (HOME, name_of(seq)), r2=FO_READ)
        got = self.read_all(h, 200)
        fe(FE_CLOSE, y=h)
        check("FE_READ of a sequential GEOS file's CVT: its data", (x, got), (0, (0, orig.contents(seq)[1])))
        check("FE_OPEN of a VLIR file's CVT", fe(FE_OPEN, s0="%s/%s.cvt" % (HOME, name_of(vlir)),
                                                  r2=FO_READ)[0], STRUCT_MISMAT)
        check("FE_OPEN of a folder, of nothing", (fe(FE_OPEN, s0=HOME, r2=FO_READ)[0],
                                                   fe(FE_OPEN, s0=HOME + "/none", r2=FO_READ)[0]),
              (IS_FOLDER, FILE_NOT_FOUND))
        fe(FE_DELETE, s0=path)


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    t = Test(crt)
    t.run()
    sys.exit(0 if t.ok else 1)


if __name__ == "__main__":
    main()
