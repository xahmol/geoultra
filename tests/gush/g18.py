#!/usr/bin/env python3
"""gush's external commands in VICE (docs/GUSH.md,
docs/GUSH_COMMANDS.md): wc (build/cmds/wc.cvt, a module) on drive B: a
file, two files and their total, the input from a pipe and from <, no
input, a missing file, by its path; an overlay command afterwards (the
area the module used fetched again).
Usage: tests/gush/g18.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT, ROOT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "words")
    open(path, "wb").write(b"alpha beta\rsecond line here\r")
    g = Gush("g18", 6596, [path, os.path.join(ROOT, "build", "cmds", "wc.cvt")])
    check = g.check

    def out(line, n=1, settle=4.0):
        g.run(line, settle=settle)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        g.run("cd /b")
        check("wc FILE", out("wc WORDS").split(), ["2", "5", "28", "WORDS"])
        check("wc two files: a total", [r.split() for r in out("wc WORDS WORDS", 3)],
              [["2", "5", "28", "WORDS"], ["2", "5", "28", "WORDS"], ["4", "10", "56", "total"]])
        check("wc from a pipe", out("echo one two three | wc").split(), ["1", "3", "14"])
        check("wc from <", out("wc < WORDS").split(), ["2", "5", "28"])
        check("wc without input: said, failed", out("wc; echo $?", 2),
              ["gush: wc: files, or an input (| or <)", "1"])
        check("wc a missing file", out("wc nope"), "gush: wc: nope: no such file or folder")
        check("wc by its path", out("/b/wc WORDS").split(), ["2", "5", "28", "WORDS"])
        check("an overlay command after it", out("test 1 -eq 1; echo $?"), "0")
        check("a file command after it", out("cat WORDS", 2), ["alpha beta", "second line here"])
        g.png("g18")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
