"""Tests for the embedding-cache backup and restore CLI."""
import importlib.util
import json
import shutil
import sqlite3
import sys
from array import array
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "lib"))
from hermes.embed_cache import EmbedCache, cache_key  # noqa: E402
from hermes.prior_art import EMBED_DIM, EMBED_MODEL, RetrievalUnavailable  # noqa: E402


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


def _store_rows(rows):
    return "".join(f"{path}\t{digest}\t{vector}\n" for path, digest, vector in rows)


def test_seed_matches_store_rows_without_embedding(monkeypatch, capsys):
    docs = [("docs/a.md", "A", "text a", "hash-a"),
            ("docs/b.md", "B", "text b", "hash-b")]
    monkeypatch.setattr(cli, "iter_corpus", lambda *_args: docs)
    monkeypatch.setattr(cli, "run_sql", lambda _sql: _store_rows(
        [("docs/a.md", "hash-a", json.dumps([0.1] * EMBED_DIM)),
         ("docs/b.md", "stale", json.dumps([0.2] * EMBED_DIM)),
         ("docs/c.md", "hash-c", json.dumps([0.3] * EMBED_DIM))]))
    import hermes.prior_art as prior_art
    monkeypatch.setattr(prior_art, "embed_batch", lambda *_args, **_kwargs: pytest.fail("embed_batch called"))
    assert cli.main(["seed"]) == 0
    cache = EmbedCache(Path(cli.cache_path()))
    assert cache.get_many([cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", "text a")])
    assert cache.get_many([cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", "text b")]) == {}
    assert cache.connection.execute("SELECT content_hash FROM embeddings").fetchone()[0] == "hash-a"
    output = capsys.readouterr().out
    assert "1 vectors" in output and "2 unmatched" in output


def test_seed_never_overwrites(monkeypatch, capsys):
    docs = [("docs/a.md", "A", "text a", "hash-a")]
    monkeypatch.setattr(cli, "iter_corpus", lambda *_args: docs)
    monkeypatch.setattr(cli, "run_sql", lambda _sql: _store_rows(
        [("docs/a.md", "hash-a", json.dumps([0.2] * EMBED_DIM))]))
    primary = Path(cli.cache_path())
    _seed(primary, ("text a",))
    cache = EmbedCache(primary)
    cache.connection.execute("UPDATE embeddings SET vector = ?", (array("f", [0.1] * EMBED_DIM).tobytes(),))
    cache.connection.commit()
    assert cli.main(["seed"]) == 0
    row = cache.connection.execute("SELECT vector FROM embeddings").fetchone()[0]
    assert row == array("f", [0.1] * EMBED_DIM).tobytes()
    assert "1 already cached" in capsys.readouterr().out


def test_seed_wrong_dimension_is_unmatched(monkeypatch, capsys):
    monkeypatch.setattr(cli, "iter_corpus", lambda *_args: [("docs/a.md", "A", "text a", "hash-a")])
    monkeypatch.setattr(cli, "run_sql", lambda _sql: _store_rows(
        [("docs/a.md", "hash-a", json.dumps([0.1] * (EMBED_DIM - 1)))]))
    assert cli.main(["seed"]) == 0
    output = capsys.readouterr().out
    assert "0 vectors" in output and "1 unmatched" in output
    assert _keys(Path(cli.cache_path())) == set()


def test_seed_store_unavailable(monkeypatch, capsys):
    monkeypatch.setattr(cli, "iter_corpus", lambda *_args: [])
    monkeypatch.setattr(cli, "run_sql", lambda _sql: (_ for _ in ()).throw(
        RetrievalUnavailable("offline")))
    assert cli.main(["seed"]) == 1
    assert "store unavailable" in capsys.readouterr().err
    assert _keys(Path(cli.cache_path())) == set()


def test_seed_passes_ref_to_iter_corpus(monkeypatch, capsys):
    calls = []
    monkeypatch.setattr(cli, "iter_corpus", lambda *args: calls.append(args) or [])
    monkeypatch.setattr(cli, "run_sql", lambda _sql: "")
    assert cli.main(["seed", "--ref", "origin/x"]) == 0
    assert calls == [(cli.ROOT, "origin/x")]


def test_backup_restore_round_trip(tmp_path, capsys):
    primary = Path(cli.cache_path())
    _seed(primary, ("a", "b", "c"))
    destination = tmp_path / "backup.sqlite"
    assert cli.main(["backup", str(destination)]) == 0
    primary.unlink()
    assert cli.main(["restore", str(destination)]) == 0
    assert _keys(primary) == {_key(name) for name in ("a", "b", "c")}
    assert "backed up 3 vectors" in capsys.readouterr().out


def test_remote_backup_command_sequence(monkeypatch, capsys):
    _seed(Path(cli.cache_path()), ("a",))
    commands = []

    def run(command, **_kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(cli.subprocess, "run", run)
    assert cli.main(["backup", "m2-air:~/.local/backup"]) == 0
    assert commands[0] == ["ssh", *cli.SSH_OPTIONS, "m2-air",
                           "mkdir -p -- .local/backup"]
    assert commands[1][:-2] == ["scp", "-q", *cli.SSH_OPTIONS]
    assert commands[1][-1] == "m2-air:.local/backup/.embeddings.sqlite.tmp"
    assert commands[2] == ["ssh", *cli.SSH_OPTIONS, "m2-air",
                           "mv -f -- .local/backup/.embeddings.sqlite.tmp .local/backup/embeddings.sqlite"]
    assert all("~" not in argument for command in commands for argument in command)
    assert not Path(commands[1][-2]).parent.exists()
    assert "m2-air:.local/backup/embeddings.sqlite" in capsys.readouterr().out


def test_remote_backup_failed_scp_never_runs_mv(monkeypatch, capsys):
    _seed(Path(cli.cache_path()), ("a",))
    commands = []

    def run(command, **_kwargs):
        commands.append(command)
        return SimpleNamespace(returncode=1 if command[0] == "scp" else 0, stderr="copy failed\n")

    monkeypatch.setattr(cli.subprocess, "run", run)
    sleeps = []
    monkeypatch.setattr(cli.time, "sleep", sleeps.append)
    assert cli.main(["backup", "m2-air:~/.local/backup"]) == 1
    assert not any(command[-1].startswith("mv -f") for command in commands)
    assert [command[0] for command in commands] == ["ssh", "scp", "scp", "scp"]
    assert sleeps == list(cli.RETRY_DELAYS)
    assert not Path(commands[1][-2]).parent.exists()
    assert "failed at scp" in capsys.readouterr().err


def test_remote_backup_retries_a_dropped_link(monkeypatch, capsys):
    _seed(Path(cli.cache_path()), ("a",))
    commands = []
    outcomes = iter([cli.subprocess.TimeoutExpired("scp", 300), SimpleNamespace(returncode=255, stderr="Broken pipe\n")])

    def run(command, **_kwargs):
        commands.append(command)
        if command[0] == "scp":
            outcome = next(outcomes, None)
            if isinstance(outcome, Exception):
                raise outcome
            if outcome is not None:
                return outcome
        return SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(cli.subprocess, "run", run)
    monkeypatch.setattr(cli.time, "sleep", lambda _delay: None)
    assert cli.main(["backup", "m2-air:~/.local/backup"]) == 0
    assert [command[0] for command in commands] == ["ssh", "scp", "scp", "scp", "ssh"]
    captured = capsys.readouterr()
    assert "attempt 2/3" in captured.err and "Broken pipe" in captured.err
    assert "backed up 1 vectors" in captured.out


def test_remote_sqlite_destination_names_file(monkeypatch):
    _seed(Path(cli.cache_path()), ("a",))
    commands = []
    monkeypatch.setattr(cli.subprocess, "run", lambda command, **_kwargs: (
        commands.append(command) or SimpleNamespace(returncode=0, stderr="")))
    assert cli.main(["backup", "host:backups/k3dm.sqlite"]) == 0
    assert commands[1][-1] == "host:backups/.embeddings.sqlite.tmp"
    assert commands[2][-1] == "mv -f -- backups/.embeddings.sqlite.tmp backups/k3dm.sqlite"


def test_local_path_containing_colon_stays_local(tmp_path, monkeypatch):
    _seed(Path(cli.cache_path()), ("a",))
    destination = tmp_path / "a:b"
    calls = []
    monkeypatch.setattr(cli.subprocess, "run", lambda *args, **kwargs: calls.append((args, kwargs)))
    assert cli.main(["backup", str(destination)]) == 0
    assert destination.exists()
    assert calls == []


def test_remote_restore(monkeypatch, tmp_path, capsys):
    fixture = tmp_path / "fixture.sqlite"
    _seed(fixture, ("a", "b"))
    calls = []

    def run(command, **_kwargs):
        calls.append(command)
        shutil.copyfile(fixture, command[-1])
        return SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(cli.subprocess, "run", run)
    assert cli.main(["restore", "m2-air:~/.local/backup"]) == 0
    assert _keys(Path(cli.cache_path())) == {_key("a"), _key("b")}
    assert calls == [["scp", "-q", *cli.SSH_OPTIONS,
                      "m2-air:.local/backup/embeddings.sqlite", calls[0][-1]]]
    assert "restored 2 new vectors" in capsys.readouterr().out


def test_remote_path_with_space_is_quoted(monkeypatch):
    _seed(Path(cli.cache_path()), ("a",))
    commands = []
    monkeypatch.setattr(cli.subprocess, "run", lambda command, **_kwargs: (
        commands.append(command) or SimpleNamespace(returncode=0, stderr="")))
    assert cli.main(["backup", "host:~/my backups"]) == 0
    assert "'my backups'" in commands[0][-1]
    assert commands[1][-1] == "host:my backups/.embeddings.sqlite.tmp"


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
