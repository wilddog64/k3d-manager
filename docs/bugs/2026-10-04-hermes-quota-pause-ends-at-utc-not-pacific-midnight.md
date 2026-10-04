# Bug: Hermes ends its quota pause at UTC midnight, but the Gemini daily quota resets at Pacific midnight

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — Codex, verified by Claude 2026-10-04: the `timezone.utc` mutation turns both reset tests red. Corrects an assumption in `2026-09-30-vectordb-index-never-refreshes-automatically.md`.
**Severity:** low. Each daily-quota hit costs most of an extra day of indexing.

## Observed

`bin/k3dm-hermes` `_refresh_index`, on `index-docs: paused`:

```python
            tomorrow = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
            metrics["paused_until"] = (tomorrow + timedelta(days=1)).timestamp()
```

The Gemini API resets requests-per-day quotas at midnight **Pacific** time. On 2026-10-04 the state
file held `index_paused_until = 2026-10-04 17:00` (local PDT), which is 00:00 UTC.

At 17:00 PDT the quota is still spent. So Hermes gets another 429 and pauses until 17:00 PDT the next
day. The quota resets at 00:00 PDT, 17 hours before Hermes looks again. Every quota hit therefore costs
about 17 extra hours.

The pause also uses `datetime.now()` and ignores the function's `now` argument, which makes it awkward
to test.

## Fix spec

### File 1 — `bin/k3dm-hermes`

- Add `from zoneinfo import ZoneInfo` and `QUOTA_RESET_TZ = ZoneInfo("America/Los_Angeles")`.
- Add a helper:

```python
def _next_quota_reset(now):
    """Return the epoch of the next 00:05 Pacific, when the Gemini per-day quota has reset."""
    local = datetime.fromtimestamp(now, QUOTA_RESET_TZ)
    reset = datetime.combine(local.date() + timedelta(days=1), datetime.min.time(),
                             tzinfo=QUOTA_RESET_TZ) + timedelta(minutes=5)
    return reset.timestamp()
```

  Building the reset from the date, not by adding 24 hours, keeps it at local 00:05 across DST changes.
  The 5-minute margin avoids a 429 right at the boundary, which would cost a whole day.
- Replace the two `tomorrow` lines with `metrics["paused_until"] = _next_quota_reset(now)`.

### File 2 — `scripts/tests/hermes/test_hermes.py`

- **Rename and rewrite.** Rename `test_refresh_index_paused_waits_for_next_utc_midnight` to
  `test_refresh_index_paused_waits_for_next_pacific_reset`.
  - Call `_refresh_index(state, now=<2026-10-04 16:42 PDT as epoch>)`.
  - Assert that `index_paused_until` equals 2026-10-05 00:05 PDT.
  - Keep the "no run before it" half, using `now=until - 60`.
- **Add a DST test:** `_next_quota_reset` at 2026-11-01 12:00 PST (the day DST ends) returns
  2026-11-02 00:05 PST. Build the expected value with `ZoneInfo`.

### File 3 — docs

- **`docs/guides/hermes.md`:** if it says the pause ends at UTC midnight, change that to 00:05 Pacific.
  Check with `grep -n -i "utc\|midnight" docs/guides/hermes.md`.
- **`docs/bugs/2026-09-30-vectordb-index-never-refreshes-automatically.md`:** add one line under its
  status, saying it is superseded on the reset time by this doc.
- **`CHANGELOG.md`:** add one `### Fixed` entry under `## [Unreleased]`.

## Rules

- Modify only Files 1–3. Do not touch `scripts/lib/foundation/`.
- Never run Hermes, kubectl, Gemini or `index-docs`.
- Run and paste: `python -m pytest scripts/tests/hermes -q`.
- Mutation (snapshot first, then restore and check with `cmp`): change the zone to `timezone.utc`, and
  show the renamed test red.
- Do not run `make test`.
