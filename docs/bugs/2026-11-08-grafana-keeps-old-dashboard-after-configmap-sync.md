# Bug: Grafana keeps serving the old dashboard after Argo CD syncs a changed dashboard ConfigMap

**Status:** OPEN — filed; root cause unknown
**Priority:** P3
**Waiting on:** investigation — since 2026-11-08
**Introduced by:** unknown
**Should have been caught by:** live check
**Severity:** low — a dashboard fix looks unfixed until Grafana restarts; the operator can misread a deployed fix as a failed one. Workaround: `kubectl -n monitoring rollout restart deploy/kube-prometheus-stack-grafana`.
**Approval:** operator, 2026-11-08 ("go ahead to file those")
**Filed:** 2026-11-08
**Detected by:** operator, Codex spend panel screenshots after the second `deploy/hub` promote
**Affected:** Grafana dashboard sidecar on the M5 hub (kube-prometheus-stack `67.9.0`, Grafana 11.4.0)
**Related:** memory `reference_bugs_dashboard_deploys_via_argocd_not_platform_ops` (Argo CD repo-cache lag, a different, earlier stage)

## Symptom

After `deploy/hub` moved to `61195319` (2026-11-08):
- Argo CD app `cicd/hub-grafana-dashboards`: `Synced`, revisions `61195319…` on both sources.
- ConfigMap `monitoring/grafana-dashboard-agent-cost`: last write 2026-11-08T13:52:19Z.
- Grafana still showed the old Codex spend by category panel (vertical bars, a "Value" bar), even after a hard
  reload in the browser.
- `kubectl -n monitoring rollout restart deploy -l app.kubernetes.io/name=grafana` fixed it at once.

## Investigation (read-only, operator on M5; Claude reads the output)

Not dispatchable until the cause is shown on the deployed versions (CLAUDE.md: prove external behaviour before
dispatch). Next time a dashboard ConfigMap changes, before restarting Grafana:

1. `kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana -c grafana-sc-dashboard --since=30m | tail -40`
   (did the sidecar see the change and write the file?)
2. `kubectl -n monitoring get deploy kube-prometheus-stack-grafana -o jsonpath='{.spec.template.spec.containers[*].image}'`
   (sidecar and Grafana versions)
3. `kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -c grafana -- ls -l /tmp/dashboards`
   (file timestamp against the ConfigMap write; path may differ, see the sidecar's `FOLDER` env)

Candidate causes, unproven: the sidecar misses updates made by a server-side apply; the sidecar writes the file but
Grafana's file provisioner does not reload it; the dashboard JSON keeps the same `version` and Grafana skips it.
