#!/usr/bin/env python3
"""gush's variables in VICE (docs/design/GUSH.md):
NAME=value, $NAME, ${NAME}, quoting ("..." expands, '...' and \\$ do
not), $? after a failed and a good line, set, unset, a lone "$".
Usage: tests/gush/g12.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    g = Gush("g12", 6578)
    check = g.check

    def out(line):
        g.run(line)
        return g.lines()[-2]
    try:
        g.start()
        g.run("A=hello")
        check("NAME=value, $NAME", out("echo $A world"), "hello world")
        check("${NAME} before letters", out("echo ${A}b"), "hellob")
        check('"..." expands', out('echo "$A"x'), "hellox")
        check("'...' does not", out("echo '$A'"), "$A")
        check("\\$ does not", out("echo \\$A"), "$A")
        g.run('B="two words"')
        check("a quoted value with a space", out("echo $B"), "two words")
        g.run("ls NOPE")
        check("$? after a failed line", out("echo $?"), "1")
        check("$? after a good line", out("echo $?"), "0")
        g.run("set")
        rows = g.lines()
        check("set lists them", [r for r in rows[-6:-1] if r.split("=")[0] in ("A", "B", "PATH")],
              ["PATH=/e/bin:/bin", "A=hello", "B=two words"])
        g.run("unset A")
        check("unset", out("echo [$A]"), "[]")
        check("a lone $", out("echo $ 5"), "$ 5")
        g.png("g12")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
