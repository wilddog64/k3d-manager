# hostinger edge recovery has no narrow, side-effect-free entrypoint

**Filed:** 2026-08-16
**Provider:** k3s-hostinger
**Severity:** low (ergonomics / operational safety — not a correctness bug)

## Problem

When the laptop edge for `k3s-hostinger` goes down — cloudflared tunnel
(`com.k3d-manager.cloudflare-tunnel`) and/or the `com.k3d-manager.*-port-forward`
launchd agents stopped by a `make up/down` or provider-switch cycle — `make status
CLUSTER_PROVIDER=k3s-hostinger` goes all-red (every Cloudflare-fronted service
HTTP 530 / Argo Tunnel error 1033, ArgoCD "Connection refused" on localhost).
The **cluster is healthy**; only the edge is down.

The correct fix is the edge-only function `_hostinger_refresh_access_layer`
(`scripts/lib/providers/k3s-hostinger.sh:522`) — restart cloudflared + regenerate
missing port-forward plists + restart all port-forwards. But that function is
**private and has no first-class entrypoint**:

- The only wired path to it is `make refresh CLUSTER_PROVIDER=k3s-hostinger` →
  `_provider_k3s_hostinger_refresh_cluster` (line 981), which calls it *last*
  (line 999) — **after** `_hostinger_reapply_gitops_applicationsets`, which
  repoints the live GitOps `$values` ref to the currently checked-out branch
  (today the unreleased `k3d-manager-v1.25.0`). Using `make refresh` to restart
  a tunnel is a documented drift hazard — see
  `docs/bugs/2026-06-30-hostinger-refresh-reapplies-gitops-appsets-to-wrong-cluster.md`.
- The alternative today is a hand-written scratchpad script that sources the
  runtime and calls the private function directly. Throwaway, unversioned, not
  reproducible.

## Goal

Add a narrow, first-class recovery command that runs **only**
`_hostinger_refresh_access_layer` — no cluster re-register, no kubeconfig rewrite,
no ApplicationSet reapply, no values-ref repoint.

## Changes

Three files. No new logic — this only exposes the existing function through the
established `_cluster_provider_call` dispatcher and a `make` target.

### 1. `scripts/lib/core.sh` — public verb

Add a `refresh_access_layer` verb immediately after the existing `refresh_cluster`
verb (currently lines 563-565), mirroring its one-line dispatch style.

**OLD:**
```bash
function refresh_cluster() {
   _cluster_provider_call refresh_cluster "$@"
}
```

**NEW:**
```bash
function refresh_cluster() {
   _cluster_provider_call refresh_cluster "$@"
}

function refresh_access_layer() {
   _cluster_provider_call refresh_access_layer "$@"
}
```

### 2. `scripts/lib/providers/k3s-hostinger.sh` — provider wrapper

Add a thin provider implementation so the dispatcher resolves
`_provider_k3s_hostinger_refresh_access_layer`. Place it immediately **before**
`_provider_k3s_hostinger_refresh_cluster` (currently at line 981).

**Insert (before `function _provider_k3s_hostinger_refresh_cluster()`):**
```bash
function _provider_k3s_hostinger_refresh_access_layer() {
  _hostinger_require_host >/dev/null || return 1
  _info "[k3s-hostinger] Refreshing edge only (cloudflared + port-forwards) — no GitOps reapply"
  _hostinger_refresh_access_layer || return 1
  _info "[k3s-hostinger] Edge refresh complete"
  printf '%s\n' "__WEBHOOK_SUCCESS__"
}

```
(Keep the existing `_provider_k3s_hostinger_refresh_cluster` function unchanged
directly below this insertion. `_hostinger_require_host` is pure/read-only and
already used by `_provider_k3s_hostinger_refresh_cluster`; it validates
`HOSTINGER_HOST` without side effects. Do NOT call `_hostinger_merge_kubeconfig`,
`_hostinger_register_cluster`, or `_hostinger_reapply_gitops_applicationsets`
here — the whole point is to skip them.)

### 3. `Makefile` — `refresh-edge` target

Add a target next to `refresh:` (currently lines 38-42) that dispatches the new
verb **only** for k3s-hostinger, and refuses clearly for other providers (whose
edge has no launchd layer). Follow the same provider-gating `case` style as the
existing `refresh:` and `status:` targets.

**Insert after the `refresh:` target block (after line 42):**
```make
## Restart the k3s-hostinger laptop edge only (cloudflared + port-forwards) — no GitOps reapply
refresh-edge:
	@case "$(CLUSTER_PROVIDER)" in \
	  k3s-hostinger) CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager refresh_access_layer ;; \
	  *) echo "refresh-edge is k3s-hostinger-only (CLUSTER_PROVIDER=$(CLUSTER_PROVIDER))"; exit 1 ;; \
	esac
```
(Match the existing file's tab indentation — recipe lines are TAB-indented, not
spaces. Preserve the leading `@` and the backslash-continued `case` layout used
by `refresh:`/`status:`.)

## Verification

1. `bash -n scripts/lib/core.sh && bash -n scripts/lib/providers/k3s-hostinger.sh`
   — syntax clean.
2. `make -n refresh-edge CLUSTER_PROVIDER=k3s-hostinger` — dry-run shows it
   dispatches `./scripts/k3d-manager refresh_access_layer`, NOT `refresh_cluster`.
3. `make refresh-edge CLUSTER_PROVIDER=k3d` — prints the k3s-hostinger-only
   message and exits 1 (no dispatch).
4. Live (hostinger edge down): `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`
   returns 0 and restarts `com.k3d-manager.cloudflare-tunnel` + the port-forward
   agents; a follow-up `make status CLUSTER_PROVIDER=k3s-hostinger` is all-green.
   **Crucially:** confirm the GitOps `$values` ref did NOT move — run
   `argocd_check_values_branch` before and after; it must be unchanged (this is
   the whole reason for the narrow path).
5. Existing shellcheck (default severity) passes on both edited shell files.

## Commit message

```
feat(hostinger): add narrow refresh-edge entrypoint (edge-only, no GitOps reapply)
```

## What NOT to Do

- Do NOT change `_provider_k3s_hostinger_refresh_cluster` behavior — it must keep
  doing the full refresh. This spec only *adds* a narrow sibling.
- Do NOT add `refresh_access_layer` implementations for other providers; the
  `_cluster_provider_call` dispatcher's "does not implement action" error is the
  intended behavior, and the Makefile target gates to hostinger anyway.
- Do NOT call GitOps reapply / kubeconfig rewrite / cluster re-register from the
  new wrapper.
- Do NOT create a PR. Do NOT commit to `main`. Do NOT use `--no-verify` or
  `ALLOW_MAIN_PUSH=1`. Commit to the current release branch only.
- Do NOT touch any shopping-cart-* repos or `scripts/lib/acg/` (subtree).
- Update `memory-bank/activeContext.md` and `memory-bank/progress.md` after the
  code commit (separate commit is fine).

## Prevention (out of scope — note only, do NOT implement here)

A follow-up could make `make status` self-diagnose the all-530 / argocd-refused
pattern and point the user at `make refresh-edge`, and/or add launchd
`KeepAlive` to the tunnel plist (self-heals a crash, though not a deliberate
`down`/provider-switch unload). Keep both out of this change.
