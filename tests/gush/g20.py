#!/usr/bin/env python3
"""Drive E by path in VICE (docs/FILE_ENGINE.md, "Drive E"; docs/GUSH.md):
the native system drive shown in a free slot for each engine call. "/"
lists e; ls /e and /e/bin; cd into it; wc found along PATH in /e/bin from
another folder; cat and cp from E; writing refused (read-only); a
program on E started by name (FE_RUNSYS), and the drives as they were
afterwards.
Usage: tests/gush/g20.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "words")
    open(path, "wb").write(b"alpha beta\rsecond line here\r")
    g = Gush("g20", 6598, [path])
    check = g.check

    def out(line, n=1, settle=4.0):
        g.run(line, settle=settle)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        check("/ lists drive e", "e" in out("ls /").split(), True)
        check("ls /e", sorted(out("ls /e").split()), ["Desktop", "GeoUltra", "bin", "geoFolder", "gush"])
        check("ls /e/bin", out("ls /e/bin"), "wc")
        check("cd /e/bin, pwd, ls", out("cd /e/bin; pwd; ls", 2), ["/e/bin", "wc"])
        g.run("cd /b")
        check("wc along PATH (/e/bin)", out("wc WORDS").split(), ["2", "5", "28", "WORDS"])
        check("ls /b after it (B as it was)", sorted(out("ls /b").split()), ["WORDS", "gush"])
        g.run("cp /e/bin/wc /b/wc2", settle=6)
        check("cp from drive E", out("/b/wc2 WORDS").split(), ["2", "5", "28", "WORDS"])
        check("rm on drive E: refused", out("rm -f /e/gush").startswith("gush: rm: /e/gush: "), True)
        check("mkdir on drive E: refused", out("mkdir /e/x").startswith("gush: mkdir: /e/x: "), True)
        check("ls /e unchanged", sorted(out("ls /e").split()), ["Desktop", "GeoUltra", "bin", "geoFolder", "gush"])
        check("test -f /e/bin/wc", out("test -f /e/bin/wc; echo $?"), "0")
        g.run("/e/gush", settle=12)                       # FE_RUNSYS: a fresh gush
        rows = g.lines()
        check("/e/gush: a fresh gush", rows[0].startswith("gush, the GeoUltra shell") if rows else rows, True)
        check("the fresh gush: drive B as it was", sorted(out("ls /b").split()), ["WORDS", "gush", "wc2"])
        g.png("g20")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
