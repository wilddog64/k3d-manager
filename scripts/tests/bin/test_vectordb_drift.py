"""Offline contracts for VectorDB drift classification and age metrics."""

import json
import runpy
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture
def status_module(monkeypatch):
    monkeypatch.setenv("K3DM_DISPATCH_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    return runpy.run_path(ROOT / "bin/k3dm-vectordb-status")


@pytest.fixture
def metrics(monkeypatch):
    monkeypatch.setenv("K3DM_VECTORDB_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    return runpy.run_path(ROOT / "bin/k3dm-vectordb-metrics")


def _payload(drift):
    return {"available": True, "rows": 3, "corpus_docs": 3,
            "last_indexed_epoch": 900, "drift": drift}


def _parse_metrics(text):
    return {line.split(" ", 1)[0]: float(line.split(" ", 1)[1])
            for line in text.splitlines() if line and not line.startswith("#")}


def test_status_classifies_missing_stale_and_deleted(status_module):
    namespace = status_module["status"].__globals__
    namespace["iter_corpus"] = lambda *_: [
        ("a", "A", "text", "h1"), ("b", "B", "text", "h2"),
        ("c", "C", "text", "h3")]
    namespace["fetch_hashes"] = lambda: {"a": "h1", "b": "hX", "d": "h4"}
    namespace["_cluster_facts"] = lambda: (True, True)
    namespace["_store_facts"] = lambda: (True, 3, 900)
    result = status_module["status"]()
    assert result["drift"] == {"missing": ["c"], "stale": ["b"], "deleted": ["d"]}


def test_offsetting_missing_and_deleted_do_not_cancel(metrics, tmp_path):
    drift = {"missing": [f"m{i}" for i in range(3)], "stale": [],
             "deleted": [f"d{i}" for i in range(3)]}
    output = metrics["_metrics"](_payload(drift), now=1000, state_path=tmp_path / "state.json")
    parsed = _parse_metrics(output)
    assert parsed["k3dm_vectordb_drift_docs"] == 0
    assert parsed['k3dm_vectordb_drift_docs_by_kind{kind="missing"}'] == 3
    assert parsed['k3dm_vectordb_drift_docs_by_kind{kind="deleted"}'] == 3


def test_first_seen_age_resets_after_fix(metrics, tmp_path):
    path = tmp_path / "state.json"
    drift = {"missing": ["b"], "stale": [], "deleted": []}
    metrics["_metrics"](_payload(drift), now=1000, state_path=path)
    output = metrics["_metrics"](_payload(drift), now=5000, state_path=path)
    assert _parse_metrics(output)['k3dm_vectordb_oldest_drift_age_seconds{kind="missing"}'] == 4000
    output = metrics["_metrics"](_payload({"missing": [], "stale": [], "deleted": []}),
                                  now=6000, state_path=path)
    assert json.loads(path.read_text()) == {}
    assert _parse_metrics(output)['k3dm_vectordb_oldest_drift_age_seconds{kind="missing"}'] == 0


def test_kind_change_preserves_first_seen(metrics, tmp_path):
    path = tmp_path / "state.json"
    metrics["_metrics"](_payload({"missing": ["b"], "stale": [], "deleted": []}),
                        now=1000, state_path=path)
    output = metrics["_metrics"](_payload({"missing": [], "stale": ["b"], "deleted": []}),
                                  now=3000, state_path=path)
    assert _parse_metrics(output)['k3dm_vectordb_oldest_drift_age_seconds{kind="stale"}'] == 2000
    assert json.loads(path.read_text()) == {"b": 1000.0}


def test_unavailable_store_leaves_state_byte_identical_and_omits_drift_metrics(metrics, tmp_path):
    path = tmp_path / "state.json"
    original = b'{"b":1000}\n'
    path.write_bytes(original)
    output = metrics["_metrics"](_payload(None), now=5000, state_path=path)
    assert path.read_bytes() == original
    assert "k3dm_vectordb_drift_docs_by_kind" not in output


def test_state_contains_only_drift_paths_and_first_seen_epochs(metrics, tmp_path):
    path = tmp_path / "nested/state.json"
    drift = {"missing": ["docs/a.md"], "stale": ["docs/b.md"], "deleted": []}
    metrics["_metrics"](_payload(drift), now=1234, state_path=path)
    contents = path.read_text()
    state = json.loads(contents)
    assert state == {"docs/a.md": 1234.0, "docs/b.md": 1234.0}
    assert "hash" not in contents and "content" not in contents
    assert path.parent.stat().st_mode & 0o777 == 0o700
    output = metrics["_metrics"](_payload(drift), now=2000, state_path=path)
    drift_lines = [line for line in output.splitlines()
                   if "drift_docs_by_kind" in line or "oldest_drift_age_seconds" in line]
    assert all("path=" not in line and "docs/" not in line for line in drift_lines)
    assert all('{kind="' in line for line in drift_lines)

