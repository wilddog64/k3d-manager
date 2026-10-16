import runpy
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


def test_bug_metric_labels_are_fixed_enums(metrics, tmp_path):
    output = metrics._bug_metrics(_repo(tmp_path))
    for line in output.splitlines():
        if "k3dm_bug_docs{" not in line:
            continue
        assert 'priority="' in line and 'state="' in line
        assert all(value in line for value in ())
        assert line.split('priority="', 1)[1].split('"', 1)[0] in {"P0", "P1", "P2", "P3", "unset"}
        assert line.split('state="', 1)[1].split('"', 1)[0] in {"open", "closed", "unknown"}


def test_open_bug_metrics_include_only_open_docs_and_sanitized_labels(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-10-01-foo.md").write_text(
        '# Bug: the `foo` "bar"\n\n**Priority:** P1\n**Filed:** 2026-10-01\n**Status:** Open\n')
    (bugs / "closed.md").write_text("# closed\n**Status:** FIXED\n")
    (bugs / "unknown.md").write_text("# unknown\n")
    output = metrics._open_bug_metrics(tmp_path, now=datetime(2026, 10, 11, tzinfo=timezone.utc))
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_open_info{")]
    assert len(info) == 1
    assert 'priority="P1"' in info[0]
    assert 'title="the foo bar"' in info[0]
    assert 'filed="2026-10-01"' in info[0]
    assert 'bug="2026-10-01-foo"' in info[0]
    assert 'docs/' not in info[0] and '.md' not in info[0]
    assert info[0].endswith(" 10")


def test_open_bug_metrics_title_fallback_truncation_and_cap(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-10-11-no-heading.md").write_text("**Status:** Open\n")
    (bugs / "long.md").write_text("# " + ("x" * 200) + "\n**Status:** Open\n")
    (bugs / "bad name.md").write_text("**Status:** Open\n")
    output = metrics._open_bug_metrics(tmp_path)
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_open_info{")]
    assert len(info) == 2
    assert any('title="no heading"' in line for line in info)
    long_line = next(line for line in info if 'bug="long"' in line)
    assert len(long_line.split('title="', 1)[1].split('"', 1)[0]) == 120
    assert long_line.split('title="', 1)[1].split('"', 1)[0].endswith("…")
    assert "k3dm_bug_open_info_skipped 1" in output
    assert "k3dm_bug_open_info_truncated 0" in output


def test_open_bug_metrics_undated_and_truncated(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    for index in range(201):
        (bugs / f"bug-{index:03d}.md").write_text("**Priority:** P2\n**Status:** Open\n")
    (bugs / "undated.md").write_text("**Priority:** P2\n**Status:** Open\n")
    output = metrics._open_bug_metrics(tmp_path, now=datetime.now(timezone.utc))
    assert output.count("k3dm_bug_open_info{") == 200
    assert "k3dm_bug_open_info_truncated 1" in output


def test_open_bug_metrics_filed_line_wins_and_undated_sorts_last(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "2026-09-01-dated.md").write_text("# dated\n**Priority:** P2\n**Filed:** 2026-10-05\n**Status:** Open\n")
    (bugs / "aaa-undated.md").write_text("# undated\n**Priority:** P2\n**Status:** Open\n")
    (bugs / "2026-10-01-p1.md").write_text("# p1\n**Priority:** P1\n**Status:** Open\n")
    output = metrics._open_bug_metrics(tmp_path, now=datetime(2026, 10, 15, tzinfo=timezone.utc))
    info = [line for line in output.splitlines() if line.startswith("k3dm_bug_open_info{")]
    assert [line.split('bug="', 1)[1].split('"', 1)[0] for line in info] == [
        "2026-10-01-p1", "2026-09-01-dated", "aaa-undated"]
    assert 'filed="2026-10-05"' in info[1] and info[1].endswith(" 10")
    assert 'filed=""' in info[2] and info[2].endswith(" -1")


def test_open_bug_metrics_with_no_open_docs_still_emits_counters(metrics, tmp_path):
    bugs = tmp_path / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "closed.md").write_text("# closed\n**Status:** FIXED\n")
    output = metrics._open_bug_metrics(tmp_path)
    assert "k3dm_bug_open_info{" not in output
    assert "k3dm_bug_open_info_skipped 0" in output
    assert "k3dm_bug_open_info_truncated 0" in output


def test_open_bug_metrics_push_is_put_and_release_inventory_stays_post(metrics, monkeypatch, tmp_path):
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


def test_open_bug_metrics_failure_does_not_block_other_groups(metrics, monkeypatch, tmp_path):
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
    urls = []
    monkeypatch.setattr(metrics.urllib.request, "urlopen", lambda request, **_kwargs: urls.append(request) or Response())
    monkeypatch.setattr(metrics, "PUSH_RETRIES", 1)
    monkeypatch.setattr(metrics, "_open_bug_metrics", lambda *_args: (_ for _ in ()).throw(RuntimeError("boom")))
    _fake_git(monkeypatch, metrics, {"v1.43.0": _bucket()}, ["v1.42.0"])
    assert metrics.publish_bug_metrics(tmp_path) is True
    pushed = [str(getattr(url, "full_url", url)) for url in urls]
    assert any("/metrics/job/k3dm-bug-docs" in url for url in pushed)
    assert any("/metrics/job/k3dm-bug-releases" in url for url in pushed)


def _fake_git(monkeypatch, metrics, tally, tags, branch="k3d-manager-v1.43.0"):
    import json as _json

    def run(argv, **_kwargs):
        if argv[1].endswith("bug-tally.py"):
            return SimpleNamespace(stdout=_json.dumps({"releases": tally}), returncode=0)
        if "tag" in argv:
            return SimpleNamespace(stdout="\n".join(tags) + "\n", returncode=0)
        if "branch" in argv:
            return SimpleNamespace(stdout=branch + "\n", returncode=0)
        raise AssertionError(argv)
    monkeypatch.setattr(metrics.subprocess, "run", run)


def _bucket(**counts):
    return {"by_priority": {p: dict(counts.get(p, {})) for p in ("P0", "P1", "P2", "P3", "unset")}}


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
