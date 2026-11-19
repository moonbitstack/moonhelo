"""Render the course site under docs/ from the content under docs/content/.

One page per chapter, and a cover. Every page carries both languages: each text
node is emitted twice, tagged `data-lang`, and the reader picks one. Every code
sample is emitted once per style it has — function, class, annotation — and the
reader picks one of those too.

Generated HTML is committed, so CI can rerun this and diff it.

Usage: python scripts/gen_site.py [--check]
"""

import argparse
import hashlib
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
CONTENT = DOCS / "content"
LANGS = ("en", "zh")
STYLES = ("function", "type", "annotation", "config", "spec")
STYLE_LABELS = {
    "function": {"en": "Function", "zh": "函数"},
    "type": {"en": "Types", "zh": "类型"},
    "annotation": {"en": "Annotations", "zh": "注解"},
    "config": {"en": "Config", "zh": "配置"},
    "spec": {"en": "From a spec", "zh": "描述生成"},
}

KEYWORDS = {
    "async", "break", "catch", "const", "continue", "else", "enum", "extern",
    "false", "fn", "for", "guard", "if", "impl", "import", "in", "is", "let",
    "match", "mut", "noraise", "open", "priv", "pub", "raise", "return",
    "self", "struct", "suberror", "test", "trait", "true", "try", "type",
    "typealias", "use", "while", "with", "derive",
}


# --------------------------------------------------------------------------
# inline text: `code`, **bold**, [a link](target), and nothing else
# --------------------------------------------------------------------------

TOKEN = re.compile(r"`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)\s]+)\)")


def inline(text: str) -> str:
    out, last = [], 0
    for m in TOKEN.finditer(text):
        out.append(html.escape(text[last:m.start()]))
        if m.group(1) is not None:
            out.append(f'<code class="ic">{html.escape(m.group(1))}</code>')
        elif m.group(2) is not None:
            out.append(f"<strong>{html.escape(m.group(2))}</strong>")
        else:
            out.append(
                f'<a href="{html.escape(m.group(4))}">{html.escape(m.group(3))}</a>'
            )
        last = m.end()
    out.append(html.escape(text[last:]))
    return "".join(out)


def bi(node: dict, tag: str = "span", cls: str = "") -> str:
    """The same text in both languages, one of them hidden by the stylesheet."""
    parts = []
    for lang in LANGS:
        text = node.get(lang, "")
        attr = f' class="{cls}"' if cls else ""
        parts.append(
            f'<{tag}{attr} lang="{lang}" data-lang="{lang}">{inline(text)}</{tag}>'
        )
    return "".join(parts)


def raw(node: dict, tag: str, cls: str = "") -> str:
    """Like `bi`, but the text is HTML the content file already wrote."""
    parts = []
    for lang in LANGS:
        attr = f' class="{cls}"' if cls else ""
        parts.append(f'<{tag}{attr} lang="{lang}" data-lang="{lang}">{node.get(lang, "")}</{tag}>')
    return "".join(parts)


# --------------------------------------------------------------------------
# code colouring: a scanner, not a pile of regular expressions
# --------------------------------------------------------------------------

def highlight(code: str, lang: str) -> str:
    if lang == "shell":
        return highlight_shell(code)
    if lang in ("api", "proto"):
        return highlight_flat(code)
    return highlight_moonbit(code)


def highlight_flat(code: str) -> str:
    """A spec file is not MoonBit: tint its comments and strings, colour nothing
    else. Guessing at keywords here would put a language's syntax on a file that
    does not have it."""
    out = []
    for line in code.splitlines(keepends=True):
        body = line.rstrip("\n")
        cut = -1
        quote = ""
        for i, ch in enumerate(body):
            if quote:
                if ch == quote:
                    quote = ""
            elif ch in "\"'":
                quote = ch
            elif body.startswith("//", i):
                cut = i
                break
        if cut >= 0:
            out.append(html.escape(body[:cut]) + span("c", body[cut:]))
        else:
            out.append(html.escape(body))
        out.append("\n")
    return "".join(out).rstrip("\n")


def span(cls: str, text: str) -> str:
    return f'<span class="{cls}">{html.escape(text)}</span>'


def highlight_shell(code: str) -> str:
    out = []
    for line in code.splitlines(keepends=True):
        body = line.rstrip("\n")
        if body.startswith("$ "):
            out.append(span("prompt", "$ ") + html.escape(body[2:]))
        elif body.startswith("> "):
            out.append(span("prompt", "> ") + html.escape(body[2:]))
        elif body.startswith("# ") or body.startswith("---"):
            out.append(span("c", body))
        else:
            out.append(span("out", body))
        out.append("\n")
    return "".join(out).rstrip("\n")


def highlight_moonbit(code: str) -> str:
    i, n, out = 0, len(code), []
    while i < n:
        ch = code[i]
        # line comments, including the `///|` separator the formatter writes
        if code.startswith("//", i):
            j = code.find("\n", i)
            j = n if j < 0 else j
            out.append(span("c", code[i:j]))
            i = j
            continue
        # strings, byte strings and chars
        if ch in "\"'" or (ch == "b" and i + 1 < n and code[i + 1] == '"'):
            start = i
            if ch == "b":
                i += 1
            quote = code[i]
            i += 1
            while i < n:
                if code[i] == "\\":
                    i += 2
                    continue
                if code[i] == quote:
                    i += 1
                    break
                i += 1
            out.append(span("s", code[start:i]))
            continue
        # attributes: #derive(...), #app.get(...)
        if ch == "#" and i + 1 < n and (code[i + 1].isalpha() or code[i + 1] == "["):
            j = i + 1
            while j < n and (code[j].isalnum() or code[j] in "._"):
                j += 1
            out.append(span("o", code[i:j]))
            i = j
            continue
        # package references: @moonapi.App
        if ch == "@" and i + 1 < n and code[i + 1].isalpha():
            j = i + 1
            while j < n and (code[j].isalnum() or code[j] == "_"):
                j += 1
            out.append(span("p", code[i:j]))
            i = j
            continue
        if ch.isdigit():
            j = i
            while j < n and (code[j].isalnum() or code[j] in "._"):
                j += 1
            out.append(span("n", code[i:j]))
            i = j
            continue
        if ch.isalpha() or ch == "_":
            j = i
            while j < n and (code[j].isalnum() or code[j] == "_"):
                j += 1
            word = code[i:j]
            if word in KEYWORDS:
                out.append(span("k", word))
            elif word[0].isupper():
                out.append(span("t", word))
            else:
                out.append(html.escape(word))
            i = j
            continue
        out.append(html.escape(ch))
        i += 1
    return "".join(out)


# --------------------------------------------------------------------------
# blocks
# --------------------------------------------------------------------------

def render_code(block: dict) -> str:
    variants = [v for v in block.get("variants", []) if v.get("style") in STYLES]
    if not variants:
        return ""
    default = block.get("default") or variants[0]["style"]
    if default not in {v["style"] for v in variants}:
        default = variants[0]["style"]

    tabs = ""
    if len(variants) > 1:
        buttons = "".join(
            f'<button role="tab" type="button" data-style="{v["style"]}" '
            f'aria-selected="{"true" if v["style"] == default else "false"}">'
            + "".join(
                f'<span lang="{lang}" data-lang="{lang}">'
                f'{STYLE_LABELS[v["style"]][lang]}</span>'
                for lang in LANGS
            )
            + "</button>"
            for v in variants
        )
        tabs = f'<div class="tabs" role="tablist" aria-label="API style">{buttons}</div>'

    panes = []
    for v in variants:
        hidden = "" if v["style"] == default else " hidden"
        lang = v.get("lang", "moonbit")
        file = v.get("file", "")
        panes.append(
            f'<div class="pane" data-style="{v["style"]}"{hidden}>'
            f'<div class="pane__bar"><span class="pane__file">{html.escape(file)}</span>'
            f'<button class="copy" type="button" data-copy>Copy</button></div>'
            f'<pre tabindex="0"><code data-lang="{lang}">{highlight(v["code"].strip(chr(10)), lang)}</code></pre>'
            f"</div>"
        )

    caption = (
        f'<div class="code__note">{bi(block["note"])}</div>' if block.get("note") else ""
    )
    return f'<div class="code" data-code>{tabs}{"".join(panes)}{caption}</div>'


def render_term(block: dict) -> str:
    rows = []
    for step in block.get("steps", []):
        cmd = html.escape(step["cmd"])
        rows.append(f'<span class="prompt">$ </span>{cmd}')
        for line in step.get("out", []):
            rows.append(f'<span class="out">{html.escape(line)}</span>')
    body = "\n".join(rows)
    return (
        '<div class="code term" data-code>'
        '<div class="pane__bar"><span class="pane__file">shell</span>'
        f'<button class="copy" type="button" data-copy>{ui("copy")}</button></div>'
        f'<pre tabindex="0"><code data-lang="shell">{body}</code></pre>'
        "</div>"
    )


def render_table(block: dict) -> str:
    head = "".join(f"<th>{bi(c)}</th>" for c in block["head"])
    rows = []
    for row in block["rows"]:
        cells = "".join(f"<td>{bi(c)}</td>" for c in row)
        rows.append(f"<tr>{cells}</tr>")
    return (
        '<div class="table-wrap scroll"><table><thead><tr>'
        f"{head}</tr></thead><tbody>{''.join(rows)}</tbody></table></div>"
    )


def render_block(block: dict) -> str:
    kind = block["type"]
    if kind == "p":
        return f"<p>{bi(block['text'])}</p>"
    if kind == "h3":
        return f'<h3 id="{block["id"]}">{bi(block["text"])}</h3>'
    if kind == "code":
        return render_code(block)
    if kind == "term":
        return render_term(block)
    if kind == "table":
        return render_table(block)
    if kind == "note":
        return (
            f'<div class="note"><b>{bi(block["title"])}</b>'
            f'<div>{bi(block["text"])}</div></div>'
        )
    if kind == "try":
        items = "".join(f"<li>{bi(i)}</li>" for i in block["items"])
        return (
            f'<div class="try"><h3>{bi(block["title"])}</h3><ol>{items}</ol></div>'
        )
    if kind == "know":
        items = "".join(
            f'<li><span class="know__tick" aria-hidden="true"><svg width="12" height="12" '
            'viewBox="0 0 12 12"><path d="M2 6.4 4.6 9 10 3.4" fill="none" stroke="currentColor" '
            'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
            f"<span>{bi(i)}</span></li>"
            for i in block["items"]
        )
        return (
            f'<div class="know"><h3>{bi(block["title"])}</h3>'
            f'<ul>{items}</ul></div>'
        )
    if kind == "list":
        items = "".join(f"<li>{bi(i)}</li>" for i in block["items"])
        return f"<ul>{items}</ul>"
    raise SystemExit(f"unknown block type: {kind}")


def render_sections(page: dict) -> str:
    out = []
    for i, sec in enumerate(page["sections"], start=1):
        body = "".join(render_block(b) for b in sec["blocks"])
        out.append(
            f'<section id="{sec["id"]}">'
            f'<h2><span class="n">{i:02d}</span>{bi(sec["title"])}</h2>'
            f"{body}</section>"
        )
    return "\n".join(out)


# --------------------------------------------------------------------------
# shell
# --------------------------------------------------------------------------

BRAND = {"en": "Hello MoonBit Stack", "zh": "Hello MoonBit Stack"}

UI = {
    "onthispage": {"en": "On this page", "zh": "本页目录"},
    "copy": {"en": "Copy", "zh": "复制"},
    "prev": {"en": "Previous", "zh": "上一章"},
    "next": {"en": "Next", "zh": "下一章"},
    "courselink": {"en": "The course", "zh": "课程首页"},
    "soon": {"en": "not written yet", "zh": "待写"},
    "progress": {"en": "Your progress", "zh": "阅读进度"},
    "edit": {"en": "Edit this page", "zh": "编辑此页"},
    "know": {"en": "You can now", "zh": "现在你能"},
}


def ui(key: str) -> str:
    pair = UI[key]
    return "".join(
        f'<span lang="{lang}" data-lang="{lang}">{pair[lang]}</span>' for lang in LANGS
    )

FAVICON = (
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E"
    "%3Crect width='32' height='32' rx='7' fill='%232f6b57'/%3E"
    "%3Cpath d='M9 21L16 11l7 10' fill='none' stroke='%23f4f1ea' stroke-width='2.2' "
    "stroke-linecap='round' stroke-linejoin='round'/%3E%3Ccircle cx='16' cy='11' r='2.6' "
    "fill='%23f4f1ea'/%3E%3C/svg%3E"
)

# Code in JetBrains Mono; every other word in HarmonyOS Sans SC, split by
# unicode range so a page fetches only the characters it shows. One sheet per
# weight the stylesheet asks for.
def stamp(name: str) -> str:
    """The first characters of an asset's hash, so a page names the version it was
    built with and a browser holding the last one fetches the new one."""
    return hashlib.sha256((DOCS / "assets" / name).read_bytes()).hexdigest()[:10]


FONTS = [
    "https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&display=swap",
] + [
    f"https://cdn.jsdelivr.net/npm/harmonyos-sans-sc-webfont-splitted@1.1.0/dist/{weight}.css"
    for weight in ("Light", "Regular", "Medium", "Semibold", "Bold")
]

GITHUB = (
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">'
    '<path d="M8 0a8 8 0 0 0-2.53 15.59c.4.07.55-.17.55-.38v-1.34c-2.23.48-2.7-1.07-2.7-1.07'
    "-.36-.92-.89-1.17-.89-1.17-.73-.5.05-.49.05-.49.8.06 1.23.83 1.23.83.72 1.23 1.88.88 "
    "2.34.67.07-.52.28-.88.51-1.08-1.78-.2-3.65-.89-3.65-3.96 0-.87.31-1.59.82-2.15-.08-.2"
    "-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.03 2.2-.82 2.2-.82.44 1.1"
    ".16 1.92.08 2.12.51.56.82 1.28.82 2.15 0 3.08-1.87 3.76-3.66 3.96.29.25.54.73.54 1.48v2.2c0 "
    '.21.15.46.55.38A8 8 0 0 0 8 0Z"/></svg>'
)

SUN = (
    '<svg class="sun" width="16" height="16" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="12" cy="12" r="4.2"/>'
    '<path d="M12 2.6v2.1M12 19.3v2.1M2.6 12h2.1M19.3 12h2.1M5.3 5.3l1.5 1.5M17.2 17.2l1.5 1.5'
    'M18.7 5.3l-1.5 1.5M6.8 17.2l-1.5 1.5" stroke-linecap="round"/></svg>'
)

MOON = (
    '<svg class="moon" width="16" height="16" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="1.7" aria-hidden="true">'
    '<path d="M20 14.4A8.4 8.4 0 0 1 9.6 4a8.4 8.4 0 1 0 10.4 10.4Z" stroke-linejoin="round"/></svg>'
)


def plain(node: dict) -> str:
    """The words of a string that may carry markup.

    A cover title is written for the page — `<br>` for the line break, `<em>` for
    the one word that should lean — and neither belongs in `<title>`, where it
    would be read out as angle brackets.
    """
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", node["en"])).strip()


def head(site: dict, page: dict, css_prefix: str = "") -> str:
    title = plain(page["title"])
    summary = page.get("lead") or page.get("standfirst") or {"en": ""}
    return f"""<!DOCTYPE html>
<html lang="en" data-lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>{html.escape(title)} — {site["short"]}</title>
<meta name="description" content="{html.escape(plain(summary))}">
<link rel="icon" href="{FAVICON}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
{"".join(f'<link rel="stylesheet" href="{href}">{chr(10)}' for href in FONTS)}
<link rel="stylesheet" href="{css_prefix}assets/site.css?v={stamp("site.css")}">
</head>
<body{" data-slug=\"" + page["slug"] + "\"" if page.get("slug") else ""}>
<a class="skip" href="#content">Skip to content</a>
<header class="topbar">
  <button class="icon-btn menu" type="button" data-menu aria-label="Contents" aria-expanded="false">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16" stroke-linecap="round"/></svg>
  </button>
  <a class="brand" href="{css_prefix}index.html">
    <svg width="20" height="20" viewBox="0 0 32 32" aria-hidden="true"><rect width="32" height="32" rx="7" fill="var(--accent)"/><path d="M9 21L16 11l7 10" fill="none" stroke="var(--accent-ink)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="16" cy="11" r="2.6" fill="var(--accent-ink)"/></svg>
    {bi(BRAND, "span", "brand__name")}
  </a>
  <div class="topbar__end">
    <div class="lang" data-lang-menu>
      <button class="lang__btn" type="button" data-lang-toggle aria-haspopup="listbox" aria-expanded="false" aria-label="Language">
        <span data-lang-current>en</span>
        <svg class="lang__chev" viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <ul class="lang__list" role="listbox" aria-label="Language" hidden>
        <li class="lang__opt" role="option" data-lang-option="en" aria-selected="true" tabindex="-1">en</li>
        <li class="lang__opt" role="option" data-lang-option="zh" aria-selected="false" tabindex="-1">zh</li>
      </ul>
    </div>
    <button class="icon-btn" type="button" data-theme-toggle aria-label="Switch theme">{SUN}{MOON}</button>
    <a class="icon-btn" href="{site["repo"]}" aria-label="Source on GitHub">{GITHUB}</a>
  </div>
</header>
"""


def sidebar(site: dict, page: dict, prefix: str) -> str:
    groups = []
    ready = len([c for c in site["chapters"] if c.get("ready")])
    for part in site["parts"]:
        items = []
        for ch in site["chapters"]:
            if ch.get("part") != part["id"]:
                continue
            current = ' class="on" aria-current="page"' if ch["slug"] == page.get("slug") else ""
            if ch.get("ready"):
                items.append(
                    f'<li data-slug="{ch["slug"]}"><a{current} href="{prefix}{ch["slug"]}.html">'
                    f'<span class="n">{ch["num"]}</span>{bi(ch["title"])}'
                    '<span class="tick" aria-hidden="true"><svg width="11" height="11" viewBox="0 0 12 12">'
                    '<path d="M2 6.4 4.6 9 10 3.4" fill="none" stroke="currentColor" '
                    'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
                    "</a></li>"
                )
            else:
                items.append(
                    f'<li><span class="soon"><span class="n">{ch["num"]}</span>'
                    f'{bi(ch["title"])}</span></li>'
                )
        groups.append(
            f'<div class="side__group"><div class="side__label">{bi(part["title"])}</div>'
            f'<ul>{"".join(items)}</ul></div>'
        )
    head = (
        '<div class="side__head">'
        f'<span>{ui("progress")}</span><span class="side__count" data-read-count data-total="{ready}">0 / {ready}</span>'
        '<span class="side__bar" aria-hidden="true"><span data-read-bar></span></span>'
        "</div>"
    )
    return (
        f'<aside class="sidebar" data-sidebar><nav aria-label="Chapters">{head}'
        f'{"".join(groups)}</nav></aside>'
    )


def toc(page: dict) -> str:
    items = "".join(
        f'<li><a href="#{s["id"]}">{bi(s["title"])}</a></li>' for s in page["sections"]
    )
    return (
        '<aside class="toc" aria-label="On this page">'
        f'<div class="toc__label">{ui("onthispage")}</div>'
        f"<ol>{items}</ol></aside>"
    )


def pager(site: dict, page: dict, prefix: str) -> str:
    chapters = [c for c in site["chapters"] if c.get("ready")]
    slugs = [c["slug"] for c in chapters]
    if page.get("slug") not in slugs:
        return ""
    i = slugs.index(page["slug"])
    left = ""
    if i > 0:
        prev = chapters[i - 1]
        left = (
            f'<a class="pager__link" href="{prefix}{prev["slug"]}.html"><span class="pager__dir">{ui("prev")}</span>'
            f'<span class="pager__title">{bi(prev["title"])}</span></a>'
        )
    else:
        left = (
            f'<a class="pager__link" href="{prefix}index.html"><span class="pager__dir">{ui("prev")}</span>'
            f'<span class="pager__title">{ui("courselink")}</span></a>'
        )
    # the next page is the next chapter in the course, written or not: when the
    # course stops at the last written chapter, the reader is told what comes next
    # instead of finding the pager empty on one side
    order = [c["slug"] for c in site["chapters"]]
    at = order.index(page["slug"])
    nxt = site["chapters"][at + 1] if at + 1 < len(site["chapters"]) else None
    right = ""
    if nxt and nxt.get("ready"):
        right = (
            f'<a class="pager__link next" href="{prefix}{nxt["slug"]}.html"><span class="pager__dir">{ui("next")}</span>'
            f'<span class="pager__title">{bi(nxt["title"])}</span></a>'
        )
    elif nxt:
        right = (
            f'<span class="pager__link next is-soon"><span class="pager__dir">{ui("next")}'
            f" · {ui('soon')}</span>"
            f'<span class="pager__title">{bi(nxt["title"])}</span></span>'
        )
    return f'<nav class="pager" aria-label="Chapters">{left}{right}</nav>'


def footer(site: dict, page: dict, prefix: str = "") -> str:
    edit = ""
    if page.get("slug"):
        edit = (
            f'<a class="foot__edit" href="{site["repo"]}/edit/master/docs/content/'
            f'{page["slug"]}.json">{ui("edit")}</a>'
        )
    return (
        '<footer class="foot"><span>Apache-2.0</span>'
        f'<a href="{site["repo"]}">github.com/moonbitstack/moonhelo</a>'
        f"{edit}"
        f'<span class="foot__end">{bi(page.get("foot", {"en": "", "zh": ""}))}</span></footer>'
    )


# --------------------------------------------------------------------------
# pages
# --------------------------------------------------------------------------

def crumb(page: dict) -> str:
    """A chapter says which chapter it is."""
    return (
        f'<p class="crumb"><span lang="en" data-lang="en">Chapter {page["num"]}</span>'
        f'<span lang="zh" data-lang="zh">第 {page["num"]} 章</span></p>'
    )


def render_chapter(site: dict, page: dict) -> str:
    body = f"""<!DOCTYPE html>
{head(site, page)}
<div class="shell">
{sidebar(site, page, "")}
  <main id="content" class="main">
    <article class="doc">
      {crumb(page)}
      <h1>{bi(page["title"], "span", "h1__t")}</h1>
      <p class="lead">{bi(page["lead"])}</p>
{render_sections(page)}
{pager(site, page, "")}
    </article>
{footer(site, page, "")}
  </main>
{toc(page)}
</div>
<script src="assets/site.js?v={stamp("site.js")}"></script>
</body>
</html>
"""
    return body


def render_cover(site: dict, page: dict) -> str:
    """The home page as a document: a gutter of numbers, a real exchange, and the
    chapters set like a printed contents page. The accent colours rules, numbers
    and states; no word of the title carries the meaning by its colour."""

    def figure(value: str) -> str:
        if value == "@chapters":
            return str(len(site["chapters"]))
        if value == "@ready":
            return str(len([c for c in site["chapters"] if c.get("ready")]))
        if value == "@libraries":
            return str(site["libraries"])
        return value

    facts = "".join(
        f'<li><span>{bi(f["label"])}</span><b>{figure(f["value"])}</b></li>'
        for f in page["facts"]
    )

    def exchange_part(label: dict, note: str, lines: list, kind: str) -> str:
        rows = []
        for i, line in enumerate(lines):
            if line == "":
                rows.append("")
            elif i == 0 and kind == "req":
                verb, _, rest = line.partition(" ")
                rows.append(f"<b>{html.escape(verb)}</b> {html.escape(rest)}")
            elif i == 0 and kind == "res":
                rows.append(f"<b>{html.escape(line)}</b>")
            elif ": " in line and not line.startswith("{"):
                name, _, value = line.partition(":")
                rows.append(
                    f'<span class="hdr">{html.escape(name)}:</span>{html.escape(value)}'
                )
            else:
                rows.append(f'<span class="body">{html.escape(line)}</span>')
        return (
            '<div class="exchange__part">'
            f'<div class="exchange__label">{bi(label)}<em>{html.escape(note)}</em></div>'
            f"<pre>{chr(10).join(rows)}</pre>"
            "</div>"
        )

    ex = page["exchange"]
    exchange = (
        '<div class="exchange">'
        + exchange_part(ex["reqLabel"], ex["reqNote"], ex["request"], "req")
        + exchange_part(ex["resLabel"], ex["resNote"], ex["response"], "res")
        + f'<p class="exchange__note">{bi(ex["note"])}</p>'
        + "</div>"
    )

    layers = "".join(
        f'<li class="layer"><span class="layer__n">{l["n"]}</span>'
        f'<span class="layer__lib">{l["lib"]}</span>'
        f'<span class="layer__did">{bi(l["did"])}'
        f'<span class="layer__lead" aria-hidden="true"></span>'
        f'<code class="layer__art">{html.escape(l["artifact"])}</code></span></li>'
        for l in page["layers"]
    )

    entries = []
    for ch in site["chapters"]:
        tag = "a" if ch.get("ready") else "span"
        href = f' href="{ch["slug"]}.html"' if ch.get("ready") else ""
        cls = "entry" + ("" if ch.get("ready") else " soon")
        tags = " · ".join(ch.get("tags", []))
        entries.append(
            f'<li class="{cls}"><{tag}{href}>'
            f'<span class="entry__n">{ch["num"]}</span>'
            f'<span class="entry__t">{bi(ch["title"])}</span>'
            f'<span class="entry__d">{bi(ch["blurb"])}</span>'
            f'<span class="entry__tags">{html.escape(tags)}</span>'
            f"</{tag}></li>"
        )

    first = next(c["slug"] for c in site["chapters"] if c.get("ready"))

    setup = page["setup"]
    styles = page["styles"]

    def style_name(row: dict) -> str:
        if row["style"]:
            return "".join(
                f'<span lang="{lang}" data-lang="{lang}">{STYLE_LABELS[row["style"]][lang]}</span>'
                for lang in LANGS
            )
        return bi(row["label"])

    style_rows = "".join(
        f'<li class="layer"><span class="layer__n">{r["n"]}</span>'
        f'<span class="layer__lib">{style_name(r)}</span>'
        f'<span class="layer__did">{bi(r["did"])}'
        f'<span class="layer__lead" aria-hidden="true"></span>'
        f'<code class="layer__art">{html.escape(r["artifact"])}</code></span></li>'
        for r in styles["rows"]
    )
    picks = "".join(
        f'<button type="button" data-style="{r["style"]}" data-style-pick aria-pressed="false">'
        f"{style_name(r)}</button>"
        for r in styles["rows"]
        if r["style"]
    )

    body = f"""<!DOCTYPE html>
{head(site, {**page, "is_cover": True})}
<main id="content" class="cover">
  <section class="sheet sheet--first">
    <div class="sheet__gutter"><span class="sheet__num">00</span>{bi(page["gutter"][0])}</div>
    <div class="sheet__body">
      <div class="masthead">
        <div>
          <p class="kicker">{bi(page["kicker"])}</p>
          <h1>{raw(page["title"], "span", "title-lines")}</h1>
          <p class="standfirst">{bi(page["standfirst"])}</p>
          <ul class="facts">{facts}</ul>
          <p class="go">
            <a class="lead-link" href="{first}.html">{bi(page["go"]["primary"])}</a>
            <a href="{site["repo"]}">{bi(page["go"]["secondary"])}</a>
          </p>
        </div>
        {exchange}
      </div>
    </div>
  </section>

  <section class="sheet">
    <div class="sheet__gutter"><span class="sheet__num">01</span>{bi(page["gutter"][1])}</div>
    <div class="sheet__body">
      <div class="sheet__head">
        <h2 class="sheet__title">{bi(page["layersTitle"])}</h2>
        <span class="sheet__hint">{bi(page["layersHint"])}</span>
      </div>
      <p class="about">{bi(page["layersLead"])}</p>
      <ol class="layers">{layers}</ol>
    </div>
  </section>

  <section class="sheet">
    <div class="sheet__gutter"><span class="sheet__num">02</span>{bi(page["gutter"][2])}</div>
    <div class="sheet__body">
      <div class="sheet__head">
        <h2 class="sheet__title">{bi(setup["title"])}</h2>
        <span class="sheet__hint">{bi(setup["hint"])}</span>
      </div>
      <p class="about">{bi(setup["lead"])}</p>
      {render_code(setup["code"])}
      <p class="about">{bi(setup["next"])}</p>
    </div>
  </section>

  <section class="sheet">
    <div class="sheet__gutter"><span class="sheet__num">03</span>{bi(page["gutter"][3])}</div>
    <div class="sheet__body">
      <div class="sheet__head">
        <h2 class="sheet__title">{bi(styles["title"])}</h2>
        <span class="sheet__hint">{bi(styles["hint"])}</span>
      </div>
      <p class="about">{bi(styles["lead"])}</p>
      <ol class="layers">{style_rows}</ol>
      <div class="picker" role="group" aria-label="API style">
        <span class="picker__label">{bi(styles["pick"])}</span>{picks}
      </div>
    </div>
  </section>

  <section class="sheet">
    <div class="sheet__gutter"><span class="sheet__num">04</span>{bi(page["gutter"][4])}</div>
    <div class="sheet__body">
      <div class="sheet__head">
        <h2 class="sheet__title">{bi(page["contentsTitle"])}</h2>
        <span class="sheet__hint">{bi(page["contentsHint"])}</span>
      </div>
      <ol class="contents">{''.join(entries)}</ol>
    </div>
  </section>

  <div class="colophon">
    <span>Apache-2.0</span>
    <a href="{site["repo"]}">github.com/moonbitstack/moonhelo</a>
    <span>{bi(page["colophon"])}</span>
  </div>
</main>
<script src="assets/site.js?v={stamp("site.js")}"></script>
</body>
</html>
"""
    return body


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if a page would change")
    args = ap.parse_args()

    site = json.loads((CONTENT / "site.json").read_text(encoding="utf-8"))
    pages = {}
    cover = json.loads((CONTENT / "cover.json").read_text(encoding="utf-8"))
    pages["index.html"] = render_cover(site, cover)
    for path in sorted(CONTENT.glob("ch*.json")):
        page = json.loads(path.read_text(encoding="utf-8"))
        page["slug"] = path.stem
        pages[f"{path.stem}.html"] = render_chapter(site, page)

    changed = []
    for name, text in pages.items():
        target = DOCS / name
        new = text.encode("utf-8")
        old = target.read_bytes() if target.exists() else b""
        if old != new:
            changed.append(name)
            if not args.check:
                target.write_bytes(new)
    if args.check and changed:
        print("out of date: " + ", ".join(changed))
        return 1
    print(f"wrote {len(pages)} pages" + (f"; {len(changed)} changed" if args.check else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
