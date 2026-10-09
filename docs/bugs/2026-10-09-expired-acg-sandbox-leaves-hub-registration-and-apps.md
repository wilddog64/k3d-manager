# An expired ACG sandbox leaves its hub ArgoCD registration and 10 apps behind

**Filed:** 2026-10-09, Claude (operator: "can we automatically clean up these after acg sandbox tear down")
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** PARTIAL — make-down path FIXED `209addbe` + `cbd2f564` (Claude-verified: RED on old code, 67/67 BATS); watcher/reaper still open (needs lib-foundation)
**Priority:** P3 — noise in ArgoCD, and alert/dashboard pollution; no outage
**Severity:** Low
**Component:**
- `scripts/lib/providers/k3s-aws.sh` (`_k3s_aws_deregister_cluster`, the sandbox watcher)
- Hub ArgoCD (`cicd`)

**Related:**
- `docs/bugs/v1.25.0-bugfix-k3s-aws-hub-deregister.md`: added the deregister, but only to
  `destroy_cluster`.
- `docs/bugs/2026-05-20-acg-up-expired-sandbox-auto-restart.md`

## Symptom (2026-10-09)

- Hub Secret `cicd/cluster-ubuntu-k3s` (`k3d-manager/provider: k3s-aws`) still exists. It was
  created 2026-10-06 00:44 UTC; the sandbox lives at most 8h.
- Ten generated Applications still target the sandbox, all with sync status `Unknown`:
  - Eight by destination name `ubuntu-k3s`:
    `ubuntu-k3s-{data-layer,grafana-dashboards,shopping-cart-basket,-frontend,-namespace,-order,-payment,-product-catalog}`.
  - Two by server `https://host.k3d.internal:6443` (the sandbox tunnel endpoint):
    `ubuntu-k3s-eso` and `ubuntu-k3s-platform`. The hub's own ESO is `k3d-cluster-eso`
    (`kubernetes.default.svc`) and is not matched.

## Root cause

`_k3s_aws_deregister_cluster` (`k3s-aws.sh:304`) deletes the registration Secret and the
generated Applications. It runs **only from `destroy_cluster --confirm`**. When the sandbox ends
any other way, nothing removes the registration:
- ACG expiry (4h, or 8h with the extension)
- a Pluralsight-side delete
- a laptop sleep through expiry

### Second gap: `make down` itself misses 2 of the 10 apps

`_k3s_aws_deregister_cluster` selects Applications only by `spec.destination.name == ubuntu-k3s`.
`ubuntu-k3s-eso` and `ubuntu-k3s-platform` target the sandbox by **server**
(`https://host.k3d.internal:6443`), so even a normal `make down` leaves them behind.

Chaining `make cleanup-stale-registration` *after* `make down` does not fix this. The deregister
has already deleted the Secret, and the cleanup script derives the server from that Secret; it
finds no registration and exits 0 ("No ArgoCD cluster registration found"). The server match has
to happen while the Secret still exists.

## Fix direction (to spec)

0. **`make down` path:** in the k3s-aws branch of `bin/cluster-down`, replace the
   `_k3s_aws_deregister_cluster` call with `bin/cleanup-stale-registration --cluster=ubuntu-k3s
   --confirm` (it reads the server before deleting the Secret), or teach the deregister to match
   by server too. BATS: a stubbed hub with one name-matched and one server-matched app; both are
   deleted, Secret first. RED first.

Deregister automatically once the sandbox is provably gone, not merely unreachable for a moment:
- **Watcher path:** when `acg_watch` sees the sandbox expire or end, call
  `_k3s_aws_deregister_cluster`.
- **Reaper path:** this backs up the watcher, since it dies with the laptop session. A periodic
  hub-side check deregisters `cluster-ubuntu-k3s` when **both** of these hold:
  - its apps have been `Unknown` for at least 30 min, and
  - a positive gone signal exists: the CloudFormation stack is absent, or the sandbox credentials
    return `InvalidClientTokenId` / expired.
  It must never act on reachability alone, because a tunnel blip is not a teardown.
- Log every deregister. Add a BATS test with stubbed AWS and kubectl: "stack gone + Unknown"
  deregisters; "Unknown only" does not. RED first.

## Immediate cleanup (operator)

Use the dedicated target, not `make down`. It is dry-run by default. It was broken (exit 2 on
every call) until fixed alongside this doc; see the CHANGELOG.
```
make cleanup-stale-registration CLUSTER=ubuntu-k3s            # preview: 1 Secret + 10 apps
make cleanup-stale-registration CLUSTER=ubuntu-k3s CONFIRM=1  # delete Secret first, then apps
```
It selects by the label `argocd.argoproj.io/cluster-name=ubuntu-k3s`, so `ubuntu-k3s-app-cluster`
(`cluster-name: k3d-cluster`, the hub) is never selected.

### Why not `make down`

`make down` (the default provider is k3s-aws, and the default `KEEP_LOCAL=1` keeps the hub) does
call `_k3s_aws_deregister_cluster`. After the provider `case` in `bin/cluster-down`, however,
these steps run **without** a `_keep_hub` guard:
- It kills `vault-pf.pid` and unloads and removes `com.k3d-manager.vault-port-forward`.
  That LaunchAgent forwards the **hub's** Vault (`vault-0 18200:8200 --context k3d-k3d-cluster`),
  so the hub loses its local Vault access.
- It stops the frontend port-forward PID and the ACG Prometheus port-forward.

That is an over-broad teardown with the hub kept. Confirm and fix it in the spec. Until then, use
the cleanup target above for a sandbox that has already expired.

## What NOT to do

- **Never delete `ubuntu-k3s-app-cluster`.** Despite its name it registers the **hub itself**
  (`cluster-name: k3d-cluster`), and four ApplicationSets select it for the hub's ESO.
- Do not deregister on unreachability alone.
- Do not delete the Applications before the registration Secret: the ApplicationSet would
  regenerate them.

---

## Implementation spec — fix item 0 + the keep-hub Vault LaunchAgent (Codex, 2026-10-09)

Scope: the `make down` path only. The watcher and reaper paths are **not** in this spec:
`acg_watch` lives in lib-foundation (`scripts/lib/foundation/scripts/lib/acg/acg.sh`), so that
change must go upstream first, and the reaper needs its own design. Until then
`make cleanup-stale-registration` remains the manual cleanup for an expired sandbox.

**Branch:** `k3d-manager-v1.42.0`.
**Files (only these):** `scripts/lib/providers/k3s-aws.sh`, `bin/cluster-down`, a new
`scripts/tests/lib/k3s_aws_deregister.bats`, `CHANGELOG.md` (`[Unreleased]` → `### Fixed`,
one bullet per change), and this doc's Status line.

### Change 1 — `_k3s_aws_deregister_cluster` also matches Applications by server

Read the registration's server **before** deleting the Secret, then select Applications whose
destination name **or** server matches. Never match the in-cluster server.

**OLD:**
```bash
  local -a hub_kubectl=()
  read -r -a hub_kubectl <<< "$(_argocd_hub_kubectl_cmd)"

  "${hub_kubectl[@]}" -n "${argocd_ns}" delete secret "${secret_name}" \
    --ignore-not-found >/dev/null 2>&1 || true
```
**NEW:**
```bash
  local -a hub_kubectl=()
  read -r -a hub_kubectl <<< "$(_argocd_hub_kubectl_cmd)"

  local server=""
  server="$("${hub_kubectl[@]}" -n "${argocd_ns}" get secret "${secret_name}" \
    -o jsonpath='{.data.server}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
  [[ "${server}" == "https://kubernetes.default.svc" ]] && server=""

  "${hub_kubectl[@]}" -n "${argocd_ns}" delete secret "${secret_name}" \
    --ignore-not-found >/dev/null 2>&1 || true
```

**OLD:**
```bash
  done < <(
    "${hub_kubectl[@]}" -n "${argocd_ns}" get applications -o \
      jsonpath='{range .items[?(@.spec.destination.name=="'"${ctx}"'")]}application/{.metadata.name}{"\n"}{end}' \
      2>/dev/null
  )
```
**NEW:**
```bash
  done < <(
    "${hub_kubectl[@]}" -n "${argocd_ns}" get applications -o json 2>/dev/null \
      | jq -r --arg ctx "${ctx}" --arg server "${server}" \
        '.items[]? | select(.spec.destination.name == $ctx or ($server != "" and .spec.destination.server == $server)) | "application/" + .metadata.name' \
        2>/dev/null
  )
```
The Secret is still deleted before any Application (the ApplicationSets would regenerate them
otherwise). Nothing else in the function changes.

### Change 2 — `bin/cluster-down` keeps the hub's Vault LaunchAgent when the hub is kept

`com.k3d-manager.vault-port-forward` forwards the **hub's** Vault (`vault-0 18200:8200
--context k3d-k3d-cluster`). Removing it on a sandbox teardown with the hub kept cuts local
Vault access to the hub.

**OLD:**
```bash
if _is_mac; then
  _vault_pf_label="com.k3d-manager.vault-port-forward"
```
**NEW:**
```bash
if [[ "${_keep_hub}" -eq 0 ]] && _is_mac; then
  _vault_pf_label="com.k3d-manager.vault-port-forward"
```
Leave the `vault-pf.pid` kill above it unchanged (that forward is started by `cluster-up` for
the sandbox run). Leave the frontend and ACG Prometheus port-forward stops unchanged.

### Tests (new `scripts/tests/lib/k3s_aws_deregister.bats`)

Follow the sourcing pattern of an existing provider test under `scripts/tests/lib/` (look for
one that sources `scripts/lib/providers/k3s-aws.sh`). Stub `_argocd_hub_kubectl_cmd` to print
`kubectl`, and stub `kubectl` to log every call (`"$*"`) in order to a file and to answer:
- `get secret cluster-ubuntu-k3s ... jsonpath={.data.server}` → `printf '%s' "$(printf '%s' https://host.k3d.internal:6443 | base64)"`
- `get applications -o json` → four apps: `ubuntu-k3s-order` (destination name `ubuntu-k3s`),
  `ubuntu-k3s-eso` (server `https://host.k3d.internal:6443`), `k3d-cluster-eso`
  (server `https://kubernetes.default.svc`), `ubuntu-hostinger-platform` (name `ubuntu-hostinger`).
- everything else: return 0.

1. **Name- and server-matched apps are both deleted; others are not.** The log contains
   `delete application/ubuntu-k3s-order` and `delete application/ubuntu-k3s-eso`, and contains
   neither `k3d-cluster-eso` nor `ubuntu-hostinger-platform` in any `delete` line.
2. **Secret first.** The line number of `delete secret cluster-ubuntu-k3s` is lower than the line
   number of the first `delete application/` line.
3. **In-cluster server is never used.** With the Secret stub returning
   `https://kubernetes.default.svc`, `k3d-cluster-eso` is not deleted.
4. **cluster-down keep-hub guard.** A grep test on `bin/cluster-down`: the line containing
   `_vault_pf_label="com.k3d-manager.vault-port-forward"` is preceded by a line containing
   `_keep_hub` (assert on the token, not the whole line).

**RED gate:** tests 1 and 4 must fail on the pre-fix files. Do NOT `git stash`/`git checkout`:
copy the old files from `git show HEAD:<path>` into a temp tree and run against them. Paste the
failing output.

### Gates
- `shellcheck -S warning scripts/lib/providers/k3s-aws.sh bin/cluster-down`
- `bash -n bin/cluster-down`
- `bats scripts/tests/lib/k3s_aws_deregister.bats` plus every existing BATS file that references
  `_k3s_aws_deregister_cluster` or `cluster-down` (`grep -rl` them under `scripts/tests`).
- Never run `bin/cluster-down` or any `make` lifecycle target, not even with `-n` or `DRY_RUN`.

### Status line
`**Status:** PARTIAL — make down path fixed (server match + keep-hub Vault agent); watcher/reaper still open (needs lib-foundation)`

### Commit message (exact)
```
fix(k3s-aws): deregister server-matched apps too; keep hub Vault agent on keep-hub down

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

### What NOT to do
- Do not touch `scripts/lib/foundation/` or `bin/cleanup-stale-registration`.
- Do not change which Secret is deleted or add deletes of `ubuntu-k3s-app-cluster` (it is the hub).
- Do not run anything against a cluster.
