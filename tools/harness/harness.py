#!/usr/bin/env python3
"""Conformance harness: run kernal routines on GEOS 2.0 and on GeoUltra in
VICE and compare the results (docs/ARCHITECTURE.md, DESIGN.md).

Usage: harness.py [--rebuild] [--keep] CASEFILE.py [CASEFILE.py ...]

For each system the harness boots VICE once, stops at the top of
MainLoop and saves a snapshot (build/harness/<system>.vsf, reused unless
--rebuild). Every test case then restores the snapshot, clears both
screen buffers, writes its inputs, calls the routine through a
trampoline in the cassette buffer and reads the results. A case passes
when every item in its `compare` list is equal on both systems.

Case files define CASES, a list of dicts:
  name     text
  routine  jump table name (src/kernal/jumptab.txt)
  a, x, y  register values (optional)
  r        {"r3": 10, "r11L": 50, ...} pseudo-register inputs
  pattern  8 bytes for curPattern (optional; curPattern points to them)
  disp     dispBufferOn (default $C0: foreground and background)
  mem      {address: bytes} extra memory writes
  compare  list of: "fore", "back" (screen buffers), "A", "X", "Y",
           r-register names (r0..r15, r0L..r15H)
"""
import argparse
import importlib.util
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "harness")
VICE = os.path.expanduser("~/.local/opt/vice-3.10/bin/x64sc")
ORACLE_DISK = os.environ.get(
    "GEOS_ORACLE", os.path.expanduser("~/geos-dev/u64-usb/GEOS64-v2.0-unkeyed.d64"))

SYSTEMS = {
    "geos": ["-drive8truedrive", "+autostart-delay-random", "-autostart-delay", "3",
             "-autostart", ORACLE_DISK],
    "geoultra": ["-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
                 "-reu", "-reusize", "16384"],
}
PORTS = {"geos": 6502, "geoultra": 6503}

TRAMPOLINE = 0x0340
TRAMP_END = 0x0344
PATTERN_BUF = 0x0380
FORE = (0xA000, 0xBF3F)
BACK = (0x6000, 0x7F3F)
CUR_PATTERN = 0x22
DISP_BUFFER_ON = 0x2F


def jumptab():
    names = [l.split("#")[0].strip()
             for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
    names = [n for n in names if n]
    return dict((n, 0xC100 + 3 * i) for i, n in enumerate(names))


def rreg(name):
    """Address and size of r0..r15, r0L..r15H."""
    base = name.rstrip("LH")
    addr = 2 + 2 * int(base[1:])
    if name.endswith("H"):
        return addr + 1, 1
    if name.endswith("L"):
        return addr, 1
    return addr, 2


class System:
    def __init__(self, name, rebuild):
        self.name = name
        self.snapshot = os.path.join(OUT, name + ".vsf")
        args = [VICE, "-default", "+sound", "-warp", "-binarymonitor",
                "-binarymonitoraddress", "127.0.0.1:%d" % PORTS[name]] + SYSTEMS[name]
        self.log = open(os.path.join(OUT, name + ".log"), "w")
        self.proc = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT)
        self.vice = Vice(port=PORTS[name])
        crt = os.path.join(ROOT, "build", "geoultra64.crt")
        stale = (name == "geoultra" and os.path.exists(self.snapshot)
                 and os.path.getmtime(crt) > os.path.getmtime(self.snapshot))
        if rebuild or stale or not os.path.exists(self.snapshot):
            self.make_snapshot()

    def make_snapshot(self):
        """Let the system boot, then stop at the top of its MainLoop."""
        v = self.vice
        for _ in range(60):
            v.resume()
            time.sleep(2)
            v.ping()                        # stops the emulation
            jt = v.mem_get(0xC1C3, 0xC1C5)
            if jt[0] == 0x4C and v.mem_get(0xA000, 0xA000)[0] != 0:
                break
        else:
            raise SystemExit("%s: no GEOS kernal after boot" % self.name)
        time.sleep(0)
        main = jt[1] | jt[2] << 8
        v.checkpoint(main)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.dump(self.snapshot)
        print("%s: snapshot at MainLoop $%04X" % (self.name, main))

    def run(self, case, table):
        v = self.vice
        v.undump(self.snapshot)
        v.mem_set(FORE[0], bytes(FORE[1] - FORE[0] + 1))
        v.mem_set(BACK[0], bytes(BACK[1] - BACK[0] + 1))
        addr = table[case["routine"]]
        v.mem_set(TRAMPOLINE, bytes([0x78, 0x20, addr & 0xFF, addr >> 8,
                                     0xEA, 0x4C, TRAMP_END & 0xFF, TRAMP_END >> 8]))
        v.mem_set(DISP_BUFFER_ON, bytes([case.get("disp", 0xC0)]))
        if "pattern" in case:
            v.mem_set(PATTERN_BUF, bytes(case["pattern"]))
            v.mem_set(CUR_PATTERN, bytes([PATTERN_BUF & 0xFF, PATTERN_BUF >> 8]))
        for name, value in case.get("r", {}).items():
            a, size = rreg(name)
            v.mem_set(a, bytes([value & 0xFF, value >> 8 & 0xFF][:size]))
        for a, data in case.get("mem", {}).items():
            v.mem_set(a, bytes(data))
        regs = {"PC": TRAMPOLINE}
        for r in ("A", "X", "Y"):
            if r.lower() in case:
                regs[r] = case[r.lower()]
        v.regs_set(regs)
        v.checkpoint(TRAMP_END)
        v.resume()
        v.wait_event(RESP_CHECKPOINT, timeout=30)
        out = {}
        cpu = v.regs_get()
        for item in case["compare"]:
            if item == "fore":
                out[item] = v.mem_get(*FORE)
            elif item == "back":
                out[item] = v.mem_get(*BACK)
            elif item in ("A", "X", "Y"):
                out[item] = cpu[item]
            else:
                a, size = rreg(item)
                out[item] = v.mem_get(a, a + size - 1)
        return out

    def close(self):
        self.vice.quit()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def describe(item, ours, ref):
    if isinstance(ref, bytes) and len(ref) > 2:
        diffs = [i for i in range(len(ref)) if ref[i] != ours[i]]
        base = FORE[0] if item == "fore" else BACK[0]
        shown = ", ".join("$%04X geos %02X ours %02X" % (base + i, ref[i], ours[i])
                          for i in diffs[:4])
        return "%s: %d bytes differ (%s)" % (item, len(diffs), shown)
    return "%s: geos %s ours %s" % (item, ref.hex() if isinstance(ref, bytes) else ref,
                                     ours.hex() if isinstance(ours, bytes) else ours)


def load_cases(paths):
    cases = []
    for p in paths:
        spec = importlib.util.spec_from_file_location(os.path.basename(p)[:-3], p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        cases += mod.CASES
    return cases


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--rebuild", action="store_true", help="make new snapshots")
    ap.add_argument("casefiles", nargs="+")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    cases = load_cases(args.casefiles)
    table = jumptab()
    results = {}
    for name in ("geos", "geoultra"):
        system = System(name, args.rebuild)
        try:
            results[name] = [system.run(c, table) for c in cases]
        finally:
            system.close()
    failed = 0
    for i, case in enumerate(cases):
        ref, ours = results["geos"][i], results["geoultra"][i]
        bad = [k for k in case["compare"] if ref[k] != ours[k]]
        if bad:
            failed += 1
            print("FAIL %-40s %s" % (case["name"], "; ".join(
                describe(k, ours[k], ref[k]) for k in bad)))
        else:
            print("pass %s" % case["name"])
    print("%d of %d cases pass" % (len(cases) - failed, len(cases)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
