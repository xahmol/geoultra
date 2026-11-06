#!/usr/bin/env python3
"""gush's drive switch in VICE (user, 2026-11-06; src/gush/drives.s): "b:"
goes back to the folder last used on drive B (its root the first time),
for a-e (either case); a folder that is gone gives the root; "x:" is no
drive (a command looked for as usual).
Usage: tests/gush/g21.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    g = Gush("g21", 6622)
    check = g.check

    def out(line, n=1, settle=3.0):
        g.run(line, settle=settle)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        check("b: the first time: its root", out("b:; pwd"), "/b")
        g.run("mkdir /b/dir1", settle=4)
        g.run("cd /b/dir1")
        check("a: then b: back in /b/dir1", out("a:; pwd; b:; pwd", 2), ["/a", "/b/dir1"])
        g.run("e:")
        g.run("cd bin")
        check("e: and its folder kept", out("a:; e:; pwd"), "/e/bin")
        check("B: in capitals", out("B:; pwd"), "/b/dir1")
        g.run("cd /")
        g.run("rmdir /b/dir1", settle=4)
        check("a folder gone: b: gives the root", out("b:; pwd"), "/b")
        check("x: is no drive", out("x:"), "gush: x:: not found")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
