#!/usr/bin/env python3
"""Check GeoUltra's answer to an application's first-run disk check.

A 1541 copy-protection loader (as described in "Inside geoWrite 5: Copy
Protection", pagetable.com) follows the NewDisk vector, finds the first
STA $8B behind it, and calls the drive-execute and status calls that
follow, between EnterTurbo/InitForIO and DoneWithIO; X = 0 means "original
disk". This test does the same in VICE with drive A (a 1541 image) and
expects an error with the optional module off and X = 0 with it on
(src/kernal/bypass.s). Usage: tests/bypass/hook.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6509


def label(name):
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        if line.strip().endswith("." + name):
            return int(line.split()[1], 16)
    return None


def run(bypass):
    apprun.reu_image()
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "+reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)                  # stop at the top of MainLoop
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        if bypass:
            v.mem_set(label("bypassOn"), b"\x80")
        t = harness.jumptab()
        entry = v.mem_get(t["NewDisk"], t["NewDisk"] + 2)
        code = entry[1] | entry[2] << 8
        if entry[0] == 0x6C:                            # jmp (vector)
            vec = v.mem_get(code, code + 1)
            code = vec[0] | vec[1] << 8
        area = v.mem_get(code, code + 255)
        i = area.find(b"\x85\x8b")
        assert i >= 0, "no STA $8B behind NewDisk"
        calls = list(area[i + 2:i + 8])

        def jsr(name):
            a = t[name]
            return [0x20, a & 0xFF, a >> 8]
        start = harness.TRAMPOLINE
        prog = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x08] + jsr("SetDevice") + jsr("OpenDisk")
                + jsr("EnterTurbo") + jsr("InitForIO")
                + [0xA9, 0x05, 0x85, 0x8B, 0xA9, 0x07, 0x85, 0x8C] + calls
                + [0x8E, 0xF0, 0x02] + jsr("DoneWithIO"))
        end = start + len(prog)
        prog += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(0x02F0, b"\xEE")
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(1)
        v.ping()
        if os.environ.get("HOOK_DEBUG"):
            print("PC $%04X, program at $%04X-$%04X, calls %s" % (
                v.regs_get()["PC"], start, end, bytes(calls).hex()))
        return v.mem_get(0x02F0, 0x02F0)[0]
    finally:
        v.quit()
        proc.kill()
        proc.wait()
        time.sleep(1)


def main():
    if label("bypassOn") is None:
        print("built without the module (BYPASS=0): only the 'off' case")
    off = run(False)
    print("module off: X = $%02X (%s)" % (off, "pass" if off not in (0, 0xEE) else "FAIL"))
    ok = off not in (0, 0xEE)
    if label("bypassOn") is not None:
        on = run(True)
        print("module on:  X = $%02X (%s)" % (on, "pass" if on == 0 else "FAIL"))
        ok = ok and on == 0
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
