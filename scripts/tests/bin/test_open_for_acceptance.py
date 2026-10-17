import importlib.machinery
import importlib.util
import os
import re
import socket
import subprocess
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
MODULE = os.environ.get("OPEN_FOR_MODULE", str(REPO / "bin" / "k3dm-vectordb-metrics"))
NOW = datetime(2026, 10, 17, 12, 0, tzinfo=timezone.utc)


def _load():
    loader = importlib.machinery.SourceFileLoader("open_for_mod", MODULE)
    spec = importlib.util.spec_from_loader("open_for_mod", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    def boom(*a, **k):
        raise AssertionError("network access attempted")
    monkeypatch.setattr(urllib.request, "urlopen", boom)
    monkeypatch.setattr(socket, "create_connection", boom)


@pytest.fixture
def repo(tmp_path):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    return tmp_path


def _doc(status, filed="2026-10-10", title="Sample bug"):
    lines = [f"# Bug: {title}", "", f"**Status:** {status}", "**Priority:** P2"]
    if filed:
        lines.append(f"**Filed:** {filed}")
    return "\n".join(lines) + "\n"


def _value(repo, release, status, filed="2026-10-10", name="2026-10-10-sample-bug"):
    mod = _load()
    path = f"docs/bugs/{name}.md"
    tally = {release: {"open_paths": [], "unknown_paths": [], "closed_paths": [{"path": path}]}}
    out = mod._bug_status_metrics(repo, now=NOW, tally=tally, texts={path: _doc(status, filed)},
                                  fixed_in={}, verification_times={})
    vals = [l for l in out.splitlines() if l.startswith("k3dm_bug_info{")]
    assert len(vals) == 1, out
    assert f'bug="{name}"' in vals[0]
    return int(vals[0].rsplit(" ", 1)[1])


def test_m1_fixed_not_verified_counts_days(repo):
    assert _value(repo, "v1.43.4", "FIXED") == 7


def test_m1_boundary_release_v1_43_2(repo):
    assert _value(repo, "v1.43.2", "FIXED") == 7


def test_m2_offline_verified_counts_days(repo):
    assert _value(repo, "v1.43.4", "VERIFIED — 2026-10-12") == 7


def test_m3_live_verified_is_minus_two(repo):
    assert _value(repo, "v1.43.4", "LIVE-VERIFIED — 2026-10-15") == -2


def test_m4_open_bug_days(repo):
    mod = _load()
    path = "docs/bugs/2026-10-10-open-one.md"
    tally = {"v1.43.4": {"open_paths": [{"path": path}], "unknown_paths": [], "closed_paths": []}}
    out = mod._bug_status_metrics(repo, now=NOW, tally=tally, texts={path: _doc("OPEN")},
                                  fixed_in={}, verification_times={})
    line = [l for l in out.splitlines() if l.startswith("k3dm_bug_info{")][0]
    assert line.endswith(" 7")


def test_m4_no_filed_date_and_no_prefix_is_minus_one(repo):
    mod = _load()
    path = "docs/bugs/undated-open-one.md"
    tally = {"v1.43.4": {"open_paths": [{"path": path}], "unknown_paths": [], "closed_paths": []}}
    out = mod._bug_status_metrics(repo, now=NOW, tally=tally, texts={path: _doc("OPEN", filed=None)},
                                  fixed_in={}, verification_times={})
    line = [l for l in out.splitlines() if l.startswith("k3dm_bug_info{")][0]
    assert line.endswith(" -1")


def test_m4_fixed_no_filed_date_is_minus_one(repo):
    assert _value(repo, "v1.43.4", "FIXED", filed=None, name="undated-fixed-one") == -1


def test_filed_falls_back_to_name_prefix(repo):
    assert _value(repo, "v1.43.4", "FIXED", filed=None, name="2026-10-01-prefix-bug") == 16


def test_n1_fixed_not_live_verified_never_minus_two(repo):
    for status in ("FIXED", "VERIFIED — 2026-10-12"):
        assert _value(repo, "v1.43.4", status) != -2


def test_n2_old_release_stays_minus_two(repo):
    for release in ("v1.40.0", "v1.43.1"):
        for status in ("FIXED", "VERIFIED — 2026-10-12", "LIVE-VERIFIED — 2026-10-15"):
            assert _value(repo, release, status) == -2


def test_m5_guide_states_open_for_until_live_verified():
    text = (REPO / "docs/guides/grafana-dashboards.md").read_text()
    paragraphs = re.split(r"\n\s*\n", text)
    assert any(re.search(r"open for", p, re.I) and re.search(r"live-verified", p, re.I)
               and re.search(r"until|counts", p, re.I) for p in paragraphs)
    assert not re.search(r"open for[^.\n]*(stops|ends)[^.\n]*fix", text, re.I)


def test_n3_module_has_no_network_calls_in_builder(repo):
    assert _value(repo, "v1.43.4", "FIXED") == 7
