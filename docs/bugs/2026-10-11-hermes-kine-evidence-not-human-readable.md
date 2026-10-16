# Bug: the Hermes `kine` finding shows raw bytes and seconds

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** LIVE-VERIFIED 2026-10-11 (`40f99b0e`, v1.43.2); live: the next Hermes cycle logged `last compaction 8d 10h ago; state.db 1.9 GiB; slow SQL 11; compaction failed: no` — live proof complete
**Approval:** explicit 2026-10-11 "can we make number more human readable" (operator, Hermes Status screenshot)
**Priority:** P3 — cosmetic; the numbers are correct
**Severity:** low

## Symptom

The Hermes Status dashboard's "Current Hermes findings" row for `kine` reads
`state.db=2043133952B, slow_sql=17, compaction_recent=False, compaction_failed=False, last_compaction_age=726883s`.
The table cuts it off after `compaction_recent=Fa`, so the stall age, the most important number,
is never visible. 2043133952 B is 1.9 GiB, and 726883 s is 8 days 9 hours.

## Root cause

`kine` in `scripts/lib/hermes/sensors.py` formats `db_bytes` and the compaction age as raw
integers and puts the age last.

The evidence string is also a label on `hermes_sensor_status`
(`vulnerability-inventory-exporter.yaml`, `metric_labels`). Every cycle with a new byte count or a
new age in seconds is a new series, so "Sensor status history" gains a `kine` legend line per poll.
Coarser units fix readability and cut that churn.

## Fix

`scripts/lib/hermes/sensors.py` only:

1. Add two private helpers next to `kine`:
   - `_human_bytes(n)`: binary units, one decimal place, `B`/`KiB`/`MiB`/`GiB`/`TiB`. So `2043133952`
     → `1.9 GiB`, `554 * 1024 * 1024` → `554.0 MiB`, `512` → `512 B`.
   - `_human_age(seconds)`: under 60 s → `<1m`; under 1 h → `<N>m`; under 1 day → `<H>h <M>m`;
     otherwise `<D>d <H>h`. So `240` → `4m`, `3600` → `1h 0m`, `726883` → `8d 9h`.
2. Degraded evidence, the stall first so it survives truncation:
   - with a timestamp: `last compaction 8d 9h ago; state.db 1.9 GiB; slow SQL 17; compaction failed: no`
   - without one (an older probe): `state.db 1.9 GiB; slow SQL 17; compaction recent: no; compaction failed: no`
   - `compaction failed: yes` when `failed`.
3. Healthy evidence: `state.db 1.9 GiB; last compaction 4m ago` (no age part when absent:
   `state.db 1.9 GiB; compaction recent`).
4. `data` is unchanged: raw integers and the epoch timestamp stay there for repairs and metrics.

Out of scope: other sensors, the dashboard JSON and the exporter.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/sensors.py` | helpers + evidence wording |
| `scripts/tests/hermes/test_hermes.py` | assertions |
| `docs/guides/hermes.md` | the `kine` row example, if it quotes the old format |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Tests

`scripts/tests/hermes/test_hermes.py`:
- `_human_bytes` and `_human_age`: each example above, plus the boundaries `59` → `<1m`,
  `60` → `1m`, `86399` → `23h 59m`, `86400` → `1d 0h`, `1023` → `1023 B`, `1024` → `1.0 KiB`.
- The quiet-stall test asserts the evidence starts with `last compaction 1h 0m ago;` (replaces the
  `last_compaction_age=3600s` assertion).
- A degraded record with `compaction_failed` true contains `compaction failed: yes`.
- A healthy record contains `GiB` or `MiB` and no digit run of 7 or more (`not re.search(r"\d{7,}", evidence)`).
- `data["state_db_bytes"]` is still the raw integer.

Mutations (each must turn a test red): swap the age units (hours shown as minutes); move the stall
age to the end of the degraded evidence; put raw `db_bytes` back in the healthy evidence.

## Proof it works

The next Hermes cycle after landing (Hermes runs from the checkout): the dashboard row reads
`last compaction 8d … ago; state.db 1.9 GiB; …`, and the `kine` legend lines in Sensor status history
stop gaining a new entry every poll (the age changes only once an hour while it is over a day).

## What NOT to Do

- Do NOT change `data` keys or values; `repairs.py` and the kine metrics push read them.
- Do NOT change the degraded/healthy logic or thresholds.
- Do NOT edit the dashboard or exporter.
