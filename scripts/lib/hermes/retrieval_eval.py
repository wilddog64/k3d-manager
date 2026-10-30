"""Shared live retrieval evaluation and daily quality probe."""

import json
import os
from collections import defaultdict
from pathlib import Path

from hermes import prior_art

ROOT = Path(__file__).resolve().parents[3]
PAIR_FILE = ROOT / "scripts/tests/fixtures/doc-dedup/pairs.jsonl"
LIVE_RECALL_FLOOR = {"bugs": 0.81, "issues": 0.66, "plans": 0.80, "retro": 0.80}


def _pairs():
    return [json.loads(line) for line in PAIR_FILE.read_text().splitlines() if line.strip()]


def _evaluate(rank, pairs, by_path):
    """Return recall and hard-negative intrusion by directory."""
    counts = {"positive": defaultdict(int), "hard-negative": defaultdict(int)}
    found = {"positive": defaultdict(int), "hard-negative": defaultdict(int)}
    for item in pairs:
        kind, directory = item["kind"], item["directory"]
        counts[kind][directory] += 1
        found[kind][directory] += item["expected"] in rank(by_path[item["query"]][1], item["query"])

    def ratio(kind):
        return {directory: round(found[kind][directory] / total, 3)
                for directory, total in counts[kind].items()}

    return ratio("positive"), ratio("hard-negative")


def rank(text, path, credential=None):
    """Search six rows, drop the query document, and retain the top five."""
    results = [result for _score, result, _title in
               prior_art.search(text, k=6, credential=credential) if result != path]
    return set(results[:5])


def probe(repo_root=None, ref=None, search=None, iter_corpus=None, fetch_hashes=None,
          push_url=None, now=None, pairs=None):
    """Evaluate retrieval and currentness; dependencies can be replaced by offline tests."""
    import time
    import urllib.request

    root = Path(repo_root or ROOT)
    search = search or prior_art.search
    credential = prior_art.api_key()
    iter_corpus = iter_corpus or prior_art.iter_corpus
    fetch_hashes = fetch_hashes or prior_art.fetch_hashes
    corpus = iter_corpus(root, ref)
    corpus_hashes = {path: digest for path, _title, _text, digest in corpus}
    by_path = {path: (title, text) for path, title, text, _digest in corpus}
    indexed_hashes = fetch_hashes()
    stale_hits = 0
    deleted_hits = 0
    results_count = 0

    def current_rank(text, path):
        nonlocal stale_hits, deleted_hits, results_count
        returned = search(text, k=6, credential=credential)
        kept = []
        candidates = [(result_path, title) for _score, result_path, title in returned
                      if result_path != path][:5]
        results_count += len(candidates)
        for result_path, _title in candidates:
            if result_path not in corpus_hashes:
                deleted_hits += 1
                continue
            if indexed_hashes.get(result_path) != corpus_hashes[result_path]:
                stale_hits += 1
                continue
            kept.append(result_path)
        return set(kept)

    recall, intrusion = _evaluate(current_rank, _pairs() if pairs is None else pairs, by_path)
    completed = time.time() if now is None else now
    lines = []
    for directory, value in sorted(recall.items()):
        lines.append(f'k3dm_vectordb_retrieval_recall_at5{{directory="{directory}"}} {value}')
        lines.append(f'k3dm_vectordb_retrieval_recall_floor{{directory="{directory}"}} {LIVE_RECALL_FLOOR[directory]}')
    for directory, value in sorted(intrusion.items()):
        lines.append(f'k3dm_vectordb_retrieval_intrusion_at5{{directory="{directory}"}} {value}')
    lines.extend([
        f"k3dm_vectordb_retrieval_stale_hits {stale_hits}",
        f"k3dm_vectordb_retrieval_deleted_hits {deleted_hits}",
        f"k3dm_vectordb_retrieval_results {results_count}",
        f"k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds {completed}",
    ])
    base = (push_url or os.environ.get("K3DM_VECTORDB_PUSHGATEWAY_URL", "http://localhost:19094")).rstrip("/")
    request = urllib.request.Request(
        f"{base}/metrics/job/k3dm-vectordb-retrieval", data=("\n".join(lines) + "\n").encode(),
        method="POST", headers={"Content-Type": "text/plain; charset=utf-8"})
    urllib.request.urlopen(request, timeout=5).close()
    return {"recall": recall, "intrusion": intrusion, "stale_hits": stale_hits,
            "deleted_hits": deleted_hits, "results": results_count, "completed": completed}
