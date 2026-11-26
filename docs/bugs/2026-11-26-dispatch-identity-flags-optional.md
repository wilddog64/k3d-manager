# Bug: dispatch identity flags are optional, so Landed by and Primary coordinator read "not recorded"

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** pre-existing (flags added optional in v1.43.7 / v1.43.9)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Prior art:** `docs/bugs/2026-10-26-primary-coordinator-and-handoff-telemetry.md` (not scored: `make find-similar-docs` retrieval unavailable, cluster context missing) — read, same fields, different cause (that fix added capture; this is callers not passing the flags); `docs/bugs/2026-11-08-dispatch-dashboard-acting-coordinator-not-recorded-without-handoff.md` — read, Acting coordinator only, closed won't-fix
**Severity:** low — attribution columns in the Agent Dispatch "Per spec" table are blank; worker, cost and landing outcome metrics are intact
**Filed:** 2026-11-26, operator: "why land for this is not recorded?" (Per spec rows `m10b0b-windows-newline-tests`, `dirused-m10b4b-docs-drift`)
**Component:** `bin/k3dm-codex-dispatch` (`start`, `land`), `bin/k3dm-codex-land-pending`, Makefile `codex-land`

## Symptom

In the Agent Dispatch dashboard Per spec table, "Landed by" shows "not recorded" for `m10b0b-windows-newline-tests`, and
"Primary coordinator" shows "not recorded" for both rows (and for today's `v1460-p7a`).

## Cause (from the ledger, m4, 2026-11-26)

- `land` defaults `landing_actor=unknown` (`bin/k3dm-codex-dispatch:1356`) when `--landing-actor`/`--landing-model` are
  omitted. The `m10b0b` land event carries `{"actor":"unknown",...}`; the `dirused-m10b4b` one carries
  `{"actor":"claude","model":"claude-opus-5-5","source":"declared"}`. Last 14 days: 34 of 185 land events unknown.
- `start` records `primary_coordinator_identity` as unknown unless `--primary-coordinator` is passed. Last 14 days: 216 of
  218 `primary_coordinator` events unknown, although `--coordinator` was passed on most of them.
- The exporter (`bin/k3dm-dispatch-metrics:1176-1179`, `:1903-1905`) and dashboard mapping (`unknown` → "not recorded")
  are working as designed.

## Fix options (for triage)

1. `land` refuses without `--landing-actor` (allow an explicit `--landing-actor unknown` for human lands), or defaults
   it from a declared env var.
2. `start` defaults `--primary-coordinator` to `--coordinator` when only the latter is given (source `inferred`).
3. Process only: the coordinator always passes all three flags. In force from 2026-11-26 regardless of 1–2.

Historical rows are not backfilled.
