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
        monkeypatch.setattr(pa, "vault_api_key", _vault_raises("no cluster"))
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
        _stub_urlopen(monkeypatch, {"embedding": {"values": [0.0] * 5}})
        with pytest.raises(pa.EmbeddingsUnavailable, match="dimension 5"):
            pa.embed_batch(["one"])

    def test_a_response_without_an_embedding_is_rejected(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        _stub_urlopen(monkeypatch, {})
        with pytest.raises(pa.EmbeddingsUnavailable, match="dimension 0"):
            pa.embed_batch(["one"])

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
        request = pa._embed_request("one", "RETRIEVAL_DOCUMENT", "unused-test-value")
        assert "unused-test-value" not in request.full_url
        assert request.get_header("X-goog-api-key") == "unused-test-value"

    def test_the_request_targets_embedcontent_and_pins_the_column_width(self):
        request = pa._embed_request("one", "RETRIEVAL_DOCUMENT", "unused-test-value")
        assert request.full_url.endswith(":embedContent")
        assert "batchEmbedContents" not in request.full_url
        payload = json.loads(request.data.decode("utf-8"))
        assert payload["outputDimensionality"] == pa.EMBED_DIM
        assert payload["content"]["parts"] == [{"text": "one"}]

    def test_every_text_gets_its_own_request_and_order_is_preserved(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        seen = []

        class _Resp:
            def __init__(self, payload):
                self._payload = payload

            def __enter__(self):
                return self

            def __exit__(self, *_a):
                return False

            def read(self):
                return json.dumps(self._payload).encode()

        def capture(request, **_k):
            seen.append(json.loads(request.data.decode("utf-8"))["content"]["parts"][0]["text"])
            index = float(len(seen))
            return _Resp({"embedding": {"values": [index] * pa.EMBED_DIM}})

        monkeypatch.setattr(pa.urllib.request, "urlopen", capture)
        monkeypatch.setattr(pa.time, "sleep", lambda *_a: None)
        vectors = pa.embed_batch(["alpha", "beta", "gamma"])
        assert seen == ["alpha", "beta", "gamma"]
        assert [vector[0] for vector in vectors] == [1.0, 2.0, 3.0]

    def test_a_429_is_retried_for_the_delay_the_server_asks_for(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        slept = []
        monkeypatch.setattr(pa.time, "sleep", lambda seconds: slept.append(seconds))
        attempts = []

        class _Resp:
            def __enter__(self):
                return self

            def __exit__(self, *_a):
                return False

            def read(self):
                return json.dumps({"embedding": {"values": [0.5] * pa.EMBED_DIM}}).encode()

        def throttle_once(_request, **_k):
            attempts.append(1)
            if len(attempts) == 1:
                body = json.dumps(
                    {"error": {"details": [{"@type": "RetryInfo", "retryDelay": "31s"}]}}
                ).encode()
                raise urllib.error.HTTPError(
                    "https://example.invalid", 429, "Too Many Requests",
                    {"Content-Type": "application/json"}, io.BytesIO(body),
                )
            return _Resp()

        monkeypatch.setattr(pa.urllib.request, "urlopen", throttle_once)
        vectors = pa.embed_batch(["one"])
        assert len(vectors) == 1
        assert 31.0 in slept

    def test_requests_are_paced_between_texts(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "unused-test-value")
        slept = []
        monkeypatch.setattr(pa.time, "sleep", lambda seconds: slept.append(seconds))
        monkeypatch.setattr(pa, "EMBED_MIN_INTERVAL", 0.6)

        class _Resp:
            def __enter__(self):
                return self

            def __exit__(self, *_a):
                return False

            def read(self):
                return json.dumps({"embedding": {"values": [0.5] * pa.EMBED_DIM}}).encode()

        monkeypatch.setattr(pa.urllib.request, "urlopen", lambda *_a, **_k: _Resp())
        pa.embed_batch(["alpha", "beta", "gamma"])
        assert slept == [0.6, 0.6]


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


def _vault_raises(message):
    def _raise():
        raise pa.EmbeddingsUnavailable(message)

    return _raise


class TestVaultFallback:
    """The third credential source: one copy in the hub Vault.

    These tests exist because the Vault path handles two secrets at once — the root token and
    the API key — and the whole point of its shape is that neither reaches an argv. An
    assertion on the argv is the only thing that keeps a later "simplify" from piping the token
    through a shell.
    """

    def test_the_root_token_is_not_in_the_exec_argv(self):
        argv = pa.vault_argv()
        assert "VAULT_TOKEN" not in " ".join(argv[:-3])
        assert "read -r VAULT_TOKEN" in argv[-3]

    def test_the_secret_path_is_a_positional_argument_not_interpolated(self):
        argv = pa.vault_argv()
        assert argv[-1] == pa.VAULT_SECRET_PATH
        assert pa.VAULT_SECRET_PATH not in argv[-3]
        assert '"$1"' in argv[-3]

    def test_the_exec_reads_the_token_from_stdin(self, monkeypatch):
        captured = {}

        class Proc:
            returncode = 0
            stdout = "the-key\n"
            stderr = ""

        monkeypatch.setattr(pa, "_vault_root_token", lambda: "root-token-test-value")
        monkeypatch.setattr(
            pa.subprocess, "run",
            lambda argv, **kw: captured.update(argv=argv, input=kw.get("input")) or Proc(),
        )
        assert pa.vault_api_key() == "the-key"
        assert captured["input"] == "root-token-test-value\n"
        assert "root-token-test-value" not in " ".join(captured["argv"])

    def test_a_path_with_shell_syntax_is_refused_before_any_call(self, monkeypatch):
        def explode(*_a, **_k):
            raise AssertionError("must not run kubectl for a rejected path")

        monkeypatch.setattr(pa.subprocess, "run", explode)
        monkeypatch.setattr(pa, "VAULT_SECRET_PATH", "embeddings/gemini; rm -rf /")
        with pytest.raises(pa.EmbeddingsUnavailable, match="not a plain KV path"):
            pa.vault_api_key()

    def test_an_empty_field_is_not_returned_as_a_credential(self, monkeypatch):
        class Proc:
            returncode = 0
            stdout = "\n"
            stderr = ""

        monkeypatch.setattr(pa, "_vault_root_token", lambda: "root-token-test-value")
        monkeypatch.setattr(pa.subprocess, "run", lambda *_a, **_k: Proc())
        with pytest.raises(pa.EmbeddingsUnavailable, match="has no api_key value"):
            pa.vault_api_key()

    def test_the_root_token_is_decoded_in_process(self, monkeypatch):
        class Proc:
            returncode = 0
            stdout = "cm9vdC10b2tlbi10ZXN0LXZhbHVl"
            stderr = ""

        captured = {}
        monkeypatch.setattr(
            pa.subprocess, "run",
            lambda argv, **kw: captured.update(argv=argv) or Proc(),
        )
        assert pa._vault_root_token() == "root-token-test-value"
        assert "base64" not in " ".join(captured["argv"])

    def test_vault_is_tried_only_after_env_and_keychain(self, monkeypatch):
        order = []
        monkeypatch.setenv(pa.KEY_ENV, "")
        monkeypatch.setattr(pa, "KEYCHAIN_ITEMS", ("k3dm-embeddings-api-key",))

        class Missing:
            returncode = 44
            stdout = ""
            stderr = "not found"

        def keychain(*_a, **_k):
            order.append("keychain")
            return Missing()

        def vault():
            order.append("vault")
            return "vault-supplied-value"

        monkeypatch.setattr(pa.subprocess, "run", keychain)
        monkeypatch.setattr(pa, "vault_api_key", vault)
        assert pa.api_key() == "vault-supplied-value"
        assert order == ["keychain", "vault"]

    def test_the_env_var_short_circuits_every_other_source(self, monkeypatch):
        def explode(*_a, **_k):
            raise AssertionError("must not consult the keychain or Vault")

        monkeypatch.setenv(pa.KEY_ENV, "env-supplied-value")
        monkeypatch.setattr(pa.subprocess, "run", explode)
        monkeypatch.setattr(pa, "vault_api_key", explode)
        assert pa.api_key() == "env-supplied-value"

    def test_the_failure_message_names_all_three_sources(self, monkeypatch):
        monkeypatch.setenv(pa.KEY_ENV, "")
        monkeypatch.setattr(pa, "KEYCHAIN_ITEMS", ("k3dm-embeddings-api-key",))

        class Denied:
            returncode = 36
            stdout = ""
            stderr = ""

        monkeypatch.setattr(pa.subprocess, "run", lambda *_a, **_k: Denied())
        monkeypatch.setattr(pa, "vault_api_key", _vault_raises("cluster unreachable"))
        with pytest.raises(pa.EmbeddingsUnavailable) as caught:
            pa.api_key()
        message = str(caught.value)
        assert pa.KEY_ENV in message
        assert "errSecInteractionNotAllowed" in message
        assert "hub Vault: cluster unreachable" in message

    def test_the_rc36_hint_names_the_fix_not_a_second_item(self, monkeypatch):
        """rc 36 is an access-control problem on one item, not a missing second item.

        The remedy is widening that item's partition list. Telling the operator to create a
        duplicate k3dm-owned item instead puts the same key in two places on one machine,
        which doubles rotation and survives nothing extra, so the hint must not suggest it.
        """
        monkeypatch.setenv(pa.KEY_ENV, "")
        monkeypatch.setattr(pa, "KEYCHAIN_ITEMS", ("gemini-cli-api-key",))

        class Denied:
            returncode = 36
            stdout = ""
            stderr = ""

        monkeypatch.setattr(pa.subprocess, "run", lambda *_a, **_k: Denied())
        monkeypatch.setattr(pa, "vault_api_key", _vault_raises("cluster unreachable"))
        with pytest.raises(pa.EmbeddingsUnavailable) as caught:
            pa.api_key()
        message = str(caught.value)
        assert "set-generic-password-partition-list" in message
        assert "gemini-cli-api-key" in message
        assert "add-generic-password" not in message


class TestExecFailureDetail:
    """``kubectl exec`` appends its own last line, so the last line is never the real error.

    This was a live defect, not a hypothetical: a Vault read of an unwritten path reported
    ``command terminated with exit code 2`` and hid ``No value found at secret/data/...``.
    """

    class _Proc:
        def __init__(self, stderr="", stdout="", returncode=1):
            self.stderr = stderr
            self.stdout = stdout
            self.returncode = returncode

    def test_kubectls_own_trailer_is_not_the_reported_reason(self):
        proc = self._Proc(
            stderr="No value found at secret/data/embeddings/gemini\n"
                   "command terminated with exit code 2\n",
            returncode=2,
        )
        assert pa._exec_detail(proc) == "No value found at secret/data/embeddings/gemini"

    def test_the_most_specific_pod_line_wins_when_several_are_emitted(self):
        proc = self._Proc(
            stderr="psql:<stdin>:3: ERROR:  relation does not exist\n"
                   "psql:<stdin>:4: ERROR:  current transaction is aborted\n"
                   "command terminated with exit code 1\n",
        )
        assert "transaction is aborted" in pa._exec_detail(proc)

    def test_a_silent_failure_falls_back_to_the_exit_code(self):
        assert pa._exec_detail(self._Proc(returncode=7)) == "rc 7"

    def test_a_trailer_only_failure_still_reports_something_useful(self):
        proc = self._Proc(stderr="command terminated with exit code 2\n", returncode=2)
        assert pa._exec_detail(proc) == "rc 2"

    def test_the_store_error_reports_the_pod_message(self, monkeypatch):
        proc = self._Proc(
            stderr="psql:<stdin>:1: ERROR:  syntax error\n"
                   "command terminated with exit code 1\n",
        )
        monkeypatch.setattr(pa.subprocess, "run", lambda *_a, **_k: proc)
        with pytest.raises(pa.StoreUnavailable, match="syntax error"):
            pa.run_sql("SELECT 1;")
