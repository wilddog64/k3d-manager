"""Best-effort local cache for document embeddings."""
import hashlib
import os
import sqlite3
import sys
from array import array
from pathlib import Path

from hermes.prior_art import EMBED_DIM


def cache_path():
    """Return the configured local embedding-cache path."""
    return Path(os.environ.get("K3DM_EMBED_CACHE", "")) if os.environ.get("K3DM_EMBED_CACHE") else Path.home() / ".cache" / "k3dm" / "embeddings.sqlite"


def cache_key(model, dim, task_type, text):
    """Return a content-addressed key for one embedding request."""
    value = f"{model}\0{dim}\0{task_type}\0{text}"
    return hashlib.sha256(value.encode()).hexdigest()


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

    def get_many(self, keys):
        """Return valid cached vectors for ``keys``."""
        if not self.enabled or not keys:
            return {}
        try:
            placeholders = ",".join("?" for _ in keys)
            rows = self.connection.execute(
                f"SELECT key, vector FROM embeddings WHERE key IN ({placeholders})", keys
            )
            hits = {}
            for key, blob in rows:
                vector = array("f")
                vector.frombytes(blob)
                if len(vector) == EMBED_DIM:
                    hits[key] = list(vector)
            return hits
        except (OSError, sqlite3.Error, ValueError) as exc:
            self._disable(exc)
            return {}

    def put_many(self, items):
        """Store newly embedded vectors in one transaction."""
        if not self.enabled or not items:
            return
        try:
            self.connection.executemany(
                "INSERT OR REPLACE INTO embeddings (key, vector) VALUES (?, ?)",
                [(key, array("f", vector).tobytes()) for key, vector in items],
            )
            self.connection.commit()
        except (OSError, sqlite3.Error, ValueError, OverflowError) as exc:
            self._disable(exc)
