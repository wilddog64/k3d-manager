# Copilot PR #111 Review Findings — v1.22.0 OpenLDAP Symas migration

**PR:** https://github.com/wilddog64/k3d-manager/pull/111
**Date:** 2026-08-07
**Reviewer:** Copilot (1 review, 3 inline comments)

Three findings on the OpenLDAP bitnami→Symas migration. Two fixed, one declined with
justification.

---

## Finding 1 — `base64 -d` is GNU-specific (FIXED)

**File:** `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl:187`
Copilot: the rotator manifest decodes the Slack webhook secret with `base64 -d`, which is
GNU-specific; use the portable `base64 --decode` form to match the repo convention.

**Fix:**
```diff
-            -o jsonpath='{.data.slack-incoming-webhook-url}' 2>/dev/null | base64 -d || true)
+            -o jsonpath='{.data.slack-incoming-webhook-url}' 2>/dev/null | base64 --decode || true)
```

**Root cause:** carried the short flag from an earlier draft; the same convention fix landed in
v1.21.0 (`Makefile` `base64 -d`→`--decode`). Process note: prefer `base64 --decode` in all new
in-pod shell.

---

## Finding 2 — Slack-notify RBAC uses a ClusterRole (DECLINED, justified)

**File:** `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl:254–276`
Copilot: the notifier access is a single namespaced `get` on `platform-ops-notifications`, so a
namespace-scoped Role + RoleBinding in `platform-ops` would be tighter than a ClusterRole/
ClusterRoleBinding.

**Decision: keep the ClusterRole, justified per CLAUDE.md "ClusterRoles must be justified".**
- The `platform-ops` namespace is created and owned by `deploy_argocd_platform_ops`
  (`scripts/plugins/argocd.sh`), **not** by `deploy_ldap`. There is no guaranteed ordering
  between the two entrypoints — on a cold bring-up where LDAP deploys before the platform-ops
  tier, a Role/RoleBinding targeting `platform-ops` would fail to apply and break the rotator
  install. A ClusterRole/ClusterRoleBinding is cluster-scoped and order-independent, keeping the
  best-effort Slack notification (`|| true`) from becoming a hard cross-namespace deploy dependency.
- The ClusterRole is already `resourceNames`-scoped to the single secret
  `platform-ops-notifications` with only `get` — the residual over-privilege (any-namespace vs
  one-namespace, for one specifically-named secret) is marginal.
- Owning `platform-ops`'s namespace lifecycle from `deploy_ldap` (to make a namespaced Role safe)
  would collide with argocd.sh's ownership/labels — out of scope and worse coupling.

If a future release guarantees `platform-ops` exists before `deploy_ldap`, this can be revisited
as a namespaced Role.

---

## Finding 3 — LDIF import checks the stale Bitnami mount path (FIXED)

**File:** `scripts/plugins/ldap.sh:707,720`
Copilot: `_ldap_import_ldif` now gates on a ConfigMap-based bootstrap (`customLdifCm`) but still
checks the LDIF file at the old Bitnami mount path (`/ldif_import/bootstrap.ldif`) and logs "LDIF
secret" even though it is a ConfigMap — the post-deploy import silently no-ops.

**Verified live** (hub `k3d-k3d-cluster`, pod `openldap-0`): the Symas chart mounts `customLdifCm`
at `/ldifs/bootstrap.ldif`; `/ldif_import` does not exist. With `LDAP_LDIF_ENABLED` defaulting to
`true` and `LDAP_LDIF_MOUNT_PATH` unset, the `test -f /ldif_import/bootstrap.ldif` guard always
failed, so the post-deploy idempotent re-import **and** the test-user password reset that follows
it were silently skipped. The release still seeded correctly only because the chart imports the
ConfigMap at container startup; the post-deploy helper was dead.

**Fix:**
```diff
-   local ldif_mount_path="${LDAP_LDIF_MOUNT_PATH:-/ldif_import/bootstrap.ldif}"
+   local ldif_mount_path="${LDAP_LDIF_MOUNT_PATH:-/ldifs/bootstrap.ldif}"
```
```diff
-      _info "[ldap] LDIF secret ${ns}/${ldif_secret} not found; skipping LDIF import"
+      _info "[ldap] LDIF ConfigMap ${ns}/${ldif_secret} not found; skipping LDIF import"
```

**Root cause:** the mount-path default was carried over from the Bitnami chart, whose LDIF volume
lived at `/ldif_import`; the Symas `jp-gouin/openldap-stack-ha` chart uses `/ldifs`. The log
string likewise predated the Secret→ConfigMap switch. Process note: when swapping a Helm chart,
re-verify every hardcoded in-pod path/mount default against the new chart's contract.

---

## Validation

- `shellcheck -S warning scripts/plugins/ldap.sh` — clean
- `bats scripts/tests/plugins/ldap_chart_passwords.bats` — 2/2 green
- Finding 3 mount path confirmed against the live `openldap-0` pod (`/ldifs/bootstrap.ldif`)
