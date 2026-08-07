# Release Split — Intent Map (k3d-manager-v1.22.0 integration branch)

**Purpose:** `k3d-manager-v1.22.0` accreted 142 commits across 7 unrelated workstreams —
far past one sprint story. This map pins every workstream, its files, its state, and its
**open blockers** to a target release so nothing is orphaned when the branch is split.

**Archive:** `origin/k3d-manager-v1.22.0` (tip `03ed9ad6`, 142 commits) is kept intact as
`archive/k3d-manager-v1.22.0-integration`. Scoped release branches are cut fresh off `main`
(`f68bdee1`). No history is rewritten; nothing is lost.

---

## Workstreams

### A — OpenLDAP bitnami→Symas migration  ✅ DONE (live cutover complete)
- **Files:** `scripts/plugins/ldap.sh`, `scripts/etc/ldap/{values.yaml.tmpl,vars.sh,eso.yaml,bootstrap-basic-schema.ldif,ldap-password-rotator.sh,ldap-password-rotator.yaml.tmpl}`, `scripts/etc/jenkins/values-ldap.yaml.tmpl`, `scripts/etc/keycloak/vars.sh`, `scripts/plugins/{jenkins.sh,keycloak.sh}`, `scripts/tests/plugins/{ldap_chart_passwords.bats,openldap.sh}`, 1-line `scripts/etc/argocd/vars.sh`
- **Key commits:** `0b23884b` (chart migration), `c6195bb2` (durable platform users), `e9fa00cc` (consumer wiring), `7fb1ad28` (chart-safe passwords)
- **Blockers:** none. Ready to ship.

### B — CVE inventory dashboard + vulnerability exporter  ✅ mostly DONE (1 live-apply pending)
- **Files:** `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`, `.../grafana-dashboard-cve-autopatch.yaml`, `.../kustomization.yaml`, `.../prometheusrule.yaml`, `scripts/plugins/observability.sh` (partial), `scripts/plugins/argocd.sh` (app-cluster kubeconfig/reports), `scripts/etc/kube-prometheus-stack-values.yaml`, tests: `grafana_dashboard_cve_autopatch.bats`, `trivy_operator_observability.bats`, `cluster_status_observability.bats`
- **Blockers:** dashboard **v18 committed but not applied live** — waiting on Hub API tunnel `127.0.0.1:57780`.

### C — CVE remediation lifecycle (phases 2–6)  ✅ deployed (1 event stuck manual_review)
- **Files:** `scripts/etc/argocd/platform-ops/{app-cve-scan-cronjob.yaml,cve-remediation-verify.sh,app-cve-scan.sh}`, `scripts/plugins/argocd.sh` (verifier), `scripts/etc/argocd/vars.sh`, `scripts/tests/plugins/app_cve_scan.bats`
- **Blockers:** payment promotion event stuck `manual_review` (target digest ≠ deployed digest) — expected gate, not a defect, but note for closeout.

### D — Webhook parsing / rate-limit / auth-order hardening  ✅ DONE (live restart recorded)
- **Files:** `scripts/lib/webhook/auth.py`, `scripts/tests/lib/webhook.bats`
- **Key commit:** `9450efd7` (validate lengths + auth-before-limit + Slack allowlist), live restart `26831922`
- **Blockers:** none.

### E — Credential rotation (Grafana admin + monthly via Vault + Slack notify)  ⚠️ PARTIAL
- **Files:** `scripts/etc/argocd/platform-ops/{grafana-admin-externalsecret.yaml,grafana-credential-rotator.yaml}`, `scripts/plugins/{vault.sh,observability.sh}`, `scripts/tests/plugins/vault.bats`
- **Key commits:** `141cfa34`/`40c8b08e` (Grafana admin → Vault), `9d5e25c5`/`5f16d736` (monthly Grafana rotation CronJob), `79019fc9` (Slack rotation notify)
- **Blockers:** recurring automation exists ONLY for LDAP + Grafana. **ArgoCD / Prometheus / Alertmanager were rotated once by hand — automation NOT built** (consumers differ; needs per-service design).
- **⚠️ Grafana slice pulled forward early (2026-08-07)** — leaked Grafana admin password drove restoring the full Grafana→Vault wiring onto **v1.23.0** ahead of schedule:
  - `31db9732` — `Makefile` `show-service-passwords` Grafana hunk (`40c8b08e`).
  - `5b418dd7` — `grafana-admin-externalsecret.yaml` + `grafana-credential-rotator.yaml` (whole files), plus the Grafana hunks of `kube-prometheus-stack-values.yaml` (existingSecret), `observability.sh` (apply manifests + configure Vault role), `vault.sh` (`_vault_configure_secret_writer_role`, incl. `5f16d736` audience fix). Slack-notify (`79019fc9`) rotator additions came in via the whole-file restore.
  - **When cutting v1.24.0 for E, SKIP the entire Grafana slice** — it is already on main via v1.23.0. Remaining E for v1.24.0 = recurring rotation automation for **ArgoCD / Prometheus / Alertmanager** (still hand-rotated), and the LDAP-rotator Slack hunk of `79019fc9` if not already shipped.
  - **NOT yet deployed** — source-only; cluster was down at restore time. Live cutover (apply manifests, configure Vault role, restart Grafana to pick up `existingSecret`, rotate the password) is pending cluster bring-up.

### F — Hostinger Istio ambient drift + Hub shopping-cart destinations + Vault unseal watchdog  ✅ DONE
- **Files:** `scripts/etc/argocd/applicationsets/istio-ambient.yaml`, `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`, `scripts/lib/providers/k3s-hostinger.sh`, `scripts/plugins/vault.sh` (watchdog `1564febd`), `scripts/plugins/argocd.sh` (hub destinations `ae266bae`), tests: `argocd.bats`, `argocd_platform_ops_bootstrap.bats`, `provider_contract.bats`
- **Blockers:** none (operational fixes, live-verified).

### G — Stripe/Go live acceptance + Hostinger capacity right-sizing  ❌ BLOCKED (cross-repo)
- **Files (this repo):** `services/shopping-cart-{order,payment,product-catalog}/kustomization.yaml`, `scripts/lib/providers/k3s-hostinger.sh` (right-sizing overlays)
- **Cross-repo:** shopping-cart-order (`0e3feb9` schema fix on `fix/live-checkout-e2e-schema`, CI green, **unmerged**), shopping-cart-infra, shopping-cart-payment
- **Blockers:**
  1. **Live E2E 2/4 pass** — Stripe cases fail on `order_items.total_price NOT NULL` schema mismatch (Go wrote only `unit_price`). Needs order-repo fix **merged + image promoted**, then rerun acceptance.
  2. **Branch-protection override OPEN** — required-approval count dropped `1→0` on **shopping-cart-infra PR #89** and **shopping-cart-order PR #63**; per notes NOT restored. ⚠️ live security gap.
  3. Hostinger 2-CPU node capacity — right-sizing is a stopgap; capacity expansion is the permanent fix.

---

## Proposed release sequence (4 releases, each ≤5 plan docs)

| Release | Contents | State | Notes |
|---|---|---|---|
| **v1.22.0** | A (OpenLDAP Symas) | ship-ready | original branch intent; smallest, cleanest, ships first |
| **v1.23.0** | B + C (CVE observability + remediation lifecycle) | ~ready; 1 live-apply | aligns with existing `k3d-manager-v1.23.0` earmark; `argocd.sh` cohesive within |
| **v1.24.0** | D + E + F (webhook + credential rotation + istio/hostinger ops + unseal watchdog) | ready; E automation gap carried | security/ops hardening; `vault.sh` cohesive within (watchdog + rotation together) |
| **v1.25.0** | G (Stripe/Go live acceptance + hostinger capacity) | blocked | carries all cross-repo blockers + the approval-override restoration |

### Carried-forward open items (must not be lost)
- [ ] **v1.23.0:** apply CVE dashboard v18 live (Hub tunnel `127.0.0.1:57780`)
- [ ] **v1.23.0:** close out payment `manual_review` digest-mismatch event (verify or document as expected)
- [ ] **v1.24.0:** design recurring rotation for ArgoCD / Prometheus / Alertmanager (only LDAP+Grafana automated)
- [ ] **v1.25.0:** merge order-repo `0e3feb9` schema fix + promote image, rerun Stripe live E2E acceptance
- [ ] **v1.25.0:** hostinger capacity expansion (permanent fix; right-sizing is stopgap)
- [ ] **INDEPENDENT / DO NOW:** restore required-approval `0→1` on shopping-cart-infra #89 + shopping-cart-order #63 (live security gap — not gated on the release split)

### Split-execution hazards (shared files)
- `scripts/plugins/vault.sh` — E (grafana rotation) + F (unseal watchdog). Both land in **v1.24.0** → no cross-release conflict.
- `scripts/plugins/argocd.sh` — B + C (all CVE/platform-ops). Both land in **v1.23.0** → cohesive.
- `scripts/plugins/observability.sh` — B (dashboard) + E (grafana admin). **Splits across v1.23.0 and v1.24.0** → will need per-hunk selection when cutting.

---

## Execution method (per release, non-destructive)
1. `git checkout -b <branch> main`
2. Bring in only that workstream's files from the integration branch:
   `git checkout archive/k3d-manager-v1.22.0-integration -- <files>` (or per-hunk for the 1 shared file).
3. Rebuild memory-bank/CHANGELOG/plan-doc scoped to that release.
4. Run shellcheck + BATS on changed files. PR gates per CLAUDE.md. STOP for user go before PR.
