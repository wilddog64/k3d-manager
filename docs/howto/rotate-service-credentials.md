# How to rotate a service credential

Three services rotate their admin credential automatically, monthly, on the 1st. This page
covers what exists, how to trigger a rotation **on demand** (after an exposure, say), how to
verify it actually worked, and which service has no rotator yet.

Until now this was documented only inside plan specs, which meant the safe procedure had to be
reverse-engineered from YAML each time. That is what this page is for.

## What exists

| Service | Mechanism | Schedule | Canonical secret |
|---|---|---|---|
| Grafana | CronJob `grafana-credential-rotator` (ns `monitoring`) | `0 0 1 * *` | `secret/observability/grafana` |
| ArgoCD | CronJob `argocd-credential-rotator` (ns `cicd`) | `0 0 1 * *` | `secret/argocd/admin` |
| Prometheus | `observability_rotate_prometheus_basic_auth`, driven by a macOS LaunchAgent | day 1, 00:00 | `secret/k3d-manager/prometheus-basic-auth` |
| **Keycloak** | **none — see [No rotator for Keycloak](#no-rotator-for-keycloak)** | — | `secret/keycloak/admin` |

## The ordering invariant

Every rotator writes **Vault first**, then propagates outward:

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

### Expect it to take a few minutes, and expect no logs

The job waits on `kubectl rollout status --timeout=5m` for the workload restart, so two to three
minutes is normal. **Its logs are empty by design** — every step redirects to `/dev/null` so no
credential can reach container logs. Track progress from cluster state instead:

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

## No rotator for Keycloak

`secret/keycloak/admin` has **no** rotator, and it cannot be rotated the same way.

Keycloak's admin password reaches the pod through
`scripts/etc/keycloak/externalsecret-admin.yaml.tmpl` → the chart's `auth.existingSecret` /
`passwordSecretKey`. That is a **bootstrap-only** input: it creates the admin user on first
start. Once the user exists in the database, changing the Secret and restarting does **not**
change the live password — you get a Vault value that no longer opens the console, which is the
exact split the ordering invariant exists to prevent.

Rotating it requires three ordered steps: change the password inside Keycloak (`kcadm
set-password` for the admin user), update `admin_password` in `secret/keycloak/admin`, then
verify with a login probe as above.

Do **not** touch `db_password` in that same secret while doing so — it is the Postgres
credential, not the console password, and rotating it requires rotating the database user too.

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
