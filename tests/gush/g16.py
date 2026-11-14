#!/usr/bin/env python3
"""gush's pipes in VICE (docs/GUSH.md): two and
three stages, ls into a pipe, read from a pipe, a pipe into a file, a
pipe as an if's condition, a quoted | as text.
Usage: tests/gush/g16.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "words")
    open(path, "wb").write(b"alpha beta\rsecond line\r")
    g = Gush("g16", 6586, [path])
    check = g.check

    def out(line, n=1, settle=3.0):
        g.run(line, settle=settle)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        g.run("cd /b")
        check("echo | cat", out("echo hello | cat"), "hello")
        check("three stages", out("echo x | cat | cat"), "x")
        check("ls | cat: a name per line", out("ls | cat", 2), ["gush", "WORDS"])
        check("read from a pipe", out("echo one two three | read A B; echo $A / $B"), "one / two three")
        g.run("cat WORDS | cat > OUT")
        check("a pipe into a file", out("cat OUT", 2), ["alpha beta", "second line"])
        check("a pipe as a condition", out("if echo x | cat; then echo ok; fi", 2), ["x", "ok"])
        check("a quoted | is text", out('echo "a | b"'), "a | b")
        g.png("g16")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
