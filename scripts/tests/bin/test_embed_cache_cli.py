"""Tests for the embedding-cache backup and restore CLI."""
import importlib.util
import sqlite3
import sys
from array import array
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
from hermes.embed_cache import EmbedCache, cache_key  # noqa: E402
from hermes.prior_art import EMBED_DIM, EMBED_MODEL  # noqa: E402


SPEC = importlib.util.spec_from_file_location("embed_cache_cli", REPO_ROOT / "scripts" / "embed-cache.py")
cli = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cli)


def _meta(content_hash, model=EMBED_MODEL, dim=EMBED_DIM):
    return {"model": model, "dim": dim, "task_type": "RETRIEVAL_DOCUMENT", "content_hash": content_hash}


def _seed(path, names):
    cache = EmbedCache(path)
    cache.put_many((cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", name),
                   [float(index)] * EMBED_DIM, _meta(f"hash-{name}"))
                  for index, name in enumerate(names))
    return cache


@pytest.fixture(autouse=True)
def cache_env(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_EMBED_CACHE", str(tmp_path / "primary.sqlite"))


def test_backup_restore_round_trip(tmp_path, capsys):
    primary = Path(cli.cache_path())
    _seed(primary, ("a", "b", "c"))
    destination = tmp_path / "backup.sqlite"
    assert cli.main(["backup", str(destination)]) == 0
    primary.unlink()
    assert cli.main(["restore", str(destination)]) == 0
    assert _keys(primary) == {_key(name) for name in ("a", "b", "c")}
    assert "backed up 3 vectors" in capsys.readouterr().out


def _key(name):
    return cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", name)


def _keys(path):
    with sqlite3.connect(path) as connection:
        return {row[0] for row in connection.execute("SELECT key FROM embeddings")}


def test_restore_merges_and_never_overwrites(tmp_path, capsys):
    primary = Path(cli.cache_path())
    cache = EmbedCache(primary)
    cache.put_many([(_key("a"), [1.0] * EMBED_DIM, _meta("a")),
                    (_key("b"), [2.0] * EMBED_DIM, _meta("b"))])
    backup = tmp_path / "backup.sqlite"
    _seed(backup, ("b", "c"))
    assert cli.main(["restore", str(backup)]) == 0
    with sqlite3.connect(primary) as connection:
        rows = dict(connection.execute("SELECT key, vector FROM embeddings"))
    assert set(rows) == {_key("a"), _key("b"), _key("c")}
    assert rows[_key("b")] == array("f", [2.0] * EMBED_DIM).tobytes()
    assert "1 new" in capsys.readouterr().out


def test_directory_destination(tmp_path):
    _seed(Path(cli.cache_path()), ("a",))
    directory = tmp_path / "folder"
    directory.mkdir()
    assert cli.main(["backup", str(directory)]) == 0
    assert (directory / "embeddings.sqlite").exists()


def test_backup_without_primary_exits_one(tmp_path, capsys):
    assert cli.main(["backup", str(tmp_path / "x")]) == 1
    assert "no cache at" in capsys.readouterr().err


def test_restore_non_cache_leaves_primary_unchanged(tmp_path, capsys):
    primary = Path(cli.cache_path())
    _seed(primary, ("a",))
    source = tmp_path / "not-cache.sqlite"
    with sqlite3.connect(source) as connection:
        connection.execute("CREATE TABLE other (value TEXT)")
    assert cli.main(["restore", str(source)]) == 1
    assert _keys(primary) == {_key("a")}
    assert "is not an embedding cache" in capsys.readouterr().err


def test_destination_with_space_and_quote(tmp_path):
    _seed(Path(cli.cache_path()), ("a",))
    destination = tmp_path / "a space's backup.sqlite"
    assert cli.main(["backup", str(destination)]) == 0
    assert destination.exists()


def test_backup_failure_leaves_no_partial_file(tmp_path, monkeypatch):
    primary = Path(cli.cache_path())
    _seed(primary, ("a",))
    destination = tmp_path / "backup.sqlite"
    real_connect = cli.sqlite3.connect

    class FailingConnection:
        def __init__(self, connection, fail=False):
            self.connection = connection
            self.fail = fail

        def __enter__(self):
            self.connection.__enter__()
            return self

        def __exit__(self, *args):
            return self.connection.__exit__(*args)

        def backup(self, _destination):
            if self.fail:
                raise sqlite3.Error("injected backup failure")
            return self.connection.backup(_destination)

        def __getattr__(self, name):
            return getattr(self.connection, name)

    calls = 0

    def connect(path, *args, **kwargs):
        nonlocal calls
        connection = real_connect(path, *args, **kwargs)
        calls += 1
        return FailingConnection(connection, fail=calls == 1)

    monkeypatch.setattr(cli.sqlite3, "connect", connect)
    assert cli.main(["backup", str(destination)]) == 1
    assert not destination.exists()
    assert not list(tmp_path.glob(".backup.sqlite.*.tmp"))


def test_migration_preserves_rows_and_null_metadata(tmp_path):
    path = tmp_path / "v1.sqlite"
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE embeddings (key TEXT PRIMARY KEY, vector BLOB NOT NULL)")
        connection.executemany("INSERT INTO embeddings VALUES (?, ?)", [("a", b"1234"), ("b", b"5678")])
    cache = EmbedCache(path)
    assert cache.connection.execute("PRAGMA user_version").fetchone()[0] == 2
    assert len(cache.get_many(["a", "b"], EMBED_MODEL, 1, "RETRIEVAL_DOCUMENT")) == 2
    assert cache.connection.execute("SELECT model, dim FROM embeddings").fetchall() == [(None, None), (None, None)]


def test_integrity_checks_on_read(tmp_path):
    cache = EmbedCache(tmp_path / "cache.sqlite")
    cache.put_many([("wrong-size", [1.0], _meta("x")),
                    ("wrong-model", [1.0] * EMBED_DIM, _meta("y", model="other"))])
    assert cache.get_many(["wrong-size", "wrong-model"], EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT") == {}


def test_hit_updates_last_used_at(tmp_path):
    cache = EmbedCache(tmp_path / "cache.sqlite")
    cache.put_many([("hit", [1.0] * EMBED_DIM, _meta("x"))])
    before = cache.connection.execute("SELECT last_used_at FROM embeddings").fetchone()[0]
    cache.get_many(["hit"], EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT")
    after = cache.connection.execute("SELECT last_used_at FROM embeddings").fetchone()[0]
    assert after >= before


def test_prune_requires_staleness_and_age(tmp_path):
    cache = EmbedCache(tmp_path / "cache.sqlite")
    old = (datetime.now(timezone.utc) - timedelta(days=100)).isoformat()
    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    cache.put_many([("current", [1.0] * EMBED_DIM, _meta("keep")),
                    ("stale-old", [1.0] * EMBED_DIM, _meta("drop-old")),
                    ("stale-new", [1.0] * EMBED_DIM, _meta("drop-new")),
                    ("old-model", [1.0] * EMBED_DIM, _meta("model-old", model="old"))])
    cache.connection.execute("UPDATE embeddings SET last_used_at = ? WHERE key IN (?, ?)", (old, "stale-old", "old-model"))
    cache.connection.execute("UPDATE embeddings SET last_used_at = ? WHERE key = ?", (yesterday, "stale-new"))
    cache.connection.commit()
    assert cache.prune({"keep"}, 90) == 2
    assert {row[0] for row in cache.connection.execute("SELECT key FROM embeddings")} == {"current", "stale-new"}


def test_restore_skips_wrong_size(tmp_path, capsys):
    source = tmp_path / "bad.sqlite"
    with sqlite3.connect(source) as connection:
        connection.execute("CREATE TABLE embeddings (key TEXT PRIMARY KEY, vector BLOB NOT NULL, dim INTEGER)")
        connection.executemany("INSERT INTO embeddings VALUES (?, ?, ?)", [("good", b"1234", 1), ("bad", b"12", 1)])
    assert cli.main(["restore", str(source)]) == 0
    assert "1 skipped (wrong size)" in capsys.readouterr().out
    assert _keys(Path(cli.cache_path())) == {"good"}


def test_prune_spares_rows_migrated_from_version_one(tmp_path):
    path = tmp_path / "v1.sqlite"
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE embeddings (key TEXT PRIMARY KEY, vector BLOB NOT NULL)")
        connection.execute("INSERT INTO embeddings VALUES (?, ?)", ("legacy", b"\0" * EMBED_DIM * 4))
    cache = EmbedCache(path)
    assert cache.prune({"anything"}, 90) == 0
    assert _keys(path) == {"legacy"}


def test_restore_keeps_metadata_and_survives_prune(tmp_path):
    backup = tmp_path / "backup.sqlite"
    _seed(backup, ("a",)).connection.close()
    assert cli.main(["restore", str(backup)]) == 0
    primary = EmbedCache(Path(cli.cache_path()))
    row = primary.connection.execute(
        "SELECT model, dim, content_hash, last_used_at FROM embeddings").fetchone()
    assert row[:3] == (EMBED_MODEL, EMBED_DIM, "hash-a")
    assert row[3] is not None
    assert primary.prune({"other"}, 90) == 0
