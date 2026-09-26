"""Shared plumbing for the docs vector store: corpus, embeddings, storage, search.

Stdlib only, by deliberate constraint. This repo carries no third-party Python runtime
dependencies, so Postgres is reached by piping SQL to ``psql`` *inside* the vectordb pod
instead of through a driver. That choice also keeps the database password where it was
generated: the argument vector carries a literal ``$POSTGRES_USER`` which the pod's own
shell expands, so no credential ever appears in argv, a log line, or this host's history.

The embeddings key is read at call time from the environment, then the login keychain, then
the hub Vault, and is never accepted as a command-line flag, so there is no sensitive flag to
register in ``_args_have_sensitive_flag``. On the Vault path the root token is delivered to the
pod on stdin, so neither credential ever appears in an argv.

Retrieval is advisory everywhere it is used. Every failure path raises
``RetrievalUnavailable`` (or a subclass) so a caller can degrade to its previous behaviour
with one ``except``; nothing here is allowed to crash a Hermes run.
"""
import base64
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]

CORPUS_GLOBS = ("docs/bugs/*.md", "docs/issues/*.md", "docs/plans/*.md", "docs/retro/*.md")

EMBED_MODEL = "text-embedding-004"
EMBED_DIM = 768
EMBED_BATCH = 100
API_ROOT = "https://generativelanguage.googleapis.com/v1beta"

KEY_ENV = "K3DM_EMBEDDINGS_API_KEY"
PRIMARY_KEYCHAIN_ITEM = "k3dm-embeddings-api-key"
# Exactly one of these should ever hold a value. This is a preference order, not a set of
# copies to keep in sync: a second keychain item shares the machine and the lock state of the
# first, so it adds rotation drift and survives nothing extra. The normal arrangement is the
# key in the Gemini CLI's own item with its access widened, and the k3dm-owned name left empty
# as an override for a host that has no Gemini CLI.
KEYCHAIN_ITEMS = (PRIMARY_KEYCHAIN_ITEM, "gemini-cli-api-key")

# Vault holds a second copy of the embeddings key, for the case the keychain cannot serve
# one: a locked login keychain, an item whose ACL trusts only the tool that created it, or a
# launchd context with no session to unlock. The two stores are independent failure domains
# because the Vault root token comes from a Kubernetes Secret read with kubectl, not from the
# keychain, so this fallback has no bootstrapping circularity.
VAULT_CONTEXT = os.environ.get("K3DM_VAULT_CONTEXT", "k3d-k3d-cluster")
VAULT_NAMESPACE = os.environ.get("K3DM_VAULT_NAMESPACE", "secrets")
VAULT_POD = os.environ.get("K3DM_VAULT_POD", "vault-0")
VAULT_ROOT_SECRET = "vault-root"
VAULT_MOUNT = "secret"
VAULT_SECRET_PATH = os.environ.get("K3DM_EMBEDDINGS_VAULT_PATH", "embeddings/gemini")
VAULT_SECRET_FIELD = "api_key"
_VAULT_PATH_RE = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._/-]{0,127}\Z")

KUBE_CONTEXT = os.environ.get("K3DM_VECTORDB_CONTEXT", "k3d-k3d-cluster")
NAMESPACE = os.environ.get("K3DM_VECTORDB_NAMESPACE", "vectordb")
WORKLOAD = os.environ.get("K3DM_VECTORDB_WORKLOAD", "statefulset/vectordb")

TABLE = "doc_embeddings"

SCHEMA_SQL = f"""
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE IF NOT EXISTS {TABLE} (
  path         text PRIMARY KEY,
  title        text NOT NULL,
  content_hash text NOT NULL,
  embedding    vector({EMBED_DIM}) NOT NULL,
  indexed_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS {TABLE}_embedding_idx
  ON {TABLE} USING hnsw (embedding vector_cosine_ops);
"""


class RetrievalUnavailable(Exception):
    """Retrieval cannot run. Callers fall back; they do not fail."""


class EmbeddingsUnavailable(RetrievalUnavailable):
    """No usable embeddings credential, or the embeddings API refused the request."""


class StoreUnavailable(RetrievalUnavailable):
    """The vector store could not be reached or returned an error."""


_FENCE = re.compile(r"^\s*(```|~~~)")
_H1 = re.compile(r"^#\s+(.+?)\s*$")
_H2 = re.compile(r"^##\s+(.+?)\s*$")
_SKIP_LINE = re.compile(r"^\s*(?:[-*+]\s|\d+\.\s|>|\||#{1,6}\s|!\[|<)")
# "**Branch:** `x`", "**Date:** ..." — front-matter-ish metadata these docs open with.
# It is not the prose that describes the problem, and embedding it adds no topical signal.
_META_LINE = re.compile(r"^\*\*[^*]{1,40}:\*\*")
_RULE_LINE = re.compile(r"^(?:-{3,}|\*{3,}|_{3,})$")
LEAD_MAX_CHARS = 600


def _exec_detail(proc):
    """Return the most specific line of a ``kubectl exec`` failure.

    ``kubectl exec`` appends its own ``command terminated with exit code N`` to the pod's stderr,
    which is the last line and says nothing. Taking the last line therefore hid the real error —
    Vault's ``No value found at secret/data/...`` became ``exit code 2``. Dropping kubectl's own
    lines first leaves the pod's message, which is what an operator needs.
    """
    lines = [
        line.strip()
        for line in ((proc.stderr or "") + "\n" + (proc.stdout or "")).splitlines()
        if line.strip() and not line.startswith("command terminated with exit code")
    ]
    return lines[-1] if lines else f"rc {proc.returncode}"


def _vault_root_token():
    """Return the hub Vault root token, read from the ``vault-root`` Kubernetes Secret.

    The token is base64-decoded in this process rather than by piping through ``base64`` in a
    shell, so the cleartext value never becomes a shell word and cannot reach history or a
    process listing.
    """
    argv = [
        "kubectl", "--context", VAULT_CONTEXT, "-n", VAULT_NAMESPACE,
        "get", "secret", VAULT_ROOT_SECRET,
        "-o", "jsonpath={.data.root_token}",
    ]
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        raise EmbeddingsUnavailable("kubectl timed out reading the Vault root token") from None
    except OSError as exc:
        raise EmbeddingsUnavailable(f"cannot run kubectl: {exc}") from None
    if proc.returncode != 0:
        detail = (proc.stderr or "").strip().splitlines()
        raise EmbeddingsUnavailable(
            f"cannot read {VAULT_ROOT_SECRET}: " + (detail[-1] if detail else f"rc {proc.returncode}")
        )
    encoded = proc.stdout.strip()
    if not encoded:
        raise EmbeddingsUnavailable(f"{VAULT_ROOT_SECRET} has no root_token field")
    try:
        return base64.b64decode(encoded).decode("utf-8").strip()
    except (ValueError, UnicodeDecodeError):
        raise EmbeddingsUnavailable(f"{VAULT_ROOT_SECRET} root_token is not valid base64") from None


def vault_argv():
    """Return the argv that reads the embeddings key inside the Vault pod.

    The token is delivered on stdin and read by the pod's own shell, so it never appears in
    this argv, in a Kubernetes audit record of the exec command, or in a log line. The secret
    path is passed as a positional argument rather than interpolated into the ``sh -c`` string,
    so an operator-supplied path cannot become shell syntax.
    """
    script = (
        "read -r VAULT_TOKEN; export VAULT_TOKEN; "
        f'exec vault kv get -mount={VAULT_MOUNT} -field={VAULT_SECRET_FIELD} "$1"'
    )
    return [
        "kubectl", "--context", VAULT_CONTEXT, "-n", VAULT_NAMESPACE,
        "exec", "-i", VAULT_POD, "--",
        "sh", "-c", script, "sh", VAULT_SECRET_PATH,
    ]


def vault_api_key():
    """Return the embeddings key stored at ``secret/embeddings/gemini`` in the hub Vault.

    Raises ``EmbeddingsUnavailable`` with the reason on every failure path, so a caller can
    report why this source was rejected alongside the others.
    """
    if not _VAULT_PATH_RE.match(VAULT_SECRET_PATH):
        raise EmbeddingsUnavailable(
            f"refusing Vault path {VAULT_SECRET_PATH!r}: not a plain KV path"
        )
    token = _vault_root_token()
    try:
        proc = subprocess.run(
            vault_argv(), input=token + "\n", capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        raise EmbeddingsUnavailable("Vault read timed out") from None
    except OSError as exc:
        raise EmbeddingsUnavailable(f"cannot run kubectl: {exc}") from None
    if proc.returncode != 0:
        raise EmbeddingsUnavailable(f"secret/{VAULT_SECRET_PATH}: {_exec_detail(proc)}")
    value = proc.stdout.strip()
    if not value:
        raise EmbeddingsUnavailable(
            f"secret/{VAULT_SECRET_PATH} has no {VAULT_SECRET_FIELD} value"
        )
    return value


def api_key():
    """Return the embeddings key from the environment, else the keychain.

    The value is returned to the caller and placed only in a request header. It is never
    logged, echoed, or passed as an argument to another process.

    A failure reports *why* each source was rejected, because "no credential" reads the same
    for an absent item, a denied read and an empty value, and those need different fixes. The
    common one here is rc 36 (``errSecInteractionNotAllowed``, -25308 truncated to a byte): the
    item exists and the keychain is unlocked, but the process cannot present the authorization
    prompt, so no value is returned.

    The hub Vault is tried last rather than first because it is the slowest and least available
    source — it needs a reachable cluster — while the keychain answers locally. It is tried at
    all because it survives the failures the keychain does not: a locked keychain, a
    single-binary ACL, or a launchd context with no login session.
    """
    value = os.environ.get(KEY_ENV, "").strip()
    if value:
        return value
    reasons = [f"${KEY_ENV} is unset or empty"]
    for item in KEYCHAIN_ITEMS:
        try:
            found = subprocess.run(
                ["security", "find-generic-password", "-s", item, "-w"],
                capture_output=True, text=True, timeout=30,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            reasons.append(f"{item}: cannot run security ({type(exc).__name__})")
            continue
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
        if found.returncode == 0:
            reasons.append(f"{item}: read succeeded but the value is empty")
            continue
        detail = (found.stderr or "").strip().splitlines()
        hint = ""
        if found.returncode == 36:
            hint = " (errSecInteractionNotAllowed — the item exists but its access control "
            hint += "will not serve this process; widen it with "
            hint += "'security set-generic-password-partition-list -S apple-tool:,apple: "
            hint += f"-s {item}', or export ${KEY_ENV})"
        reasons.append(
            f"{item}: rc {found.returncode}{hint}"
            + (f" — {detail[-1]}" if detail else "")
        )
    try:
        return vault_api_key()
    except EmbeddingsUnavailable as exc:
        reasons.append(f"hub Vault: {exc}")
    raise EmbeddingsUnavailable("no embeddings credential. " + "; ".join(reasons))


def doc_embed_text(path, raw):
    """Return ``(title, embed_text)`` for one document.

    Only the title, the leading prose paragraph and the ``##`` headings are embedded. The
    bodies of these docs are largely shell transcripts and command output, which dominate
    the token count while carrying almost no topical signal.
    """
    title = ""
    lead = []
    lead_done = False
    in_meta = False
    headings = []
    in_fence = False
    for line in raw.splitlines():
        if _FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        h1 = _H1.match(line)
        if h1:
            if not title:
                title = h1.group(1).strip()
            continue
        h2 = _H2.match(line)
        if h2:
            headings.append(h2.group(1).strip())
            continue
        if not title or lead_done:
            continue
        stripped = line.strip()
        if not stripped:
            in_meta = False
            if lead:
                lead_done = True
            continue
        if _META_LINE.match(stripped):
            in_meta = True
            continue
        # A metadata line wraps onto following lines; its continuation is metadata too.
        if in_meta or _RULE_LINE.match(stripped) or _SKIP_LINE.match(line):
            continue
        lead.append(stripped)
    if not title:
        title = Path(path).stem.replace("-", " ")
    parts = [title]
    joined = " ".join(lead).strip()
    if joined:
        parts.append(joined[:LEAD_MAX_CHARS])
    if headings:
        parts.append(" \u00b7 ".join(headings))
    return title, "\n".join(parts)


def content_hash(embed_text):
    """Hash exactly the text that gets embedded.

    Keying on the embedded text rather than the whole file means an edit confined to a
    transcript body correctly re-embeds nothing, because it cannot change the vector.
    """
    return hashlib.sha256(embed_text.encode("utf-8")).hexdigest()


def iter_corpus(repo_root=None):
    """Return ``[(relpath, title, embed_text, hash)]`` for every tracked corpus doc."""
    root = Path(repo_root or REPO_ROOT)
    listed = subprocess.run(
        ["git", "ls-files", "-z", *CORPUS_GLOBS],
        cwd=str(root), capture_output=True, text=True, timeout=120,
    )
    if listed.returncode != 0:
        raise StoreUnavailable(f"git ls-files failed: {listed.stderr.strip()}")
    docs = []
    for rel in sorted(p for p in listed.stdout.split("\0") if p):
        try:
            raw = (root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        title, text = doc_embed_text(rel, raw)
        if not text.strip():
            continue
        docs.append((rel, title, text, content_hash(text)))
    return docs


def _embed_request(texts, task_type, key):
    payload = {
        "requests": [
            {
                "model": f"models/{EMBED_MODEL}",
                "content": {"parts": [{"text": text}]},
                "taskType": task_type,
            }
            for text in texts
        ]
    }
    return urllib.request.Request(
        f"{API_ROOT}/models/{EMBED_MODEL}:batchEmbedContents",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
        method="POST",
    )


def embed_batch(texts, task_type="RETRIEVAL_DOCUMENT", attempts=3):
    """Embed up to ``EMBED_BATCH`` texts. Returns one vector per input, in order."""
    if not texts:
        return []
    if len(texts) > EMBED_BATCH:
        raise ValueError(f"batch of {len(texts)} exceeds {EMBED_BATCH}")
    key = api_key()
    delay = 2.0
    last = None
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(_embed_request(texts, task_type, key), timeout=120) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as exc:
            last = f"HTTP {exc.code}"
            if exc.code not in (429, 500, 502, 503, 504) or attempt == attempts:
                raise EmbeddingsUnavailable(f"embeddings API returned {last}") from None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last = type(exc).__name__
            if attempt == attempts:
                raise EmbeddingsUnavailable(f"embeddings API unreachable ({last})") from None
        time.sleep(delay)
        delay *= 2
    vectors = [item.get("values") or [] for item in data.get("embeddings", [])]
    if len(vectors) != len(texts):
        raise EmbeddingsUnavailable(
            f"embeddings API returned {len(vectors)} vectors for {len(texts)} inputs"
        )
    for vector in vectors:
        if len(vector) != EMBED_DIM:
            raise EmbeddingsUnavailable(
                f"embeddings API returned dimension {len(vector)}, expected {EMBED_DIM}"
            )
    return vectors


def _psql_argv():
    return [
        "kubectl", "--context", KUBE_CONTEXT, "-n", NAMESPACE,
        "exec", "-i", WORKLOAD, "--",
        "sh", "-c",
        'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_USER" -v ON_ERROR_STOP=1 -qAt -f -',
    ]


def run_sql(sql, timeout=600):
    """Pipe SQL to psql inside the vectordb pod and return stdout."""
    try:
        proc = subprocess.run(
            _psql_argv(), input=sql, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise StoreUnavailable(f"vector store timed out after {timeout}s") from None
    except OSError as exc:
        raise StoreUnavailable(f"cannot run kubectl: {exc}") from None
    if proc.returncode != 0:
        raise StoreUnavailable(f"vector store error: {_exec_detail(proc)}")
    return proc.stdout


def copy_escape(value):
    """Escape one field for psql COPY text format."""
    return (
        value.replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )


def vector_literal(values):
    """Render a float sequence as a pgvector literal."""
    return "[" + ",".join(repr(float(v)) for v in values) + "]"


def ensure_schema():
    run_sql(SCHEMA_SQL)


def fetch_hashes():
    """Return ``{path: content_hash}`` for everything currently indexed."""
    out = run_sql(
        f"SELECT coalesce(json_object_agg(path, content_hash)::text, '{{}}') FROM {TABLE};"
    ).strip()
    return json.loads(out or "{}")


def search(text, k=5):
    """Return ``[(score, path, title)]`` most similar to ``text``, best first.

    ``score`` is cosine similarity in ``[-1, 1]``; 1.0 is identical. Raises
    ``RetrievalUnavailable`` when the credential or the store is missing.
    """
    if not text or not text.strip():
        return []
    k = max(1, min(int(k), 50))
    literal = vector_literal(embed_batch([text], task_type="RETRIEVAL_QUERY")[0])
    sql = (
        "SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.score DESC)::text, '[]') FROM ("
        f"  SELECT round((1 - (embedding <=> '{literal}'))::numeric, 4)::float8 AS score,"
        "         path, title"
        f"  FROM {TABLE} ORDER BY embedding <=> '{literal}' LIMIT {k}"
        ") t;"
    )
    rows = json.loads(run_sql(sql).strip() or "[]")
    return [(row["score"], row["path"], row["title"]) for row in rows]
