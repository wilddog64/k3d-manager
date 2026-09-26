#!/usr/bin/env python3
"""Embed the docs corpus into the pgvector store, re-embedding only what changed.

Usage:
    scripts/index-docs.py                 # index every tracked corpus doc
    scripts/index-docs.py --dry-run       # report what would change, embed nothing
    scripts/index-docs.py --limit 5       # embed at most 5 changed docs (contract smoke)

The corpus is ``docs/bugs``, ``docs/issues``, ``docs/plans`` and ``docs/retro``, enumerated
with ``git ls-files`` so untracked scratch files are never indexed. Each document is keyed by
a hash of the text actually embedded, so a re-run with no doc changes performs zero
embedding calls and costs one round trip.

Exit status is 0 on success, 1 when the credential or the store is unavailable, 2 on usage
error. The store is a rebuildable cache: losing it costs one re-index, not data.
"""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from hermes.prior_art import (  # noqa: E402
    EMBED_BATCH,
    TABLE,
    RetrievalUnavailable,
    copy_escape,
    embed_batch,
    ensure_schema,
    fetch_hashes,
    iter_corpus,
    run_sql,
    vector_literal,
)


def _upsert_script(rows):
    """Build one psql script that upserts ``rows`` in its own transaction.

    One batch per transaction, deliberately. Embedding 1,700 documents and writing once at the
    end meant a failure on the last batch discarded every batch already paid for; committing
    per batch makes a re-run resume, because ``fetch_hashes`` then sees what landed.
    """
    parts = [
        "BEGIN;",
        "CREATE TEMP TABLE staging (path text, title text, content_hash text, "
        "embedding vector) ON COMMIT DROP;",
        "COPY staging (path, title, content_hash, embedding) FROM STDIN;",
    ]
    for path, title, digest, vector in rows:
        parts.append(
            "\t".join(
                (
                    copy_escape(path),
                    copy_escape(title),
                    copy_escape(digest),
                    vector_literal(vector),
                )
            )
        )
    parts.append("\\.")
    parts.append(
        f"INSERT INTO {TABLE} (path, title, content_hash, embedding) "
        "SELECT path, title, content_hash, embedding FROM staging "
        "ON CONFLICT (path) DO UPDATE SET title = EXCLUDED.title, "
        "content_hash = EXCLUDED.content_hash, embedding = EXCLUDED.embedding, "
        "indexed_at = now();"
    )
    parts.append("COMMIT;")
    return "\n".join(parts) + "\n"


def _prune_script(present_paths):
    """Build one psql script that deletes rows for docs no longer in the corpus."""
    parts = [
        "BEGIN;",
        "CREATE TEMP TABLE present (path text) ON COMMIT DROP;",
        "COPY present (path) FROM STDIN;",
    ]
    for path in present_paths:
        parts.append(copy_escape(path))
    parts.append("\\.")
    parts.append(
        f"SELECT 'pruned=' || count(*) FROM {TABLE} "
        "WHERE path NOT IN (SELECT path FROM present);"
    )
    parts.append(f"DELETE FROM {TABLE} WHERE path NOT IN (SELECT path FROM present);")
    parts.append("COMMIT;")
    parts.append(f"SELECT 'indexed=' || count(*) FROM {TABLE};")
    return "\n".join(parts) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="report what would change without calling the embeddings API")
    parser.add_argument("--limit", type=int, default=0,
                        help="embed at most N changed documents (0 = no limit)")
    parser.add_argument("--quiet", action="store_true", help="only print the summary line")
    args = parser.parse_args(argv)

    try:
        docs = iter_corpus(ROOT)
        ensure_schema()
        existing = fetch_hashes()
    except RetrievalUnavailable as exc:
        print(f"index-docs: unavailable — {exc}", file=sys.stderr)
        return 1

    changed = [doc for doc in docs if existing.get(doc[0]) != doc[3]]
    stale = sorted(set(existing) - {doc[0] for doc in docs})

    if args.dry_run:
        print(f"index-docs: {len(docs)} docs, {len(changed)} would be embedded, "
              f"{len(stale)} would be pruned (dry run, no API calls)")
        for path, _title, _text, _digest in changed[:20]:
            print(f"  embed  {path}")
        for path in stale[:20]:
            print(f"  prune  {path}")
        return 0

    if args.limit > 0:
        changed = changed[: args.limit]

    written = 0
    try:
        for start in range(0, len(changed), EMBED_BATCH):
            batch = changed[start:start + EMBED_BATCH]
            vectors = embed_batch([doc[2] for doc in batch], task_type="RETRIEVAL_DOCUMENT")
            rows = [
                (path, title, digest, vector)
                for (path, title, _text, digest), vector in zip(batch, vectors)
            ]
            run_sql(_upsert_script(rows))
            written += len(rows)
            if not args.quiet:
                print(f"index-docs: committed {written}/{len(changed)}", file=sys.stderr)
    except RetrievalUnavailable as exc:
        print(f"index-docs: unavailable — {exc}", file=sys.stderr)
        print(
            f"index-docs: {written} of {len(changed)} documents were committed before the "
            "failure; re-running resumes from there",
            file=sys.stderr,
        )
        return 1

    present = [doc[0] for doc in docs]
    if args.limit > 0 and stale:
        present = sorted(set(present) | set(existing))
    try:
        summary = run_sql(_prune_script(present))
    except RetrievalUnavailable as exc:
        print(f"index-docs: unavailable — {exc}", file=sys.stderr)
        print(f"index-docs: {written} documents were committed; only the prune failed",
              file=sys.stderr)
        return 1

    counts = dict(
        line.split("=", 1) for line in summary.split() if "=" in line
    )
    print(
        f"index-docs: {len(docs)} docs, {written} embedded, "
        f"{counts.get('pruned', '0')} pruned, {counts.get('indexed', '?')} in store"
    )
    subprocess.run([str(ROOT / "bin" / "k3dm-vectordb-metrics")],
                   cwd=ROOT, capture_output=True, text=True, timeout=120, check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
