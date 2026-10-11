import runpy
import sys
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
