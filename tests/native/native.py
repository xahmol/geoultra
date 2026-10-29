#!/usr/bin/env python3
"""Writing to a native (DNP) drive on GeoUltra in VICE.

GEOS 2.0 has no native drives, so this checks GeoUltra against itself:
drive B is a native image (GEOS_NATIVE_DISK, default the user's own
~/geos-dev/u64-usb/ramapps.DNP, never committed). For a sequential and a
VLIR file: CalcBlksFree, SaveFile, FindFile, ReadFile (the data must come
back), CalcBlksFree (blocks used as expected), DeleteFile, CalcBlksFree
(back to the start). Usage: tests/native/native.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
SOURCE = os.environ.get("GEOS_NATIVE_DISK", os.path.expanduser("~/geos-dev/u64-usb/ramapps.DNP"))
TEST_DISK = os.path.join(ROOT, "build", "harness", "native-test.dnp")
os.environ["GEOS_APPS_DISK"] = TEST_DISK
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6523
NAME, HDR, DATA, BACK, RES = 0x4F00, 0x4000, 0x4400, 0x5000, 0x02F0


def header(struct, length):
    h = [0] * 256
    h[0], h[1] = NAME & 0xFF, NAME >> 8
    h[2], h[3], h[4] = 3, 21, 0xBF
    h[0x44], h[0x45], h[0x46] = 0x83, 7, struct
    end = DATA + length
    h[0x47], h[0x48], h[0x49], h[0x4A] = DATA & 0xFF, DATA >> 8, end & 0xFF, end >> 8
    h[0x4D:0x4D + 12] = [ord(c) for c in "GeoUltraTest"]
    return h


def test_disk():
    """A copy of the source image whose directory is cut back to its
    first block (1/34), so that saving more files must grow it."""
    d = bytearray(open(SOURCE, "rb").read())
    first = ((1 - 1) * 256 + 34) * 256
    d[first:first + 2] = b"\x00\xFF"
    os.makedirs(os.path.dirname(TEST_DISK), exist_ok=True)
    open(TEST_DISK, "wb").write(d)


def main():
    test_disk()
    apprun.APPS_DISK = os.environ["GEOS_APPS_DISK"]
    apprun.REU_IMAGE = apprun.REU_IMAGE.replace("reu-apps", "reu-native")
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

    def free():                                 # CalcBlksFree -> r4
        run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
            + ldw(0x8200, 0x0C) + jsr("CalcBlksFree"))
        z = v.mem_get(0x0A, 0x0B)
        return z[0] | z[1] << 8

    def free_slots():                           # empty entries in the directory
        slots = 0
        tr, sc = 1, 34                          # native: directory from 1/34
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
            v.mem_set(NAME, b"GeoUltra native\0")
            v.mem_set(HDR, bytes(header(struct, length)))
            v.mem_set(DATA, data)
            v.mem_set(BACK, b"\xEE" * 1100)
            v.mem_set(RES, b"\xEE" * 4)
            run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + ldw(HDR, 0x14) + [0xA9, 0, 0x85, 0x16] + jsr("SaveFile")
                + [0x8E, RES & 0xFF, RES >> 8]
                + ldw(NAME, 0x0E) + jsr("FindFile") + [0x8E, (RES + 1) & 0xFF, RES >> 8]
                + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05]
                + ldw(BACK, 0x10) + ldw(0x1000, 0x06) + jsr("ReadFile")
                + [0x8E, (RES + 2) & 0xFF, RES >> 8], wait=5)
            res = v.mem_get(RES, RES + 2)
            back = v.mem_get(BACK, BACK + length - 1) if length else b""
            used = before - free()
            run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + ldw(NAME, 0x02) + jsr("DeleteFile") + [0x8E, (RES + 3) & 0xFF, RES >> 8], wait=5)
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
        # The BAM works on a copy, as GEOS 2.0's curDirHead: an allocation
        # without PutDirHead is gone after GetDirHead (OpenDisk); with
        # PutDirHead it stays (and FreeBlock + PutDirHead gives it back).
        base = free()
        blk6 = [0xA9, 60, 0x85, 0x0E, 0xA9, 5, 0x85, 0x0F]      # r6 = 60/5
        run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk") + blk6 + jsr("AllocateBlock")
            + [0x8E, RES & 0xFF, RES >> 8] + ldw(0x8200, 0x0C) + jsr("CalcBlksFree"))
        alloc_x = v.mem_get(RES, RES)[0]
        z = v.mem_get(0x0A, 0x0B)
        in_copy = z[0] | z[1] << 8
        dropped = free()                        # OpenDisk: GetDirHead
        run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk") + blk6 + jsr("AllocateBlock")
            + jsr("PutDirHead"))
        kept = free()
        run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk") + blk6 + jsr("FreeBlock")
            + jsr("PutDirHead"))
        back = free()
        good = alloc_x == 0 and in_copy == base - 1 and dropped == base and kept == base - 1 \
            and back == base
        ok = ok and good
        print("%s BAM copy: AllocateBlock X=$%02X, free %d -> %d in the copy, %d after GetDirHead "
              "(dropped), %d with PutDirHead (kept), %d after FreeBlock + PutDirHead"
              % ("pass" if good else "FAIL", alloc_x, base, in_copy, dropped, kept, back))

        # The directory grows: as many files as free slots plus 10, then all
        # deleted again (the new directory block stays, as on GEOS 2.0).
        before = free()
        slots = free_slots()
        count = slots + 10
        v.mem_set(HDR, bytes(header(0, 300)))
        names = ["GU dir %03d" % i for i in range(count)]
        saved = 0
        for n in names:
            v.mem_set(NAME, n.encode() + b"\0")
            v.mem_set(RES, b"\xEE")
            run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + ldw(HDR, 0x14) + [0xA9, 0, 0x85, 0x16] + jsr("SaveFile")
                + [0x8E, RES & 0xFF, RES >> 8], wait=1.5)
            x = v.mem_get(RES, RES)[0]
            saved += x == 0
            if x and os.environ.get("NATIVE_DEBUG"):
                print("  SaveFile %s: X=$%02X r10L=%02X r1=%s" % (n, x, v.mem_get(0x16, 0x16)[0],
                                                             v.mem_get(0x04, 0x05).hex()))
        mid = free()
        gone = 0
        for n in names:
            v.mem_set(NAME, n.encode() + b"\0")
            v.mem_set(RES, b"\xEE")
            run([0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + ldw(NAME, 0x02) + jsr("DeleteFile") + [0x8E, RES & 0xFF, RES >> 8], wait=1.5)
            gone += v.mem_get(RES, RES)[0] == 0
        after = free()
        grown = -(-(count - slots) // 8)        # new directory blocks
        good = saved == count and gone == count and before - mid == 3 * count + grown \
            and before - after == grown
        ok = ok and good
        print("%s directory growth: %d free slots, %d files saved, %d deleted; free %d -> %d "
              "(expected -%d: 3 blocks a file, %d new directory blocks) -> %d (the directory "
              "blocks stay)" % ("pass" if good else "FAIL", slots, saved, gone, before, mid,
                                3 * count + grown, grown, after))
    finally:
        v.quit()
        proc.kill()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
