import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[2] / "lib"))
from hermes.e2e_triage import classify, redact, service_for


CORPUS = Path(__file__).parents[1] / "fixtures" / "e2e-corpus" / "corpus.jsonl"


def entries():
    return [json.loads(line) for line in CORPUS.read_text().splitlines() if line]


@pytest.mark.parametrize("entry", entries(), ids=lambda entry: entry["id"])
def test_corpus_classification(entry):
    assert classify(entry) == (entry["expected_kind"], entry["expected_target"]), entry


def test_corpus_routing():
    for entry in entries():
        assert service_for(entry["expected_target"]) == entry["expected_service"], entry


def test_every_kind_is_covered():
    assert {entry["expected_kind"] for entry in entries()} == {
        "assertion", "contract-drift", "service-unreachable", "timeout", "auth"
    }


def test_redaction_entries():
    for entry in entries():
        if entry["id"].startswith("synthetic-redact-"):
            value = redact(entry["error"])
            assert "<redacted>" in value
            assert entry["error"] not in value


def test_corpus_is_well_formed():
    required = {
        "id", "source", "file", "status", "error", "expected_kind",
        "expected_target", "expected_service",
    }
    rows = entries()
    assert rows
    assert all(set(entry) == required for entry in rows)
    assert len({entry["id"] for entry in rows}) == len(rows)
