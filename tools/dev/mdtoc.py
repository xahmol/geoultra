#!/usr/bin/env python3
"""mdtoc.py - a table of contents in Markdown files, for reading them on
GitHub or in an editor (the PDFs get pandoc's own: pandoc-defaults.yaml).

    tools/dev/mdtoc.py FILE.md [FILE.md ...]

The list goes between the lines <!-- toc --> and <!-- /toc --> (put
those once where it belongs; the text between them is replaced on each
run). It is raw HTML: GitHub shows it, with links to GitHub's heading
anchors, while pandoc leaves raw HTML out of a PDF, so the PDF does not
show it twice. Levels: the file's two highest heading levels, a top
level used once (a title) left out (the manuals: # and ##; the README:
## and ###). Headings inside fenced code
blocks do not count. Run by make docs. Own code.
"""
import html
import re
import sys

START, END = "<!-- toc -->", "<!-- /toc -->"


def slug(text, seen):
    """GitHub's anchor for a heading: lower case, punctuation (but - and _)
    dropped, spaces as -, a repeated one numbered."""
    s = text
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)       # links: their text
    s = s.replace("`", "").lower()
    s = re.sub(r"[^\w\- ]", "", s)
    s = s.replace(" ", "-")
    n = seen.get(s, 0)
    seen[s] = n + 1
    return s if n == 0 else "%s-%d" % (s, n)


def headings(lines):
    out, fence = [], False
    for line in lines:
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        m = None if fence else re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if m:
            out.append((len(m.group(1)), m.group(2)))
    return out


def toc(lines):
    hs = headings(lines)
    levels = sorted({lv for lv, _ in hs})
    if levels and sum(1 for lv, _ in hs if lv == levels[0]) == 1:
        levels = levels[1:]             # (the title alone: the README's #)
    levels = levels[:2]
    seen = {}
    items = []
    for lv, text in hs:
        anchor = slug(text, seen)
        if lv in levels:
            items.append((levels.index(lv), text, anchor))
    out = ["<ul>"]
    open_sub = False
    for depth, text, anchor in items:
        label = html.escape(re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text).replace("`", "").replace("**", ""))
        if depth == 0:
            if open_sub:
                out.append("</ul></li>")
                open_sub = False
            elif len(out) > 1:
                out.append("</li>")
            out.append('<li><a href="#%s">%s</a>' % (anchor, label))
        else:
            if not open_sub:
                out.append("<ul>")
                open_sub = True
            out.append('<li><a href="#%s">%s</a></li>' % (anchor, label))
    out.append("</ul></li>" if open_sub else "</li>")
    out.append("</ul>")
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().split("\n\n")[1].strip())
    for path in sys.argv[1:]:
        lines = open(path, encoding="utf-8").read().split("\n")
        if START not in lines or END not in lines:
            print("mdtoc: %s has no %s ... %s lines: skipped" % (path, START, END))
            continue
        a, b = lines.index(START), lines.index(END)
        new = lines[:a + 1] + toc(lines[:a] + lines[b + 1:]) + lines[b:]
        if new != lines:
            open(path, "w", encoding="utf-8").write("\n".join(new))
            print("mdtoc: %s updated" % path)


if __name__ == "__main__":
    main()
