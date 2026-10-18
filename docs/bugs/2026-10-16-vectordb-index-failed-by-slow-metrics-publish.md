# Bug: a slow metrics publish marks a completed VectorDB index run as failed (2026-10-16)

**Status:** LIVE-VERIFIED — 2026-10-16: Hermes index pass at 21:35:33Z (fix in the Hermes working tree since 14:49Z) published `k3dm_vectordb_index_last_result{result="success"} 1`, `failed` 0 (Pushgateway :19094, read by Claude). Landed `b7afa46d` (Codex; Claude verified: pytest 136/136, all 6 new tests red on the old code, all 4 mutations red).
**Priority:** P3 — the index itself succeeds and the next pass self-heals; only the Last run result tile and its history are wrong
**Branch:** `k3d-manager-v1.43.3`
**Release:** v1.43.3
**Filed:** 2026-10-16, at operator request
**Approval:** explicit 2026-10-16 "yes, go ahead to open a P3 bug" (operator)
**Component:** `scripts/index-docs.py`, `bin/k3dm-hermes`, `bin/k3dm-vectordb-metrics`, `scripts/bug-tally.py`
**Related:** `docs/bugs/2026-09-30-vectordb-index-never-refreshes-automatically.md` (introduced the Hermes
index refresh), `docs/plans/v1.43.2-bug-dashboard-live-verified-column.md` (latest change to the
bug metrics in `k3dm-vectordb-metrics`)

## Observed

The **VectorDB** dashboard tile **Last run result (last published)** showed `failed` (red).
Read-only checks on 2026-10-16:

- Hub: `k3dm_vectordb_index_last_result{result="failed"} = 1`; the last success was about 23
  minutes earlier; the index duration was 213–237s.
- `~/Library/Logs/k3dm-hermes.log`:

  ```text
  vectordb index failed: subprocess.TimeoutExpired: Command '['…/bin/k3dm-vectordb-metrics']' timed out after 120 seconds
  ```

- The Mac's load average was about 10–11 at the time (concurrent BATS, mutation and Codex
  `make test` runs).
- The next pass succeeded (`result="success"`), with no change.

## Root cause

1. **A metrics side effect fails the index run.** `scripts/index-docs.py` ends, after the index is
   written and its summary printed, with an unguarded
   `subprocess.run([... "k3dm-vectordb-metrics"], timeout=120, check=False)`. `check=False` does
   not cover a timeout: `TimeoutExpired` escapes `main()`, the script exits non-zero, and
   `_refresh_index` in `bin/k3dm-hermes` records `result="failed"`, uses the traceback's last line as
   the reason, and does not save the fingerprint, so the next pass indexes again.
2. **Hermes has the same unguarded call on every poll.** `_publish_health_metrics` runs the same
   command with `timeout=120` and no `try`. A timeout there raises out of the poll *before*
   `_publish_disk_metrics`, `_schedule_e2e` and `_save_state`, so the whole poll's state is lost.
   `_publish_disk_metrics` beside it already has the guard.
3. **The bug metrics fork one git process per doc, three times.** With a `ref`, `_bug_texts` in
   `bin/k3dm-vectordb-metrics` runs one `git show <ref>:<path>` per bug doc, and is called twice
   per run (`_bug_metrics` and `_bug_status_metrics`). `scripts/bug-tally.py`, which the same run
   calls, reads every doc the same way again. Measured 2026-10-16 at load ~8 on 756 docs: per-file
   `git show` 7.3s, one `git cat-file --batch` 0.2s. The cost grows with every bug filed, and under
   load it pushes the run past 120s.

## Fix

Work only in the worktree and branch you were launched in. Read the four Component files in full
first, plus `scripts/tests/bin/test_index_docs.py`, `scripts/tests/bin/test_vectordb_bug_metrics.py`
and `scripts/tests/bin/test_bug_tally.py`.

### 1. `scripts/index-docs.py`: the metrics publish never fails the run

Replace

```python
    subprocess.run([str(ROOT / "bin" / "k3dm-vectordb-metrics")],
                   cwd=ROOT, capture_output=True, text=True, timeout=120, check=False)
    return 0
```

with

```python
    try:
        subprocess.run([str(ROOT / "bin" / "k3dm-vectordb-metrics")],
                       cwd=ROOT, capture_output=True, text=True, timeout=120, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"index-docs: metrics publish skipped: {exc}", file=sys.stderr)
    return 0
```

### 2. `bin/k3dm-hermes`, `_publish_health_metrics`: guard like `_publish_disk_metrics`

Wrap the existing `subprocess.run(...)` in `try:` / `except Exception as exc:` printing
`f"vectordb health metrics publish skipped: {exc}"` to stderr, the same shape as
`_publish_disk_metrics`. No other change in `k3dm-hermes`.

### 3. One batch read of the bug docs

**3a. `bin/k3dm-vectordb-metrics`, `_bug_texts`:** in the `if ref:` branch, keep the `ls-tree`
listing and the `paths` filter, and replace the per-path `git show` dict with one
`git cat-file --batch` call:

```python
        request = "".join(f"{ref}:{p}\n" for p in paths).encode()
        blob = subprocess.run(["git", "-C", str(root), "cat-file", "--batch"], input=request,
                              capture_output=True, check=True, timeout=60).stdout
        texts = {}
        offset = 0
        for p in paths:
            header_end = blob.index(b"\n", offset)
            header = blob[offset:header_end].split()
            if len(header) != 3 or header[1] != b"blob":
                raise RuntimeError(f"git cat-file: unexpected header for {p}: {blob[offset:header_end]!r}")
            start = header_end + 1
            size = int(header[2])
            texts[p] = blob[start:start + size].decode("utf-8")
            offset = start + size + 1
```

A missing object prints `<name> missing`, which has two fields and raises, as the old
`check=True` did. The working-tree branch (`ref` empty) is unchanged.

**3b. Read once per run.** `_bug_metrics` and `_bug_status_metrics` must not each call
`_bug_texts`. Have `publish_bug_metrics` read the texts once and pass them in: add an optional
`texts=None` parameter to both functions, used in place of `_bug_texts(root, ref)` when given. Their
existing callers and tests keep working without it.

**3c. `scripts/bug-tally.py`, `tally`:** replace the per-path `_git("show", f"{ref}:{path}")` with
texts read up front by one `git cat-file --batch`, using the same parsing as 3a in a small
`_read_blobs(ref, paths)` helper in this file. Decode as UTF-8, as `_git` does today. No other
change to the tally: same output, same JSON.

### 4. Docs

- `docs/guides/vector-store.md`, where it describes the Hermes index refresh (add a short
  paragraph if it has none): one sentence saying that the VectorDB dashboard's **Last run result**
  `failed` means the index run itself failed; a metrics publish failure is logged as
  `metrics publish skipped` and does not count.
- `CHANGELOG.md` `[Unreleased]`: one `Fixed:` entry.

## Files

| File | Change |
|---|---|
| `scripts/index-docs.py` | item 1 |
| `bin/k3dm-hermes` | item 2 |
| `bin/k3dm-vectordb-metrics` | items 3a, 3b |
| `scripts/bug-tally.py` | item 3c |
| `scripts/tests/bin/test_index_docs.py`, `scripts/tests/bin/test_vectordb_bug_metrics.py`, `scripts/tests/bin/test_bug_tally.py`, and the Hermes test file that covers `_publish_disk_metrics` (find it with `grep -rln _publish_disk_metrics scripts/tests`) | tests below |
| `docs/guides/vector-store.md`, `CHANGELOG.md` | item 4 |

No other file.

## Tests (each new one shown failing against the pre-change code, on a temp copy)

No test may run the real `k3dm-vectordb-metrics` or push to any Pushgateway. Use temp git repos
for the git reads.

1. `test_index_docs.py`: with the metrics `subprocess.run` raising `TimeoutExpired`, `main()`
   still returns 0 and stderr contains `metrics publish skipped`.
2. Hermes: `_publish_health_metrics` with `subprocess.run` raising `TimeoutExpired` returns
   normally and prints `vectordb health metrics publish skipped`.
3. `test_vectordb_bug_metrics.py`, in a temp repo with three committed bug docs (one with
   non-ASCII text):
   - `_bug_texts(root, "HEAD")` returns exactly the committed texts;
   - it starts **one** `git cat-file` process and **no** `git show` (count the calls with a
     `subprocess.run` wrapper);
   - a ref where a listed path is missing raises.
4. `publish_bug_metrics` reads the bug texts once (count `_bug_texts` calls: 1).
5. `test_bug_tally.py`: `tally` on the temp repo gives the same result as before, with no
   `git show` call.
6. Every existing test in these files stays green.

### Mutations (Claude, at verification)

Each must turn a test red:

- drop the `except` in item 1;
- drop the `try` in item 2;
- `_bug_texts` falls back to per-path `git show`;
- `publish_bug_metrics` stops passing `texts`.

## Operational Requirements

| Item | Requirement |
|---|---|
| Resources | About 2,300 fewer `git` processes per metrics run at today's 756 docs. No new series. |
| Rollback | Revert. No state change; the next Hermes poll republishes. |
| Proof it works | Hermes runs from this checkout, so the change applies on its next poll after landing. `k3dm_vectordb_index_last_result` stays `success` or `noop` across an index pass, and a timed `bin/k3dm-vectordb-metrics` run (operator) finishes well under 120s. |

## Definition of Done

- [ ] Items 1–4 exactly as written.
- [ ] `python3 -m pytest -q` on the four test files is green; paste the tail.
- [ ] No test pushes to a real Pushgateway.
- [ ] Leave the changes **uncommitted**. Claude verifies, commits and lands them with:
  `fix(vectordb): a slow metrics publish no longer fails the index run`

## What NOT to Do

- Do NOT run `bin/k3dm-vectordb-metrics`, `bin/k3dm-hermes` or `index-docs.py` against the real
  store, hub or Pushgateway.
- Do NOT change the 120s timeouts, the Hermes poll interval, the metric names or labels, or the
  index logic.
- Do NOT change `doc_status`, `doc_meta` or `doc_verification`.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.
- Do NOT modify files outside the Files table, including `memory-bank/`.
