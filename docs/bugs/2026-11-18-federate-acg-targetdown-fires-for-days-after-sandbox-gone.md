# Hub TargetDown{job=federate-acg} fires for days after the ACG sandbox is gone

**Status:** OPEN — captured 2026-11-18 (operator reported the alert email)
**Priority:** P3 — one warning email a day while no sandbox runs; no workaround needed, but it trains the operator to ignore TargetDown
**Triage:** backlog — pull into a release that already touches `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** pre-existing
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Alert noise where `TargetDown{job="federate-acg"}` sends a daily warning email after an ACG sandbox is torn down or expires.)
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md` (exact-slug review) — read, related (sandbox expiry leaves hub state behind), different object; `docs/bugs/2026-10-03-acg-sandbox-critical-alerts-send-sms.md` — read, routing only. `make find-similar-docs` not run.
**Filed:** 2026-11-18

## Facts (Claude, read-only, hub m5-air, 2026-11-18 ~16:00Z)

- Alertmanager `/api/v2/alerts`: `TargetDown{cluster="acg",job="federate-acg",severity="warning"}` active since
  2026-11-11T20:20Z (7 days, one continuous episode), receiver `platform-warning`, `repeat_interval: 24h`
  (`scripts/etc/prometheus/alertmanager.yaml.tmpl:13`), so one email a day.
- The scrape job is static: `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml:47-60`, target
  `host.internal:19190` (the port-forward `bin/cluster-up` starts for a live sandbox). On the hub `localhost:19190`
  does not answer and `kubectl --context ubuntu-k3s` times out against the old sandbox IP: no sandbox is running.
- So whenever no sandbox exists the hub alerts that the sandbox target is down. Nothing in teardown or expiry
  silences, inhibits or removes it.

## Fix options (for triage)

1. Exclude `job="federate-acg"` from TargetDown and add a sandbox-specific rule that fires only while a sandbox is
   registered (e.g. joined with a "sandbox registered" metric).
2. An Alertmanager inhibit rule: TargetDown{job="federate-acg"} inhibited while a "no sandbox" signal is present.
3. Teardown and expiry create a silence for it; `acg-up` expires that silence. (Weakest: missed when a sandbox
   expires on its own.)
