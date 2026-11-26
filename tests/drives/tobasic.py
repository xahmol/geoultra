#!/usr/bin/env python3
"""ToBASIC with programs on a GeoUltra drive, in VICE (src/kernal/tobasic.s,
modules 128-130).

GEOS 2.0's deskTop starts a BASIC file through ToBASIC itself only when
it loads at $0801 and has fewer than 121 blocks; any other with r5 = 0
and the command LOAD "name",8[,1], which BASIC would send to the IEC bus.
GeoUltra loads such a file from its own drive (staged in the REU, put in
place after the switch to BASIC) and types the rest of the command, or
RUN. Boot files of other GEOS systems are refused with a dialog.

Drive B (device 9) is a D64 made here with geosdisk: BIG, a BASIC program
of 153 blocks up to $9EFF (PRINT "BIG OK", then a pattern over GEOS's
own memory); ML, three bytes at $2000 that store $5A at $033C. Cases (each in its own VICE run):
- r5 = an entry named RBOOT: refused (the dialog, no BASIC);
- LOAD "GEOS",9,1: refused by its name;
- LOAD "BIG",9: loaded from drive B, RUN typed: "BIG OK" on the screen,
  the pattern in place up to $9EFF;
- LOAD "ML",9,1:SYS8192: at $2000, SYS typed, $5A.
Usage: tests/drives/tobasic.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
import geosdisk  # noqa: E402

TEST_DISK = os.path.join(ROOT, "build", "harness", "tobasic-test.d64")
os.environ["GEOS_APPS_DISK"] = TEST_DISK
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6527
CMD, ENTRY, RES = 0x5000, 0x5100, 0x02F0
FILE_HEADER = 0x8100
BIG_END = 0x9F00


def big_program():
    """PRINT "BIG OK" at $0801, then a pattern up to BIG_END."""
    line = bytes([0x99]) + b' "BIG OK"' + b"\0"
    nxt = 0x0801 + 4 + len(line)
    prog = bytes([nxt & 0xFF, nxt >> 8, 10, 0]) + line + b"\0\0"
    pad = bytes(((a * 7) ^ 0x5A) & 0xFF for a in range(0x0801 + len(prog), BIG_END))
    return b"\x01\x08" + prog + pad


def make_disk():
    os.makedirs(os.path.dirname(TEST_DISK), exist_ok=True)
    if os.path.exists(TEST_DISK):
        os.remove(TEST_DISK)
    d = geosdisk.Disk.new(TEST_DISK, "TOBASIC", "TB")
    d.add(geosdisk.plain("BIG", big_program()))
    d.add(geosdisk.plain("ML", b"\x00\x20" + bytes([0xA9, 0x5A, 0x8D, 0x3C, 0x03, 0x60])))
    d.save()


def pattern_ok(v):
    want = bytes(((a * 7) ^ 0x5A) & 0xFF for a in range(0x9000, BIG_END))
    return bytes(v.mem_get(0x9000, BIG_END - 1)) == want


def screen_has(v, text):
    codes = bytes((c - 0x40) if 0x41 <= c <= 0x5A else c for c in text.encode())
    return codes in bytes(v.mem_get(0x0400, 0x07E7))


class Session:
    def __init__(self):
        apprun.APPS_DISK = TEST_DISK
        apprun.REU_IMAGE = apprun.REU_IMAGE.replace("reu-apps", "reu-tobasic")
        apprun.reu_image()
        cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
               "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
               "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
               "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "+reuimagerw"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.v = Vice(port=PORT)
        self.t = harness.jumptab()
        v = self.v
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)                  # MainLoop reached
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)

    def jsr(self, name):
        a = self.t[name]
        return [0x20, a & 0xFF, a >> 8]

    def to_basic(self, command, entry=None, wait=6):
        """ToBASIC with r0 = command, r5 = entry (or 0), r7 = $0803."""
        v = self.v
        v.mem_set(CMD, command.encode() + b"\0")
        r5 = 0
        if entry is not None:
            v.mem_set(ENTRY, bytes(entry))
            r5 = ENTRY
        prog = [0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + self.jsr("SetDevice") + self.jsr("OpenDisk")
        for value, zp in ((CMD, 0x02), (r5, 0x0C), (0x0803, 0x10)):
            prog += [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]
        prog += self.jsr("ToBASIC")
        start = harness.TRAMPOLINE
        end = start + len(prog)
        prog += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(FILE_HEADER, b"\0" * 256)
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(wait)
        v.ping()

    def refused(self):
        """The refusal dialog's text in fileHeader, and GEOS still on."""
        text = bytes(self.v.mem_get(FILE_HEADER, FILE_HEADER + 0xFF))
        port = self.v.mem_get(0x01, 0x01)[0] & 7
        return b"another GEOS system" in text and port != 7, port

    def close(self):
        try:
            self.v.quit()
        except OSError:
            pass
        self.proc.kill()
        self.proc.wait()                            # (the port free for the
        time.sleep(1)                               # next case's VICE)


def main():
    make_disk()
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, (": " + detail) if detail else ""))

    def fresh(case):                                # one VICE run per case: a
        s = Session()                               # refusal leaves its dialog
        try:                                        # open, BASIC ends GEOS
            case(s)
        finally:
            s.close()

    def rboot(s):
        entry = [0x82, 1, 0] + list(b"RBOOT".ljust(16, b"\xA0")) + [0] * 11
        s.to_basic("RUN", entry=entry, wait=4)
        good, port = s.refused()
        check("r5 = RBOOT's entry: refused with the dialog", good, "CPU port %d" % port)

    def geos(s):
        s.to_basic('LOAD "GEOS",9,1', wait=4)
        good, port = s.refused()
        check('LOAD "GEOS",9,1: refused by its name', good, "CPU port %d" % port)

    def big(s):
        s.to_basic('LOAD "BIG",9', wait=10)
        shown, placed = screen_has(s.v, "BIG OK"), pattern_ok(s.v)
        check('LOAD "BIG",9 (153 blocks): from drive B, RUN typed, it ran', shown and placed,
              "screen %s, pattern up to $9EFF %s" % ("BIG OK" if shown else "without it",
                                                    "in place" if placed else "NOT in place"))

    def ml(s):
        s.to_basic('LOAD "ML",9,1:SYS8192', wait=10)
        marker = s.v.mem_get(0x033C, 0x033C)[0]
        code = bytes(s.v.mem_get(0x2000, 0x2004))
        check('LOAD "ML",9,1:SYS8192: at $2000, SYS typed and run',
              marker == 0x5A and code == bytes([0xA9, 0x5A, 0x8D, 0x3C, 0x03]),
              "$033C = $%02X, $2000: %s" % (marker, code.hex()))

    for case in (rboot, geos, big, ml):
        fresh(case)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
