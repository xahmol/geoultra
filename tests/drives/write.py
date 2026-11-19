#!/usr/bin/env python3
"""Writing to native (DNP) and 1571 (D71) drives on GeoUltra in VICE.

GEOS 2.0 in VICE has no native drives and no 1571 set-up here, so this
checks GeoUltra against itself and, for the 1571, against a model of GEOS
2.0's SetNextFree (mist64/geos drv/drv1571.s, behaviour reference only).
Drive B is the image:

  native  a copy of GEOS_NATIVE_DISK (default the user's own
          ramapps.DNP in GEOS_DEV, only read, never committed)
          with its directory cut back to its first block
  d71     a freshly formatted, empty double-sided D71 made here

Checks: for a sequential and a VLIR file SaveFile, FindFile, ReadFile
(the data must come back), the blocks used, DeleteFile and the free count;
BAM changes without PutDirHead are dropped by GetDirHead; the directory
grows; for the 1571 also a sequence of SetNextFree results.
Usage: tests/drives/write.py native|d71
"""
import os
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
KIND = sys.argv[1] if len(sys.argv) > 1 else "native"
SOURCE = localcfg.disk("GEOS_NATIVE_DISK", "ramapps.DNP")
TEST_DISK = os.path.join(ROOT, "build", "harness", {"native": "native-test.dnp",
                                                    "d71": "write-test.d71"}[KIND])
os.environ["GEOS_APPS_DISK"] = TEST_DISK
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6523
NAME, HDR, DATA, BACK, RES = 0x4F00, 0x4000, 0x4400, 0x5000, 0x02F0
DIR_START = {"native": (1, 34), "d71": (18, 1)}[KIND]
SPARE = {"native": (60, 5), "d71": (40, 3)}[KIND]      # a free block to allocate


def sectors(track):
    t = track - 35 if track > 35 else track
    return 21 if t < 18 else 19 if t < 25 else 18 if t < 31 else 17


def header(struct, length):
    h = [0] * 256
    h[0], h[1] = NAME & 0xFF, NAME >> 8
    h[2], h[3], h[4] = 3, 21, 0xBF
    h[0x44], h[0x45], h[0x46] = 0x83, 7, struct
    end = DATA + length
    h[0x47], h[0x48], h[0x49], h[0x4A] = DATA & 0xFF, DATA >> 8, end & 0xFF, end >> 8
    h[0x4D:0x4D + 12] = [ord(c) for c in "GeoUltraTest"]
    return h


def blank_d71():
    """An empty double-sided 1571 disk in the CBM DOS layout: BAM 18/0
    (tracks 1-35, the free counts of 36-70 at $DD), 53/0 (sector bits of
    tracks 36-70), the directory from 18/1."""
    d = bytearray(1366 * 256)
    offset = {}
    o = 0
    for t in range(1, 71):
        offset[t] = o
        o += sectors(t) * 256
    bam = bytearray(256)
    bam[0:4] = bytes([18, 1, 0x41, 0x80])
    bam2 = bytearray(256)
    for t in range(1, 71):
        n = sectors(t)
        free = set(range(n))
        if t == 18:
            free -= {0, 1}
        if t == 53:
            free = set()
        bits = 0
        for s in free:
            bits |= 1 << s
        if t <= 35:
            bam[4 * t] = len(free)
            bam[4 * t + 1:4 * t + 4] = bits.to_bytes(3, "little")
        else:
            bam[0xDD + t - 36] = len(free)
            bam2[3 * (t - 36):3 * (t - 36) + 3] = bits.to_bytes(3, "little")
    bam[0x90:0xA0] = b"GEOULTRA D71" + b"\xA0" * 4
    bam[0xA0:0xAB] = b"\xA0\xA0GU\xA02A\xA0\xA0\xA0\xA0"
    d[offset[18]:offset[18] + 256] = bam
    d[offset[18] + 256:offset[18] + 258] = b"\x00\xFF"
    d[offset[53]:offset[53] + 256] = bam2
    return d


def next_free_model(bam, bam2, r3, interleave=8):
    """GEOS 2.0's 1571 SetNextFree on a model BAM (dicts track -> set of
    free sectors in bam/bam2 are folded into one: bam[track])."""
    r3l, r3h = r3
    r6l, r6h = r3l, (r3h + interleave) & 0xFF
    track = r6l
    check = track in (18, 53)
    while True:
        if check or track not in (18, 53):
            check = False
            if bam[track]:
                n = sectors(track)
                for _ in range(n):
                    r6h %= n
                    if r6h in bam[track]:
                        bam[track].discard(r6h)
                        return track, r6h
                    r6h += 1
        if track < 36:
            track += 35
        else:
            track -= 34
            if track >= 36:
                return None
        a = (track - r3l) & 0xFF
        carry = a >> 7
        r6h = ((a << 1) & 0xFF) + 4 + carry
        r6h = (r6h + interleave) & 0xFF


def make_disk():
    os.makedirs(os.path.dirname(TEST_DISK), exist_ok=True)
    if KIND == "d71":
        open(TEST_DISK, "wb").write(blank_d71())
        return
    d = bytearray(open(SOURCE, "rb").read())   # native: directory cut back to 1/34
    first = ((1 - 1) * 256 + 34) * 256
    d[first:first + 2] = b"\x00\xFF"
    open(TEST_DISK, "wb").write(d)


def main():
    make_disk()
    apprun.APPS_DISK = os.environ["GEOS_APPS_DISK"]
    apprun.REU_IMAGE = apprun.REU_IMAGE.replace("reu-apps", "reu-write-" + KIND)
    apprun.reu_image()
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "+reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    t = harness.jumptab()

    def jsr(name):
        a = t[name]
        return [0x20, a & 0xFF, a >> 8]

    def ldw(value, zp):
        return [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]

    def run(code, wait=3):
        start = harness.TRAMPOLINE
        prog = [0x78, 0xA9, 0x30, 0x85, 0x01] + code
        end = start + len(prog)
        prog += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(wait)
        v.ping()

    open_b = [0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")

    def free():                                 # CalcBlksFree -> r4
        run(open_b + ldw(0x8200, 0x0C) + jsr("CalcBlksFree"))
        z = v.mem_get(0x0A, 0x0B)
        return z[0] | z[1] << 8

    def free_slots():                           # empty entries in the directory
        slots = 0
        tr, sc = DIR_START
        while tr:
            run(ldw(0x8000, 0x0A) + [0xA9, tr, 0x85, 0x04, 0xA9, sc, 0x85, 0x05]
                + [0xA9, 0x09] + jsr("SetDevice") + jsr("GetBlock"), wait=1)
            blk = v.mem_get(0x8000, 0x80FF)
            slots += sum(1 for i in range(8) if blk[i * 32 + 2] == 0)
            tr, sc = blk[0], blk[1]
        return slots

    ok = True
    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        for title, struct, length, blocks in (("sequential, 1000 bytes", 0, 1000, 5),
                                              ("VLIR, empty index", 1, 0, 2)):
            before = free()
            if not free_slots():
                blocks += 1                     # a new directory block (it stays)
            data = bytes((i * 13 + 5) & 0xFF for i in range(1000))
            v.mem_set(NAME, b"GeoUltra write\0")
            v.mem_set(HDR, bytes(header(struct, length)))
            v.mem_set(DATA, data)
            v.mem_set(BACK, b"\xEE" * 1100)
            v.mem_set(RES, b"\xEE" * 4)
            run(open_b + ldw(HDR, 0x14) + [0xA9, 0, 0x85, 0x16] + jsr("SaveFile")
                + [0x8E, RES & 0xFF, RES >> 8]
                + ldw(NAME, 0x0E) + jsr("FindFile") + [0x8E, (RES + 1) & 0xFF, RES >> 8]
                + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05]
                + ldw(BACK, 0x10) + ldw(0x1000, 0x06) + jsr("ReadFile")
                + [0x8E, (RES + 2) & 0xFF, RES >> 8], wait=5)
            res = v.mem_get(RES, RES + 2)
            back = v.mem_get(BACK, BACK + length - 1) if length else b""
            used = before - free()
            run(open_b + ldw(NAME, 0x02) + jsr("DeleteFile")
                + [0x8E, (RES + 3) & 0xFF, RES >> 8], wait=5)
            deleted = v.mem_get(RES + 3, RES + 3)[0]
            after = free()
            kept = blocks - (5 if length else 2)        # directory blocks stay
            good = (list(res) == [0, 0, 0] if length else list(res[:2]) == [0, 0]) \
                and back == data[:length] and used == blocks and deleted == 0 \
                and before - after == kept
            ok = ok and good
            print("%s %s: SaveFile X=$%02X, FindFile X=$%02X, ReadFile X=$%02X, data %s, "
                  "%d blocks used (expected %d), DeleteFile X=$%02X, free %d -> %d"
                  % ("pass" if good else "FAIL", title, res[0], res[1], res[2],
                     "same" if back == data[:length] else "DIFFERENT", used, blocks,
                     deleted, before, after))

        # BAM changes without PutDirHead are gone after GetDirHead (OpenDisk),
        # with PutDirHead they stay (FreeBlock + PutDirHead gives it back).
        base = free()
        blk6 = [0xA9, SPARE[0], 0x85, 0x0E, 0xA9, SPARE[1], 0x85, 0x0F]
        run(open_b + blk6 + jsr("AllocateBlock")
            + [0x8E, RES & 0xFF, RES >> 8] + ldw(0x8200, 0x0C) + jsr("CalcBlksFree"))
        alloc_x = v.mem_get(RES, RES)[0]
        z = v.mem_get(0x0A, 0x0B)
        in_copy = z[0] | z[1] << 8
        dropped = free()
        run(open_b + blk6 + jsr("AllocateBlock") + jsr("PutDirHead"))
        kept = free()
        run(open_b + blk6 + jsr("FreeBlock") + jsr("PutDirHead"))
        back = free()
        good = alloc_x == 0 and in_copy == base - 1 and dropped == base and kept == base - 1 \
            and back == base
        ok = ok and good
        print("%s BAM in memory: AllocateBlock X=$%02X, free %d -> %d, %d after GetDirHead "
              "(dropped), %d with PutDirHead (kept), %d after FreeBlock + PutDirHead"
              % ("pass" if good else "FAIL", alloc_x, base, in_copy, dropped, kept, back))

        if KIND == "d71":
            # SetNextFree on the empty disk from several starts, 30 times
            # each (without PutDirHead), against the model.
            model_bam = {}
            for tr in range(1, 71):
                n = sectors(tr)
                fs = set(range(n))
                if tr == 18:
                    fs -= {0, 1}
                if tr == 53:
                    fs = set()
                model_bam[tr] = fs
            for start in ((1, 0), (17, 10), (35, 5), (52, 0), (70, 3)):
                bam = {k: set(s) for k, s in model_bam.items()}
                expect, r3 = [], start
                for _ in range(30):             # no free block: r3 stays
                    r3 = next_free_model(bam, None, r3) or r3
                    expect.append(r3)
                code = open_b + [0xA9, start[0], 0x85, 0x08, 0xA9, start[1], 0x85, 0x09]
                for i in range(30):              # SetNextFree, store r3 at $4C00 + 2i
                    code += jsr("SetNextFree") + [0xA5, 0x08, 0x8D, (2 * i) & 0xFF, 0x4C,
                                                  0xA5, 0x09, 0x8D, (2 * i + 1) & 0xFF, 0x4C]
                v.mem_set(0x4C00, b"\x00" * 60)
                run(code, wait=3)
                got = v.mem_get(0x4C00, 0x4C3B)
                got = [(got[2 * i], got[2 * i + 1]) for i in range(30)]
                good = got == expect
                ok = ok and good
                print("%s SetNextFree from %d/%d: %s%s" % (
                    "pass" if good else "FAIL", start[0], start[1],
                    " ".join("%d/%d" % b for b in got[:8]) + " ...",
                    "" if good else "\n     expected " + " ".join(
                        "%d/%d" % b if b else "-" for b in expect[:12])))

        # The directory grows: as many files as free slots plus 10, then all
        # deleted again (the new directory blocks stay, as on GEOS 2.0).
        before = free()
        slots = free_slots()
        count = slots + 10
        v.mem_set(HDR, bytes(header(0, 300)))
        names = ["GU dir %03d" % i for i in range(count)]
        saved = 0
        for n in names:
            v.mem_set(NAME, n.encode() + b"\0")
            v.mem_set(RES, b"\xEE")
            run(open_b + ldw(HDR, 0x14) + [0xA9, 0, 0x85, 0x16] + jsr("SaveFile")
                + [0x8E, RES & 0xFF, RES >> 8], wait=1.5)
            saved += v.mem_get(RES, RES)[0] == 0
        mid = free()
        gone = 0
        for n in names:
            v.mem_set(NAME, n.encode() + b"\0")
            v.mem_set(RES, b"\xEE")
            run(open_b + ldw(NAME, 0x02) + jsr("DeleteFile") + [0x8E, RES & 0xFF, RES >> 8],
                wait=1.5)
            gone += v.mem_get(RES, RES)[0] == 0
        after = free()
        grown = -(-(count - slots) // 8)        # new directory blocks
        counted = grown if KIND == "native" else 0      # (track 18 is not counted)
        good = saved == count and gone == count and before - mid == 3 * count + counted \
            and before - after == counted
        ok = ok and good
        print("%s directory growth: %d free slots, %d files saved, %d deleted; free %d -> %d "
              "(expected -%d: 3 blocks a file, %d new directory blocks) -> %d (the directory "
              "blocks stay)" % ("pass" if good else "FAIL", slots, saved, gone, before, mid,
                                3 * count + counted, grown, after))
    finally:
        v.quit()
        proc.kill()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
