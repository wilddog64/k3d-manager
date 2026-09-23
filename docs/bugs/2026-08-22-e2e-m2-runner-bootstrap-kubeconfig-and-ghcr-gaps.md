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

> **RESOLVED 2026-08-24.** Publish-back wired: dedicated restricted key
> `~/.ssh/e2e-m4-publisher` generated on M2 (private key stays on M2); M4 `authorized_keys`
> gained the restricted forced-command entry (`command="…/k3d-manager e2e_result_publish",
> restrict,no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding`) via
> `e2e_result_publisher_install`; `E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local` set in the
> gitignored `k3d-manager/.envrc` (with `source_up` to preserve the parent thinking-cap).
> M2→M4 smoke test confirmed: publisher key authenticates, the forced command fires (no-pty),
> and an invalid payload is rejected by schema validation with **no** ConfigMap written. Hub
> write target (`platform-ops`, ctx `k3d-k3d-cluster`) reachable. A real passing `make
> e2e-remote RUNNER=m2` will now land in the hub ConfigMap → Prometheus → Grafana.

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

---

## Gap 3 REGRESSED — 2026-09-23 (reopened)

Gap 3 is live again. `make e2e-remote RUNNER=m2` (run `1790162339-22194`) brought the
vCluster up healthy, then failed at `deploying-substrate` with the same error this doc
recorded in August:

```
INFO: [acg-up] GHCR_PAT not in env — checking Vault...
error: context "k3d-k3d-cluster" does not exist
ERROR: [acg-up] GHCR_PAT not set and no valid PAT in Vault — set GHCR_PAT env var
       or run: pbpaste | bin/rotate-ghcr-pat
```

**Both credential paths are dead on the runner, for two different reasons:**

1. **Vault path — dead by construction, unchanged since August.**
   `scripts/plugins/shopping_cart.sh:321` hardcodes
   `kubectl get secret vault-root -n secrets --context k3d-k3d-cluster` and reads Vault over
   `localhost:${_vault_local_port}`. Both are M4-only. On m2jump the context does not exist,
   so this path can never succeed off-hub. This is the "design follow-up" named above and it
   was never actioned.

2. **`gh` fallback — newly broken.** The August remediation was
   `gh auth refresh -h github.com -s read:packages` on M2. That is now undone:

   ```
   X Failed to log in to github.com account wilddog64 (default)
     - The token in default is invalid.
   ```

   `gh` is present (`/opt/homebrew/bin/gh`) but its stored token is invalid, so
   `gh auth token` (`shopping_cart.sh:366`) returns empty and the fallback bails at
   `shopping_cart.sh:367` before the `read:packages` pull check
   (`_shopping_cart_ghcr_pat_can_pull`) is ever reached.

### Correction to a note carried in the memory bank

The 2026-09-22 entry "Tier 1 e2e credential gate cleared (`read:packages` + `workflow`)"
refers to the **M4's** `gh` token. It says nothing about M2. The runner is where the
GHCR pull actually happens, so that entry never cleared Tier 1 — the two hosts have
independent `gh` credentials and only the runner's matters for the substrate.

### Also relevant — `e2e_remote.sh` forwards no credential

`e2e_runner_dispatch` (`scripts/plugins/e2e_remote.sh:430-438`) exports only
`PATH`, `E2E_RUNNER`, `KUBECONFIG`, `E2E_REPORT_DIR`, optional `E2E_IMAGE_TAG` and the
publish-back vars. There is no `GHCR_PAT`, so "set `GHCR_PAT` env var" — what the error
message advises — is not reachable through the dispatch path as written.

**Security constraint on any fix:** the dispatch command string is `tee`'d to
`~/.k3dm/e2e/dispatch/<runner>-<ts>.log`. A PAT must therefore never be interpolated into
the remote command or passed in argv. It has to travel over stdin or an `ssh` `SendEnv`
that is not echoed, consistent with the repo rule that tokens never appear in script
arguments or logs.

### Immediate unblock (requires the operator — interactive, real TTY)

On m2jump, from the operator's own terminal:

```bash
gh auth login -h github.com                        # device flow, needs a real TTY
gh auth refresh -h github.com -s read:packages     # restore the packages scope
```

Then re-verify against a **private** package (the public `shopping-cart-e2e-tests` returns
200 anonymously and proves nothing):

```bash
gh auth status
./scripts/k3d-manager e2e_runner_health m2
```

### Durable fix — pick one, this is the third occurrence

1. Teach the Vault path to be host-aware instead of hardcoding the hub context, so the
   runner either skips it cleanly or reaches Vault over a real endpoint.
2. Forward a short-lived, `read:packages`-scoped token over the dispatch **via stdin**
   (never argv, never the tee'd command string).
3. Keep the runner's own `gh` authoritative, but add a preflight assertion so an invalid
   runner token fails `e2e_runner_health` loudly instead of surfacing 40 minutes later as
   a substrate failure.

Option 3 is the smallest and would have caught this before the run started; option 1 or 2
is still needed so the credential does not silently rot again.
