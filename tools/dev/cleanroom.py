#!/usr/bin/env python3
"""cleanroom.py - how much of GeoUltra's code resembles GEOS 2.0's.

    tools/dev/cleanroom.py MIST64_GEOS_CHECKOUT [--binary]

A rough check for the clean-room approach (docs/reference/CLEAN_ROOM.md),
two ways:

1. Source: GeoUltra's assembler (src/kernal, src/drivers) against the
   reassembled GEOS 2.0 source (mist64/geos: kernal/, drv/). Every
   instruction is reduced to its mnemonic and addressing mode (names and
   numbers differ between the two anyway: comparing them would hide
   copying that renamed things); windows of K instructions in a row are
   compared. Reported: the share of GeoUltra's windows that also occur in
   GEOS 2.0, and the longest runs of instructions both have in the same
   order. Calibration: the same numbers for GeoUltra's desktop
   (src/desktop: a different program, written the same way), which show
   what common 6502 and GEOS idioms give on their own.
2. Binary (--binary): GeoUltra's and GEOS 2.0's RAM $9000-$9FFF and
   $C000-$FFFF after the boot (both in VICE at MainLoop; GEOS 2.0 from
   the user's own disk, GEOS_ORACLE), the longest byte runs both hold,
   at least MIN_RUN bytes; runs that are mostly one byte value (fill,
   cleared memory) left out.

Nothing of GEOS 2.0 is written into the repository: the reports show
addresses, lengths and mnemonics only.
"""
import collections
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
K = 12                          # instructions in a window
MIN_RUN = 16                    # bytes, for the binary comparison
OUT = os.path.join(ROOT, "build", "cleanroom")

MNEMONICS = set("""adc and asl bcc bcs beq bit bmi bne bpl brk bvc bvs clc cld cli clv cmp cpx
cpy dec dex dey eor inc inx iny jmp jsr lda ldx ldy lsr nop ora pha php pla plp rol ror rti
rts sbc sec sed sei sta stx sty tax tay tsx txa txs tya""".split())
# Loads and stores of immediate values and plain addresses: a window of
# only these is a routine's parameter set-up ("lda #<x / sta r0L ..."),
# which reduced to mnemonics matches any other such set-up.
TRIVIAL = {"lda imm", "ldx imm", "ldy imm", "sta abs", "stx abs", "sty abs"}
LINE = re.compile(r"^\s*(?:[@A-Za-z_.][\w.@]*:)?\s*([A-Za-z]{3})\b\s*([^;]*)")


def mode(op):
    """The addressing mode of an operand text."""
    op = op.strip().lower().replace(" ", "")
    if not op or op == "a":
        return "imp"
    if op.startswith("#"):
        return "imm"
    if op.startswith("("):
        if op.endswith(",x)"):
            return "(x)"
        if op.endswith("),y"):
            return "(y)"
        return "(ind)"
    if op.endswith(",x"):
        return "x"
    if op.endswith(",y"):
        return "y"
    return "abs"


def instructions(path):
    """The file's instructions as (mnemonic, mode), in order, and their
    source lines."""
    out, lines = [], []
    for n, line in enumerate(open(path, encoding="latin1")):
        m = LINE.match(line)
        if not m or m.group(1).lower() not in MNEMONICS:
            continue
        mn = m.group(1).lower()
        md = "rel" if mn[0] == "b" and mn not in ("bit", "brk") else mode(m.group(2))
        out.append(mn + " " + md)
        lines.append(n + 1)
    return out, lines


def files(roots):
    out = []
    for r in roots:
        out += sorted(glob.glob(os.path.join(r, "**", "*.s"), recursive=True))
    return out


def corpus(paths):
    seqs = {}
    for p in paths:
        ins, lines = instructions(p)
        if len(ins) >= K:
            seqs[p] = (ins, lines)
    return seqs


def windows(seqs):
    w = collections.defaultdict(list)
    for p, (ins, _) in seqs.items():
        for i in range(len(ins) - K + 1):
            w[tuple(ins[i:i + K])].append((p, i))
    return w


def compare(ours, ref, label):
    """Share of our windows found in ref; the longest common runs."""
    refw = windows(ref)
    total = shared = 0
    runs = []
    for p, (ins, lines) in ours.items():
        i = 0
        n = len(ins)
        while i <= n - K:
            total += 1
            key = tuple(ins[i:i + K])
            if all(x in TRIVIAL for x in key):          # (parameter set-up: matches
                i += 1                                  # any other; not counted)
                continue
            if key in refw:
                shared += 1
                best = (0, None)                # extend the run as far as it goes
                for rp, ri in refw[key][:50]:
                    rins = ref[rp][0]
                    L = K
                    while i + L < n and ri + L < len(rins) and ins[i + L] == rins[ri + L]:
                        L += 1
                    if L > best[0]:
                        best = (L, (rp, ri))
                runs.append((best[0], p, lines[i], best[1][0], ref[best[1][0]][1][best[1][1]]))
                i += max(1, best[0] - K + 1)
                total += max(0, best[0] - K)
                shared += max(0, best[0] - K)
            i += 1
    runs.sort(reverse=True)
    print("\n== %s: %d of %d windows of %d instructions also in GEOS 2.0 (%.1f%%)"
          % (label, shared, total, K, 100.0 * shared / max(total, 1)))
    seen = set()
    for L, p, line, rp, rline in runs[:12]:
        if (p, line) in seen:
            continue
        seen.add((p, line))
        print("  %3d instructions: %s:%d  ~  %s:%d" % (L, os.path.relpath(p, ROOT), line,
                                                     "/".join(rp.split("/")[-2:]), rline))
    return shared, total, runs


def binary():
    sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
    import harness
    harness.use_disk_set("d64")
    harness.prepare_disks()
    os.makedirs(OUT, exist_ok=True)
    mem = {}
    for name in ("geos", "geoultra"):
        s = harness.System(name, True)
        try:
            mem[name] = (bytes(s.vice.mem_get(0x9000, 0x9FFF, bank="ram")),
                         bytes(s.vice.mem_get(0xC000, 0xFFFF, bank="ram")))
        finally:
            s.close()
    print("\n== Binary: RAM $9000-$9FFF and $C000-$FFFF after the boot, runs of %d bytes or more"
          % MIN_RUN)
    ref = mem["geos"][0] + mem["geos"][1]
    ours = mem["geoultra"][0] + mem["geoultra"][1]
    addr = lambda i: 0x9000 + i if i < 0x1000 else 0xC000 + i - 0x1000
    index = collections.defaultdict(list)
    for i in range(len(ref) - MIN_RUN + 1):
        index[ref[i:i + MIN_RUN]].append(i)
    runs = []
    i = 0
    while i <= len(ours) - MIN_RUN:
        chunk = ours[i:i + MIN_RUN]
        if max(chunk.count(b) for b in set(chunk)) <= MIN_RUN * 3 // 4 and chunk in index:
            best = (0, 0)
            for j in index[chunk][:50]:
                L = MIN_RUN
                while i + L < len(ours) and j + L < len(ref) and ours[i + L] == ref[j + L]:
                    L += 1
                best = max(best, (L, j))
            run = ours[i:i + best[0]]
            if max(run.count(b) for b in set(run)) <= len(run) * 3 // 4:   # (not fill)
                runs.append((best[0], addr(i), addr(best[1])))
            i += best[0]
        else:
            i += 1
    runs.sort(reverse=True)
    print("  %d runs, %d bytes in all (of %d)" % (len(runs), sum(r[0] for r in runs), len(ours)))
    import bisect
    labs = sorted((int(p[1], 16), p[2].lstrip(".")) for p in
                  (line.split() for line in open(os.path.join(ROOT, "build", "kernal64.lbl")))
                  if not p[2].lstrip(".").startswith(("@", "__")))
    def name(a):
        i = bisect.bisect_right(labs, (a, "\xff")) - 1
        return "%s+%d" % (labs[i][1], a - labs[i][0]) if i >= 0 else "?"
    for L, a, b in runs[:25]:
        print("  %4d bytes: GeoUltra $%04X (%s), GEOS 2.0 $%04X" % (L, a, name(a), b))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().split("\n\n")[1].strip())
    mist = sys.argv[1]
    ref = corpus([f for f in files([os.path.join(mist, "kernal"), os.path.join(mist, "drv")])
                  if "/wheels/" not in f])        # (mist64/geos holds Wheels' source too)
    kern = corpus(files([os.path.join(ROOT, "src", "kernal"), os.path.join(ROOT, "src", "drivers")]))
    desk = corpus(files([os.path.join(ROOT, "src", "desktop")]))
    print("GEOS 2.0 (mist64/geos kernal, drv; not wheels/): %d files, %d instructions"
          % (len(ref), sum(len(v[0]) for v in ref.values())))
    print("GeoUltra kernal and drivers: %d files, %d instructions"
          % (len(kern), sum(len(v[0]) for v in kern.values())))
    print("GeoUltra desktop (calibration): %d files, %d instructions"
          % (len(desk), sum(len(v[0]) for v in desk.values())))
    compare(kern, ref, "GeoUltra kernal and drivers")
    compare(desk, ref, "GeoUltra desktop (calibration)")
    if "--binary" in sys.argv:
        binary()


if __name__ == "__main__":
    main()
