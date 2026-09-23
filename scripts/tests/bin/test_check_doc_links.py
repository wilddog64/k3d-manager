"""Tests for scripts/check-doc-links.py.

Each broken-link case asserts the checker *fails*, and each false-positive case asserts it
*passes* — a checker that never fires and a checker that always fires are equally useless.
"""
import re
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "check-doc-links.py"

_loader = importlib.machinery.SourceFileLoader("check_doc_links", str(SCRIPT))
_spec = importlib.util.spec_from_loader("check_doc_links", _loader)
cdl = importlib.util.module_from_spec(_spec)
_loader.exec_module(cdl)


def write(tmp_path, name, text):
    p = tmp_path / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    return p


# --- slug algorithm -------------------------------------------------------------------

@pytest.mark.parametrize("heading,expected", [
    ("Tier 1: per-candidate vCluster gate", "tier-1-per-candidate-vcluster-gate"),
    ("Tier 2: ACG sandbox Stripe verification", "tier-2-acg-sandbox-stripe-verification"),
    ("Roadmap (remaining phases)", "roadmap-remaining-phases"),
    ("1. Create Slack App", "1-create-slack-app"),
    ("`/cluster-diagnose` usage", "cluster-diagnose-usage"),
    ("/k3dm targets", "k3dm-targets"),
    # github-slugger replaces EACH space, so "/ /" leaves a double hyphen. Collapsing runs
    # here would report a correct link as broken.
    ("/claude / /gemini / /codex Commands", "claude--gemini--codex-commands"),
])
def test_slugify_matches_github(heading, expected):
    assert cdl.slugify(heading) == expected


def test_duplicate_headings_get_numeric_suffixes(tmp_path):
    f = write(tmp_path, "d.md", "## Notes\n\n## Notes\n\n## Notes\n")
    assert cdl.anchors_of(f) == {"notes", "notes-1", "notes-2"}


def test_explicit_html_anchor_is_found(tmp_path):
    f = write(tmp_path, "d.md", '<a id="manual-target"></a>\n\ntext\n')
    assert "manual-target" in cdl.anchors_of(f)


# --- broken links must fail ------------------------------------------------------------

def test_missing_path_is_reported(tmp_path):
    f = write(tmp_path, "a.md", "See [other](./nope.md).\n")
    problems = cdl.check_file(f)
    assert [p[2] for p in problems] == ["path does not exist"]
    assert problems[0][0] == 1


def test_missing_anchor_in_other_file_is_reported(tmp_path):
    write(tmp_path, "b.md", "# Real Heading\n")
    f = write(tmp_path, "a.md", "See [b](./b.md#not-there).\n")
    assert [p[2] for p in cdl.check_file(f)] == ["target file has no such heading"]


def test_missing_same_file_anchor_is_reported(tmp_path):
    f = write(tmp_path, "a.md", "# Top\n\nJump to [nowhere](#nowhere).\n")
    assert [p[2] for p in cdl.check_file(f)] == ["no such heading in this file"]


def test_bad_relative_depth_is_reported(tmp_path):
    """The real ldap-bulk-user-import bug: ../bin/x where ../../bin/x was meant."""
    write(tmp_path, "bin/tool", "#!/bin/sh\n")
    f = write(tmp_path, "docs/howto/g.md", "Run [tool](../bin/tool).\n")
    assert [p[2] for p in cdl.check_file(f)] == ["path does not exist"]


# --- valid links must pass ------------------------------------------------------------

def test_good_links_pass(tmp_path):
    write(tmp_path, "b.md", "# Real Heading\n")
    f = write(tmp_path, "a.md", "[b](./b.md) and [h](./b.md#real-heading)\n")
    assert cdl.check_file(f) == []


def test_correct_relative_depth_passes(tmp_path):
    write(tmp_path, "bin/tool", "#!/bin/sh\n")
    f = write(tmp_path, "docs/howto/g.md", "Run [tool](../../bin/tool).\n")
    assert cdl.check_file(f) == []


def test_external_links_are_never_checked(tmp_path):
    f = write(tmp_path, "a.md",
              "[x](https://example.invalid/nope)\n[y](http://h/n)\n[z](mailto:a@b.c)\n")
    assert cdl.check_file(f) == []


def test_regex_in_inline_code_is_not_a_link(tmp_path):
    """`[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?` looks exactly like [text](target)."""
    f = write(tmp_path, "a.md",
              "Validate with `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$` before use.\n")
    assert cdl.check_file(f) == []


def test_sample_markdown_in_inline_code_is_not_a_link(tmp_path):
    f = write(tmp_path, "a.md", "README had `[v0.9.17](releases/tag/v0.9.17)` too early.\n")
    assert cdl.check_file(f) == []


def test_links_inside_fenced_blocks_are_ignored(tmp_path):
    f = write(tmp_path, "a.md", "```\n[gone](./nope.md)\n```\n")
    assert cdl.check_file(f) == []


def test_headings_inside_fenced_blocks_are_not_anchors(tmp_path):
    """A shell comment in a code block is not a heading."""
    f = write(tmp_path, "a.md", "# Real\n\n```bash\n# Requires a host context\n```\n")
    assert cdl.anchors_of(f) == {"real"}


def test_path_with_line_suffix_resolves_to_the_file(tmp_path):
    """This repo writes clickable `path:line` references."""
    write(tmp_path, "bin/tool", "#!/bin/sh\n")
    f = write(tmp_path, "a.md", "See [tool](./bin/tool:95).\n")
    assert cdl.check_file(f) == []


def test_directory_link_with_fragment_is_not_anchor_checked(tmp_path):
    (tmp_path / "sub").mkdir()
    f = write(tmp_path, "a.md", "[dir](./sub#whatever)\n")
    assert cdl.check_file(f) == []


# --- the live tree ---------------------------------------------------------------------

def test_no_doc_links_target_an_absolute_path():
    """An absolute link resolves on the author's machine and nowhere else.

    `/Users/cliang/.../scripts/plugins/vault.sh` exists locally, so both `make check-doc-links`
    and this module's broken-link gate pass on a Mac and fail on the Linux CI runner. Banning the
    shape outright makes the failure reproducible locally.
    """
    offenders = []
    for path in cdl.default_files():
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for match in re.finditer(r"\]\((/[^)\s]+)\)", line):
                offenders.append(
                    f"{path.relative_to(ROOT)}:{lineno} {match.group(1)}"
                    " — absolute link target; use a repo-relative path"
                )
    assert offenders == [], "\n".join(offenders)


def test_repo_docs_have_no_broken_links():
    """The gate itself: the committed tree must stay clean."""
    broken = []
    for path in cdl.default_files():
        for lineno, target, reason in cdl.check_file(path):
            broken.append(f"{path.relative_to(ROOT)}:{lineno} {target} — {reason}")
    assert broken == [], "\n".join(broken)
