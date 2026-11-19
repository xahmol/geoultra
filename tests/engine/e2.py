#!/usr/bin/env python3
"""File engine on GeoUltra in VICE (docs/design/FILE_ENGINE.md).

On the drives of feharness.py (A the GEOS 2.0 disk, only read; B the
reference D81 of the real 1581 DOS): FE_COPY and FE_MOVE (a CBM file in
a folder and into partitions, a VLIR file from A to B, overwrite, the
errors, the progress routine and a cancelled copy, no room), then
streams (FE_OPEN, FE_WRITE across block ends, FE_APPEND, FE_READ in
pieces, the errors). Afterwards, read from the images in Python: the VLIR
copy equals the original record by record, and drive B's root BAM marks
exactly the blocks in use; the real 1581 DOS reads the written file back.
No private files are written.
Usage: tests/engine/e2.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feharness import *  # noqa: E402,F401,F403  (Engine, constants, part81)

WBUF, RBUF, PROG, COUNT = 0x5200, 0x5600, 0x5A00, 0x5A80
COUNTER = [0xEE, COUNT & 0xFF, COUNT >> 8, 0xD0, 0x03, 0xEE, (COUNT + 1) & 0xFF, COUNT >> 8,
           0xA2, 0x55, 0x18, 0x60]           # inc COUNT (a word); ldx #$55; clc; rts
                                             # (X changed: the engine must not rely on it)
CANCEL = [0x38, 0x60]                        # sec; rts
DATA = bytes((i * 7 + 3) & 0xFF for i in range(810))

CHECK = """10 open15,8,15:r$=""
20 open2,8,2,"newfile,s,r":n=0
30 get#2,a$:n=n+1:if st=0 then 30
40 close2:input#15,a:r$=r$+str$(a)+str$(n)
50 open2,8,2,"rootfile,s,r":input#15,a:r$=r$+str$(a):close2
60 print#15,"/0:sub1":input#15,a:r$=r$+str$(a)
70 open2,8,2,"rootfile,s,r":input#15,a:r$=r$+str$(a):close2
75 print#15,"/"
80 open2,8,2,"@0:result,s,w":print#2,r$:close2:close15
"""


# --- images in Python: blocks, chains, the root BAM -------------------------

def d64_offset(t, s):
    zones = [(17, 21), (24, 19), (30, 18), (40, 17)]
    off, first = 0, 1
    for last, n in zones:
        if t <= last:
            return (off + (t - first) * n + s) * 256
        off += (last - first + 1) * n
        first = last + 1
    raise ValueError(t)


def d81_offset(t, s):
    return ((t - 1) * 40 + s) * 256


class Image:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        self.d81 = path.endswith(".d81")
        self.offset = d81_offset if self.d81 else d64_offset
        self.first_dir = (40, 3) if self.d81 else (18, 1)

    def block(self, t, s):
        o = self.offset(t, s)
        return self.data[o:o + 256]

    def chain(self, t, s, blocks=None):
        """The data of the chain from t/s (its blocks added to blocks)."""
        out = b""
        seen = 0
        while t:
            if blocks is not None:
                blocks.add((t, s))
            b = self.block(t, s)
            t, s = b[0], b[1]
            out += b[2:] if t else b[2:s + 1]
            seen += 1
            if seen > 4000:
                raise ValueError("a chain without end")
        return out

    def entries(self):
        t, s = self.first_dir
        while t:
            b = self.block(t, s)
            for i in range(8):
                e = b[i * 32 + 2:i * 32 + 32]
                if e[0]:
                    yield e
            t, s = b[0], b[1]

    def entry(self, name):
        for e in self.entries():
            if e[3:19].split(b"\xA0")[0] == name.encode("latin1"):
                return e
        return None

    def contents(self, e, blocks=None):
        """A file's parts: its header block, then its data or each record."""
        parts = []
        if e[19]:
            parts.append(self.block(e[19], e[20])[2:])
            if blocks is not None:
                blocks.add((e[19], e[20]))
        if e[19] and e[21] == 1:
            if blocks is not None:
                blocks.add((e[1], e[2]))
            index = self.block(e[1], e[2])
            for r in range(127):
                t, s = index[2 + 2 * r], index[3 + 2 * r]
                parts.append(self.chain(t, s, blocks) if t else ("none" if s == 0xFF else "empty"))
        else:
            parts.append(self.chain(e[1], e[2], blocks))
        return parts

    def root_bam_check(self):
        """D81: blocks marked used in the root BAM and blocks in use (the
        header and BAM blocks, the directory, the files' blocks, the
        partitions' areas) differ by these."""
        used = {(40, 0), (40, 1), (40, 2)}
        t, s = self.first_dir
        while t:
            used.add((t, s))
            t, s = self.block(t, s)[:2]
        for e in self.entries():
            if e[0] & 7 == 5:                    # a partition: its area
                n = e[28] | e[29] << 8
                start = (e[1] - 1) * 40 + e[2]
                used |= {(b // 40 + 1, b % 40) for b in range(start, start + n)}
            else:
                self.contents(e, used)
        marked = set()
        for t in range(1, 81):
            bam = self.block(40, 1 if t <= 40 else 2)
            o = 0x10 + 6 * ((t - 1) % 40)
            bits = int.from_bytes(bam[o + 1:o + 6], "little")
            marked |= {(t, s) for s in range(40) if not bits >> s & 1}
        return sorted(marked - used), sorted(used - marked)


def main():
    e = Engine("e2", 6548)
    v, fe, stat, info, listing, check = e.v, e.fe, e.stat, e.info, e.listing, e.check
    vlir = None
    try:
        e.start()
        free = lambda p: fe(FE_DF, s0=p)[2][1]  # noqa: E731
        check("FE_VERSION", fe(FE_VERSION)[2][0], 3)

        # --- FE_COPY, a CBM file ---------------------------------------
        check("FE_COPY to a new name", (fe(FE_COPY, s0="/b/ROOTFILE", s1="/b/COPY1")[0], stat("/b/COPY1")),
              (0, (0, K_CBM, 1)))
        check("FE_COPY into a folder keeps the name",
              (fe(FE_COPY, s0="/b/ROOTFILE", s1="/b/SUB1")[0], stat("/b/SUB1/ROOTFILE")), (0, (0, K_CBM, 1)))
        check("FE_COPY into a nested partition",
              (fe(FE_COPY, s0="/b/SUB1/HELLO", s1="/b/SUB1/SUB2/HI")[0], stat("/b/SUB1/SUB2/HI")),
              (0, (0, K_CBM, 1)))
        check("FE_COPY relative paths", (fe(FE_CD, s0="/b/SUB1")[0], fe(FE_COPY, s0="HELLO", s1="../HELLO2")[0],
                                         stat("/b/HELLO2"), fe(FE_CD, s0="/")[0]), (0, 0, (0, K_CBM, 1), 0))
        check("FE_COPY onto a file refused", fe(FE_COPY, s0="/b/ROOTFILE", s1="/b/COPY1")[0], FILE_EXISTS)
        check("FE_COPY with overwrite", fe(FE_COPY, s0="/b/ROOTFILE", s1="/b/COPY1", r2=FC_OVERWRITE)[0], 0)
        check("FE_COPY onto itself refused",
              fe(FE_COPY, s0="/b/ROOTFILE", s1="/b/ROOTFILE", r2=FC_OVERWRITE)[0], FILE_EXISTS)
        check("FE_COPY a folder refused", fe(FE_COPY, s0="/b/SUB1", s1="/b/X")[0], IS_FOLDER)
        check("FE_COPY a missing file", fe(FE_COPY, s0="/b/NOPE", s1="/b/X")[0], FILE_NOT_FOUND)
        check("FE_COPY to / refused", fe(FE_COPY, s0="/b/ROOTFILE", s1="/")[0], BAD_PATH)
        check("FE_COPY a partition refused", fe(FE_COPY, s0="/b/RAW", s1="/b/X")[0], IS_FOLDER)

        # --- FE_COPY, a VLIR file from the GEOS disk --------------------
        files = listing("/a", infos=True)
        vlirs = sorted((i[4] | i[5] << 8, n) for n, i in files if i[0] == K_GEOS and i[2] == 1)
        check("the GEOS disk has VLIR files", len(vlirs) > 0, True)
        before = free("/b")
        vlir = [n for size, n in vlirs if size < 200][-1]
        size = [s for s, n in vlirs if n == vlir][0]
        v.mem_set(COUNT, b"\0\0")
        v.mem_set(PROG, bytes(COUNTER))
        x = fe(FE_COPY, s0="/a/" + vlir, s1="/b/VCOPY", r3=PROG)[0]
        a_info, b_info = info("/a/" + vlir)[1], info("/b/VCOPY")[1]
        check("FE_COPY a VLIR file (%s, %d blocks) from A" % (vlir, size), (x, b_info == a_info), (0, True))
        count = v.mem_get(COUNT, COUNT + 1)
        check("the progress routine: once a block", count[0] | count[1] << 8, size)
        check("its blocks taken on B", before - free("/b"), size)
        check("its header copied (FE_STAT's fileHeader)", v.mem_get(0x8100 + 0x4D, 0x8100 + 0x60)[:12] != b"\0" * 12,
              True)
        v.mem_set(PROG, bytes(CANCEL))
        before = free("/b")
        check("a cancelled copy", (fe(FE_COPY, s0="/a/" + vlir, s1="/b/CANCEL", r3=PROG)[0], stat("/b/CANCEL"),
                                   free("/b")), (CANCELLED, (FILE_NOT_FOUND,), before))
        room = free("/b/SUB1/SUB2")
        big = [n for n, i in files if i[0] in (K_GEOS, K_CBM) and (i[4] | i[5] << 8) > room]
        if big:
            check("no room: INSUFF_SPACE", (fe(FE_COPY, s0="/a/" + big[0], s1="/b/SUB1/SUB2")[0],
                                            stat("/b/SUB1/SUB2/" + big[0])), (INSUFF_SPACE, (FILE_NOT_FOUND,)))

        # --- FE_MOVE -------------------------------------------------------
        before = free("/b")
        check("FE_MOVE in one folder: a rename",
              (fe(FE_MOVE, s0="/b/COPY1", s1="/b/MOVED")[0], stat("/b/COPY1"), stat("/b/MOVED"), free("/b")),
              (0, (FILE_NOT_FOUND,), (0, K_CBM, 1), before))
        check("FE_MOVE into a partition",
              (fe(FE_MOVE, s0="/b/MOVED", s1="/b/SUB1/SUB2")[0], stat("/b/MOVED"), stat("/b/SUB1/SUB2/MOVED"),
               free("/b")), (0, (FILE_NOT_FOUND,), (0, K_CBM, 1), before + 1))
        check("FE_MOVE onto a file refused", fe(FE_MOVE, s0="/b/HELLO2", s1="/b/ROOTFILE")[0], FILE_EXISTS)
        check("FE_MOVE with overwrite", (fe(FE_MOVE, s0="/b/HELLO2", s1="/b/SUB1/ROOTFILE", r2=FC_OVERWRITE)[0],
                                         stat("/b/HELLO2")), (0, (FILE_NOT_FOUND,)))

        # --- streams -------------------------------------------------------
        v.mem_set(WBUF, DATA)

        def write(h, start, n):
            return fe(FE_WRITE, y=h, r1=WBUF + start, r2=n)[0]

        def read_all(path, piece):
            x, h, _ = fe(FE_OPEN, s0=path, r2=FO_READ)
            if x:
                return x
            got = b""
            while True:
                x, _, r = fe(FE_READ, y=h, r1=RBUF, r2=piece)
                if x:
                    return ("error", x)
                got += v.mem_get(RBUF, RBUF + piece - 1)[:r[2]] if r[2] else b""
                if r[2] < piece:
                    break
            fe(FE_CLOSE, y=h)
            return got

        x, h, _ = fe(FE_OPEN, s0="/b/NEWFILE", r2=FO_WRITE)
        check("FE_OPEN a new file", (x, stat("/b/NEWFILE")), (0, (0, K_CBM, 1)))
        check("FE_WRITE a block's worth, then across two block ends",
              [write(h, 0, 254), write(h, 254, 254), write(h, 508, 92), fe(FE_CLOSE, y=h)[0]], [0, 0, 0, 0])
        check("its size", stat("/b/NEWFILE"), (0, K_CBM, 3))
        check("FE_READ it whole", read_all("/b/NEWFILE", 1000) == DATA[:600], True)
        x, h, _ = fe(FE_OPEN, s0="/b/NEWFILE", r2=FO_APPEND)
        check("FE_APPEND", [x, write(h, 600, 10), write(h, 610, 200), fe(FE_CLOSE, y=h)[0], stat("/b/NEWFILE")],
              [0, 0, 0, 0, (0, K_CBM, 4)])
        check("FE_READ in pieces of 100", read_all("/b/NEWFILE", 100) == DATA, True)
        check("FE_READ in pieces of 254", read_all("/b/NEWFILE", 254) == DATA, True)
        check("FE_READ a CBM file of the 1581 DOS", read_all("/b/SUB1/HELLO", 50), b"IN SUB1\r")
        x, h, _ = fe(FE_OPEN, s0="/b/SUB1/SUB2/NEW2", r2=FO_APPEND)
        check("FE_APPEND makes a file in a partition",
              [x, write(h, 0, 300), fe(FE_CLOSE, y=h)[0], read_all("/b/SUB1/SUB2/NEW2", 400) == DATA[:300]],
              [0, 0, 0, True])
        x, h, _ = fe(FE_OPEN, s0="/b/SUB1/SUB2/NEW2", r2=FO_WRITE)
        check("FE_OPEN for writing replaces a file",
              [x, write(h, 0, 5), fe(FE_CLOSE, y=h)[0], stat("/b/SUB1/SUB2/NEW2"),
               read_all("/b/SUB1/SUB2/NEW2", 400)], [0, 0, 0, (0, K_CBM, 1), DATA[:5]])
        x, h, _ = fe(FE_OPEN, s0="/b/NEWFILE", r2=FO_READ)
        check("FE_WRITE on a read handle refused", (write(h, 0, 1), fe(FE_CLOSE, y=h)[0]), (BAD_HANDLE, 0))
        x, h, _ = fe(FE_OPEN, s0="/b/NEWFILE", r2=FO_APPEND)
        check("FE_READ on a write handle refused",
              (fe(FE_READ, y=h, r1=RBUF, r2=1)[0], fe(FE_CLOSE, y=h)[0]), (BAD_HANDLE, 0))
        check("FE_OPEN a VLIR file refused", fe(FE_OPEN, s0="/b/VCOPY", r2=FO_READ)[0], STRUCT_MISMAT)
        check("FE_OPEN a folder refused", fe(FE_OPEN, s0="/b/SUB1", r2=FO_READ)[0], IS_FOLDER)
        check("FE_OPEN a missing file to read", fe(FE_OPEN, s0="/b/NOPE", r2=FO_READ)[0], FILE_NOT_FOUND)
        check("FE_OPEN a drive refused", fe(FE_OPEN, s0="/b", r2=FO_WRITE)[0], BAD_PATH)
        check("no handle left open", (fe(FE_OPENDIR, s0="/b")[:2], fe(FE_CLOSE, y=0)[0]), ((0, 0), 0))
    finally:
        after = e.stop()

    # --- the images, read in Python -----------------------------------------
    a, b = Image(harness.ORACLE_DISK), Image(after)
    if vlir:
        src, dst = a.entry(vlir), b.entry("VCOPY")
        check("the VLIR copy: entry fields", (dst[0], dst[19] != 0, dst[21:28], dst[28:30]),
              (src[0], True, src[21:28], src[28:30]))
        check("the VLIR copy: header and records equal", b.contents(dst) == a.contents(src), True)
    check("drive B's root BAM: exactly the blocks in use", b.root_bam_check(), ([], []))
    part81.basic_on(after, CHECK, "e2-check")
    # NEWFILE read (0, 810 bytes), ROOTFILE (0), SUB1 (2), the copy in it (0)
    check("the real 1581 DOS reads them", (part81.result_text(after) or "").split(),
          ["0", "810", "0", "2", "0"])
    sys.exit(0 if e.ok else 1)


if __name__ == "__main__":
    main()
