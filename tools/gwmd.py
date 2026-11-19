"""gwmd.py - a geoWrite 2.x document as Markdown, for gwtool.py's `md`
command (docs/TOOLS_MANUAL.md, "Markdown"; the user's request of
2026-11-18). No packages needed: pictures are written as PNG files by
gwdocx.py's own writer.

geoWrite's pages are read as for Word (gwdocx.py; the 2.x format: Michael
Steil, "Inside geoWrite - 7", pagetable.com) and written as CommonMark
with GitHub's tables:
- a paragraph (up to CR) becomes a paragraph; empty ones only separate;
- headings: a paragraph all in a size larger than the body text (the
  size most of the text has) is a heading, the largest size level 1,
  the next level 2 and so on (at most 6);
- styles: bold **, italic *, underline <u>, superscript <sup>, subscript
  <sub>; text in a fixed-width font (GU Mono, Commodore, Cory) as `code`;
  outline and reverse are dropped; fonts and sizes otherwise are not
  kept (Markdown has none);
- paragraphs that start with "- ", "* " or a number and a full stop stay
  list items (no empty line between them; a bulleted and a numbered list
  apart); paragraphs all in a fixed-width font a code block (```); a
  "* * *" line (frommd's rule) a rule again;
- two or more paragraphs in a row with the same number of tabs (one or
  more) become a table, the first row its header; a tab elsewhere is a
  space;
- pictures (records 64-126) as PNG files at 80 dpi in a folder beside
  the Markdown file (NAME_files/picture1.png ...), linked with ![...];
- page breaks: geoWrite's own ($0C) as <!-- pagebreak --> (invisible when
  shown; `gwtool frommd` reads them back), or at every geoWrite page
  with page_breaks="records";
- header and footer (records 61, 62) as HTML comments at the start and
  the end, so their text is not lost.
Alignment, margins, tab positions and line spacing have no Markdown form
and are not written. Own code (GeoUltra, 2026).
"""
import os
import re
from collections import Counter

import gwdocx

ESC_GRAPHICS, ESC_RULER, ESC_NEWCARDSET = 0x10, 0x11, 0x17
MONO_FAMILIES = {30, 8, 5}              # GU Mono, Commodore, Cory
BOLD, ITALIC, UNDERLINE, SUPER, SUB = 0x40, 0x10, 0x80, 0x04, 0x02
SPECIAL = re.compile(r"([\\`*_\[\]<>|])")
LIST_START = re.compile(r"^(?:[-*+] |\d{1,9}\. )")


def paragraphs(records, pics, page_breaks):
    """[(runs, kind)]: runs [(fid, style, text)] with text "\\t" for a
    tab; kind None (text), "pic" (runs = picture record data), "break"."""
    out, runs = [], []
    st = {"fid": 0, "style": 0}

    def add(s):
        if runs and runs[-1][0] == st["fid"] and runs[-1][1] == st["style"]:
            runs[-1] = (st["fid"], st["style"], runs[-1][2] + s)
        else:
            runs.append((st["fid"], st["style"], s))

    def end():
        out.append((list(runs), None))
        runs.clear()
    for k, rec in enumerate(records):
        if k and page_breaks == "records":
            if runs:
                end()
            out.append(([], "break"))
        i = 0
        while i < len(rec):
            b = rec[i]
            if b == ESC_RULER:
                i += 27
            elif b == ESC_NEWCARDSET:
                st["fid"], st["style"] = rec[i + 1] | rec[i + 2] << 8, rec[i + 3]
                i += 4
            elif b == ESC_GRAPHICS:
                r = rec[i + 4]
                if runs:
                    end()
                if r in pics:
                    out.append((pics[r], "pic"))
                i += 5
            elif b == 0x0D:
                end()
                i += 1
            elif b == 0x0C:
                if runs:
                    end()
                out.append(([], "break"))
                i += 1
            elif b == 0x09:
                add("\t")
                i += 1
            elif b == 0:
                break
            else:
                if 0x20 <= b < 0x7F:
                    add(chr(b))
                i += 1
    if runs:
        end()
    return out


def escape(s, line_start):
    s = SPECIAL.sub(r"\\\1", s)
    if line_start:
        s = re.sub(r"^(\s*)(#|[-+*](?= )|\d+(?=[.)] ))", r"\1\\\2", s)
    return s


def inline(runs, keep_list=False):
    """Markdown text of runs (styles as markers, spaces kept outside)."""
    out = []
    first = True
    for fid, style, s in runs:
        if not s:
            continue
        mono = (fid >> 6) in MONO_FAMILIES
        lead = len(s) - len(s.lstrip(" "))
        trail = len(s) - len(s.rstrip(" "))
        core = s.strip(" ")
        if not core:
            out.append(s)
            continue
        if first and keep_list and LIST_START.match(s):
            m = LIST_START.match(s)
            out.append(s[:m.end()])
            s = s[m.end():]
            lead = len(s) - len(s.lstrip(" "))
            core = s.strip(" ")
            if not core:
                first = False
                continue
        if mono:
            ticks = "``" if "`" in core else "`"
            text = "%s%s%s" % (ticks, core, ticks)
        else:
            text = escape(core, first and not out)
            if style & BOLD:
                text = "**%s**" % text
            if style & ITALIC:
                text = "*%s*" % text
        if style & UNDERLINE:
            text = "<u>%s</u>" % text
        if style & SUPER:
            text = "<sup>%s</sup>" % text
        elif style & SUB:
            text = "<sub>%s</sub>" % text
        out.append(" " * lead + text + " " * trail)
        first = False
    return "".join(out)


def write(path, pages_, header, footer, pics, page_breaks="explicit", title=None):
    """The Markdown file at path, pictures beside it; returns the number of
    pictures written."""
    paras = paragraphs(pages_, pics, page_breaks)
    sizes = Counter()
    for runs, kind in paras:
        if kind is None:
            for fid, style, s in runs:
                sizes[fid & 63] += len(s.strip())
    body = sizes.most_common(1)[0][0] if sizes else 12
    larger = sorted({fid & 63 for runs, kind in paras if kind is None for fid, _, s in runs
                     if s.strip() and fid & 63 > body}, reverse=True)
    level = {size: min(6, k + 1) for k, size in enumerate(larger)}
    stem = os.path.splitext(os.path.basename(path))[0]
    folder = stem + "_files"
    lines = []
    if title:
        lines += ["<!-- %s, written by GeoUltra's gwtool -->" % title.replace("--", "-"), ""]

    def side(rec, what):
        if not rec:
            return
        text = " / ".join(inline(r).strip() for r, k in paragraphs([rec], {}, "explicit")
                          if k is None and inline(r).strip())
        if text:
            lines.extend(["<!-- %s: %s -->" % (what, text.replace("--", "-")), ""])
    side(header, "header")
    n_pics = 0
    k = 0
    while k < len(paras):
        runs, kind = paras[k]
        if kind == "break":
            lines += ["<!-- pagebreak -->", ""]
            k += 1
            continue
        if kind == "pic":
            n_pics += 1
            if n_pics == 1:
                os.makedirs(os.path.join(os.path.dirname(os.path.abspath(path)), folder), exist_ok=True)
            w, h, data = gwdocx.picture(runs)
            name = "picture%d.png" % n_pics
            open(os.path.join(os.path.dirname(os.path.abspath(path)), folder, name), "wb").write(data)
            lines += ["![picture %d](%s/%s)" % (n_pics, folder, name), ""]
            k += 1
            continue
        text = "".join(s for _, _, s in runs)
        if not text.strip():
            k += 1
            continue
        tabs = text.count("\t")
        if tabs:                                        # a table?
            rows = []
            j = k
            while j < len(paras) and paras[j][1] is None:
                t = "".join(s for _, _, s in paras[j][0])
                if t.count("\t") != tabs or not t.strip():
                    break
                rows.append(paras[j][0])
                j += 1
            if len(rows) >= 2:
                for r_k, row in enumerate(rows):
                    cells = [[]]
                    for fid, style, s in row:
                        for part_k, part in enumerate(s.split("\t")):
                            if part_k:
                                cells.append([])
                            if part:
                                cells[-1].append((fid, style, part))
                    lines.append("| " + " | ".join(inline(c).strip() or " " for c in cells) + " |")
                    if r_k == 0:
                        lines.append("|" + "|".join(" --- " for _ in cells) + "|")
                lines.append("")
                k = j
                continue
        if text.strip() == "* * *":                     # (a rule, as frommd makes it)
            lines += ["***", ""]
            k += 1
            continue
        if all((fid >> 6) in MONO_FAMILIES for fid, _, s in runs if s.strip()):
            code = []                                   # a code block: paragraphs all
            while k < len(paras) and paras[k][1] is None:   # in a fixed-width font
                r = paras[k][0]
                t = "".join(s for _, _, s in r)
                if not t.strip() or not all((fid >> 6) in MONO_FAMILIES for fid, _, s in r if s.strip()):
                    break
                code.append(t.replace("\t", "    "))
                k += 1
            fence = "````" if any("```" in c for c in code) else "```"
            lines += [fence] + code + [fence, ""]
            continue
        sizes_here = {fid & 63 for fid, _, s in runs if s.strip()}
        runs = [(fid, style, s.replace("\t", " ")) for fid, style, s in runs]
        if sizes_here and all(sz in level for sz in sizes_here):
            plain = [(fid, style & ~BOLD, s) for fid, style, s in runs]
            lines += ["#" * level[max(sizes_here)] + " " + inline(plain).strip(), ""]
            k += 1
            continue
        if LIST_START.match(text.lstrip()):
            items = []
            bullet = text.lstrip()[0] in "-*+"
            while k < len(paras) and paras[k][1] is None:
                t = "".join(s for _, _, s in paras[k][0])
                if not LIST_START.match(t.lstrip()) or (t.lstrip()[0] in "-*+") != bullet:
                    break                               # (another kind: a new list)
                r = [(fid, style, s.replace("\t", " ")) for fid, style, s in paras[k][0]]
                items.append(inline(r, keep_list=True).strip())
                k += 1
            lines += items + [""]
            continue
        lines += [inline(runs).strip(), ""]
        k += 1
    side(footer, "footer")
    while lines and not lines[-1]:
        lines.pop()
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    return n_pics
