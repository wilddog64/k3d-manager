# Bug: the bug dashboard counts offline-only fixes as "not live-verified" forever

**Status:** OPEN
**Priority:** P3 — the Verified vs Live-verified gap overstates outstanding live work; no fix is wrong, and the list can be read by hand.
**Severity:** low
**Release:** v1.43.6 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, during the verified-not-live sweep the operator approved ("go ahead")
**Approval:** pending — filed for triage; not dispatched.
**Component:** `bin/k3dm-vectordb-metrics` (`_bug_status_metrics`), `scripts/lib/hermes/prior_art.py` (`doc_verification`), `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, `scripts/check-bug-evidence.py`
**Related:** `docs/bugs/2026-10-17-bug-table-open-for-stops-at-fix-not-live-verify.md`

## Symptom

2026-10-24: the bugs dashboard showed Verified 67, Live-verified 46. The operator read the gap as
open live work. On the current tree, 31 fixed docs from v1.43.2 onward were VERIFIED but not
LIVE-VERIFIED:

- 10 had already passed their live check, and the Status line was never promoted. Those were
  promoted on 2026-10-24.
- Most of the other 21 have no live surface at all: a test fixture, a BATS expectation, a
  macOS-only test path. They can never become LIVE-VERIFIED, so the gap never closes.

## Root cause

A fixed doc has two verification states, `verified` and `live`. There is no third state for "live
check not applicable", so `_bug_status_metrics` sets `live_verified="false"` for every
offline-only fix.

## Fix

- **F1.** A new doc header `**Verification type:** offline`. When it is present, `doc_verification` returns
  `offline`, and the exporter emits `live_verified="n/a"` for that doc. The header requires a reason
  on the same line, for example `**Verification type:** offline — test-only fixture fix`.
- **F2.** The Live-verified stat stays as it is. Add an "Awaiting live check" stat:
  `verified="true", live_verified="false"`. Docs marked offline drop out of it.
- **F3.** `scripts/check-bug-evidence.py` rejects `offline` on a doc whose Component names a deployed
  path: `scripts/etc/argocd/`, `bin/k3dm-webhook`, or a plugin that a make lifecycle target runs.
  This stops the tag from being used to dodge a live check.
- **F4.** Docs: the verification states in `docs/guides/grafana-dashboards.md`.

## Acceptance

```yaml
must:
  - id: M1
    text: A fixed doc with "**Verification type:** offline — <reason>" exports live_verified="n/a".
  - id: M2
    text: The dashboard shows an Awaiting live check count that excludes offline-typed docs.
must_not:
  - id: N1
    text: A doc without the header must not change its exported labels (red on a mutant that defaults to n/a).
  - id: N2
    text: The offline type must be refused for a doc whose Component names a deployed path (red on the pre-fix checker, which accepts it).
  - id: N3
    text: The offline type without a reason must be refused.
evidence:
  - id: E1
    kind: offline
    proves: [M1, N1, N2, N3]
    text: pytest for the exporter and checker green; N1 and N2 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M2]
    text: After the dashboard syncs, the operator's screenshot shows Awaiting live check equal to the offline count of verified-not-live docs minus the offline-typed ones.
interface:
  - bin/k3dm-vectordb-metrics _bug_status_metrics (imported offline)
  - scripts/check-bug-evidence.py <doc paths>
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml
```
