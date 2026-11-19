#!/usr/bin/env python3
"""gush in VICE (docs/design/GUSH.md, "Syntax", "Commands"): words with
quotes and backslash, wildcards through the engine's listing (a match,
none, a folder part), ls on "/" and a drive, ls -l, cd and pwd (also cd
without a path: the start drive's root), errors as text.
Usage: tests/gush/g3.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for name, size in (("alpha", 10), ("alps", 300), ("beta", 600)):
        path = os.path.join(OUT, name)
        open(path, "wb").write(bytes(i & 0xFF for i in range(size)))
        files.append(path)
    g = Gush("g3", 6563, files)
    check = g.check

    def out(line, n=1):
        g.run(line)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        check("ls /: the drives (and e, the system drive)", out("ls /"), "a  b  e")
        check("cd /b, pwd", (out("cd /b", 0) if False else g.run("cd /b"), out("pwd")), (None, "/b"))
        check("ls", out("ls"), "gush  ALPHA  ALPS  BETA")
        check("echo with a wildcard", out("echo AL*"), "ALPHA ALPS")
        check("a wildcard with a folder part", out("echo /b/*TA"), "/b/BETA")
        check("a wildcard that matches nothing", out("echo Z*"), "Z*")
        check("a quoted wildcard", out("echo 'AL*'"), "AL*")
        check("quotes and backslash", out("echo \"a  b\" 'c d' e\\ f"), "a  b c d e f")
        lines = out("ls -l AL* BETA", 3)
        check("ls -l: kind, type, size", [l[:15] for l in lines],
              ["- prg        1 ", "- prg        2 ", "- prg        3 "])
        check("ls -l: the names", [l.split()[-1] for l in lines], ["ALPHA", "ALPS", "BETA"])
        check("ls a missing name", out("ls NOPE"), "gush: ls: NOPE: no such file or folder")
        check("cd into a file", out("cd ALPHA"), "gush: cd: ALPHA: not a folder")
        g.run("cd /a")
        g.run("cd")
        check("cd without a path: the start drive's root", out("pwd"), "/b")
        check("an unknown command", out("frob x"), "gush: frob: not found")
        g.png("g3-ls")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
