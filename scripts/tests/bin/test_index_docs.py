#!/usr/bin/env python3
"""Offline tests for the indexer's write strategy.

The indexer used to embed the whole corpus into memory and write once at the end, so a failure
on the last batch discarded every batch already paid for — 1,700 embedding calls for nothing.
These tests pin the replacement: one committed transaction per batch, pruning separated out, and
a failure that reports how much survived. None of them touch a cluster or the embeddings API.
"""
import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from hermes import prior_art as pa  # noqa: E402
from hermes.embed_cache import EmbedCache, cache_key  # noqa: E402


def _load_indexer():
    spec = importlib.util.spec_from_file_location(
        "index_docs", REPO_ROOT / "scripts" / "index-docs.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ix = _load_indexer()


@pytest.fixture(autouse=True)
def isolated_embedding_cache(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_EMBED_CACHE", str(tmp_path / "cache.sqlite"))


def _doc(name):
    return (f"docs/bugs/{name}.md", name.title(), f"text for {name}", f"hash-{name}")


def _vectors(count):
    return [[0.5] * pa.EMBED_DIM for _ in range(count)]


class TestScriptShape:
    def test_each_upsert_is_its_own_transaction(self):
        sql = ix._upsert_script([("docs/bugs/a.md", "A", "h", [0.1])])
        assert sql.startswith("BEGIN;")
        assert "COMMIT;" in sql
        assert sql.count("BEGIN;") == 1

    def test_the_upsert_script_never_deletes(self):
        sql = ix._upsert_script([("docs/bugs/a.md", "A", "h", [0.1])])
        assert "DELETE" not in sql.upper()

    def test_the_prune_script_is_separate_and_reports_counts(self):
        sql = ix._prune_script(["docs/bugs/a.md"])
        assert "DELETE FROM" in sql
        assert "'pruned=' ||" in sql
        assert "'indexed=' ||" in sql
        assert "staging" not in sql


class TestPerBatchCommit:
    def test_one_write_per_batch(self, monkeypatch):
        monkeypatch.setattr(ix, "EMBED_BATCH", 2)
        docs = [_doc(n) for n in ("one", "two", "three", "four", "five")]
        writes = []
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})
        monkeypatch.setattr(ix, "embed_batch",
                            lambda texts, task_type=None: _vectors(len(texts)))
        monkeypatch.setattr(ix, "run_sql", lambda sql: writes.append(sql) or "indexed=5")
        monkeypatch.setattr(ix.subprocess, "run", lambda *_a, **_k: None)

        assert ix.main([]) == 0
        upserts = [sql for sql in writes if "staging" in sql]
        prunes = [sql for sql in writes if "DELETE FROM" in sql]
        assert len(upserts) == 3
        assert len(prunes) == 1
        assert writes[-1] is prunes[0]

    def test_a_late_failure_keeps_the_earlier_batches(self, monkeypatch, capsys):
        monkeypatch.setattr(ix, "EMBED_BATCH", 2)
        docs = [_doc(n) for n in ("one", "two", "three", "four")]
        committed = []
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})
        monkeypatch.setattr(ix, "embed_batch",
                            lambda texts, task_type=None: _vectors(len(texts)))

        def flaky(sql):
            if len(committed) == 1:
                raise pa.StoreUnavailable("connection reset")
            committed.append(sql)
            return "indexed=2"

        monkeypatch.setattr(ix, "run_sql", flaky)

        assert ix.main([]) == 1
        assert len(committed) == 1
        stderr = capsys.readouterr().err
        assert "2 of 4 documents were committed" in stderr
        assert "re-running resumes" in stderr

    def test_a_spent_daily_quota_says_paused_not_unavailable(self, monkeypatch, capsys):
        """A daily cap is arithmetic, not a fault: the wording must not read as breakage."""
        monkeypatch.setattr(ix, "EMBED_BATCH", 2)
        docs = [_doc(n) for n in ("one", "two", "three", "four")]
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})
        monkeypatch.setattr(ix, "run_sql", lambda sql: "indexed=2")

        calls = []

        def spent(texts, task_type=None):
            calls.append(texts)
            if len(calls) == 2:
                raise pa.RetrievalUnavailable(
                    "embeddings API returned HTTP 429 "
                    "(quota EmbedContentRequestsPerDayPerProjectPerModel-FreeTier)")
            return _vectors(len(texts))

        monkeypatch.setattr(ix, "embed_batch", spent)

        assert ix.main([]) == 1
        stderr = capsys.readouterr().err
        assert "index-docs: paused" in stderr
        assert "unavailable" not in stderr
        assert "daily embeddings quota is spent" in stderr
        assert "2 of 4 documents were committed" in stderr

    def test_a_failed_embed_call_commits_nothing_for_that_batch(self, monkeypatch):
        monkeypatch.setattr(ix, "EMBED_BATCH", 2)
        docs = [_doc(n) for n in ("one", "two")]
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})

        def refuse(*_a, **_k):
            raise pa.EmbeddingsUnavailable("quota exhausted")

        def explode(_sql):
            raise AssertionError("must not write when the embed call failed")

        monkeypatch.setattr(ix, "embed_batch", refuse)
        monkeypatch.setattr(ix, "run_sql", explode)
        assert ix.main([]) == 1

    def test_an_unchanged_corpus_makes_no_embedding_call(self, monkeypatch):
        docs = [_doc("one")]
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {docs[0][0]: docs[0][3]})

        def explode(*_a, **_k):
            raise AssertionError("must not embed an unchanged document")

        monkeypatch.setattr(ix, "embed_batch", explode)
        monkeypatch.setattr(ix, "run_sql", lambda _sql: "pruned=0 indexed=1")
        monkeypatch.setattr(ix.subprocess, "run", lambda *_a, **_k: None)
        assert ix.main([]) == 0

    def test_a_prune_failure_says_the_documents_landed(self, monkeypatch, capsys):
        docs = [_doc("one")]
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})
        monkeypatch.setattr(ix, "embed_batch",
                            lambda texts, task_type=None: _vectors(len(texts)))

        def fail_on_prune(sql):
            if "DELETE FROM" in sql:
                raise pa.StoreUnavailable("deadlock")
            return ""

        monkeypatch.setattr(ix, "run_sql", fail_on_prune)
        assert ix.main([]) == 1
        assert "only the prune failed" in capsys.readouterr().err


class TestDryRun:
    def test_dry_run_neither_embeds_nor_writes(self, monkeypatch):
        docs = [_doc("one")]
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})

        def explode(*_a, **_k):
            raise AssertionError("dry run must not embed or write")

        monkeypatch.setattr(ix, "embed_batch", explode)
        monkeypatch.setattr(ix, "run_sql", explode)
        assert ix.main(["--dry-run"]) == 0

    def test_dry_run_creates_no_cache_file(self, monkeypatch, tmp_path):
        docs = [_doc("one")]
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})
        assert ix.main(["--dry-run"]) == 0
        assert not (tmp_path / "cache.sqlite").exists()


class TestEmbeddingCache:
    def _configure(self, monkeypatch, docs, writes, embed):
        monkeypatch.setattr(ix, "iter_corpus", lambda _root: docs)
        monkeypatch.setattr(ix, "ensure_schema", lambda: None)
        monkeypatch.setattr(ix, "fetch_hashes", lambda: {})
        monkeypatch.setattr(ix, "embed_batch", embed)
        monkeypatch.setattr(ix, "run_sql", lambda sql: writes.append(sql) or "indexed=5")
        monkeypatch.setattr(ix.subprocess, "run", lambda *_a, **_k: None)

    def test_rebuild_after_store_loss_uses_cache_without_api_calls(self, monkeypatch, capsys):
        docs = [_doc(n) for n in ("one", "two", "three", "four", "five")]
        writes = []
        calls = []
        self._configure(monkeypatch, docs, writes,
                        lambda texts, task_type=None: calls.append(texts) or _vectors(len(texts)))
        assert ix.main([]) == 0
        first_writes = len(writes)

        monkeypatch.setattr(ix, "embed_batch", lambda *_a, **_k: pytest.fail("cache miss"))
        assert ix.main([]) == 0
        assert len(writes) == first_writes * 2
        assert "5 from cache, 0 embedded" in capsys.readouterr().out

    def test_partial_hit_embeds_only_misses_and_preserves_order(self, monkeypatch):
        docs = [_doc(n) for n in ("one", "two", "three", "four")]
        cache = EmbedCache()
        cache.put_many((cache_key(ix.EMBED_MODEL, ix.EMBED_DIM, "RETRIEVAL_DOCUMENT", docs[i][2]),
                        [[float(i + 1)] * pa.EMBED_DIM][0]) for i in (0, 2))
        calls = []
        writes = []

        def embed(texts, task_type=None):
            calls.append(texts)
            return [[float(10 + i)] * pa.EMBED_DIM for i in range(len(texts))]

        self._configure(monkeypatch, docs, writes, embed)
        assert ix.main([]) == 0
        assert calls == [[docs[1][2], docs[3][2]]]
        upsert = writes[0]
        paths = [line.split("\t", 1)[0] for line in upsert.splitlines() if line.startswith("docs/")]
        assert paths == [doc[0] for doc in docs]
        data_lines = [line for line in upsert.splitlines() if line.startswith("docs/")]
        assert data_lines[0].endswith("[1.0," + "1.0," * (pa.EMBED_DIM - 2) + "1.0]")
        assert data_lines[1].endswith("[10.0," + "10.0," * (pa.EMBED_DIM - 2) + "10.0]")
        assert data_lines[2].endswith("[3.0," + "3.0," * (pa.EMBED_DIM - 2) + "3.0]")
        assert data_lines[3].endswith("[11.0," + "11.0," * (pa.EMBED_DIM - 2) + "11.0]")

    def test_model_or_task_type_change_is_a_cache_miss(self):
        text = "same"
        assert cache_key("model-a", 768, "RETRIEVAL_DOCUMENT", text) != cache_key(
            "model-b", 768, "RETRIEVAL_DOCUMENT", text)
        assert cache_key("model-a", 768, "RETRIEVAL_DOCUMENT", text) != cache_key(
            "model-a", 768, "RETRIEVAL_QUERY", text)

    def test_unwritable_cache_does_not_fail_index(self, monkeypatch, tmp_path, capsys):
        blocker = tmp_path / "plain-file"
        blocker.write_text("x")
        monkeypatch.setenv("K3DM_EMBED_CACHE", str(blocker / "cache.sqlite"))
        docs = [_doc(n) for n in ("one", "two")]
        writes = []
        self._configure(monkeypatch, docs, writes,
                        lambda texts, task_type=None: _vectors(len(texts)))
        assert ix.main([]) == 0
        assert "embedding cache unavailable" in capsys.readouterr().err

    def test_quota_pause_keeps_embedded_vectors_in_cache(self, monkeypatch):
        monkeypatch.setattr(ix, "EMBED_BATCH", 2)
        docs = [_doc(n) for n in ("one", "two", "three", "four")]
        writes = []
        calls = []

        def embed(texts, task_type=None):
            calls.append(texts)
            if len(calls) == 2:
                raise pa.RetrievalUnavailable("perday quota")
            return _vectors(len(texts))

        self._configure(monkeypatch, docs, writes, embed)
        assert ix.main([]) == 1
        cached = EmbedCache()
        keys = [cache_key(ix.EMBED_MODEL, ix.EMBED_DIM, "RETRIEVAL_DOCUMENT", doc[2]) for doc in docs[:2]]
        assert len(cached.get_many(keys)) == 2

        monkeypatch.setattr(ix, "embed_batch",
                            lambda *_a, **_k: (_ for _ in ()).throw(pa.RetrievalUnavailable("perday quota")))
        writes.clear()
        assert ix.main([]) == 1
        assert writes and "docs/bugs/one.md" in writes[0]

    def test_newest_dated_docs_are_embedded_first_under_limit(self, monkeypatch):
        docs = [
            ("docs/plans/v1.0.0-x.md", "X", "x", "hx"),
            ("docs/bugs/2026-01-01-a.md", "A", "a", "ha"),
            ("docs/bugs/2026-10-01-b.md", "B", "b", "hb"),
        ]
        calls = []
        writes = []
        self._configure(monkeypatch, docs, writes,
                        lambda texts, task_type=None: calls.append(texts) or _vectors(len(texts)))
        assert ix.main(["--limit", "1"]) == 0
        assert calls == [["b"]]


if __name__ == "__main__":
    sys.exit(pytest.main([__file__]))
