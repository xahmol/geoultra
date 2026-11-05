#!/usr/bin/env python3
"""gush's redirection in VICE (docs/GUSH.md, "Step 3", sub-step 2): >,
>> and < with files on a GEOS drive; an error stays on the screen while
the output goes to a file; > without a file; a quoted > is text.
Usage: tests/gush/g13.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    g = Gush("g13", 6579)
    check = g.check
    try:
        g.start()
        g.run("cd /b")
        g.run("echo hello > OUT")
        check("echo > a file: nothing on the screen", g.lines()[-2], "$ echo hello > OUT")
        g.run("cat OUT")
        check("its text", g.lines()[-2], "hello")
        g.run("echo more >>OUT")
        g.run("cat OUT")
        check(">> adds", g.lines()[-3:-1], ["hello", "more"])
        g.run("cat < OUT")
        check("< as cat's input", g.lines()[-3:-1], ["hello", "more"])
        g.run("cat NOPE > OUT2")
        check("an error stays on the screen", g.lines()[-2], "gush: cat: NOPE: no such file or folder")
        g.run("ls -l OUT2")
        check("the file made, empty", g.lines()[-2].split()[:3], ["-", "seq", "1"])
        g.run("echo x >")
        check("> without a file", g.lines()[-2], "gush: echo: wrong words (see help)")
        g.run('echo "a > b"')
        check("a quoted > is text", g.lines()[-2], "a > b")
        g.run("ls > LIST")
        check("ls into a file: nothing on the screen", g.lines()[-2], "$ ls > LIST")
        g.run("cat LIST")
        check("the names in the file, one a line", g.lines()[-5:-1], ["gush", "OUT", "OUT2", "LIST"])
        g.png("g13")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
