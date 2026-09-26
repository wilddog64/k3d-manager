#!/usr/bin/env python3
"""Offline tests for the docs vector store: extraction, hashing, escaping, failure modes.

Everything here runs without a cluster, a credential or a network call. The embeddings HTTP
call is the only stubbed seam; the extraction, hashing and SQL-building code under test is
the real code, because that is where this feature's defects live.
"""
import io
import json
import sys
import urllib.error
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))

from hermes import prior_art as pa  # noqa: E402


BUG_DOC = """# Bugfix: the widget refused to start

**Branch:** `k3d-manager-v1.0.0`
**Scope:** one thing, and the sentence
wraps onto a second line.

---

## Problem

The widget returns 403 where a 404 was expected, so the operator reads it as
a missing path.

```bash
kubectl get widget   # this transcript must not be embedded
## Not a real heading, it is inside a fence
```

## Fix

Grant the prefix.
"""


class TestExtraction:
    def test_title_is_the_h1(self):
        title, _ = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert title == "Bugfix: the widget refused to start"

    def test_lead_is_the_problem_prose_not_the_metadata(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert "The widget returns 403" in text
        assert "**Branch:**" not in text
        assert "k3d-manager-v1.0.0" not in text

    def test_metadata_continuation_line_is_not_lead_prose(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert "wraps onto a second line" not in text

    def test_horizontal_rule_is_not_lead_prose(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert "---" not in text

    def test_fenced_transcript_is_excluded(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert "kubectl get widget" not in text

    def test_a_heading_inside_a_fence_is_not_a_heading(self):
        """Fence tracking is load-bearing: a ## line in a transcript must not be embedded."""
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert "Not a real heading" not in text

    def test_h2_headings_are_embedded(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert "Problem" in text and "Fix" in text

    def test_title_falls_back_to_the_filename(self):
        title, text = pa.doc_embed_text("docs/bugs/no-heading-here.md", "just prose\n")
        assert title == "no heading here"
        assert text.startswith("no heading here")

    def test_extraction_is_a_small_fraction_of_the_file(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert len(text) < len(BUG_DOC)

    def test_lead_is_capped(self):
        raw = "# t\n\n" + ("word " * 500) + "\n"
        _, text = pa.doc_embed_text("docs/bugs/x.md", raw)
        assert len(text) <= len("t\n") + pa.LEAD_MAX_CHARS + 1


class TestHashing:
    def test_hash_is_stable(self):
        _, text = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        assert pa.content_hash(text) == pa.content_hash(text)

    def test_hash_changes_when_the_embedded_text_changes(self):
        _, a = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        _, b = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC.replace("403", "401"))
        assert pa.content_hash(a) != pa.content_hash(b)

    def test_body_only_edit_does_not_change_the_hash(self):
        """A transcript edit cannot change the vector, so it must not trigger a re-embed."""
        edited = BUG_DOC.replace("kubectl get widget", "kubectl get widget -o yaml")
        _, a = pa.doc_embed_text("docs/bugs/x.md", BUG_DOC)
        _, b = pa.doc_embed_text("docs/bugs/x.md", edited)
        assert pa.content_hash(a) == pa.content_hash(b)


class TestEscaping:
    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("a\tb", "a\\tb"),
            ("a\nb", "a\\nb"),
            ("a\rb", "a\\rb"),
            ("a\\b", "a\\\\b"),
        ],
    )
    def test_copy_escape(self, raw, expected):
        assert pa.copy_escape(raw) == expected

    def test_backslash_is_escaped_before_the_others(self):
        """Escaping \\ last would turn a literal \\t into a tab on load."""
        assert pa.copy_escape("a\\tb") == "a\\\\tb"

    def test_vector_literal_is_bracketed_floats(self):
        assert pa.vector_literal([1, 0.5]) == "[1.0,0.5]"


class TestPsqlInvocation:
    def test_password_is_never_in_argv(self):
        argv = pa._psql_argv()
        joined = " ".join(argv)
        assert "$POSTGRES_USER" in joined
        assert "PGPASSWORD" not in joined
        assert "--password" not in joined

    def test_reads_sql_from_stdin(self):
        argv = pa._psql_argv()
        assert "-i" in argv
        assert argv[-1].endswith("-f -")

    def test_on_error_stop_is_set(self):
        assert "ON_ERROR_STOP=1" in pa._psql_argv()[-1]


class TestFailureModes:
    def test_missing_credential_raises_embeddings_unavailable(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "")
        monkeypatch.setattr(pa, "KEYCHAIN_ITEMS", ())
        with pytest.raises(pa.EmbeddingsUnavailable):
            pa.api_key()

    def test_every_failure_is_catchable_as_retrieval_unavailable(self):
        assert issubclass(pa.EmbeddingsUnavailable, pa.RetrievalUnavailable)
        assert issubclass(pa.StoreUnavailable, pa.RetrievalUnavailable)

    def test_search_of_empty_text_makes_no_call(self, monkeypatch):
        def explode(*_a, **_k):
            raise AssertionError("must not embed an empty query")

        monkeypatch.setattr(pa, "embed_batch", explode)
        assert pa.search("   ") == []

    def test_wrong_dimension_is_rejected(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        _stub_urlopen(monkeypatch, {"embeddings": [{"values": [0.0] * 5}]})
        with pytest.raises(pa.EmbeddingsUnavailable, match="dimension 5"):
            pa.embed_batch(["one"])

    def test_vector_count_mismatch_is_rejected(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        _stub_urlopen(monkeypatch, {"embeddings": [{"values": [0.0] * pa.EMBED_DIM}]})
        with pytest.raises(pa.EmbeddingsUnavailable, match="1 vectors for 2 inputs"):
            pa.embed_batch(["one", "two"])

    def test_oversized_batch_is_refused_before_the_call(self, monkeypatch):
        def explode(*_a, **_k):
            raise AssertionError("must not call the API")

        monkeypatch.setattr(pa.urllib.request, "urlopen", explode)
        with pytest.raises(ValueError):
            pa.embed_batch(["x"] * (pa.EMBED_BATCH + 1))

    def test_http_403_is_not_retried(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        calls = []

        def raise_403(*_a, **_k):
            calls.append(1)
            raise urllib.error.HTTPError("u", 403, "Forbidden", {}, None)

        monkeypatch.setattr(pa.urllib.request, "urlopen", raise_403)
        with pytest.raises(pa.EmbeddingsUnavailable, match="403"):
            pa.embed_batch(["one"])
        assert len(calls) == 1

    def test_the_key_is_sent_as_a_header_not_a_query_parameter(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        request = pa._embed_request(["one"], "RETRIEVAL_DOCUMENT", "unused-test-value")
        assert "unused-test-value" not in request.full_url
        assert request.get_header("X-goog-api-key") == "unused-test-value"


class TestSearchSql:
    def test_limit_is_clamped_and_never_interpolated_raw(self, monkeypatch):
        monkeypatch.setattr(pa, "embed_batch", lambda *_a, **_k: [[0.25] * pa.EMBED_DIM])
        captured = {}

        def fake_run_sql(sql, **_k):
            captured["sql"] = sql
            return "[]"

        monkeypatch.setattr(pa, "run_sql", fake_run_sql)
        pa.search("anything", k=10_000)
        assert "LIMIT 50" in captured["sql"]

    def test_scores_and_paths_are_returned_best_first(self, monkeypatch):
        monkeypatch.setattr(pa, "embed_batch", lambda *_a, **_k: [[0.25] * pa.EMBED_DIM])
        monkeypatch.setattr(
            pa, "run_sql",
            lambda *_a, **_k: json.dumps(
                [{"score": 0.9, "path": "docs/bugs/a.md", "title": "A"},
                 {"score": 0.4, "path": "docs/bugs/b.md", "title": "B"}]
            ),
        )
        assert pa.search("q", k=2) == [
            (0.9, "docs/bugs/a.md", "A"),
            (0.4, "docs/bugs/b.md", "B"),
        ]


def _stub_urlopen(monkeypatch, payload):
    class _Resp:
        def __enter__(self):
            return self

        def __exit__(self, *_a):
            return False

        def read(self):
            return json.dumps(payload).encode()

    monkeypatch.setattr(pa.urllib.request, "urlopen", lambda *_a, **_k: _Resp())
