#!/usr/bin/env python3
"""gush's completion with the <- key in VICE (docs/GUSH.md): a command name, a file name (a space after it), a path with
a folder part, the common part of two names, a second <- listing them
(the line shown again), one folder (a "/" after it).
Usage: tests/gush/g17.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402

KEY_LARROW = 20


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "words")
    open(path, "wb").write(b"alpha beta\r")
    g = Gush("g17", 6594, [path])
    check = g.check
    lb = g.lbl["lineBuf"]
    ln = g.lbl["lineLen"]

    def line():
        n = g.v.mem_get(ln, ln)[0]
        return bytes(g.v.mem_get(lb, lb + 80))[:n].decode("latin1")

    def complete(text, presses=1):
        g.keys(text)
        g.keys([KEY_LARROW] * presses, settle=2)
        got = line()
        return got

    def clear():
        g.keys("\r", settle=2)                       # (the line run: harmless)
    try:
        g.start()
        g.run("cd /b")
        check("a command name", complete("ec"), "echo ")
        clear()
        check("a file name, a space after it", complete("cat WO"), "cat WORDS ")
        clear()
        check("a path with a folder part", complete("cat /b/WO"), "cat /b/WORDS ")
        clear()
        g.run("mkdir folder1")
        g.run("mkdir folder2")
        check("two names: their common part", complete("cd fo"), "cd folder")
        g.keys([KEY_LARROW], settle=3)
        rows = g.lines()
        check("a second <-: the names listed, the line again", rows[-2:],
              ["folder1  folder2", "$ cd folder"])
        clear()
        g.run("rmdir folder2")
        check("one folder: a / after it", complete("cd fo"), "cd folder1/")
        clear()
        check("nothing fits: the line as it was", complete("cat zz"), "cat zz")
        clear()
        g.png("g17")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
