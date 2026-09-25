# The ArgoCD browser listener is never restarted when only its wrapper changes

**Filed:** 2026-09-24
**Status:** FIXED — `bin/cluster-up` guard + `scripts/tests/bin/cluster_up.bats`
**Branch:** `k3d-manager-v1.37.0`
**Follow-up to:** `2026-09-17-argocd-browser-tls-path-unification.md` (landed in `e259c718`, v1.35.0)

## Symptom

`make up CLUSTER_PROVIDER=k3s-aws` provisioned the sandbox cluster successfully — three nodes
`Ready`, `ubuntu-k3s` merged into the kubeconfig, `/readyz` answering `ok` — then aborted at
**Step 4c/12**, so Steps 5–14 (argocd-manager SA, app-cluster registration, data layer,
Keycloak + LDAP identity stack, ClusterSecretStore, ACG observability) never ran:

```
ERROR: [argocd] Argo CD did not become reachable on argocd.shopping-cart.local:443 within 30s
[argocd-browser] starting HTTPS listener: 127.0.0.1:443 -> 127.0.0.1:8080
socat E SSL_CTX_use_certificate_file(): error:80000002:system library::No such file or directory
[argocd-browser] listener exited before healthz became reachable — restarting
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

The cert file socat could not find **did exist**, with all four files present and issued
seconds earlier:

```
~/.local/share/k3d-manager/k3s-aws/argocd-browser-https-tls/
  ca.crt  fullchain.crt  tls.crt  tls.key     (all Sep 24 19:44, mode 0600)
```

## Root cause

The listener daemon process was **20 days old**:

```
PID   STARTED                    ELAPSED
29808 Fri Sep  4 08:41:23 2026   20-11:04:54   /bin/bash .../bin/argocd-browser-https.sh
```

`e259c718` (the TLS path unification, v1.35.0) moved the cert directory from the legacy flat
path to the provider-scoped one. This run correctly rewrote the wrapper at 19:44 with the new
scoped paths. But the wrapper text the running `bash` had already read into memory still named
the **legacy flat** dir — `~/.local/share/k3d-manager/argocd-browser-https-tls`, which is empty
(dir dated Sep 20). Hence "no such file" on a cert that exists.

Nothing restarted it, because the plist-unchanged short-circuit compared **only the plist**:

```bash
if [[ -f "${_argocd_browser_plist}" ]] && diff -q "${_argocd_browser_plist_tmp}" "${_argocd_browser_plist}" >/dev/null 2>&1; then
  _info "[acg-up] ArgoCD browser HTTPS listener LaunchDaemon unchanged — skipping reinstall"
```

The plist only names the wrapper *path*, never its contents, so it stays byte-identical across
any wrapper rewrite. The guard therefore skipped the `launchctl bootout` / `bootstrap` pair that
is the only thing that makes a rewritten wrapper take effect. **A rewritten wrapper was
unobservable to the guard that decides whether to restart the thing running it.**

This was latent from `e259c718` until now for a specific reason: the v1.35.0 spec said
"do NOT write a migration that moves or copies the existing flat cert material" and "do NOT
touch a live listener or launchd job." Both were right for that change's scope, and both mean
the long-running daemon was left bound to the old path with nothing scheduled to rebind it.

## Fix

`bin/cluster-up` now hashes the wrapper either side of the rewrite and treats a content change
as a reason to reinstall, independent of the plist:

```bash
_argocd_browser_wrapper_before=""
if [[ -f "${_argocd_browser_wrapper}" ]]; then
  _argocd_browser_wrapper_before="$(shasum -a 256 "${_argocd_browser_wrapper}" | awk '{print $1}')"
fi
_argocd_write_browser_https_wrapper ...
_argocd_browser_wrapper_changed=0
if [[ "$(shasum -a 256 "${_argocd_browser_wrapper}" | awk '{print $1}')" != "${_argocd_browser_wrapper_before}" ]]; then
  _argocd_browser_wrapper_changed=1
  _info "[acg-up] ArgoCD browser HTTPS wrapper changed — forcing a listener restart so the new paths take effect"
fi
```

and the guard gains one condition:

```bash
if [[ -f "${_argocd_browser_plist}" ]] && [[ "${_argocd_browser_wrapper_changed}" -eq 0 ]] && diff -q ...
```

Unchanged wrapper plus unchanged plist still short-circuits, so the idempotent path keeps its
behaviour. Only a genuine wrapper rewrite now forces the bootout/bootstrap.

## Recovery for an already-stale daemon

The fix prevents recurrence; it does not restart a daemon already running old text. That needs
one operator command (`launchctl kickstart` is not in `/etc/sudoers.d/k3d-manager`, and
restarting a system LaunchDaemon needs a TTY for the sudo prompt):

```
sudo launchctl kickstart -k system/com.k3d-manager.argocd-browser-https
```

Confirmed recovery: pid 29808 replaced by 59280, `healthz` returning 200, and the resumed
`make up` cleared Step 4c and reached Step 10/12.

## Test

`scripts/tests/bin/cluster_up.bats` — "acg-up restarts the argocd browser listener when only
the wrapper changed" asserts the three-part ordering (snapshot → write → compare) and the
compound guard. Mutation-proven: it fails against `git show HEAD:bin/cluster-up` and passes on
the patched tree.

## Lesson

A cached-state guard must compare **everything that determines the running behaviour**, not
just the file it happens to write. The plist was a proxy for "is the listener current," and it
was a false proxy the moment the wrapper became the thing that changed. This is the same shape
as the name-enumerated stub list that bit the Tier 2 tests three times this release: an
enumeration that silently stops covering what it is supposed to represent.
