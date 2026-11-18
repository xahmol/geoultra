"""mdgw.py - a Markdown text as a geoWrite 2.1 document, for gwtool.py's
`frommd` command (docs/GWTOOL_MANUAL.md, "From Markdown"; the user's
request of 2026-11-18). Needs Pillow only for pictures.

The Markdown is read line by line (CommonMark and GitHub's tables, the
parts a letter or a manual uses) into the reader items of docxgw.py, which
lays out the pages exactly as for a Word document (docxgw.paginate):
- headings (# to ######, and underlined with === or ---): bold, in GU
  Sans 24, 18 and 14 dots for levels 1-3, 12 for 4-6;
- paragraphs (lines joined; two spaces or a backslash at a line's end: a
  line break), an empty line after each, as Word's Normal style;
- **bold**, __bold__, *italic*, _italic_, `code` (GU Mono), <u>, <sup>,
  <sub>, <br>; other HTML tags dropped, ~~strike~~ as plain text (GEOS
  has no strike-through); \\-escapes; [links](url) as their text with
  the address in brackets when it differs; text as docxgw.ascii_text;
- lists (-, *, +, 1. or 1)): "- " or the number, hanging, indented per
  level; block quotes (>): indented and italic; code blocks (``` or
  ~~~, or indented 4 spaces): GU Mono, line by line;
- tables (GitHub pipes): a row as one paragraph, its cells at tab stops
  across the text width, the header row bold;
- pictures: ![text](file) beside the Markdown file (PNG, JPEG, GIF ...),
  at their own width up to the text width (docxgw.picture); web
  addresses are not fetched (a warning);
- page breaks: <!-- pagebreak --> (as `gwtool md` writes them), \\pagebreak
  or \\newpage on a line of their own; a rule (---, ***, ___) as a centred
  "* * *" line;
- a YAML front matter block (--- at the very start) is skipped.
Own code (GeoUltra, 2026).
"""
import os
import re
import xml.etree.ElementTree as ET

import docxgw

W = docxgw.W
TWIPS = docxgw.DOT_TWIPS
BODY_PT = 11                            # 12 dots, as Word's Normal style
HEADING_PT = (22, 16, 13, 11, 11, 11)   # 24, 18, 14, 12 dots (docxgw.gu_size)
INDENT = 24                             # dots per list or quote level
SANS, MONO = "Calibri", "Courier New"   # GU Sans, GU Mono (docxgw.FONTS)

RE_HEADING = re.compile(r"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$")
RE_SETEXT = re.compile(r"^ {0,3}(=+|-+)[ \t]*$")
RE_RULE = re.compile(r"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")
RE_FENCE = re.compile(r"^( {0,3})(`{3,}|~{3,})")
RE_ITEM = re.compile(r"^([ \t]*)([-*+]|\d{1,9}[.)])(?:[ \t]+(.*))?$")
RE_QUOTE = re.compile(r"^ {0,3}>[ ]?(.*)$")
RE_TABLE_SEP = re.compile(r"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$")
RE_PAGEBREAK = re.compile(r"^[ \t]*(<!--\s*pagebreak\s*-->|\\pagebreak|\\newpage)[ \t]*$", re.I)
RE_IMAGE_ONLY = re.compile(r"^[ \t]*!\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)[ \t]*$")
ESCAPABLE = "\\`*_{}[]()#+-.!|<>~\""


def font(pt=BODY_PT, b=False, i=False, u=False, mono=False, va=None, name=SANS):
    return {"font": MONO if mono else name, "pt": pt, "b": b, "i": i, "u": u,
            "outline": False, "va": va}


def para_layers(left=0, hanging=0, jc="left"):
    """A Word paragraph's properties as docxgw.ruler reads them."""
    p = ET.Element(W + "pPr")
    ind = ET.SubElement(p, W + "ind")
    ind.set(W + "left", str(left * TWIPS))
    if hanging:
        ind.set(W + "hanging", str(hanging * TWIPS))
    ET.SubElement(p, W + "jc").set(W + "val", jc)
    return [p]


class Inline:
    """Inline Markdown as reader pieces: ("text", (font, s)), ("tab", None),
    ("br", None), ("img", (alt, src))."""

    def __init__(self, base, bad, warnings):
        self.base = base
        self.bad = bad
        self.warnings = warnings

    def pieces(self, s, b=False, i=False, mono=False, pt=BODY_PT, name=SANS):
        out = []
        st = {"b": b, "i": i, "u": False, "mono": mono, "va": None}
        buf = []

        def flush():
            if buf:
                out.append(("text", (font(pt, st["b"], st["i"], st["u"], st["mono"], st["va"], name),
                                     docxgw.ascii_text("".join(buf), self.bad))))
                buf.clear()

        def closes(delim, start):
            """The closing delimiter's index, or -1 (then the text stays)."""
            j = s.find(delim, start)
            while j != -1 and s[j - 1] == "\\":
                j = s.find(delim, j + 1)
            return j
        k, n = 0, len(s)
        while k < n:
            c = s[k]
            if c == "\\" and k + 1 < n and s[k + 1] in ESCAPABLE:
                buf.append(s[k + 1])
                k += 2
                continue
            if c == "`":
                ticks = len(s[k:]) - len(s[k:].lstrip("`"))
                j = s.find("`" * ticks, k + ticks)
                if j != -1:
                    flush()
                    code = s[k + ticks:j]
                    if code.startswith(" ") and code.endswith(" ") and code.strip():
                        code = code[1:-1]
                    out.append(("text", (font(pt, st["b"], st["i"], st["u"], True, None, name),
                                         docxgw.ascii_text(code, self.bad))))
                    k = j + ticks
                    continue
            if s.startswith("![", k) or c == "[":
                m = re.match(r"(!?)\[((?:[^\]\\]|\\.)*)\]\(([^)\s]*)(?:\s+\"[^\"]*\")?\)", s[k:])
                if m:
                    flush()
                    if m.group(1):
                        out.append(("img", (m.group(2), m.group(3))))
                    else:
                        label, url = m.group(2), m.group(3)
                        out += self.pieces(label, st["b"], st["i"], st["mono"], pt, name)
                        if url and url != label and not url.startswith("#"):
                            buf.append(" (%s)" % url)
                    k += m.end()
                    continue
            if c == "<":
                m = re.match(r"<(/?)([a-zA-Z]+)[^>]*>|<(https?://[^>]+)>|<!--.*?-->", s[k:])
                if m:
                    flush()
                    if m.group(3):
                        buf.append(m.group(3))
                    elif m.group(2):
                        tag, end = m.group(2).lower(), bool(m.group(1))
                        if tag == "u":
                            st["u"] = not end
                        elif tag in ("b", "strong"):
                            st["b"] = not end
                        elif tag in ("i", "em"):
                            st["i"] = not end
                        elif tag in ("sup", "sub"):
                            st["va"] = None if end else ("superscript" if tag == "sup" else "subscript")
                        elif tag == "br":
                            out.append(("br", None))
                    k += m.end()
                    continue
            if c in "*_~":
                run = len(s[k:]) - len(s[k:].lstrip(c))
                before = s[k - 1] if k else " "
                after = s[k + run] if k + run < n else " "
                if c == "_" and before.isalnum() and after.isalnum():
                    buf.append(s[k:k + run])                    # (snake_case stays)
                    k += run
                    continue
                if c == "~":
                    if run >= 2 and closes(c * run, k + run) != -1:
                        k += run                                # (strike: no GEOS style)
                        continue
                    buf.append(s[k:k + run])
                    k += run
                    continue
                opening = not after.isspace()
                if run >= 2 and (st["b"] or (opening and closes(c * 2, k + 2) != -1)):
                    flush()
                    st["b"] = not st["b"]
                    k += 2
                    continue
                if st["i"] or (opening and closes(c, k + 1) != -1):
                    flush()
                    st["i"] = not st["i"]
                    k += 1
                    continue
            if c == "\t":
                flush()
                out.append(("tab", None))
                k += 1
                continue
            buf.append(c)
            k += 1
        flush()
        return out


class Reader:
    def __init__(self, path, width, body_font=SANS):
        self.path = path
        self.width = width
        self.name = body_font
        self.base = os.path.dirname(os.path.abspath(path))
        self.bad = [0]
        self.warnings = []
        self.inline = Inline(self.base, self.bad, self.warnings)

    def para(self, pieces, layers, after=True):
        """Reader items for one paragraph: line breaks and pictures split it."""
        rl, sp = docxgw.ruler(layers, self.width)
        out, cur = [], []
        for kind, data in pieces:
            if kind == "br":
                out.append(("para", (rl, sp, cur, False)))
                cur = []
            elif kind == "img":
                if cur:
                    out.append(("para", (rl, sp, cur, False)))
                    cur = []
                out += self.picture(*data)
            else:
                cur.append((kind, data))
        if cur or not out:
            out.append(("para", (rl, sp, cur, after)))
        elif out and out[-1][0] == "para" and after:
            k, (r, s, p, _) = out[-1]
            out[-1] = (k, (r, s, p, True))
        return out

    def picture(self, alt, src):
        if re.match(r"[a-z]+://", src):
            self.warnings.append("a picture on the web not fetched: %s" % src)
            return []
        path = os.path.join(self.base, src)
        try:
            blob = open(path, "rb").read()
            wc, h, rec = docxgw.picture(blob, 0, 0, self.width)
        except Exception as e:          # (missing, Pillow missing, an odd format)
            self.warnings.append("a picture not converted (%s): %s" % (src, e))
            return []
        return [("pic", (wc, h, rec))]

    def text(self, s, **kw):
        return self.inline.pieces(s, name=self.name, **kw)

    def items(self, text):
        lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        if lines and lines[0].strip() == "---":             # YAML front matter
            for j in range(1, len(lines)):
                if lines[j].strip() in ("---", "..."):
                    lines = lines[j + 1:]
                    break
        out = []
        para = []
        k = 0

        def end_para():
            if para:
                joined = ""
                for ln in para:
                    hard = ln.endswith("  ") or ln.endswith("\\")
                    ln = ln.rstrip()
                    if ln.endswith("\\"):
                        ln = ln[:-1]
                    joined += ln.strip() + ("<br>" if hard else " ")
                out.extend(self.para(self.text(joined.strip()), para_layers()))
                para.clear()
        while k < len(lines):
            ln = lines[k]
            if not ln.strip():
                end_para()
                k += 1
                continue
            if RE_PAGEBREAK.match(ln):
                end_para()
                out.append(("pagebreak", None))
                k += 1
                continue
            m = RE_FENCE.match(ln)
            if m:
                end_para()
                fence = m.group(2)
                code = []
                k += 1
                while k < len(lines) and not lines[k].strip().startswith(fence):
                    code.append(lines[k])
                    k += 1
                k += 1
                out.extend(self.code(code))
                continue
            if ln.startswith("    ") and not para:
                code = []
                while k < len(lines) and (lines[k].startswith("    ") or not lines[k].strip()):
                    code.append(lines[k][4:])
                    k += 1
                while code and not code[-1].strip():
                    code.pop()
                out.extend(self.code(code))
                continue
            m = RE_HEADING.match(ln)
            if m:
                end_para()
                out.extend(self.heading(len(m.group(1)), m.group(2) or ""))
                k += 1
                continue
            if para and RE_SETEXT.match(ln) and not RE_ITEM.match(para[-1]):
                level = 1 if ln.strip()[0] == "=" else 2
                title = " ".join(x.strip() for x in para)
                para.clear()
                out.extend(self.heading(level, title))
                k += 1
                continue
            if RE_RULE.match(ln):
                end_para()
                out.append(("para", (docxgw.ruler(para_layers(jc="center"), self.width)[0], 0,
                                     [("text", (font(BODY_PT, name=self.name), "* * *"))], True)))
                k += 1
                continue
            m = RE_IMAGE_ONLY.match(ln)
            if m and not para:
                out += self.picture(m.group(1), m.group(2))
                k += 1
                continue
            if RE_QUOTE.match(ln):
                end_para()
                quote = []
                while k < len(lines) and RE_QUOTE.match(lines[k]):
                    quote.append(RE_QUOTE.match(lines[k]).group(1))
                    k += 1
                out.extend(self.quote(quote))
                continue
            if "|" in ln and k + 1 < len(lines) and RE_TABLE_SEP.match(lines[k + 1]) and "-" in lines[k + 1]:
                end_para()
                rows = [ln]
                k += 2
                while k < len(lines) and "|" in lines[k] and lines[k].strip():
                    rows.append(lines[k])
                    k += 1
                out.extend(self.table(rows))
                continue
            if RE_ITEM.match(ln) and not RE_RULE.match(ln) and (not para or RE_ITEM.match(ln).group(3)):
                end_para()
                k = self.list_(lines, k, out)
                continue
            para.append(ln)
            k += 1
        end_para()
        return out

    def heading(self, level, title):
        pt = HEADING_PT[level - 1]
        return self.para(self.text(title.strip(), b=True, pt=pt), para_layers())

    def code(self, code):
        out = []
        for j, ln in enumerate(code):
            pieces = [("text", (font(BODY_PT, mono=True), docxgw.ascii_text(ln.expandtabs(4), self.bad)))]
            out.extend(self.para(pieces, para_layers(left=INDENT), after=j == len(code) - 1))
        return out

    def quote(self, quote):
        out, buf = [], []
        for ln in quote + [""]:
            if ln.strip():
                buf.append(ln.strip())
                continue
            if buf:
                out.extend(self.para(self.text(" ".join(buf), i=True), para_layers(left=INDENT)))
                buf = []
        return out

    def table(self, rows):
        def cells(row):
            row = row.strip()
            if row.startswith("|"):
                row = row[1:]
            if row.endswith("|") and not row.endswith("\\|"):
                row = row[:-1]
            return [c.strip() for c in re.split(r"(?<!\\)\|", row)]
        table = [cells(r) for r in rows]
        ncols = max(len(r) for r in table)
        step = self.width // max(1, ncols)
        rl, sp = docxgw.ruler(para_layers(), self.width, [step * j for j in range(1, ncols)])
        out = []
        for j, row in enumerate(table):
            pieces = []
            for c_k, c in enumerate(row):
                if c_k:
                    pieces.append(("tab", None))
                pieces += [p for p in self.text(c.replace("\\|", "|"), b=j == 0) if p[0] == "text"]
            out.append(("para", (rl, sp, pieces, j == len(table) - 1)))
        return out

    def list_(self, lines, k, out):
        """The list starting at line k into out; returns the next line."""
        counters = {}
        items = []
        while k < len(lines):
            m = RE_ITEM.match(lines[k])
            if not m or RE_RULE.match(lines[k]):
                if not lines[k].strip():
                    nxt = k + 1
                    while nxt < len(lines) and not lines[nxt].strip():
                        nxt += 1
                    if nxt < len(lines) and RE_ITEM.match(lines[nxt]) and not RE_RULE.match(lines[nxt]):
                        k = nxt
                        continue
                    break
                if items and lines[k].startswith((" ", "\t")):
                    items[-1][2].append(lines[k].strip())  # (a continuation line)
                    k += 1
                    continue
                break
            indent = len(m.group(1).expandtabs(4))
            level = min(3, indent // 2)
            marker = m.group(2)
            if marker in "-*+":
                prefix = "- "
            else:
                key = level
                if key not in counters:
                    counters[key] = int(marker[:-1])
                else:
                    counters[key] += 1
                for deeper in [x for x in counters if x > level]:
                    del counters[deeper]
                prefix = "%d. " % counters[key]
            items.append((level, prefix, [m.group(3) or ""]))
            k += 1
        for j, (level, prefix, text) in enumerate(items):
            body = " ".join(text)
            task = re.match(r"\[([ xX])\][ \t]+", body)
            if task:
                prefix += "[%s] " % ("x" if task.group(1) in "xX" else " ")
                body = body[task.end():]
            pieces = [("text", (font(BODY_PT, name=self.name), prefix))] + self.text(body)
            left = INDENT * (level + 1)
            out.extend(self.para(pieces, para_layers(left=left, hanging=INDENT // 2 + 4),
                                 after=j == len(items) - 1))
        return k


def convert(path, width=480, body_font=SANS):
    """(pages, header, footer, pictures {record: data}, warnings), as
    docxgw.convert; no header or footer."""
    rd = Reader(path, width, body_font)
    text = open(path, encoding="utf-8-sig", errors="replace").read()
    pages, pics, _ = docxgw.paginate(rd.items(text), width, rd.warnings)
    if rd.bad[0]:
        rd.warnings.append("%d character(s) without an ASCII form became '?'" % rd.bad[0])
    return pages, None, None, pics, rd.warnings
