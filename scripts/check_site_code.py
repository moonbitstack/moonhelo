"""Check every MoonBit block on the course pages.

Two kinds of block, two kinds of proof:

- a **quoted** block is a piece of a file in this repository, and every line of it
  must be a line of that file. The file already compiles because the build
  compiles it, so the check is that the page has not drifted from it;
- a **standalone** block is code written for the page. It is compiled here, with
  the context the content file gives it, so a page cannot teach code that does
  not build.

The content file says which is which: `"check": "compile"` marks a standalone
block; anything else with a `file` is a quote. Shell transcripts are neither —
they are the recorded output of a run, and they carry `"check": "skip"`.

Usage: python scripts/check_site_code.py
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "docs" / "content"
SCRATCH = ROOT / "src" / "site_check"

# aliases whose package name is not their last path segment
ALIASES = {
    "sqlite": "moonbitstack/moonsqlite",
    "gql": "moonbitstack/moongql",
    "zero": "moonbitstack/moonzero",
    "moonjson": "moonbitstack/moonjson",
    "genmodel": "moonbitstack/moonhelo/genmodel",
    "moonrpc": "moonbitstack/moonrpc",
    "moonapi": "moonbitstack/moonapi",
    "moonasgi": "moonbitstack/moonasgi",
    "moonorm": "moonbitstack/moonorm",
    "moondb": "moonbitstack/moondb",
    "mooncat": "moonbitstack/mooncat",
    "moonmuse": "moonbitstack/moonmuse",
    "moonstate": "moonbitstack/moonstate",
    "prompt": "moonbitstack/moonmuse/prompt",
    "fake": "moonbitstack/moonmuse/fake",
}
CORE = {"json": "moonbitlang/core/json", "utf8": "moonbitlang/core/encoding/utf8"}


def norm(line: str) -> str:
    return re.sub(r"\s+", " ", line).strip()


def is_comment(line: str) -> bool:
    s = line.strip()
    return not s or s.startswith("//")


def blocks():
    """Every code variant on every page, with the page it came from."""
    for path in sorted(CONTENT.glob("*.json")):
        page = json.loads(path.read_text(encoding="utf-8"))
        stack = list(page.get("sections", []))
        # the cover keeps its figures in JSON, no code blocks
        while stack:
            sec = stack.pop()
            for block in sec.get("blocks", []):
                if block.get("type") != "code":
                    continue
                for variant in block.get("variants", []):
                    yield path.name, block, variant


def check_quote(variant: dict) -> list:
    file = variant.get("file", "")
    if not file:
        return ["a quoted block needs a `file`"]
    target = ROOT / file
    if not target.exists():
        return [f"{file}: no such file"]
    known = {norm(l) for l in target.read_text(encoding="utf-8").splitlines()}
    missing = [
        l.strip()
        for l in variant["code"].splitlines()
        if not is_comment(l) and norm(l) not in known
    ]
    return [f"{file}: not a line of the file: {m}" for m in missing]


def check_compile(page: str, variant: dict) -> list:
    code = variant["code"]
    context = variant.get("context", "")
    body = "\n".join(
        part for part in (context, code) if part.strip()
    )
    used = set(re.findall(r"@([a-z_][a-z0-9_]*)\.", body))
    imports = []
    for alias in sorted(used):
        if alias in ALIASES:
            imports.append(ALIASES[alias])
        elif alias in CORE:
            imports.append(CORE[alias])
        else:
            return [f"{page}: no package known for `@{alias}`"]

    shutil.rmtree(SCRATCH, ignore_errors=True)
    SCRATCH.mkdir(parents=True)
    pkg = "import {\n" + "".join(f'  "{m}",\n' for m in imports) + "}\n"
    (SCRATCH / "moon.pkg").write_text(pkg, encoding="utf-8", newline="\n")
    (SCRATCH / "snippet.mbt").write_text(
        f"async fn snippet() -> Unit raise {{\n{body}\n}}\n", encoding="utf-8", newline="\n"
    )
    try:
        run = subprocess.run(
            ["moon", "check", "--target", "native", "src/site_check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    finally:
        shutil.rmtree(SCRATCH, ignore_errors=True)

    if run.returncode == 0:
        return []
    detail = (run.stdout + run.stderr).strip().splitlines()
    tail = next((l for l in reversed(detail) if "Error" in l or "error" in l), "")
    return [f"{page}: does not compile: {tail or (detail[-1] if detail else 'unknown')}"]


def main() -> int:
    failures = []
    quoted = compiled = skipped = 0
    for page, _block, variant in blocks():
        mode = variant.get("check", "quote")
        if mode == "skip":
            skipped += 1
            continue
        if mode == "compile":
            compiled += 1
            failures += check_compile(page, variant)
            continue
        quoted += 1
        failures += [f"{page}: {m}" for m in check_quote(variant)]

    for line in failures:
        print(line)
    print(
        f"{quoted} quoted blocks, {compiled} compiled, {skipped} skipped"
        + (f", {len(failures)} problems" if failures else ", all good")
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
