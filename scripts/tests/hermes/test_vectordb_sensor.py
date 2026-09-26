import importlib.machinery
import importlib.util
import json
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / "scripts" / "lib"
import sys
sys.path.insert(0, str(LIB))

from hermes.sensors import vectordb

loader = importlib.machinery.SourceFileLoader("k3dm_vectordb_status", str(ROOT / "bin" / "k3dm-vectordb-status"))
spec = importlib.util.spec_from_loader("k3dm_vectordb_status", loader)
status_probe = importlib.util.module_from_spec(spec)
loader.exec_module(status_probe)


def payload(**overrides):
    value = {"available": True, "external_secret_synced": True, "pod_ready": True,
             "rows": 10, "corpus_docs": 12, "last_indexed_epoch": 1_000_000.0}
    value.update(overrides)
    return value


def runner(value, code=0):
    return lambda *_args: (code, json.dumps(value) if value is not None else "")


def test_kubectl_json_argv_has_the_vectordb_contract():
    assert status_probe.kubectl_json_argv("pod", "vectordb-0", "ctx", "vectordb") == [
        "kubectl", "--context", "ctx", "-n", "vectordb", "get", "pod", "vectordb-0", "-o", "json"
    ]


def test_status_offline_is_end_to_end_and_has_every_key():
    result = subprocess.run([str(ROOT / "bin" / "k3dm-vectordb-status"), "--offline"],
                            cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode == 0
    assert set(json.loads(result.stdout)) == {
        "available", "external_secret_synced", "pod_ready", "rows", "corpus_docs",
        "last_indexed_epoch",
    }


def test_external_secret_failure_is_upstream_and_does_not_name_pod():
    result = vectordb(runner(payload(external_secret_synced=False, pod_ready=False)), {}, threshold=0)
    assert result["status"] == "degraded"
    assert "ExternalSecret vectordb-postgres" in result["evidence"]
    assert "vectordb-0" not in result["evidence"]


def test_pod_failure_is_reported_after_synced_external_secret():
    result = vectordb(runner(payload(pod_ready=False)), {}, threshold=0)
    assert result["status"] == "degraded"
    assert "vectordb-0" in result["evidence"]


@pytest.mark.parametrize("field", [
    "available", "external_secret_synced", "pod_ready", "rows", "corpus_docs",
    "last_indexed_epoch",
])
def test_each_null_source_is_unknown(field):
    result = vectordb(runner(payload(**{field: None})), {}, threshold=0)
    assert result["status"] == "unknown"


@pytest.mark.parametrize("raw", [None, "not-json"])
def test_malformed_or_empty_payload_is_unknown(raw):
    result = vectordb(runner(None if raw is None else raw), {})
    assert result["status"] == "unknown"


def test_stale_index_is_degraded_and_fresh_index_is_healthy():
    stale = vectordb(runner(payload(last_indexed_epoch=100.0)), {}, threshold=0,
                     max_index_age_seconds=100, now=201.0)
    fresh = vectordb(runner(payload(last_indexed_epoch=150.0)), {}, threshold=0,
                     max_index_age_seconds=100, now=201.0)
    assert stale["status"] == "degraded"
    assert "rows=10" in stale["evidence"]
    assert fresh["status"] == "healthy"


def test_debounce_holds_first_degraded_sample_and_reports_the_next_over_threshold():
    state = {}
    sample = runner(payload(available=False))
    first = vectordb(sample, state, threshold=2)
    second = vectordb(sample, state, threshold=2)
    third = vectordb(sample, state, threshold=2)
    assert first["status"] == "healthy"
    assert second["status"] == "healthy"
    assert third["status"] == "degraded"


def test_sensor_never_raises_for_every_health_payload():
    cases = [payload(external_secret_synced=False, pod_ready=False),
             payload(pod_ready=False), payload(available=False),
             payload(last_indexed_epoch=0.0), payload(last_indexed_epoch=None),
             payload(rows=None)]
    for value in cases:
        assert vectordb(runner(value), {}, threshold=0, now=1_000_000.0)["sensor"] == "vectordb"
