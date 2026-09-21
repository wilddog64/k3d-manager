# `bin/rotate-ghcr-pat` cannot fix the hub, accepts a PAT that cannot pull, and puts the PAT in argv

**Filed:** 2026-09-21
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Medium — the tool an operator would reach for during a GHCR outage silently does not
touch the affected cluster, and leaks credentials into the process table.
**Status:** Open

## Context

Found while walking the operator restore for
`docs/bugs/2026-09-21-ghcr-pat-validated-for-auth-not-packages-scope.md`. `bin/rotate-ghcr-pat` is the
obvious tool to reach for — the plugin's own error message recommends it:

```
_err "[acg-up] GHCR_PAT not set and no valid PAT in Vault — set GHCR_PAT env var or run: pbpaste | bin/rotate-ghcr-pat"
```

It is the wrong tool for a hub outage, in three independent ways.

## Defect 1 — hardcoded `ubuntu-k3s` context, so it cannot fix the hub

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="${SHOPPING_CART_ORG}" \
  --docker-password="${TOKEN}" \
  --context ubuntu-k3s \
  -n "$ns" ...
```

`--context ubuntu-k3s` is hardcoded in the propagation loop. Running this during a **hub**
`ImagePullBackOff` reports `✅ namespace: shopping-cart-apps` three times while changing nothing on
the hub. The success output is actively misleading.

This is a **recurrence** of an already-filed defect —
`docs/bugs/2026-06-14-bugfix-ghcr-pull-secret-hardcoded-context.md` — in a different file. The fix
must take the context from the provider resolution (`_acg_provider_context` /
`_shopping_cart_resolve_app_context`) or an explicit flag, never a literal.

Related: on the hub, `ghcr-pull-secret` is **ESO-managed** from Vault `secret/github/pat`. A
`kubectl create secret` there would be reverted on the next reconcile anyway, so the correct hub path
is *write Vault, then force-sync the ExternalSecret* — not a direct secret write.

## Defect 2 — validates authentication, not package-pull

```bash
_pat_http=$(curl -s -o /dev/null -w "%{http_code}" -u "${SHOPPING_CART_ORG}:${TOKEN}" \
  "https://api.github.com/user" 2>/dev/null || true)
if [[ "$_pat_http" == "200" ]]; then
  echo "Using PAT from Vault..."
```

Identical to the defect just fixed in `scripts/plugins/shopping_cart.sh`: `GET /user` returns 200 for
any token that authenticates and never checks `read:packages`, the only scope GHCR enforces. This
tool will accept a scope-less PAT, **store it to Vault**, push it to seven GitHub repos as
`PACKAGES_TOKEN`, and write it into three namespaces — all reporting success.

Use the helper added in `cb428d09`: `_shopping_cart_ghcr_pat_can_pull`, a real GHCR token exchange
plus a pull-scoped `tags/list` call. Never persist a credential that has not passed it.

## Defect 3 — PAT and Vault token in argv

Three violations of the CLAUDE.md rule that secrets must never appear in script arguments or in
`kubectl` command strings that reach logs:

```bash
curl -s -u "${SHOPPING_CART_ORG}:${TOKEN}" "https://api.github.com/user"
curl -s -X POST -H "X-Vault-Token: ${_vault_root_token}" -d "{\"data\": {\"token\": \"${TOKEN}\"}}" ...
kubectl create secret docker-registry ... --docker-password="${TOKEN}" ...
```

All three are visible in the process table. Use `--netrc-file` for the GitHub probe, a `0600` header
file plus `--data-binary @-` for Vault (see `_shopping_cart_store_ghcr_pat_in_vault`), and
`kubectl apply -f -` from a generated manifest on stdin instead of `--docker-password`.

The `-d "{\"data\": {\"token\": \"${TOKEN}\"}}"` form also produces invalid JSON when the PAT contains
a quote or backslash — use `jq -n --arg`.

## Interim mitigation already in place

`bin/restore-hub-ghcr-pat` was added for the hub path: stdin-only PAT, probe-before-write, explicit
`HUB_CONTEXT` (default `k3d-k3d-cluster`, not hardcoded), Vault write via the hardened helper, ESO
force-sync, then rollout restart. It does **not** replace `rotate-ghcr-pat`, which still owns the
seven-repo `PACKAGES_TOKEN` rotation and the ubuntu-k3s path.

## Definition of Done

- [ ] Cluster context resolved, never a hardcoded `ubuntu-k3s`
- [ ] PAT gated on `_shopping_cart_ghcr_pat_can_pull` before any store or push
- [ ] No PAT or Vault token in argv, including `--docker-password`
- [ ] Vault body built with `jq -n --arg`
- [ ] ESO-managed clusters get a Vault write + force-sync, not a direct `kubectl create secret`
- [ ] BATS covers the context resolution and the refuse-on-unpullable-PAT path
- [ ] Consider consolidating with `bin/restore-hub-ghcr-pat` rather than keeping two tools

## What NOT to Do

- Do NOT hardcode a kube context in a tool that runs against more than one cluster.
- Do NOT treat `GET /user` 200 as evidence a PAT can pull from GHCR.
- Do NOT `kubectl create secret` a credential on a cluster where ESO owns it — it will be reverted.
- Do NOT print success per namespace without confirming the target cluster was the intended one.
