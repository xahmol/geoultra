#!/usr/bin/env python3
"""gush's control flow in VICE (docs/design/GUSH.md): if,
elif, else, while, for, nesting, test and [ ], read from the keyboard
and a file, a script with blocks over lines, errors of unbalanced blocks.
(RUN/STOP: not here; the monitor cannot hold a key in the matrix.)
Usage: tests/gush/g15.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402

LOOP = (b"# blocks over lines\rfor W in red green\rdo\r  if [ $W = red ]\r  then\r"
        b"    echo first $W\r  else\r    echo then $W\r  fi\rdone\rread L < /b/WORDS\recho got $L\r")


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for name, data in (("loop", LOOP), ("words", b"alpha beta\rsecond line\r")):
        path = os.path.join(OUT, name)
        open(path, "wb").write(data)
        files.append(path + ",s")             # (SEQ: a PRG would run in BASIC)
    g = Gush("g15", 6581, files)
    check = g.check

    def out(line, n=1, settle=2.0):
        g.run(line, settle=settle)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        g.run("cd /b")
        check("if true", out("if true; then echo yes; else echo no; fi"), "yes")
        check("elif", out("if false; then echo a; elif true; then echo b; else echo c; fi"), "b")
        check("else", out("if false; then echo a; else echo c; fi"), "c")
        check("[ numbers ]", out("if [ 3 -lt 5 ]; then echo less; fi"), "less")
        check("[ -5 -lt -2 ] (signed)", out("[ -5 -lt -2 ]; echo $?"), "0")
        g.run("X=a")
        check('[ "$X" = a ]', out('if [ "$X" = a ]; then echo same; fi'), "same")
        check("[ a != b ]", out("[ a != b ]; echo $?"), "0")
        check("test -d, -f", (out("test -d /b; echo $?"), out("test -f /b; echo $?"),
                               out("test -f WORDS; echo $?")), ("0", "1", "0"))
        check("! and -z", (out("test ! -z x; echo $?"), out("test -z ''; echo $?")), ("0", "0"))
        check("for", out("for i in 1 2 3; do echo n$i; done", 3), ["n1", "n2", "n3"])
        check("for in for", out("for a in x y; do for b in 1 2; do echo $a$b; done; done", 4),
              ["x1", "x2", "y1", "y2"])
        g.run("cp WORDS F")
        check("while", out("while [ -e F ]; do rm -f F; echo gone; done; echo end", 2), ["gone", "end"])
        check("fi without if", out("fi"), "gush: elif, else or fi without if")
        check("a block left open", out("if true; then echo x"), "gush: a block left open (if/while/for)")
        g.keys("read A B\r", settle=1)
        g.queue("one two three\r", settle=2)
        check("read from the keyboard", (out("echo $A"), out("echo $B")), ("one", "two three"))
        check("a script with blocks over lines", out("LOOP", 3, settle=4), ["first red", "then green", "got alpha beta"])
        g.png("g15")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
