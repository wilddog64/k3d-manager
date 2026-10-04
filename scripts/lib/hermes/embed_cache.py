"""Best-effort local cache for document embeddings."""
import hashlib
import os
import sqlite3
import sys
from array import array
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hermes.prior_art import EMBED_DIM, EMBED_MODEL

SCHEMA_VERSION = 2


def cache_path():
    """Return the configured local embedding-cache path."""
    return Path(os.environ.get("K3DM_EMBED_CACHE", "")) if os.environ.get("K3DM_EMBED_CACHE") else Path.home() / ".cache" / "k3dm" / "embeddings.sqlite"


def cache_key(model, dim, task_type, text):
    """Return a content-addressed key for one embedding request."""
    value = f"{model}\0{dim}\0{task_type}\0{text}"
    return hashlib.sha256(value.encode()).hexdigest()


def _now():
    return datetime.now(timezone.utc).isoformat()


class EmbedCache:
    """A best-effort SQLite cache whose failures never stop indexing."""

    def __init__(self, path=None):
        self.path = Path(path) if path is not None else cache_path()
        self.enabled = True
        self.connection = None
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.connection = sqlite3.connect(self.path)
            self.connection.execute(
                "CREATE TABLE IF NOT EXISTS embeddings "
                "(key TEXT PRIMARY KEY, vector BLOB NOT NULL)"
            )
            columns = {row[1] for row in self.connection.execute("PRAGMA table_info(embeddings)")}
            for name, definition in (
                ("model", "TEXT"),
                ("dim", "INTEGER"),
                ("task_type", "TEXT"),
                ("content_hash", "TEXT"),
                ("created_at", "TEXT"),
                ("last_used_at", "TEXT"),
            ):
                if name not in columns:
                    self.connection.execute(f"ALTER TABLE embeddings ADD COLUMN {name} {definition}")
            now = _now()
            self.connection.execute(
                "UPDATE embeddings SET created_at = COALESCE(created_at, ?), "
                "last_used_at = COALESCE(last_used_at, ?) "
                "WHERE created_at IS NULL OR last_used_at IS NULL",
                (now, now),
            )
            self.connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            self.connection.commit()
        except (OSError, sqlite3.Error) as exc:
            self._disable(exc)

    def _disable(self, exc):
        self.enabled = False
        if self.connection is not None:
            self.connection.close()
            self.connection = None
        print(
            f"index-docs: embedding cache unavailable ({self.path}): {exc} — continuing without it",
            file=sys.stderr,
        )

    def get_many(self, keys, model=EMBED_MODEL, dim=EMBED_DIM, task_type="RETRIEVAL_DOCUMENT"):
        """Return compatible cached vectors for ``keys`` and mark hits used."""
        if not self.enabled or not keys:
            return {}
        try:
            placeholders = ",".join("?" for _ in keys)
            rows = self.connection.execute(
                f"SELECT key, vector, model, dim, task_type FROM embeddings "
                f"WHERE key IN ({placeholders})", keys
            )
            hits = {}
            for key, blob, stored_model, stored_dim, stored_task in rows:
                if len(blob) != dim * 4:
                    continue
                if stored_model is not None and stored_model != model:
                    continue
                if stored_dim is not None and stored_dim != dim:
                    continue
                if stored_task is not None and stored_task != task_type:
                    continue
                vector = array("f")
                vector.frombytes(blob)
                hits[key] = list(vector)
            if hits:
                marks = ",".join("?" for _ in hits)
                self.connection.execute(
                    f"UPDATE embeddings SET last_used_at = ? WHERE key IN ({marks})",
                    [_now(), *hits],
                )
                self.connection.commit()
            return hits
        except (OSError, sqlite3.Error, ValueError) as exc:
            self._disable(exc)
            return {}

    def put_many(self, items):
        """Store ``(key, vector, metadata)`` items in one transaction."""
        if not self.enabled or not items:
            return
        try:
            now = _now()
            values = []
            for item in items:
                if len(item) == 2:
                    key, vector = item
                    meta = {"model": EMBED_MODEL, "dim": EMBED_DIM,
                            "task_type": "RETRIEVAL_DOCUMENT", "content_hash": None}
                else:
                    key, vector, meta = item
                values.append((
                    key, array("f", vector).tobytes(), meta["model"], meta["dim"],
                    meta["task_type"], meta["content_hash"], now, now,
                ))
            self.connection.executemany(
                "INSERT OR REPLACE INTO embeddings "
                "(key, vector, model, dim, task_type, content_hash, created_at, last_used_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", values
            )
            self.connection.commit()
        except (OSError, sqlite3.Error, ValueError, OverflowError) as exc:
            self._disable(exc)

    def prune(self, keep_hashes, max_age_days=90):
        """Delete stale vectors that have not been used within ``max_age_days``."""
        if not self.enabled:
            return 0
        try:
            cutoff = datetime.now(timezone.utc) - timedelta(days=max_age_days)
            rows = self.connection.execute(
                "SELECT key, model, dim, content_hash, last_used_at FROM embeddings"
            ).fetchall()
            delete = []
            for key, model, dim, content_hash, last_used_at in rows:
                stale = content_hash not in keep_hashes or model != EMBED_MODEL or dim != EMBED_DIM
                unused = last_used_at is None
                if last_used_at is not None:
                    try:
                        unused = datetime.fromisoformat(last_used_at) < cutoff
                    except (TypeError, ValueError):
                        unused = True
                if stale and unused:
                    delete.append(key)
            if delete:
                marks = ",".join("?" for _ in delete)
                self.connection.execute(f"DELETE FROM embeddings WHERE key IN ({marks})", delete)
                self.connection.commit()
            return len(delete)
        except (OSError, sqlite3.Error, ValueError) as exc:
            self._disable(exc)
            return 0

    def stats(self):
        """Return grouped counts and timestamp bounds for the cache."""
        if not self.enabled:
            return []
        try:
            rows = self.connection.execute(
                "SELECT model, dim, task_type, COUNT(*), MIN(created_at), MAX(last_used_at) "
                "FROM embeddings GROUP BY model, dim, task_type ORDER BY model, dim, task_type"
            )
            return [
                {"model": model, "dim": dim, "task_type": task_type, "count": count,
                 "oldest_created_at": oldest, "newest_last_used_at": newest}
                for model, dim, task_type, count, oldest, newest in rows
            ]
        except (OSError, sqlite3.Error) as exc:
            self._disable(exc)
            return []
