#!/usr/bin/env python3
"""Validate relative links and heading anchors in the repo's Markdown docs.

Catches the class of defect where a doc links to a path that does not exist, or to a
``#anchor`` that no heading generates — both of which render as working links and only
fail when a reader clicks them.

Usage:
    scripts/check-doc-links.py                # every tracked doc (default scope)
    scripts/check-doc-links.py FILE [FILE …]  # only these files (pre-commit passes staged)

Exit status is 1 when any link is broken, 0 otherwise. External links (http, https,
mailto) are never fetched.
"""
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Default scope: standing docs a reader navigates. Plans/retros are included because their
# links are followed too, but see SKIP_DIRS for vendored trees.
DEFAULT_GLOBS = ("docs/**/*.md", "memory-bank/**/*.md", "README.md", "CHANGELOG.md")
SKIP_DIRS = ("scripts/lib/foundation/", "scripts/lib/acg/", "node_modules/")

EXTERNAL = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//)", re.IGNORECASE)
# [text](target) — target stops at whitespace so an optional "title" is ignored.
LINK = re.compile(r"\[(?:[^\]\[]|\[[^\]]*\])*\]\(\s*([^)\s]+)")
# Inline code spans: a regex like `[a-z0-9]([a-z-]{0,61})?` inside backticks is not a link.
CODE_SPAN = re.compile(r"(`+)(?:(?!\1).)*?\1", re.DOTALL)
# This repo uses clickable `path:line` references; the line suffix is not part of the path.
LINE_SUFFIX = re.compile(r":\d+(?:-\d+)?$")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
# Explicit anchors readers can target: <a id="x">, <a name="x">, {#x}
EXPLICIT_ANCHOR = re.compile(r"""<a\s+(?:id|name)\s*=\s*["']([^"']+)["']|\{#([A-Za-z0-9_-]+)\}""")


def strip_code_fences(lines):
    """Yield (lineno, text) for lines outside fenced code blocks.

    Headings and links inside a fenced block are examples, not real ones — a shell comment
    like ``# Requires a host context`` is not a heading.
    """
    fence = None
    for idx, line in enumerate(lines, start=1):
        match = FENCE.match(line)
        if fence is None:
            if match:
                fence = match.group(1)[0] * 3
                continue
            yield idx, line
        elif match and match.group(1)[0] * 3 == fence:
            fence = None


def slugify(text):
    """GitHub's heading-anchor algorithm."""
    text = re.sub(r"<[^>]+>", "", text)            # inline HTML
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)  # links keep their text
    text = text.replace("`", "")
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    # github-slugger does `.replace(/ /g, '-')` — each space becomes its own hyphen, so
    # "/claude / /gemini" collapses to "claude--gemini", NOT "claude-gemini". Collapsing
    # runs here would report correct links as broken.
    return re.sub(r"\s", "-", text.strip())


def anchors_of(path, cache={}):
    """Every anchor a reader can link to in ``path`` (headings + explicit ids)."""
    key = str(path)
    if key in cache:
        return cache[key]
    found = set()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        cache[key] = found
        return found
    seen = {}
    for _, line in strip_code_fences(lines):
        match = HEADING.match(line)
        if match:
            slug = slugify(match.group(2))
            if not slug:
                continue
            # GitHub disambiguates repeats with -1, -2, …
            count = seen.get(slug, 0)
            seen[slug] = count + 1
            found.add(slug if count == 0 else f"{slug}-{count}")
        for explicit in EXPLICIT_ANCHOR.finditer(line):
            found.add(explicit.group(1) or explicit.group(2))
    cache[key] = found
    return found


def default_files():
    """Tracked Markdown files in the default scope, so untracked scratch is ignored."""
    try:
        tracked = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files", "-z", *DEFAULT_GLOBS],
            capture_output=True, text=True, check=True,
        ).stdout.split("\0")
    except (OSError, subprocess.CalledProcessError):
        return sorted(
            p for glob in DEFAULT_GLOBS for p in REPO_ROOT.glob(glob)
            if not any(s in p.as_posix() for s in SKIP_DIRS)
        )
    return [
        REPO_ROOT / rel for rel in tracked
        if rel and not any(s in rel for s in SKIP_DIRS)
    ]


def check_file(path):
    """Return a list of (lineno, target, reason) for every broken link in ``path``."""
    problems = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return problems

    for lineno, line in strip_code_fences(lines):
        # Blank out inline code so regexes and sample markup inside backticks are not
        # mistaken for links, while keeping column positions intact.
        line = CODE_SPAN.sub(lambda m: " " * len(m.group(0)), line)
        for match in LINK.finditer(line):
            target = match.group(1).strip("<>")
            if not target or EXTERNAL.match(target):
                continue
            rel, _, anchor = target.partition("#")
            rel = LINE_SUFFIX.sub("", rel.strip())

            if not rel:                                  # same-file anchor
                if anchor and anchor not in anchors_of(path):
                    problems.append((lineno, target, "no such heading in this file"))
                continue

            resolved = (path.parent / rel).resolve()
            if not resolved.exists():
                problems.append((lineno, target, "path does not exist"))
                continue
            # Only .md files have anchors we can verify; a directory or asset link with a
            # fragment is out of scope.
            if anchor and resolved.is_file() and resolved.suffix == ".md":
                if anchor not in anchors_of(resolved):
                    problems.append((lineno, target, "target file has no such heading"))
    return problems


def main(argv):
    if argv:
        files = [Path(a).resolve() for a in argv]
        files = [f for f in files if f.suffix == ".md" and f.is_file()]
    else:
        files = default_files()

    broken = 0
    for path in files:
        for lineno, target, reason in check_file(path):
            try:
                shown = path.relative_to(REPO_ROOT)
            except ValueError:
                shown = path
            print(f"{shown}:{lineno}: broken link {target!r} — {reason}", file=sys.stderr)
            broken += 1

    if broken:
        print(
            f"\n{broken} broken link(s) in {len(files)} file(s). "
            "Fix the path or the anchor — do not delete the link.",
            file=sys.stderr,
        )
        return 1
    print(f"check-doc-links: {len(files)} file(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
