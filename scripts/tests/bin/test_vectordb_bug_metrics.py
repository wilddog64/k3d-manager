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
