# Bug: `make embed-cache-backup` can only write to a local path, so a second Mac needs a manual share mount

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — Codex, verified by Claude 2026-10-04. Claude added keepalives, two retries per step, and
`TimeoutExpired` handling (the operator's M4↔M2 link drops), and stopped quoting scp remote paths: OpenSSH 10's
scp uses SFTP, which takes paths literally. 26 tests; 5 mutations each turn a test red.
**Severity:** low. The second copy is a manual, error-prone step.

## Observed

The operator ran `make embed-cache-backup DEST=m2-air.local`. `backup()` treats `DEST` as a local
path, so this would have written a file named `m2-air.local` in the repo root, and nothing would
have reached the M2 Air. The only way to reach another Mac today is to mount an SMB share first,
or to back up locally and run `scp` by hand.

## Fix spec

`DEST` (backup) and `SRC` (restore) accept scp syntax, `host:path`, as well as a local path. The
operator's target is `m2-air:~/.local/backup`.

### File 1 — `scripts/embed-cache.py`

1. **Detection.** Add `_remote(spec)`. It returns `(host, path)` when `spec` contains `:`, the part
   before the first `:` is non-empty and contains no `/`, and `os.path.exists(spec)` is false.
   Otherwise it returns `None`. So `./a:b` and `/x/y:z` stay local.
2. **Remote path.** Add `_remote_path(path)`. It maps `~` or an empty path to `.`, and `~/rest` to
   `rest`. ssh and scp start in the remote home, and a quoted `~` would never expand. Any other path
   is kept as given.
3. **Remote file name.** If the remote path ends with `.sqlite`, it names the file. Otherwise it is
   a directory, and the file is `<dir>/embeddings.sqlite`.
4. **Remote backup, in `backup()`.**
   - Snapshot to a local file in `tempfile.mkdtemp()`, using the same `src.backup(dst)` the local
     path uses.
   - Run `ssh <host> mkdir -p -- <quoted dir>`.
   - Run `scp -q <snapshot> <host>:<dir>/.embeddings.sqlite.tmp`.
   - Run `ssh <host> mv -f -- <quoted tmp> <quoted final>`.
   - Run every command through `subprocess.run([...], check=False, timeout=300)` with a list of
     arguments, never `shell=True`.
   - Quote remote shell arguments with `shlex.quote`. Pass `-o ConnectTimeout=10` to ssh and scp.
   - Always delete the local temp directory in `finally`.
   - On any non-zero exit, print `embed-cache: backup to <host> failed at <step>: <stderr tail>`,
     exit 1, and skip the later steps. A failed scp must never run the `mv`.
   - On success, print `embed-cache: backed up <n> vectors to <host>:<final>`.
5. **Remote restore, in `restore()`.**
   - Run `scp -q <host>:<file> <tmpdir>/embeddings.sqlite`. Name the file with the same `.sqlite`
     rule as backup.
   - Run the existing restore on that local copy, then delete the temp directory.
   - A failed scp prints `embed-cache: no backup at <host>:<file>: <stderr tail>` and exits 1.
6. **Secrets.** The commands carry no secrets. ssh authenticates with the operator's own keys or
   agent. Do not read or touch `~/.ssh`.

### File 2 — `Makefile`

Change the two `ERROR:` example lines to mention both forms, for example
`DEST=/Volumes/m2-share/k3dm or DEST=m2-air:~/.local/backup`. Do the same in the `##` help comments
of `embed-cache-backup` and `embed-cache-restore`. The recipes need no other change: `"$(DEST)"` is
already passed as one argument after `--`.

### File 3 — `scripts/tests/bin/test_embed_cache_cli.py`

Monkeypatch `cli.subprocess.run` with a recorder that returns `returncode=0`. Its scp stub copies
files locally, so a restore has a real file to read. Never run real ssh or scp. Add:

1. **Remote backup command sequence.** With `DEST=m2-air:~/.local/backup`, assert the commands in
   order:
   - ssh `mkdir -p -- .local/backup`;
   - scp to `m2-air:.local/backup/.embeddings.sqlite.tmp`;
   - ssh `mv -f -- .local/backup/.embeddings.sqlite.tmp .local/backup/embeddings.sqlite`.

   Assert that no argument contains `~`, that the local temp directory is gone afterwards, and that
   the output names `m2-air:.local/backup/embeddings.sqlite`.
2. **A failed scp never runs the mv.** Make the scp return 1. Assert exit 1, `failed at scp` in
   stderr, no mv call, and the temp directory gone.
3. **A `.sqlite` destination names the file.** `host:backups/k3dm.sqlite` writes to
   `backups/k3dm.sqlite`.
4. **Local paths containing a colon stay local.** `tmp_path / "a:b"` is a local backup, with no
   subprocess calls.
5. **Remote restore.** With `SRC=m2-air:~/.local/backup`, the scp stub copies a fixture backup.
   Assert the vectors are restored and the scp source is `m2-air:.local/backup/embeddings.sqlite`.
6. **A remote path with a space is quoted.** In `host:~/my backups`, the ssh remote command contains
   `'my backups'`.

### File 4 — `docs/howto/find-prior-art.md`

In the "Second copy" paragraph, add one sentence: `DEST`/`SRC` may be `host:path`, for example
`make embed-cache-backup DEST=m2-air:~/.local/backup`. The copy goes over ssh/scp with the
operator's own keys, the directory is created when missing, and the file lands atomically.

### File 5 — `CHANGELOG.md`

Add one line to the embed-cache entry under `## [Unreleased]` → `### Added`.

## Rules

- Modify only Files 1–5. Do not touch `scripts/lib/`, or `scripts/lib/foundation/`.
- Never run real ssh, scp, or `make embed-cache-*`. Never touch the real `~/.cache/k3dm` or `~/.ssh`.
- Run and paste:
  - `python -m pytest scripts/tests/bin/test_embed_cache_cli.py -q`
  - `make -n embed-cache-backup DEST=m2-air:~/.local/backup`
- Mutations (snapshot first, then restore and check with `cmp`):
  - drop the `~/` rewrite, and show test 1 red;
  - scp straight to the final name with no `mv`, and show test 1 red;
  - run the mv even when scp fails, and show test 2 red.
- Do not run `make test`.
