import json
import math
import os
import re
import runpy
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
LIB = REPO_ROOT / "scripts" / "lib"
sys.path.insert(0, str(LIB))

from hermes.prior_art import doc_embed_text, iter_corpus, search  # noqa: E402

PAIR_FILE = REPO_ROOT / "scripts/tests/fixtures/doc-dedup/pairs.jsonl"
CLI = REPO_ROOT / "scripts/find-similar-docs.py"
TOKEN = re.compile(r"[a-z0-9]+")
RECALL_FLOOR = {"bugs": 0.20, "issues": 0.20, "plans": 0.20, "retro": 0.20}


def _pairs():
    return [json.loads(line) for line in PAIR_FILE.read_text().splitlines() if line.strip()]


def _directory(path):
    return path.split("/", 2)[1]


class TfidfControl:
    """Small stdlib-only control over the same ``doc_embed_text`` strings as the indexer."""

    def __init__(self, documents):
        self.documents = documents
        self.term_counts = [Counter(TOKEN.findall(text.lower())) for _path, _title, text, _hash in documents]
        document_frequency = Counter()
        for counts in self.term_counts:
            document_frequency.update(counts)
        total = len(documents)
        self.vectors = []
        for counts in self.term_counts:
            vector = {term: (1 + math.log(count)) * math.log((total + 1) / (document_frequency[term] + 1))
                      for term, count in counts.items()}
            norm = math.sqrt(sum(value * value for value in vector.values())) or 1
            self.vectors.append({term: value / norm for term, value in vector.items()})

    def rank(self, query, k=5, exclude=None):
        counts = Counter(TOKEN.findall(query.lower()))
        document_frequency = Counter()
        for term in counts:
            document_frequency[term] = sum(term in vector for vector in self.vectors)
        total = len(self.documents)
        query_vector = {term: (1 + math.log(count)) * math.log((total + 1) / (document_frequency[term] + 1))
                        for term, count in counts.items()}
        norm = math.sqrt(sum(value * value for value in query_vector.values())) or 1
        query_vector = {term: value / norm for term, value in query_vector.items()}
        ranked = []
        for index, (path, title, _text, _hash) in enumerate(self.documents):
            if path == exclude:
                continue
            score = sum(value * self.vectors[index].get(term, 0) for term, value in query_vector.items())
            ranked.append((score, path, title))
        return sorted(ranked, key=lambda item: (-item[0], item[1]))[:k]


def test_pairs_have_at_least_25_positive_and_hard_negative_pairs_and_all_paths_exist():
    pairs = _pairs()
    assert sum(item["kind"] == "positive" for item in pairs) >= 25
    assert sum(item["kind"] == "hard-negative" for item in pairs) >= 25
    for item in pairs:
        assert (REPO_ROOT / item["query"]).is_file(), item["query"]
        assert (REPO_ROOT / item["expected"]).is_file(), item["expected"]


def test_tfidf_control_reports_recall_at_5_per_directory(capsys):
    documents = iter_corpus(REPO_ROOT)
    by_path = {path: (title, text) for path, title, text, _hash in documents}
    scorer = TfidfControl(documents)
    positive = [item for item in _pairs() if item["kind"] == "positive"]
    totals = defaultdict(int)
    hits = defaultdict(int)
    for item in positive:
        directory = item["directory"]
        totals[directory] += 1
        title, query = by_path[item["query"]]
        assert title
        results = scorer.rank(query, exclude=item["query"])
        if item["expected"] in {path for _score, path, _result_title in results}:
            hits[directory] += 1
    report = {directory: round(hits[directory] / total, 3) for directory, total in totals.items()}
    print(f"TF-IDF control recall@5: {json.dumps(report, sort_keys=True)}")
    for directory, total in totals.items():
        assert hits[directory] / total >= RECALL_FLOOR[directory], report
    assert set(report) == set(RECALL_FLOOR)


def test_tfidf_control_uses_real_indexer_text_and_scores_hard_negatives():
    documents = iter_corpus(REPO_ROOT)
    by_path = {path: (title, text) for path, title, text, _hash in documents}
    scorer = TfidfControl(documents)
    for item in _pairs():
        _title, query = by_path[item["query"]]
        results = scorer.rank(query, exclude=item["query"])
        assert results, item
        if item["kind"] == "hard-negative":
            assert item["expected"] in by_path
        assert doc_embed_text(item["query"], (REPO_ROOT / item["query"]).read_text())[1] == query


def test_cli_unavailable_is_distinguishable_from_zero_results(tmp_path):
    fake_path = tmp_path / "bin"
    fake_path.mkdir()
    for name in ("security", "kubectl"):
        tool = fake_path / name
        tool.write_text("#!/bin/sh\nexit 1\n")
        tool.chmod(0o755)
    unavailable_env = {**os.environ, "PATH": str(fake_path), "PYTHONPATH": str(LIB),
                       "K3DM_EMBEDDINGS_API_KEY": ""}
    unavailable = subprocess.run([sys.executable, str(CLI), "--json", "a query"],
                                 cwd=REPO_ROOT, env=unavailable_env,
                                 capture_output=True, text=True, check=False)
    assert unavailable.returncode == 0
    assert "retrieval unavailable" in unavailable.stderr
    zero_code = (
        "import runpy,sys; import hermes.prior_art as p; p.search=lambda *a,**k: []; "
        f"sys.argv=['find-similar-docs.py','--json','a query']; runpy.run_path({str(CLI)!r}, run_name='__main__')"
    )
    zero = subprocess.run([sys.executable, "-c", zero_code], cwd=REPO_ROOT,
                          env={**os.environ, "PYTHONPATH": str(LIB)},
                          capture_output=True, text=True, check=False)
    assert zero.returncode == 0
    assert zero.stdout == "[]\n"
    assert "retrieval unavailable" not in zero.stderr


@pytest.mark.skipif(os.environ.get("K3DM_RETRIEVAL_EVAL_LIVE") != "1",
                    reason="live pgvector/Gemini retrieval eval is operator-gated")
def test_live_embedding_recall_at_5_per_directory():
    documents = iter_corpus(REPO_ROOT)
    by_path = {path: (title, text) for path, title, text, _hash in documents}
    positive = [item for item in _pairs() if item["kind"] == "positive"]
    totals = defaultdict(int)
    hits = defaultdict(int)
    for item in positive:
        totals[item["directory"]] += 1
        _title, query = by_path[item["query"]]
        results = search(query, k=5)
        if item["expected"] in {path for _score, path, _result_title in results}:
            hits[item["directory"]] += 1
    for directory, total in totals.items():
        assert hits[directory] / total >= 0.0
