# Bugfix: v1.16.0 — webhook `datetime.utcnow()` deprecation (and naive-timestamp latent bug)

**Branch:** `k3d-manager-v1.16.0`
**Files:** `bin/k3dm-webhook`

---

## Problem

Running the webhook on Homebrew Python 3.14 (after the `python@3.13`→`python@3.14` drift) emits
this on every affected call:

```
bin/k3dm-webhook:591: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled
for removal in a future version. Use timezone-aware objects to represent datetimes in UTC:
datetime.datetime.now(datetime.UTC).
```

`datetime.datetime.utcnow()` is deprecated in 3.12+ and slated for removal — once removed this
becomes a hard error, not a warning.

**Root cause:** `bin/k3dm-webhook` calls `datetime.datetime.utcnow().timestamp()` in 10 places.
Beyond the deprecation, this pattern is also **subtly incorrect**: `utcnow()` returns a *naive*
datetime (no `tzinfo`), and `.timestamp()` on a naive datetime interprets it as **local** time,
not UTC — so the resulting epoch value is off by the host's UTC offset. In the 9 elapsed-time
call sites the offset cancels (both endpoints share the same wrong offset, so the *difference* is
correct), but line **697** (`ts = str(int(datetime.datetime.utcnow().timestamp()))`) is an
**absolute** epoch used as the Pushgateway metrics-push timestamp — it is genuinely wrong by the
local offset. The timezone-aware replacement fixes the deprecation and this latent offset bug in
one change.

---

## Reproduction

1. `make restart-webhook` (webhook now runs on Python 3.14).
2. Trigger any job that measures elapsed time or pushes metrics (e.g. a `cluster-up`/`cluster-refresh`
   job, or a metrics push).
3. `tail ~/Library/Logs/k3dm-webhook.log` → `DeprecationWarning: datetime.datetime.utcnow() is deprecated`.

Expected: no deprecation warning; timestamps computed from a timezone-aware UTC value.

---

## Fix

### Change 1 — `bin/k3dm-webhook`: replace all naive `utcnow()` with timezone-aware UTC

Replace **every** occurrence of the exact substring:

```
datetime.datetime.utcnow()
```

with:

```
datetime.datetime.now(datetime.timezone.utc)
```

There are **10 occurrences**, at lines **491, 505, 543, 607, 618, 633, 678, 697, 1824, 1877**.
This is a pure substring replacement — the rest of each line (the `.timestamp()` call, arithmetic,
and surrounding code) is unchanged. No new import is required: `import datetime` already exists at
module level (line 4). Do **not** use `datetime.UTC` — use `datetime.timezone.utc`, which is
portable to all supported Python versions.

**Representative before/after** (the same transform applies to all 10 lines):

Line 491 / 607 (identical):
```python
    _start = datetime.datetime.utcnow().timestamp()
```
→
```python
    _start = datetime.datetime.now(datetime.timezone.utc).timestamp()
```

Line 505 / 618 (identical):
```python
        elapsed = int((datetime.datetime.utcnow().timestamp() - _start) / 60)
```
→
```python
        elapsed = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - _start) / 60)
```

Line 543 / 633 (identical):
```python
        elapsed_secs = int(datetime.datetime.utcnow().timestamp() - _start)
```
→
```python
        elapsed_secs = int(datetime.datetime.now(datetime.timezone.utc).timestamp() - _start)
```

Line 678:
```python
        now = datetime.datetime.utcnow().timestamp()
```
→
```python
        now = datetime.datetime.now(datetime.timezone.utc).timestamp()
```

Line 697:
```python
    ts = str(int(datetime.datetime.utcnow().timestamp()))
```
→
```python
    ts = str(int(datetime.datetime.now(datetime.timezone.utc).timestamp()))
```

Line 1824:
```python
            elapsed = int((datetime.datetime.utcnow().timestamp() - mtime) / 60)
```
→
```python
            elapsed = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - mtime) / 60)
```

Line 1877:
```python
                    age_min = int((datetime.datetime.utcnow().timestamp() - int(parts[0])) / 60)
```
→
```python
                    age_min = int((datetime.datetime.now(datetime.timezone.utc).timestamp() - int(parts[0])) / 60)
```

> Note: line 2518 has a redundant local `import datetime` inside a function — leave it as-is
> (out of scope; harmless).

---

## Files Changed

| File | Change |
|------|--------|
| `bin/k3dm-webhook` | 10× `datetime.datetime.utcnow()` → `datetime.datetime.now(datetime.timezone.utc)` |

---

## Rules

- Only `bin/k3dm-webhook` is touched. No other files.
- After the change, **zero** occurrences of `utcnow` must remain:
  `grep -c 'utcnow' bin/k3dm-webhook` → `0`.
- Exactly **10** occurrences of the new form must exist:
  `grep -c 'datetime.datetime.now(datetime.timezone.utc)' bin/k3dm-webhook` → `10`.
- File must still parse: `python3 -c "import ast; ast.parse(open('bin/k3dm-webhook').read())"` → exit 0.
- Do not add or remove any `import`. Do not change `.timestamp()`, arithmetic, or any surrounding logic.
- Do not touch the redundant local `import datetime` at line 2518.

---

## Definition of Done

- [ ] `grep -c 'utcnow' bin/k3dm-webhook` returns `0`.
- [ ] `grep -c 'datetime.datetime.now(datetime.timezone.utc)' bin/k3dm-webhook` returns `10`.
- [ ] `python3 -c "import ast; ast.parse(open('bin/k3dm-webhook').read())"` exits 0.
- [ ] No other file changed (`git show --stat` lists only `bin/k3dm-webhook`).
- [ ] Committed and pushed to `k3d-manager-v1.16.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(webhook): use timezone-aware UTC timestamps (drop deprecated datetime.utcnow)
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Claude will `make restart-webhook` (already on Python 3.14), trigger a metrics-push / elapsed-time
job, and confirm `~/Library/Logs/k3dm-webhook.log` no longer emits the `utcnow` DeprecationWarning
and that `/api/v1/health` still returns 200 for all services.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `bin/k3dm-webhook`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT use `datetime.UTC` (use `datetime.timezone.utc`).
- Do NOT add a new `import time` or refactor to `time.time()` — keep the change to the minimal
  substring replacement so the diff stays reviewable.
- Do NOT touch the redundant local `import datetime` at line 2518.
