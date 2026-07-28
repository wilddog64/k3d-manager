# Copilot PR #108 Review Findings — v1.18.0 (first-mile CVE gap closure)

**PR:** [#108](https://github.com/wilddog64/k3d-manager/pull/108)
**Date:** 2026-07-28
**Reviewer:** `copilot-pull-request-reviewer[bot]` (3 inline comments; CI green)

---

## Finding 1 — `scripts/etc/argocd/platform-ops/prometheusrule.yaml:76` (FIXED)

**Flagged:** the alert `description` contained the placeholder text `vulnerabilit(y/ies)`, which renders **verbatim** in Alertmanager/Grafana notifications instead of a real word.

**Fix:**

Before:
```yaml
description: "{{ $value }} Critical vulnerabilit(y/ies) in {{ $labels.image_repository }} (ns {{ $labels.namespace }}); event-driven app-cve-scan will attempt promotion/rebuild."
```
After:
```yaml
description: "{{ $value }} critical vulnerabilities in {{ $labels.image_repository }} (ns {{ $labels.namespace }}); event-driven app-cve-scan will attempt promotion/rebuild."
```

**Root cause:** shorthand `(y/ies)` pluralization notation left in a string that becomes user-facing notification text. `{{ $value }}` already carries the count, so a flat plural ("vulnerabilities") reads correctly for any count.

**Process note:** any string in a `PrometheusRule` `summary`/`description` is operator-facing — no `(x/xs)` or `TODO`-style placeholders in alert annotations.

---

## Finding 2 — `scripts/tests/lib/webhook.bats:291` (FIXED)

**Flagged:** a `[[ ... || ... ]]` assertion with two **identical** patterns — redundant OR, no added coverage.

**Fix:**

Before:
```bash
[[ "$output" == *'"skipped_on_cooldown":[{'* || "$output" == *'"skipped_on_cooldown":[{'* ]]
```
After:
```bash
[[ "$output" == *'"skipped_on_cooldown":[{'* ]]
```

**Root cause:** copy/paste of the left operand into the right operand of the OR when the assertion was written.

**Process note:** a `||` with matching operands is always a mistake — collapse to a single check.

---

## Finding 3 — `Makefile:395` (DECLINED — intentional)

**Flagged:** `make show-service-passwords` prints hard-coded dev Keycloak credentials (`admin / Shopping1!`, `developer / Dev1234!`, `operator / Ops5678!`).

**Decision:** decline. This target is a **dev-only local convenience** whose entire purpose (the v1.18.0 fix `ad96c028`, which replaced the stale `alice/test1234`) is to surface the fixed **seed** credentials the setup provisions for the local cluster. The sensitive value — the Keycloak *admin* password — is already fetched dynamically from the `keycloak-secrets` Secret, never hardcoded. The dev-user passwords are deterministic seed fixtures, not secrets; hiding them would defeat the helper. Output goes to the operator's own terminal and is never committed as data.

**Guardrail unchanged:** per CLAUDE.md, test credentials remain dev-only and must never appear in a **production** config path — this Makefile helper is not one.

---

## Summary

| # | File:line | Verdict | Fix commit |
|---|-----------|---------|------------|
| 1 | `prometheusrule.yaml:76` | Fixed | (see PR) |
| 2 | `webhook.bats:291` | Fixed | (see PR) |
| 3 | `Makefile:395` | Declined (intentional dev helper) | — |
