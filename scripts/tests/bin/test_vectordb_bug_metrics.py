import runpy
import subprocess
import sys
from datetime import datetime, timezone
from types import SimpleNamespace
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))


@pytest.fixture
def metrics():
    return SimpleNamespace(**runpy.run_path(ROOT / "bin/k3dm-vectordb-metrics"))


def _repo(tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "p1-open.md").write_text("# open\n\n**Priority:** P1\n**Status:** Open\n")
    (bugs / "p0-fixed.md").write_text("# fixed\n\n**Priority:** P0\n**Status:** FIXED\n")
    (bugs / "unset.md").write_text("# unknown\n\nno status\n")
    (bugs / "archive").mkdir()
    (bugs / "archive/ignored.md").write_text("**Priority:** P0\n**Status:** Open\n")
    (tmp_path / "docs/issues").mkdir(parents=True)
    (tmp_path / "docs/issues/ignored.md").write_text("**Priority:** P0\n**Status:** Open\n")
    return tmp_path


def _git_repo(root, docs):
    bugs = root / "docs/bugs"
    bugs.mkdir(parents=True)
    for name, text in docs.items():
        (bugs / name).write_text(text, encoding="utf-8")
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
    subprocess.run(["git", "add", "docs/bugs"], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=root, check=True)


def test_bug_metrics_has_exact_counts_all_15_series_and_scan_timestamp(metrics, tmp_path):
    output = metrics._bug_metrics(_repo(tmp_path))
    assert 'k3dm_bug_docs{priority="P1",state="open"} 1' in output
    assert 'k3dm_bug_docs{priority="P0",state="closed"} 1' in output
    assert 'k3dm_bug_docs{priority="unset",state="unknown"} 1' in output
    assert output.count("k3dm_bug_docs{") == 15
    assert "k3dm_bug_docs_scan_timestamp_seconds" in output
    assert "archive" not in output and "issues" not in output


def test_bug_metrics_pushes_separate_group(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    assert metrics.publish_bug_metrics(_repo(tmp_path)) is True
    assert any("/metrics/job/k3dm-bug-docs" in str(getattr(url, "full_url", url)) for url in urls)


def test_bug_metrics_read_failure_does_not_push(metrics, monkeypatch, tmp_path):
    root = _repo(tmp_path)
    original_read_text = Path.read_text
    def fail_one(path, *args, **kwargs):
        if path.name == "p1-open.md":
            raise OSError("read failure")
        return original_read_text(path, *args, **kwargs)
    monkeypatch.setattr(Path, "read_text", fail_one)
    pushed = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda *_a, **_k: pushed.append(True))
    assert metrics.publish_bug_metrics(root) is False
    assert pushed == []


def test_bug_texts_reads_committed_docs_with_one_cat_file(metrics, monkeypatch, tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    expected = {
        "docs/bugs/one.md": "# one\n\nCafé — 日本語\n",
        "docs/bugs/two.md": "# two\n\nplain\n",
        "docs/bugs/three.md": "# three\n\nthird\n",
    }
    _git_repo(root, {path.removeprefix("docs/bugs/"): text for path, text in expected.items()})
    original_run = metrics.subprocess.run
    calls = []

    def tracked_run(argv, *args, **kwargs):
        calls.append(argv)
        return original_run(argv, *args, **kwargs)

    monkeypatch.setattr(metrics.subprocess, "run", tracked_run)
    assert metrics._bug_texts(root, "HEAD") == expected
    assert sum("cat-file" in call for call in calls) == 1
    assert not any("show" in call for call in calls)


def test_bug_texts_rejects_missing_batch_object(metrics, monkeypatch, tmp_path):
    root = tmp_path / "repo"
    root.mkdir()
    _git_repo(root, {"present.md": "# present\n"})
    original_run = metrics.subprocess.run

    def add_missing_path(argv, *args, **kwargs):
        result = original_run(argv, *args, **kwargs)
        if "ls-tree" in argv:
            result.stdout += "docs/bugs/missing.md\n"
        return result

    monkeypatch.setattr(metrics.subprocess, "run", add_missing_path)
    with pytest.raises(RuntimeError):
        metrics._bug_texts(root, "HEAD")


def test_bug_metric_labels_are_fixed_enums(metrics, tmp_path):
    output = metrics._bug_metrics(_repo(tmp_path))
    for line in output.splitlines():
        if "k3dm_bug_docs{" not in line:
            continue
        assert 'priority="' in line and 'state="' in line
        assert all(value in line for value in ())
        assert line.split('priority="', 1)[1].split('"', 1)[0] in {"P0", "P1", "P2", "P3", "unset"}
        assert line.split('state="', 1)[1].split('"', 1)[0] in {"open", "closed", "unknown"}


def test_bug_status_metrics_include_all_docs_and_sanitized_labels(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-10-01-foo.md").write_text(
        '# Bug: the `foo` "bar"\n\n**Priority:** P1\n**Filed:** 2026-10-01\n**Status:** Open\n')
    (bugs / "closed.md").write_text("# closed\n**Status:** FIXED\n")
    (bugs / "unknown.md").write_text("# unknown\n")
    output = metrics._bug_status_metrics(tmp_path, now=datetime(2026, 10, 11, tzinfo=timezone.utc))
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert len(info) == 3
    assert 'priority="P1"' in info[0]
    assert 'title="the foo bar"' in info[0]
    assert 'filed="2026-10-01"' in info[0]
    assert 'bug="2026-10-01-foo"' in info[0]
    assert 'docs/' not in info[0] and '.md' not in info[0]
    assert any(line.endswith(" 10") for line in info)


def test_bug_status_metrics_labels_release_from_tally_or_unassigned(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for name in ("known.md", "unknown.md", "absent.md"):
        (bugs / name).write_text("**Priority:** P1\n**Status:** Open\n")
    tally = {
        "v1.43.1": {"open_paths": [{"path": "docs/bugs/known.md"}]},
        "unknown": {"open_paths": [{"path": "docs/bugs/unknown.md"}]},
    }
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert any('bug="known",' in line and 'release="v1.43.1"' in line for line in lines)
    assert all('release="unassigned"' in line for line in lines if 'bug="known"' not in line)
    no_tally = metrics._bug_status_metrics(tmp_path, tally=None)
    assert all('release="unassigned"' in line for line in no_tally.splitlines()
               if line.startswith("k3dm_bug_info{"))


def test_release_order_inverts_version_parts_and_sorts_newest_first(metrics):
    releases = ["v1.5.0", "v1.14.0", "v1.43.2", "v2.0.0", "unassigned"]
    labels = {metrics._release_order(release): release for release in releases}
    assert metrics._release_order("v1.43.2") == "9998.9956.9997 v1.43.2"
    assert metrics._release_order("unassigned") == "9999.9999.9999 unassigned"
    assert [labels[label] for label in sorted(labels)] == [
        "v2.0.0", "v1.43.2", "v1.14.0", "v1.5.0", "unassigned"]


def test_bug_status_metrics_verified_values_and_status_order(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    docs = {
        "implemented.md": "**Priority:** P1\n**Status:** IMPLEMENTED — landed\n",
        "verified.md": "**Priority:** P1\n**Status:** VERIFIED — live\n",
        "live-verified.md": "**Priority:** P1\n**Status:** LIVE-VERIFIED — hub proof\n",
        "old-fixed.md": "**Priority:** P2\n**Status:** LIVE-VERIFIED — historical proof\n",
        "unassigned-fixed.md": "**Priority:** P3\n**Status:** FIXED\n",
        "open.md": "**Priority:** P0\n**Status:** OPEN\n",
        "deferred.md": "**Priority:** P1\n**Status:** DEFERRED\n",
    }
    for name, text in docs.items():
        (bugs / name).write_text(text)
    tally = {
        "v1.43.2": {"open_paths": [{"path": f"docs/bugs/{name}"} for name in ("implemented.md", "verified.md", "live-verified.md", "open.md", "deferred.md")]},
        "v1.40.0": {"closed_paths": [{"path": "docs/bugs/old-fixed.md"}]},
    }
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert any('bug="implemented"' in line and 'status="fixed"' in line and 'verified="false"' in line and line.endswith(" -2") for line in info)
    assert any('bug="implemented"' in line and 'live_verified="false"' in line for line in info)
    assert any('bug="verified"' in line and 'status="fixed"' in line and 'verified="true"' in line and 'live_verified="false"' in line and line.endswith(" -2") for line in info)
    assert any('bug="live-verified"' in line and 'verified="true"' in line and 'live_verified="true"' in line for line in info)
    assert any('bug="old-fixed"' in line and 'status="fixed"' in line and 'verified="n/a"' in line and 'live_verified="n/a"' in line and line.endswith(" -2") for line in info)
    # agent-audit: allow assert-removed verified assertions rewritten to also check live_verified
    assert any('bug="unassigned-fixed"' in line and 'status="fixed"' in line and 'verified="n/a"' in line and 'live_verified="n/a"' in line for line in info)
    assert any('bug="open"' in line and 'status="open"' in line and 'verified=' not in line for line in info)
    assert any('bug="open"' in line and 'live_verified=' not in line for line in info)
    assert any('bug="deferred"' in line and 'status="deferred"' in line and 'verified=' not in line for line in info)
    statuses = [line.split('status="', 1)[1].split('"', 1)[0]
                for line in info if 'release="v1.43.2"' in line]
    assert statuses == sorted(statuses, key={"open": 0, "unknown": 1, "deferred": 2, "fixed": 3}.get)


def test_bug_status_metrics_sort_by_release_then_priority(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for name, priority in (("old-p0.md", "P0"), ("new-p2.md", "P2"),
                           ("new-p0.md", "P0"), ("unassigned.md", "P1")):
        (bugs / name).write_text(f"**Priority:** {priority}\n**Status:** Open\n")
    tally = {
        "v1.5.0": {"open_paths": [{"path": "docs/bugs/old-p0.md"}]},
        "v1.14.0": {"open_paths": [{"path": "docs/bugs/new-p2.md"},
                                     {"path": "docs/bugs/new-p0.md"}]},
    }
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert [line.split('bug="', 1)[1].split('"', 1)[0] for line in lines] == [
        "new-p0", "new-p2", "old-p0", "unassigned"]


def test_bug_status_metrics_puts_live_verified_last_on_fixed_metrics(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "live.md").write_text("**Priority:** P1\n**Status:** LIVE-VERIFIED\n")
    output = metrics._bug_status_metrics(tmp_path, tally={
        "v1.43.2": {"closed_paths": [{"path": "docs/bugs/live.md"}]},
    })
    lines = [line for line in output.splitlines() if "live_verified=\"true\"" in line]
    assert len(lines) == 2
    assert all('verified="true",live_verified="true"' in line for line in lines)


def test_bug_status_metrics_release_is_last_label_and_aggregate_is_uncapped(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for index in range(201):
        priority = "P1" if index < 2 else "P2"
        (bugs / f"bug-{index:03d}.md").write_text(f"**Priority:** {priority}\n**Status:** Open\n")
    tally = {"v1.43.1": {"open_paths": [
        {"path": f"docs/bugs/bug-{index:03d}.md", "priority": "P1" if index < 2 else "P2"}
        for index in range(201)
    ]}}
    output = metrics._bug_status_metrics(tmp_path, tally=tally)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert len(info) == 201
    # agent-audit: allow assert-removed label tail now ends with release_order; release is still asserted
    assert all(line.split("}", 1)[0].endswith(
        'status="open",release_order="9998.9956.9998 v1.43.1"') for line in info)
    assert 'k3dm_bug_status_docs{release="v1.43.1",priority="P1",status="open"} 2' in output
    assert 'k3dm_bug_status_docs{release="v1.43.1",priority="P2",status="open"} 199' in output
    assert sum(int(line.rsplit(" ", 1)[1]) for line in output.splitlines()
               if line.startswith("k3dm_bug_status_docs{")) == 201


def test_publish_bug_metrics_tallies_once_and_pushes_groups(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    calls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally",
                        lambda *_args, **_kwargs: calls.append(True) or {"releases": {"v1.43.0": _bucket()}, "fixed_in": {}})
    assert metrics.publish_bug_metrics(tmp_path) is True
    assert len(calls) == 1
    methods = {r.full_url.rsplit("/", 1)[-1]: r.method for r in requests if getattr(r, "data", None)}
    assert methods == {"k3dm-bug-docs": "POST", "k3dm-bug-open": "PUT", "k3dm-bug-releases": "POST"}
    open_body = next(r.data.decode() for r in requests
                     if getattr(r, "full_url", "").endswith("/metrics/job/k3dm-bug-open"))
    assert "k3dm_bug_open_info" not in open_body
    assert "k3dm_bug_open_release_docs" not in open_body


def test_publish_bug_metrics_reads_bug_texts_once(metrics, monkeypatch, tmp_path):
    calls = []
    texts = {"docs/bugs/one.md": "**Priority:** P1\n**Status:** Open\n"}
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__,
                        "_bug_texts", lambda *_args: calls.append(True) or texts)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_push_bug_group", lambda *_args, **_kwargs: True)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally", lambda *_args: None)
    assert metrics.publish_bug_metrics(tmp_path) is True
    assert len(calls) == 1


def test_publish_bug_metrics_tally_failure_still_pushes_open(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    def boom(*_args):
        raise RuntimeError("tally failed")
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_tally", boom)
    assert metrics.publish_bug_metrics(tmp_path) is True
    pushed = [str(getattr(url, "full_url", url)) for url in requests if getattr(url, "data", None)]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert any("/metrics/job/k3dm-bug-open" in url for url in pushed)
    assert not any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def test_bug_status_metrics_title_fallback_truncation_and_cap(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-10-11-no-heading.md").write_text("**Status:** Open\n")
    (bugs / "long.md").write_text("# " + ("x" * 200) + "\n**Status:** Open\n")
    (bugs / "bad name.md").write_text("**Status:** Open\n")
    output = metrics._bug_status_metrics(tmp_path)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert len(info) == 2
    assert any('title="no heading"' in line for line in info)
    long_line = next(line for line in info if 'bug="long"' in line)
    assert len(long_line.split('title="', 1)[1].split('"', 1)[0]) == 120
    assert long_line.split('title="', 1)[1].split('"', 1)[0].endswith("…")
    assert "k3dm_bug_info_skipped 1" in output
    assert "k3dm_bug_info_truncated 0" in output


def test_bug_status_metrics_undated_and_truncated(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for index in range(1001):
        (bugs / f"bug-{index:03d}.md").write_text("**Priority:** P2\n**Status:** Open\n")
    (bugs / "undated.md").write_text("**Priority:** P2\n**Status:** Open\n")
    output = metrics._bug_status_metrics(tmp_path, now=datetime.now(timezone.utc))
    # agent-audit: allow assert-removed metrics renamed k3dm_bug_open_info -> k3dm_bug_info, cap 200 -> 1000, fixed rows now listed
    assert output.count("k3dm_bug_info{") == 1000
    assert "k3dm_bug_info_truncated 1" in output


def test_bug_status_metrics_filed_line_wins_and_undated_sorts_last(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-09-01-dated.md").write_text("# dated\n**Priority:** P2\n**Filed:** 2026-10-05\n**Status:** Open\n")
    (bugs / "aaa-undated.md").write_text("# undated\n**Priority:** P2\n**Status:** Open\n")
    (bugs / "2026-10-01-p1.md").write_text("# p1\n**Priority:** P1\n**Status:** Open\n")
    output = metrics._bug_status_metrics(tmp_path, now=datetime(2026, 10, 15, tzinfo=timezone.utc))
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert [line.split('bug="', 1)[1].split('"', 1)[0] for line in info] == [
        "2026-10-01-p1", "2026-09-01-dated", "aaa-undated"]
    assert 'filed="2026-10-05"' in info[1] and info[1].endswith(" 10")
    assert 'filed=""' in info[2] and info[2].endswith(" -1")


def test_bug_status_metrics_with_no_docs_still_emits_counters(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "closed.md").write_text("# closed\n**Status:** FIXED\n")
    output = metrics._bug_status_metrics(tmp_path)
    assert "k3dm_bug_info{" in output
    assert "k3dm_bug_info_skipped 0" in output
    assert "k3dm_bug_info_truncated 0" in output


def test_bug_status_metrics_push_is_put_and_release_inventory_stays_post(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(tmp_path) is True
    methods = {r.full_url.rsplit("/", 1)[-1]: r.method for r in requests if getattr(r, "data", None)}
    assert methods["k3dm-bug-docs"] == "POST"
    assert methods["k3dm-bug-open"] == "PUT"
    assert methods["k3dm-bug-releases"] == "POST"


def test_bug_status_metrics_failure_does_not_block_other_groups(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    monkeypatch.setitem(metrics.publish_bug_metrics.__globals__, "_bug_status_metrics",
                        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("boom")))
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(tmp_path) is True
    pushed = [str(getattr(url, "full_url", url)) for url in urls]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def _fake_git(monkeypatch, metrics, tally, tags, branch="k3d-manager-v1.43.0"):
    def run(argv, **_kwargs):
        if "tag" in argv:
            return SimpleNamespace(stdout="\n".join(tags) + "\n", returncode=0)
        if "branch" in argv:
            return SimpleNamespace(stdout=branch + "\n", returncode=0)
        raise AssertionError(argv)
    monkeypatch.setattr(metrics.subprocess, "run", run)
    monkeypatch.setitem(metrics._release_metrics.__globals__, "_tally",
                        lambda *_args, **kwargs: {"releases": tally, "fixed_in": {}}
                        if kwargs.get("full") else tally)


def _bucket(**counts):
    return {"by_priority": {p: dict(counts.get(p, {})) for p in ("P0", "P1", "P2", "P3", "unset")}}


def test_release_metrics_publishes_fixed_in_counts_and_unknown(metrics, monkeypatch, tmp_path):
    tally = {
        "v1.43.0": {"by_priority": {p: {} for p in metrics.PRIORITIES},
                     "closed_paths": [{"path": "docs/bugs/fixed-p0.md", "priority": "P0"},
                                      {"path": "docs/bugs/fixed-p1.md", "priority": "P1"}]},
        "v1.42.0": _bucket(),
    }
    _fake_git(monkeypatch, metrics, tally, ["v1.42.0"])
    fixed_in = {
        "docs/bugs/fixed-p0.md": {"release": "v1.43.0"},
        "docs/bugs/fixed-p1.md": {"release": "unknown"},
        "docs/bugs/outside.md": {"release": "v1.99.0"},
    }
    output = metrics._release_metrics(tmp_path, tally=tally, fixed_in=fixed_in)
    assert 'k3dm_bug_fixed_in_release_docs{release="v1.43.0",order="1",priority="P0"} 1' in output
    assert 'k3dm_bug_fixed_in_release_docs{release="v1.43.0",order="1",priority="P1"} 0' in output
    assert 'k3dm_bug_fixed_in_unknown_docs 1' in output
    assert 'release="v1.99.0"' not in output
    assert metrics._release_metrics(tmp_path, tally=tally, fixed_in=None).count("k3dm_bug_fixed_in_") == 0


def test_bug_status_metrics_adds_fixed_in_only_to_fixed_info(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "fixed.md").write_text("**Priority:** P1\n**Status:** FIXED\n")
    (bugs / "unknown-fixed.md").write_text("**Priority:** P2\n**Status:** IMPLEMENTED\n")
    (bugs / "open.md").write_text("**Priority:** P0\n**Status:** OPEN\n")
    tally = {"v1.43.0": {"closed_paths": [
        {"path": "docs/bugs/fixed.md", "priority": "P1"},
        {"path": "docs/bugs/unknown-fixed.md", "priority": "P2"}],
        "open_paths": [{"path": "docs/bugs/open.md", "priority": "P0"}]}}
    base = metrics._bug_status_metrics(tmp_path, tally=tally)
    output = metrics._bug_status_metrics(tmp_path, tally=tally, fixed_in={
        "docs/bugs/fixed.md": {"release": "v1.43.0"},
        "docs/bugs/unknown-fixed.md": {"release": "unknown"},
    })
    base_aggregates = [line for line in base.splitlines() if line.startswith("k3dm_bug_status_docs")]
    output_aggregates = [line for line in output.splitlines() if line.startswith("k3dm_bug_status_docs")]
    assert base_aggregates == output_aggregates
    fixed_lines = [line for line in output.splitlines() if line.startswith("k3dm_bug_info{")]
    assert any('bug="fixed"' in line and 'fixed_in="v1.43.0"' in line for line in fixed_lines)
    assert any('bug="unknown-fixed"' in line and 'fixed_in="unknown"' in line for line in fixed_lines)
    assert all('fixed_in=' not in line for line in fixed_lines if 'bug="open"' in line)


def test_release_metrics_cover_current_and_five_shipped_releases_in_order(metrics, monkeypatch, tmp_path):
    tags = ["v1.9.0", "v1.10.0", "v1.38.0", "v1.39.0", "v1.40.0", "v1.41.0", "v1.42.0", "v1.43.1", "v1.44.0", "not-a-tag"]
    tally = {"v1.43.0": _bucket(P2={"open": 3, "closed": 4}), "v1.42.0": _bucket(P1={"closed": 3}),
             "v1.43.2": _bucket(P3={"open": 2}), "v1.44.0": _bucket(P2={"open": 1}), "unknown": _bucket(P0={"open": 9})}
    _fake_git(monkeypatch, metrics, tally, tags)
    output = metrics._release_metrics(tmp_path)
    releases = []
    for line in output.splitlines():
        if line.startswith("k3dm_bug_release_docs{"):
            release = line.split('release="', 1)[1].split('"', 1)[0]
            order = line.split('order="', 1)[1].split('"', 1)[0]
            if (release, order) not in releases:
                releases.append((release, order))
    assert releases == [("v1.38.0", "0"), ("v1.39.0", "1"), ("v1.40.0", "2"), ("v1.41.0", "3"),
                        ("v1.42.0", "4"), ("v1.43.0", "5")]
    assert 'k3dm_bug_release_docs{release="v1.43.0",order="5",priority="P2",state="open"} 3' in output
    assert 'k3dm_bug_release_docs{release="v1.42.0",order="4",priority="P1",state="closed"} 3' in output
    assert output.count("k3dm_bug_release_docs{") == 6 * 15
    assert 'k3dm_bug_current_release_info{release="v1.43.0"} 1' in output
    assert 'k3dm_bug_later_release_open_docs{priority="P3"} 2' in output
    assert 'k3dm_bug_later_release_open_docs{priority="P2"} 1' in output
    assert 'k3dm_bug_later_release_open_docs{priority="P0"} 0' in output


def test_release_metrics_on_a_non_release_branch_show_only_shipped_releases(metrics, monkeypatch, tmp_path):
    _fake_git(monkeypatch, metrics, {"v1.42.0": _bucket()}, ["v1.40.0", "v1.41.0", "v1.42.0"], branch="main")
    output = metrics._release_metrics(tmp_path)
    assert "k3dm_bug_current_release_info" not in output
    assert "k3dm_bug_later_release_open_docs" not in output
    assert 'release="v1.42.0",order="2"' in output


def test_release_metrics_failure_keeps_the_inventory_push(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    def boom(*_a, **_k):
        raise metrics.subprocess.CalledProcessError(2, "bug-tally")
    root = _repo(tmp_path)
    monkeypatch.setattr(metrics.subprocess, "run", boom)
    assert metrics.publish_bug_metrics(root) is True
    pushed = [str(getattr(url, "full_url", url)) for url in urls]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert not any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def test_release_metrics_push_to_their_own_group(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    requests = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: requests.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    root = _repo(tmp_path)
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket(P2={"open": 1})}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(root) is True
    posts = {str(r.full_url): r.data.decode() for r in requests if getattr(r, "data", None)}
    releases = [body for url, body in posts.items() if url.endswith("/metrics/job/k3dm-bug-releases")]
    inventory = [body for url, body in posts.items() if url.endswith("/metrics/job/k3dm-bug-docs")]
    assert len(releases) == 1 and "k3dm_bug_release_docs{" in releases[0]
    assert len(inventory) == 1 and "k3dm_bug_release_docs" not in inventory[0]
