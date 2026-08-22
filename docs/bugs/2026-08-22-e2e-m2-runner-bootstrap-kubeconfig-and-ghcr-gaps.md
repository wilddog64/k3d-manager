# M2 e2e runner bootstrap leaves no host kubeconfig, no current-context, and no off-hub GHCR pull path (2026-08-22)

**Severity:** medium-high (a freshly bootstrapped M2 runner cannot complete an E2E:
the host context is unusable and the private shopping-cart images 403 on pull).
**Component:** `scripts/plugins/e2e_remote.sh` — `_e2e_remote_reconcile_cluster`
(line ~214–223), `e2e_runner_dispatch` (GHCR/publish-back), and the substrate
`acg-up`-style ghcr-pull-secret path when run off-hub.
**Found while:** the v1.27.0 plan #2 live-acceptance passing run on the M2 OrbStack
runner (`make e2e-remote RUNNER=m2`). The lock + repo-currency gaps were cleared first
(see `2026-08-22-e2e-m2-runner-lock-acquire-missing-parent-dir.md`); these are the
next-layer gaps that surfaced once the harness actually ran.

## Gap 1 — bootstrap creates the k3d cluster but writes no kubeconfig

`_e2e_remote_reconcile_cluster` runs:

```bash
KUBECONFIG=${E2E_M2_KUBECONFIG} k3d cluster create ${E2E_M2_RUNNER_CLUSTER} \
  --wait --kubeconfig-update-default=false --kubeconfig-switch-context=false
```

`--kubeconfig-update-default=false` tells k3d **not to write any kubeconfig file at
all**. Combined with `--kubeconfig-switch-context=false`, the dedicated kubeconfig
`$HOME/.kube/e2e-runner.yaml` (`E2E_M2_KUBECONFIG`) is **never created**. The dispatch
then exports `KUBECONFIG=$HOME/.kube/e2e-runner.yaml` and the harness fails:

```
ERROR: Host cluster context not available; set VCLUSTER_HOST_CONTEXT or configure a current kubectl context
```

`kubectl --kubeconfig=$KC config get-contexts` shows an **empty** table and
`current-context is not set`; the file does not exist on disk.

**Fix:** after `k3d cluster create`, materialize the dedicated kubeconfig with a
current-context set. Simplest:

```bash
_e2e_remote_ssh "k3d kubeconfig get ${E2E_M2_RUNNER_CLUSTER} > ${E2E_M2_KUBECONFIG}"
```

`k3d kubeconfig get <cluster>` emits a standalone kubeconfig with
`current-context: k3d-<cluster>` set — which is exactly what the harness needs, and
also fixes Gap 2. (Alternatively flip to `--kubeconfig-update-default=true` with the
`KUBECONFIG` env pointing at the dedicated file so k3d writes it directly.)

Worked around live: `ssh m2jump 'k3d kubeconfig get e2e-runner > ~/.kube/e2e-runner.yaml'`
→ `current-context=k3d-e2e-runner`, node Ready.

## Gap 2 — no current-context even if a kubeconfig exists

`--kubeconfig-switch-context=false` means that even when a kubeconfig is written, k3d
does not set `current-context`. The harness needs either `current-context` set or
`VCLUSTER_HOST_CONTEXT` exported. `e2e_runner_dispatch` exports neither. Prefer the
`k3d kubeconfig get` fix above (it sets current-context); optionally also export
`VCLUSTER_HOST_CONTEXT=k3d-${E2E_M2_RUNNER_CLUSTER}` in the remote command as a belt.

## Gap 3 — no off-hub GHCR pull credential path (private images 403)

Once the substrate applied, postgres/redis (public multi-arch) rolled out, but
`basket`, `order`, and `product-catalog` went `ImagePullBackOff`:

```
HEAD https://ghcr.io/v2/wilddog64/shopping-cart-product-catalog/manifests/sha-6ca5e88d... : 403 Forbidden
```

The ghcr-pull-secret path tried Vault first and failed off-hub
(`error: context "k3d-k3d-cluster" does not exist` — no hub context on M2), then fell
back to the M2 `gh` CLI token. M2's `gh` is logged in as **wilddog64** (the package
owner) but the token scopes are `admin:public_key, gist, read:org, repo` — **no
`read:packages`** — so ghcr returns **403** (authenticated but not authorized). A raw
`curl -H "Authorization: Bearer $(gh auth token)"` HEAD reproduces the 403.

**Fix (one-time, on M2):** add the packages scope to M2's gh token —

```bash
gh auth refresh -h github.com -s read:packages   # interactive device flow, run on M2
```

Then the dispatch's gh-token fallback produces a working ghcr-pull-secret.
**Design follow-up:** the Vault-first path assumes the hub context exists locally; on a
remote runner it always errors before the gh fallback. Decide how a remote runner
obtains a `read:packages` credential without persisting an M4/hub secret on it (plan
constraint) — e.g. require `gh` on the runner to carry `read:packages`, or pass a
scoped, short-lived GHCR token over the dispatch env (not written to disk).

## Gap 4 — results never reach the hub (no publish-back configured)

Every run ended with:

```
WARN: [e2e-remote] M4 publication unavailable; retained <id>.publication_pending.json for replay
```

`E2E_M2_PUBLISH_BACK_HOST` is unset, so the M2 retains results as `publication_pending`
and nothing lands in the hub `platform-ops` ConfigMap / Prometheus / Grafana. Even a
passing run will not show in Grafana until either publish-back is configured
(`E2E_M2_PUBLISH_BACK_HOST` + `E2E_M2_PUBLISH_BACK_KEY`, an M4 SSH key the M2 uses to
push only validated results) or `make e2e-replay RUNNER=m2` is run from M4 to pull and
publish the retained result. Configure/verify this before asserting the
"Grafana displays runner-labelled E2E results" DoD.

## Provisioning order that actually works (observed)

1. `ssh m2jump 'mkdir -p ~/.k3dm/e2e'` (lock parent — until the mkdir -p fix lands).
2. Repo current on M2 (rsync overlay from M4, or GitHub fetch once M2 has access).
3. `./scripts/k3d-manager e2e_runner_bootstrap` (creates k3d e2e-runner cluster).
4. `ssh m2jump 'k3d kubeconfig get e2e-runner > ~/.kube/e2e-runner.yaml'` (until Gap 1 fix).
5. `gh auth refresh -h github.com -s read:packages` on M2 (until Gap 3 design fix).
6. Configure publish-back OR plan to `make e2e-replay RUNNER=m2` (Gap 4).
7. `make e2e-remote RUNNER=m2` (needs M2 CPU idle ≥ `E2E_M2_MIN_CPU_IDLE`, default 35%).
