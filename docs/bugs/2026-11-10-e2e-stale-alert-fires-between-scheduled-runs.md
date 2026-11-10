# Bug: `E2EVerificationStale` fires every week between the Saturday and Wednesday e2e runs

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-10 (P3 batch; WIP 3/3 with the third-round-land P2)
**Introduced by:** `978ea60f` (v1.34.0, Hermes e2e schedule `wed,sat@02:00`), against the 3-day threshold from `d48e465f` (v1.25.0)
**Should have been caught by:** spec
**Prior art:** exact-slug glob: none. `make find-similar-docs` unavailable (vector store context missing on the M4, 2026-11-10). Read `docs/bugs/2026-10-11-e2e-stale-alert-fires-for-an-idle-runner.md` (different root cause: grouping by runner; fixed and live-verified 2026-10-24)
**Severity:** a false warning for about a day every week, even when every scheduled run passes. It trains the operator
to ignore the alert that should say the verification signal really is stale.
**Approval:** operator, 2026-11-10 (reported the alert email; filing follows the deep-dive-every-alert rule)
**Intent approved:** operator, 2026-11-10 ("approve P3 intents")
**Filed:** 2026-11-10
**Detected by:** operator, alert email 2026-11-10
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10 ~22:50Z, read-only over SSH)

- Rule `scripts/etc/argocd/platform-ops/prometheusrule.yaml:162-171`: `time() - max by (tier, exported_service,
  project) (e2e_last_success_timestamp_seconds) > 259200` (3 days), `for: 30m`.
- Schedule `scripts/lib/hermes/e2e_schedule.py:28`: default `wed,sat@02:00`; the M5 LaunchAgents set no
  `K3DM_HERMES_E2E_SCHEDULE` override. Saturday to Wednesday is **4 days**, longer than the threshold.
- The schedule ran as designed: M5 `~/.k3dm/hermes/e2e` holds claims `2026-10-31.json`, `2026-11-04.json`,
  `2026-11-07.json`.
- The m2 runner's newest result is `1794086864-5662` (vcluster/product-catalog, pass, 91/0) at 2026-11-07 21:27Z,
  with no run after it. Age at the alert ≈ 3.06 days. The next slot is Wed 2026-11-11 02:00 PST.
- Cosmetic, same rule: the static label `tier: e2e` (`:168`) overwrites the series' `tier="vcluster"`, so the email's
  labels say `tier = e2e` while its description says "vcluster substrate".

## Fix

Set the threshold to the longest scheduled gap plus margin: 4.5 days (`388800`), so one missed slot (a 7-day gap) still
fires and an on-time run never does. Update the summary and description text from ">3d"/"3 days" to ">4.5d"/"4.5 days".
Rename the static rule label `tier: e2e` to a label that does not collide (e.g. `alert_tier: e2e`), after checking the
Alertmanager routes that read it (Contract readers).

## Contract readers

- Alert label `tier` on `E2EVerificationStale`: Alertmanager routes and receivers that match `tier="e2e"` (grep
  `scripts/etc` for `tier` matchers before the change; the worker lists each with file:line and keeps routing
  identical). Writer: this rule only.
- `e2e_last_success_timestamp_seconds`: unchanged; readers the E2E dashboard and this rule.
- The Hermes schedule is not changed.

## Acceptance

```yaml
must:
  - id: M1
    text: "With the default wed,sat@02:00 schedule and every run passing, E2EVerificationStale never fires."
  - id: M2
    text: "When one scheduled run is missed (last success 7 days old), E2EVerificationStale fires."
must_not:
  - id: N1
    text: "The alert's routing does not change: it reaches the same receiver as before."
  - id: N2
    text: "The alert's labels never show tier=e2e for a vcluster series."
evidence:
  - {id: E1, proves: [M1, M2], kind: offline, intent: "You will see a promtool test where the last success is 4 days old (Saturday to Wednesday) and the alert stays quiet, and one where it is 7 days old and the alert fires; against today's rule the 4-day case fires."}
  - {id: E2, proves: [N1, N2], kind: offline, intent: "You will see the alert's labels keep tier=vcluster from the series, and an amtool route test send it to the same receiver as before."}
  - {id: E3, proves: [M1], kind: live, intent: "After make platform-ops, Claude reads the live rule on the hub and shows the 388800 threshold; the next Saturday-to-Wednesday gap passes with no alert email."}
interface:
  - "scripts/etc/argocd/platform-ops/prometheusrule.yaml (E2EVerificationStale)"
  - "promtool test rules; amtool config routes test"
```

## Worker definition of done

- Change only the rule file, its promtool test and any route test. Show E1's 4-day case red against today's rule, then
  green. Paste command, rc and proving lines. Leave changes uncommitted; Claude reviews and lands.
