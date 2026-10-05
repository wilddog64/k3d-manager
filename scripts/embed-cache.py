#!/usr/bin/env python3
"""Back up, restore, inspect, prune, and seed the local embedding cache."""
import argparse
import json
import os
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from hermes.embed_cache import EmbedCache, cache_key, cache_path  # noqa: E402
from hermes.prior_art import (EMBED_DIM, EMBED_MODEL, TABLE, RetrievalUnavailable,
                              iter_corpus, run_sql)  # noqa: E402


def _count(path):
    with sqlite3.connect(path) as connection:
        return connection.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]


SSH_OPTIONS = ["-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3"]
RETRY_DELAYS = (5, 15)


def _remote(spec):
    if ":" not in spec or os.path.exists(spec):
        return None
    host, path = spec.split(":", 1)
    if not host or "/" in host or host.startswith("-"):
        return None
    return host, path


def _remote_path(path):
    if path in ("", "~"):
        return "."
    if path.startswith("~/"):
        return path[2:]
    return path


def _remote_file(path):
    return path if path.endswith(".sqlite") else f"{path}/embeddings.sqlite"


def _command_error(result):
    stderr = getattr(result, "stderr", "") or ""
    return stderr.strip().splitlines()[-1] if stderr.strip() else "unknown error"


def _run_remote(command, step):
    """Run one ssh/scp step, retrying a flaky link; every step is safe to repeat."""
    for attempt, delay in enumerate((*RETRY_DELAYS, None), start=1):
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=False, timeout=300)
        except (OSError, subprocess.TimeoutExpired) as exc:
            result = SimpleNamespace(returncode=1, stderr=str(exc))
        if result.returncode == 0 or delay is None:
            return result
        print(f"embed-cache: {step} failed (attempt {attempt}/{len(RETRY_DELAYS) + 1}): "
              f"{_command_error(result)} — retrying in {delay}s", file=sys.stderr)
        time.sleep(delay)


def _restore_local(source):
    source = Path(source)
    if not source.exists():
        print(f"embed-cache: no backup at {source}", file=sys.stderr)
        return 1
    try:
        with sqlite3.connect(source) as source_connection:
            columns = _embedding_table(source_connection)
            if columns is None:
                print(f"embed-cache: {source} is not an embedding cache", file=sys.stderr)
                return 1
            source_rows = source_connection.execute(
                "SELECT vector" + (", dim" if "dim" in columns else "") + " FROM embeddings"
            ).fetchall()
            skipped = 0
            for row in source_rows:
                vector, *stored_dim = row
                dim = stored_dim[0] if stored_dim and stored_dim[0] is not None else EMBED_DIM
                if len(vector) != dim * 4:
                    skipped += 1

        cache = EmbedCache()
        if not cache.enabled:
            return 1
        before = cache.connection.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]
        cache.connection.execute("ATTACH DATABASE ? AS b", (str(source),))
        cache.connection.execute("BEGIN")
        dimension = "COALESCE(dim, ?)" if "dim" in columns else "?"
        metadata = [name if name in columns else "NULL"
                    for name in ("model", "dim", "task_type", "content_hash")]
        stamps = [f"COALESCE({name}, ?)" if name in columns else "?"
                  for name in ("created_at", "last_used_at")]
        now = datetime.now(timezone.utc).isoformat()
        cache.connection.execute(
            "INSERT OR IGNORE INTO embeddings "
            "(key, vector, model, dim, task_type, content_hash, created_at, last_used_at) "
            f"SELECT key, vector, {', '.join(metadata + stamps)} FROM b.embeddings "
            f"WHERE length(vector) = ({dimension}) * 4",
            (now, now, EMBED_DIM),
        )
        cache.connection.commit()
        total = cache.connection.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]
        cache.connection.execute("DETACH DATABASE b")
    except (OSError, sqlite3.Error) as exc:
        print(f"embed-cache: restore failed: {exc}", file=sys.stderr)
        return 1
    message = f"embed-cache: restored {total - before} new vectors ({total} in cache)"
    if skipped:
        message += f", {skipped} skipped (wrong size)"
    print(message)
    return 0


def backup(destination):
    source = cache_path()
    if not source.exists():
        print(f"embed-cache: no cache at {source} — run make index-docs first", file=sys.stderr)
        return 1
    remote = _remote(destination)
    if remote is not None:
        host, raw_path = remote
        remote_path = _remote_path(raw_path)
        remote_file = _remote_file(remote_path)
        remote_dir = str(Path(remote_file).parent)
        temporary_dir = Path(tempfile.mkdtemp())
        snapshot = temporary_dir / "embeddings.sqlite"
        try:
            with sqlite3.connect(source) as src, sqlite3.connect(snapshot) as dst:
                src.backup(dst)
            count = _count(snapshot)
            commands = [
                ("mkdir", ["ssh", *SSH_OPTIONS, host,
                            f"mkdir -p -- {shlex.quote(remote_dir)}"]),
                ("scp", ["scp", "-q", *SSH_OPTIONS, str(snapshot),
                         f"{host}:{remote_dir}/.embeddings.sqlite.tmp"]),
                ("mv", ["ssh", *SSH_OPTIONS, host,
                         f"mv -f -- {shlex.quote(remote_dir + '/.embeddings.sqlite.tmp')} "
                         f"{shlex.quote(remote_file)}"]),
            ]
            for step, command in commands:
                result = _run_remote(command, step)
                if result.returncode != 0:
                    print(f"embed-cache: backup to {host} failed at {step}: "
                          f"{_command_error(result)}", file=sys.stderr)
                    return 1
        except (OSError, sqlite3.Error) as exc:
            print(f"embed-cache: backup to {host} failed at snapshot: {exc}", file=sys.stderr)
            return 1
        finally:
            shutil.rmtree(temporary_dir, ignore_errors=True)
        print(f"embed-cache: backed up {count} vectors to {host}:{remote_file}")
        return 0
    destination = Path(destination)
    if destination.is_dir():
        destination = destination / "embeddings.sqlite"
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with sqlite3.connect(source) as src:
            with tempfile.NamedTemporaryFile(
                dir=destination.parent, prefix=f".{destination.name}.", suffix=".tmp", delete=False
            ) as handle:
                temporary = Path(handle.name)
            with sqlite3.connect(temporary) as dst:
                src.backup(dst)
            count = _count(temporary)
        os.replace(temporary, destination)
    except (OSError, sqlite3.Error) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        print(f"embed-cache: backup failed: {exc}", file=sys.stderr)
        return 1
    print(f"embed-cache: backed up {count} vectors to {destination}")
    return 0


def _embedding_table(connection):
    row = connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='embeddings'"
    ).fetchone()
    if row is None:
        return None
    columns = {item[1] for item in connection.execute("PRAGMA table_info(embeddings)")}
    return columns if {"key", "vector"}.issubset(columns) else None


def restore(source):
    remote = _remote(source)
    if remote is not None:
        host, raw_path = remote
        remote_file = _remote_file(_remote_path(raw_path))
        temporary_dir = Path(tempfile.mkdtemp())
        local_copy = temporary_dir / "embeddings.sqlite"
        try:
            result = _run_remote(["scp", "-q", *SSH_OPTIONS,
                                  f"{host}:{remote_file}", str(local_copy)], "scp")
            if result.returncode != 0:
                print(f"embed-cache: no backup at {host}:{remote_file}: "
                      f"{_command_error(result)}", file=sys.stderr)
                return 1
            return _restore_local(local_copy)
        finally:
            shutil.rmtree(temporary_dir, ignore_errors=True)
    return _restore_local(source)


def stats():
    cache = EmbedCache()
    for row in cache.stats():
        print(
            f"{row['model']} dim={row['dim']} task={row['task_type']} "
            f"count={row['count']} oldest={row['oldest_created_at']} newest={row['newest_last_used_at']}"
        )
    return 0


def prune(days):
    cache = EmbedCache()
    keep_hashes = {digest for _path, _title, _text, digest in iter_corpus(ROOT)}
    deleted = cache.prune(keep_hashes, days)
    total = cache.connection.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]
    print(f"embed-cache: pruned {deleted} stale vectors ({total} remain)")
    return 0


def seed(ref=None):
    """Fill the local cache from matching vectors already in the hub store."""
    cache = EmbedCache()
    if not cache.enabled:
        return 1
    corpus = {
        path: (embed_text, digest)
        for path, _title, embed_text, digest in iter_corpus(ROOT, ref)
    } if ref is not None else {
        path: (embed_text, digest)
        for path, _title, embed_text, digest in iter_corpus(ROOT)
    }
    try:
        output = run_sql(
            f"COPY (SELECT path, content_hash, embedding::text FROM {TABLE}) TO STDOUT;"
        )
    except RetrievalUnavailable as exc:
        print(f"embed-cache: store unavailable — {exc}", file=sys.stderr)
        return 1

    matches = []
    unmatched = 0
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 3 or "\\" in fields[0]:
            unmatched += 1
            continue
        path, digest, encoded = fields
        try:
            vector = json.loads(encoded)
        except (TypeError, ValueError, json.JSONDecodeError):
            unmatched += 1
            continue
        doc = corpus.get(path)
        if doc is None or digest != doc[1] or len(vector) != EMBED_DIM:
            unmatched += 1
            continue
        embed_text, content_hash = doc
        matches.append((cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", embed_text),
                        vector, {"model": EMBED_MODEL, "dim": EMBED_DIM,
                                 "task_type": "RETRIEVAL_DOCUMENT", "content_hash": content_hash}))

    cached = cache.get_many([key for key, _vector, _meta in matches], EMBED_MODEL,
                            EMBED_DIM, "RETRIEVAL_DOCUMENT")
    pending = [item for item in matches if item[0] not in cached]
    for start in range(0, len(pending), 200):
        cache.put_many(pending[start:start + 200])
    total = cache.connection.execute("SELECT COUNT(*) FROM embeddings").fetchone()[0]
    print(f"embed-cache: seeded {len(matches)} vectors from the store "
          f"({len(cached)} already cached, {unmatched} unmatched, {total} in cache)")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    backup_parser = subparsers.add_parser("backup")
    backup_parser.add_argument("destination")
    restore_parser = subparsers.add_parser("restore")
    restore_parser.add_argument("source")
    subparsers.add_parser("stats")
    prune_parser = subparsers.add_parser("prune")
    prune_parser.add_argument("--days", type=int, default=90)
    seed_parser = subparsers.add_parser("seed")
    seed_parser.add_argument("--ref")
    args = parser.parse_args(argv)
    if args.command == "backup":
        return backup(args.destination)
    if args.command == "restore":
        return restore(args.source)
    if args.command == "stats":
        return stats()
    if args.command == "seed":
        return seed(args.ref)
    return prune(args.days)


if __name__ == "__main__":
    raise SystemExit(main())
