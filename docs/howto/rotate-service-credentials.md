# How to rotate a service credential

Four services rotate their admin credential automatically, monthly, on the 1st. This page
covers what exists, how to trigger a rotation **on demand** (after an exposure, say), how to
verify it actually worked.

Until now this was documented only inside plan specs, which meant the safe procedure had to be
reverse-engineered from YAML each time. That is what this page is for.

## What exists

| Service | Mechanism | Schedule | Canonical secret |
|---|---|---|---|
| Grafana | CronJob `grafana-credential-rotator` (ns `monitoring`) | `0 0 1 * *` | `secret/observability/grafana` |
| ArgoCD | CronJob `argocd-credential-rotator` (ns `cicd`) | `0 0 1 * *` | `secret/argocd/admin` |
| Prometheus | `observability_rotate_prometheus_basic_auth`, driven by a macOS LaunchAgent | day 1, 00:00 | `secret/k3d-manager/prometheus-basic-auth` |
| Keycloak | CronJob `keycloak-credential-rotator` (ns `identity`) | `0 0 1 * *` | `secret/keycloak/admin` |

## The ordering invariant

Grafana and ArgoCD write **Vault first**, then propagate outward:

1. Write the new password to Vault (the canonical source).
2. Force the ExternalSecret to re-sync so the Kubernetes Secret matches.
3. Restart the workload so it picks the Secret up.
4. Set the password *inside* the application so it matches what Vault now holds.

The Grafana and ArgoCD jobs install a `trap restore EXIT` before step 1's effects can escape:
if any later step fails, Vault is rolled back to the old value and the ExternalSecret re-synced,
leaving Vault and the service consistent on the **old** password rather than split.

This ordering is why you must not rotate by hand. Running
`grafana cli admin reset-admin-password` (or `argocd account update-password`) directly changes
the application while leaving Vault stale — so `make show-service-passwords` then prints a
password that no longer works, and the next ExternalSecret sync may overwrite the application
back. Those standalone commands are forbidden for that reason; the CronJob is the sanctioned
path precisely because it does step 4 *last* and rolls back on failure.

Keycloak is the exception: its database is authoritative. Its rotator resets the master-realm
admin password inside Keycloak first, then writes Vault, with a rollback trap installed before
the reset so a later failure can restore the old Keycloak password.

## Trigger a rotation on demand

Rotate immediately when a password has been exposed — pasted into a chat or terminal, printed
by a tool, or committed. Do not wait for the 1st.

Check the prerequisites first (all read-only). A rotation that fails midway is safe, but a
rotation that cannot start wastes a Grafana restart:

```bash
kubectl --context k3d-k3d-cluster get cronjob grafana-credential-rotator -n monitoring
kubectl --context k3d-k3d-cluster get externalsecret grafana-admin-credentials -n monitoring
kubectl --context k3d-k3d-cluster get deploy kube-prometheus-stack-grafana -n monitoring
kubectl --context k3d-k3d-cluster get pod vault-0 -n secrets
```

The CronJob must not be `SUSPEND=true`, the ExternalSecret should report `SecretSynced`, Grafana
should be `1/1`, and `vault-0` must be ready — the job authenticates to Vault in-cluster at
`http://vault.secrets.svc:8200`.

Then create a one-off Job from the CronJob:

```bash
kubectl --context k3d-k3d-cluster create job "grafana-rotate-manual-$(date +%Y%m%d-%H%M%S)" \
  --from=cronjob/grafana-credential-rotator -n monitoring
```

Substitute `argocd-credential-rotator` / `-n cicd` for ArgoCD. For Prometheus the entrypoint is
a plugin function rather than a CronJob:

```bash
./scripts/k3d-manager observability_rotate_prometheus_basic_auth
```

For Keycloak, create a one-off Job in `identity`:

```bash
kubectl --context k3d-k3d-cluster create job "keycloak-rotate-manual-$(date +%Y%m%d-%H%M%S)" \
  --from=cronjob/keycloak-credential-rotator -n identity
```

### Expect it to take a few minutes, and expect no logs

Grafana and ArgoCD jobs wait on `kubectl rollout status --timeout=5m` for the workload restart,
so two to three minutes is normal. Keycloak changes its database directly and does not restart
the workload. **Logs are empty by design** — every step redirects to `/dev/null` so no credential
can reach container logs. The corollary is worth internalising: on a successful run there is
nothing to read, so *any* log output is a defect. That is how the `base64 --decode` bug was found
— the image's `base64` is BusyBox and accepts only `-d`, and the usage error it printed was the
only sign that every Slack notification was being silently dropped.

Do not use Slack as the signal either way: a missing notification does not mean the rotation
failed, and a notification does not prove it succeeded. Track progress from cluster state instead:

```bash
kubectl --context k3d-k3d-cluster get job <job-name> -n monitoring \
  -o custom-columns='STATUS:.status.conditions[0].type,SUCCEEDED:.status.succeeded,FAILED:.status.failed'
```

`SuccessCriteriaMet` with `succeeded=1` means the whole chain ran, including step 4, and the
rollback trap did not fire.

## Verify it worked

A succeeded Job is good evidence but not proof that the application and Vault agree. Prove it
with a login probe **and a negative control** — without the negative control, a `200` might mean
"auth is not enforced" rather than "the password is right":

```bash
kubectl --context k3d-k3d-cluster exec -n monitoring deploy/kube-prometheus-stack-grafana \
  -c grafana -- sh -c '
    curl -s -o /dev/null -w "good=%{http_code}\n" \
      -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" http://localhost:3000/api/user
    curl -s -o /dev/null -w "bad=%{http_code}\n" \
      -u "$GF_SECURITY_ADMIN_USER:definitely-not-the-password" http://localhost:3000/api/user'
```

Expect `good=200` and `bad=401`. The probe reads the password from the pod's own environment,
which ESO populated from Vault, so a `200` proves Grafana matches Vault. Note the command string
contains only the variable *name* — never paste a credential into a `kubectl exec` argument, as
it lands in shell history and CI logs.

Cross-check the timeline if you want to see each step landed:

```bash
kubectl --context k3d-k3d-cluster get externalsecret grafana-admin-credentials -n monitoring \
  -o jsonpath='{.metadata.annotations.force-sync}{"\n"}{.status.refreshTime}{"\n"}'
```

The `force-sync` annotation is an epoch stamped by the job; it and `refreshTime` must fall
inside the Job's `startTime`–`completionTime` window.

## Keycloak rotation details

Keycloak's `keycloak-secrets` Secret is a **bootstrap-only** input: it creates the admin user
when Keycloak first starts. The live service admin is in the `master` realm, not the `home`
realm, and the rotator changes it through the Keycloak Admin API before updating Vault.

`secret/keycloak/admin` contains both `admin_password` and `db_password`. The job reads and
writes both fields, changing only `admin_password`; `db_password` must not be rotated by this
job because it is the Postgres credential and changing it requires rotating the database user.

The Kubernetes Secret is not force-synced. It converges through its 15m `refreshInterval`; the
ExternalSecret is ArgoCD-managed with `selfHeal`, so an out-of-band annotation would be reverted.

Verify Keycloak with a master-realm token request using the new password and a negative control
using a definitely wrong password. The good request must return a token; the bad request must
fail. Keep both requests value-free in shell history and logs.

Also distinct, and frequently confused: `secret/keycloak/admin` is the **service** admin, while
`secret/keycloak/users/*` holds the **realm SSO** users (admin/developer/operator). The latter is
written only by `bin/cluster-up` and is not in the hub seed allowlist, so a hub rebuild never
restores it. See [hub-rebuild-from-gitops-vault.md](hub-rebuild-from-gitops-vault.md).

## Where to look next

- [hub-rebuild-from-gitops-vault.md](hub-rebuild-from-gitops-vault.md) — which secrets a rebuild
  restores, and which it does not
- `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml` — the Grafana job
- `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml` — the ArgoCD job
- `docs/plans/v1.24.0-credential-rotation-automation.md` — the original design intent
