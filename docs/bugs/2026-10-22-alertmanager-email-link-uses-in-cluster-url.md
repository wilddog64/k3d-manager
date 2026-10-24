# Bug: alert email "View In Alertmanager" link points at the in-cluster service address

**Filed:** 2026-10-22 (Claude, from the operator's HubDataExportFailed email)
**Status:** OPEN
**Priority:** P3 — cosmetic; the alert state is reachable at `https://alertmanager.3ai-talk.org`
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "yes" (file as P3)
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`
**Related:** `docs/bugs/archive/2026-08-20-pre-v1.26/2026-06-30-alertmanager-login-basic-auth.md`
(public login gate); `docs/howto/argocd-alerts.md`

## Symptom

The hub's alert emails have a **View In Alertmanager** button linking to
`http://kube-prometheus-stack-alertmanager.monitoring:9093/#/alerts?receiver=...`. Safari reports
"can't find the server": that name only resolves inside the cluster.

## Root cause

The hub Alertmanager has no `externalUrl` set, so the operator uses the default service address
(live: `kubectl -n monitoring get alertmanager` shows
`externalUrl=http://kube-prometheus-stack-alertmanager.monitoring:9093`). Alertmanager builds
every notification's `.ExternalURL` from it.

The public, login-gated address already exists: `scripts/etc/cloudflared/config.yml` routes
`alertmanager.3ai-talk.org` to the local `bin/alertmanager-auth-proxy` on `127.0.0.1:9093`.

## Fix

- **F1.** In `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, set
  `alertmanager.alertmanagerSpec.externalUrl: https://alertmanager.3ai-talk.org`. Leave
  `kube-prometheus-stack-acg-values.yaml` unchanged: ACG sandbox Alertmanager has no public route.
- **F2.** Offline test: the hub values set exactly that `externalUrl`; the acg values set none.
- **F3.** `docs/howto/argocd-alerts.md`: one line saying the email button opens the public login
  page, and that `http://127.0.0.1:9093` (not `localhost`, which Safari tries over IPv6) is the
  local route through the same proxy.
- **F4.** `CHANGELOG.md` entry.

## Files

- `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`
- a test under `scripts/tests/` (new or existing file)
- `docs/howto/argocd-alerts.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: The hub kube-prometheus-stack values set alertmanager.alertmanagerSpec.externalUrl to https://alertmanager.3ai-talk.org.
  - id: M2
    text: argocd-alerts.md tells the reader the email button opens the public login page and names http://127.0.0.1:9093 as the local route.
must_not:
  - id: N1
    text: The hub values must not leave externalUrl unset or pointing at a *.svc / *.monitoring in-cluster host (test red on the pre-fix values file).
  - id: N2
    text: The acg values must not gain an externalUrl.
  - id: N3
    text: No other Alertmanager setting (routes, receivers, resources) changes.
evidence:
  - id: E1
    kind: offline
    proves: [M1, N1, N2, N3]
    text: The new test passes; it fails against the pre-fix hub values file.
  - id: E2
    kind: live
    proves: [M1]
    text: After the hub monitoring stack is synced from the release branch, kubectl -n monitoring get alertmanager shows the new externalUrl, and the next alert email's button opens the login page.
interface:
  - scripts/etc/helm/observability/kube-prometheus-stack-values.yaml (alertmanager.alertmanagerSpec.externalUrl)
  - Alertmanager CR kube-prometheus-stack-alertmanager in namespace monitoring (spec.externalUrl)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix values file.
- [ ] Commit: `fix(alerts): link alert emails to the public Alertmanager login page`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT touch any cluster or run a helm upgrade; live steps are Claude's and the operator's.
- Do NOT change the auth proxy, cloudflared config or Alertmanager routing.
