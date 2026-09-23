# How-To: Controlled hub rebuild from GitOps + Vault

**Audience:** the operator. **Not** an agent task.
**Status:** **EXECUTED 2026-09-20** — the kine stall is cleared. `state.db` 2.72 GiB → 25.8 MB,
`kubectl get nodes` 5.5s → 0.05s, and `COMPACT deleted` is logging on a 5-minute cadence after
having had **zero** matches in the entire retained log beforehand. The procedure below is corrected
against what actually happened; two steps as originally written were wrong (see §2b and §3).

This is the indicated remedy for the kine compaction stall
(`docs/bugs/2026-09-09-hub-kine-compaction-stall.md`): the hub's `state.db` cannot be compacted in
place on this hardware, and a bare `docker restart` of the k3s server makes it strictly worse by
forfeiting an already-bootstrapped process (that mistake is recorded in the same doc).

## Why a rebuild is the fix

The hub datastore is saturated: `state.db` ~2.4 GiB and growing ~580 MB/day, `slow_sql` climbing
447 → 616 → 898 across three Hermes cycles, `compaction_recent=False`. Compaction advances at
`compactRev + 1000` per cycle against ~407,000 revisions of backlog — ~34 h minimum if it ran at
all, which it does not.

Everything downstream follows from that one fault:

| Symptom | Mechanism |
|---|---|
| Cloudflare 502 on all tunnel hosts | apiserver unreachable → `kubectl port-forward` SPDY streams break → supervisor kills and respawns (18,211 restarts, ~1 per 35 s) → no listener → cloudflared connection refused |
| `kube-state-metrics` CrashLoopBackOff (356 restarts) | same |
| `kubectl exec` / `logs` fail with `net/http: TLS handshake timeout` | same |
| `secrets/vault-0` at `0/1` | same (unverified — see Blocker) |

None of these have independent fixes. The rebuild clears all of them together.

## What survives a rebuild, and what does not

**Survives — verified present in Keychain on 2026-09-20:**

- `k3d-manager-vault-unseal` — unseal shards. Note these belong to the *current* Vault; a rebuild
  re-initialises Vault and mints new ones. `bin/cluster-up:417-432` handles the sealed case via
  `deploy_vault --re-unseal` using the cached shards.
- `k3d-manager-app-cluster-secrets` — all **14** canonical KV keys confirmed present:
  `redis/{cart,orders-cache}`, `postgres/{orders,products,payment}`,
  `payment/{encryption,stripe,paypal}`, `rabbitmq/default`, `minio/credentials`, `ldap/admin`,
  `keycloak/{admin,clients}`, `github/pat`.
- `k3dm-stripe-sk-test` — the real Stripe test secret key.
- All cluster config: it is in git and reconciled by ArgoCD.

**Does not survive:**

- The hub Vault's own storage — `bin/cluster-down:330` runs `k3d cluster delete`, which destroys
  the PVC. The unseal shards are worthless without it.
- All PersistentVolumes: Postgres, Redis, RabbitMQ, MinIO data.
- Docker build cache and unused images (`bin/cluster-down` runs `docker system prune --force`).

## BLOCKER — CLEARED in `f28a4539` before the rebuild ran

`scripts/plugins/shopping_cart.sh:716-718` wrote `payment/encryption`, `payment/stripe` and
`payment/paypal` **unconditionally** on every run, and `bin/cluster-up:851` calls that function.
A rebuild would have come back up with `api_key: sk_test_placeholder` and silently broken payments.
All three are now guarded `reuse → copy-from-source → Keychain (Stripe only) → placeholder`.

Spec: `docs/bugs/2026-09-20-seed-clobbers-real-payment-secrets.md`.

Note the hub-only sequence in §3 does **not** run `deploy_shopping_cart_data`, so on a hub-only
rebuild the payment keys are not seeded at all until that runs. Verify with the Stripe check in §5
before trusting payments.

The other eleven keys are safe: ten are guarded `reuse → copy-from-source → generate`, and for
infra passwords regeneration is harmless because the services are redeployed in the same run and
ESO syncs the new values.

### Credential paths after a Vault rebuild

Credential paths are not all reseeded automatically after a Vault rebuild. `secret/argocd/admin` is repopulated by `hub_recovery_reconcile`, and `k3d-manager/prometheus-basic-auth` is repopulated by the Prometheus auth-proxy refresh. `~/.local/share/k3d-manager/prometheus-basic-auth.env` is a derived cache, not a source of truth. `secret/keycloak/users/*` holds the realm SSO users, is written only by `bin/cluster-up`, is **not** in the 14-key seed allowlist, and is therefore expected to be absent on a rebuilt hub — `make show-service-passwords` reports it as not provisioned rather than as a failure.

## Procedure

Run from `/Users/cliang/src/gitrepo/personal/k3d-manager`. Do not delete the `profile` or
`pw-profile` directories at any point. Raw SQLite retention deletion remains forbidden.

### 0. Preconditions

- [ ] The Stripe-clobber fix above is merged and on the checked-out branch.
- [ ] `security find-generic-password -s k3d-manager-app-cluster-secrets >/dev/null && echo OK`
      — confirm the backup exists. **Without `-w`**; never print values.
- [ ] `security find-generic-password -s k3dm-stripe-sk-test >/dev/null && echo OK`
- [ ] Note the current branch: config is applied from whatever is checked out.

### 1. Capture pre-teardown state

The apiserver is degraded, so capture what still answers and accept gaps:

```bash
kubectl --context k3d-k3d-cluster get pods -A > ~/hub-rebuild-pods-before.txt
kubectl --context k3d-k3d-cluster get pvc -A > ~/hub-rebuild-pvc-before.txt
argocd app list > ~/hub-rebuild-apps-before.txt 2>&1 || true
```

Do **not** spend effort trying to dump Vault KV from the live cluster. `kubectl exec` into
`vault-0` currently fails with `net/http: TLS handshake timeout`, and the Keychain backup already
holds all 14 keys — it is the better source.

### 2. Tear down

**Use the explicit provider. A bare `make down` is wrong here and destructive beyond the hub.**

```bash
make down CLUSTER_PROVIDER=k3d
```

Why the override matters — verified 2026-09-20:

- The Makefile defaults to `CLUSTER_PROVIDER ?= k3s-aws` (line 12), **not** the local hub. With
  that default, `bin/cluster-down` enters its `k3s-aws` branch and runs
  `acg_teardown --confirm`, which **deletes the ACG CloudFormation stack** and deregisters the
  sandbox from hub ArgoCD. That is out of scope for a hub rebuild.
- `CLUSTER_PROVIDER=k3s-hostinger` would destroy the **hostinger** cluster — there is a live
  `ubuntu-hostinger` context. Never use it here.
- `CLUSTER_PROVIDER=k3d` falls to the `*)` branch, which logs
  `Unknown CLUSTER_PROVIDER 'k3d' — skipping remote teardown` and proceeds to the local hub only.
- A bare `make down` also **refuses** outright: `bin/require-unambiguous-provider` exits 3 because
  two providers are live (`k3s-aws`, `k3s-hostinger`) and `CLUSTER_PROVIDER` was not set
  explicitly. That guard is doing its job — do not defeat it, give it the right provider.

**Dry-run first and read the scope before committing to it:**

```bash
DRY_RUN=1 make down CLUSTER_PROVIDER=k3d
```

The dry run must print `skipping remote teardown` and must **not** mention `acg_teardown`,
CloudFormation or deregistration. If it does, stop.

The real run unloads the port-forward launchd agents (vault, argocd, keycloak, alertmanager and its
auth proxy, pushgateway, frontend, and the Cloudflare named tunnel), deletes the k3d hub cluster,
prunes Docker, and cleans stale `/tmp` files. Expect several minutes.

Note the Grafana port-forward supervisor (`com.k3d-manager.grafana-port-forward`) is **not** in
that list, so it keeps looping against the dead cluster during the rebuild. That is harmless noise;
it recovers once the cluster is back.

### 2b. Clear teardown debris before rebuilding — verified necessary 2026-09-20

`k3d cluster delete` does **not** reliably finish. On the 2026-09-20 run it reported:

```
ERRO docker failed to remove the container 'k3d-k3d-cluster-agent-1': ... tried to kill
     container, but did not receive an exit event
WARN Failed to delete cluster network 'k3d-k3d-cluster': ... has active endpoints
WARN Failed to delete volume 'k3d-k3d-cluster-images': ... volume is in use
```

The orphaned container pins the network, which pins the volume. Cluster creation then fails.
Remove all three **by exact name** — never with a wildcard, and never touch `profile` or
`pw-profile`:

```bash
docker rm -f k3d-k3d-cluster-agent-1
docker network rm k3d-k3d-cluster
docker volume rm k3d-k3d-cluster-images
```

Then confirm the slate is clean before proceeding:

```bash
docker ps -a --filter name=k3d --format '{{.Names}}'   # expect empty
k3d cluster list                                       # expect header only
```

Leave `k3d-k3d-cluster-recovery-server-data` alone.

### 3. Rebuild — hub only

**Do not run `make up` for a hub-only rebuild.** Both obvious forms are wrong:

- `make up CLUSTER_PROVIDER=k3d` **fails outright**: `bin/cluster-up:78` rejects it with
  `Unsupported CLUSTER_PROVIDER: k3d (supported: k3s-aws, k3s-gcp, k3s-az)`. The k3d hub is not a
  `bin/cluster-up` provider — it is the *local* cluster that script manages alongside a remote one.
- Bare `make up` defaults to `CLUSTER_PROVIDER=k3s-aws` and runs the **full 12-step ACG path**:
  Playwright AWS credential extraction, sandbox TTL checks, remote 3-node provisioning, SSH tunnel,
  and an interactive `read -r -p "Press Enter once you are signed in..."` prompt. That is a
  sandbox bring-up, not a hub rebuild.

Run the hub-only sequence instead — this is exactly what `bin/cluster-up` Steps 3.5 and 3.6 do
internally when it finds the hub missing:

```bash
./scripts/k3d-manager deploy_cluster --provider k3d k3d-cluster
kubectl config use-context k3d-k3d-cluster
./scripts/k3d-manager deploy_vault --confirm
./scripts/k3d-manager deploy_ldap --confirm
./scripts/k3d-manager deploy_argocd --confirm
make observability
make platform-ops
```

Timings from the 2026-09-20 run: cluster + Istio ~2 min, Vault ~2 min, LDAP ~1.5 min, ArgoCD
~3.5 min (deploys 12/12 ApplicationSets itself), observability ~2 min. Grafana reaches `3/3` about
3 min after the observability ApplicationSet syncs.

Vault came back **initialized and unsealed** on this run — no `--re-unseal` was needed. If it does
report sealed, `bin/cluster-up:417-432` handles it via `deploy_vault --re-unseal` from the cached
shards.

### 4. Reapply the ApplicationSets — required, not optional

ApplicationSets template their `$values` source at `${K3D_MANAGER_BRANCH}`, frozen to whatever
branch was checked out when they were last applied. Config on a newer branch stays **inert** until
they are reapplied.

```bash
./scripts/k3d-manager deploy_argocd_applicationsets --confirm
```

`K3D_MANAGER_BRANCH` defaults to the checked-out branch, which is what you want here. This
entrypoint is surgical: unlike `deploy_argocd_bootstrap` it does **not** redeploy the image updater
or platform-ops, and it preserves each live set's destination cluster and `istio-cni` dirs by
default — a reapply never retargets. It also runs `argocd_check_values_branch` itself afterwards
unless `--no-verify` is passed, so no separate verify call is needed. Do not set
`ARGOCD_APPSET_IGNORE_LIVE=1`.

### 5. Verify

- [ ] `kubectl --context k3d-k3d-cluster get pods -A` — diff against `~/hub-rebuild-pods-before.txt`
- [ ] Compaction is alive — the whole point of the exercise. Case-sensitive predicate; a
      case-insensitive `grep -i compact` returns ~50,000 false positives from kine's Slow SQL
      messages, which embed `compact_rev_key`:
      ```bash
      docker logs k3d-k3d-cluster-server-0 2>&1 | command grep 'msg="COMPACT deleted' | tail -5
      ```
      Healthy cadence is ~288/day. Seeing any recent line is the success signal.
- [ ] `./bin/public-endpoint-probe --json` → `verdict: ok`. With the 401 fix landed,
      prometheus/alertmanager/webhook count healthy while still reporting 401.
- [ ] `make status`
- [ ] Grafana port-forward stable — the restart loop should stop:
      ```bash
      wc -l < ~/.local/share/k3d-manager/logs/grafana-pf.log   # compare after 10 min
      ```
- [ ] `kube-state-metrics` no longer restarting.
- [ ] **Stripe key is real, not the placeholder.** Verify without printing it:
      ```bash
      bin/vault-exec -- vault kv get -field=api_key secret/payment/stripe \
        | command grep -q 'sk_test_placeholder' && echo PLACEHOLDER-BAD || echo REAL-OK
      ```
- [ ] `payment-service` reaches `1/1`. It is `0/1` with 13 restarts today; the cause was **not**
      confirmed (logs unreadable). If it still fails after the rebuild with a real Stripe key, the
      remaining candidate is the `fix/keycloak-role-authority-mapping` work in
      `shopping-cart-payment` (P3, PR not yet opened).

### 6. Aftermath

- [ ] Re-mint the ArgoCD Hermes token — Hermes logs
      `argocd unknown "credential rejected; re-mint k3dm-hermes-argocd-token"`.
- [ ] The alertmanager resource fix (`limits` 500m/128Mi, `requests` 50m/64Mi) is committed to
      `kube-prometheus-stack-values.yaml` and applies itself through this rebuild — no separate
      `helm upgrade` needed. Confirm the throttle fraction has dropped from ~0.83:
      ```promql
      rate(container_cpu_cfs_throttled_periods_total{namespace="monitoring",container="alertmanager"}[10m])
        / rate(container_cpu_cfs_periods_total{namespace="monitoring",container="alertmanager"}[10m])
      ```
- [ ] Stale generated ACG Applications (`istio-{base,cni}-ubuntu-k3s`, `istiod-ubuntu-k3s`) have no
      `ubuntu-k3s` context. Delete the registration Secret **before** the Applications.
- [ ] Update `memory-bank/activeContext.md` with the outcome.

## If a rebuild is refused

The only in-place alternative is to quiesce churn so a single compaction transaction can finish:
stop the ArgoCD application controller and the agent nodes, give the control plane the datastore to
itself, and watch for the first `COMPACT deleted`. That is **unproven**, costs ~34 h at 1000
revisions/cycle, and does not address the ~580 MB/day growth. It is not recommended.
