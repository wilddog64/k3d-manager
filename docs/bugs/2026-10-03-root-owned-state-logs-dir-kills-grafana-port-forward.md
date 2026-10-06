# Bug: a root-owned `~/.local/share/k3d-manager/logs` stops the Grafana port-forward agent

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude (found during the hub-loss recovery)
**Status:** FIXED — Codex, verified by Claude 2026-10-04: both `argocd.sh` defaults removed; `cluster-up` stops with the exact `chown` before any sudo step. 6 new tests; both mutations red. The creator of the 744 folder is still unconfirmed; the preflight makes a recurrence loud. Live state has no root-owned folders today, so the next `make up` is not blocked.
**Severity:** Medium. Local Grafana (`localhost:3001`) stays down after a rebuild, and nothing reports why.

## Evidence (2026-10-03, about 09:12)

- **The folder is owned by root:**
  - `ls -ld ~/.local/share/k3d-manager/logs` gives `drwxr--r-- root staff`, created 07:34 today;
  - the parent `~/.local/share/k3d-manager` is `cliang staff`.
- **The user cannot read it:** a non-root `ls` of the folder returns `Permission denied`.
- **It holds the browser-listener logs:** the names visible inside are `keycloak-browser-http.log`, `argocd-browser-https.log` and `frontend-browser-http.log`. Those are the logs of the three root LaunchDaemons that `bin/cluster-up` installs through `_run_command --interactive-sudo`.
- **The Grafana agent cannot start:**
  - `com.k3d-manager.grafana-port-forward`'s plist sends `StandardOutPath` / `StandardErrorPath` to `.../logs/grafana-pf.log`, and its wrapper appends to the same file;
  - after `launchctl kickstart -k`, launchd reports exit **78** and no `kubectl port-forward` child starts;
  - `localhost:3001` refuses connections, while the in-cluster Grafana `/api/health` is `ok`.
- **The forward had been dead since the hub loss:** the old wrapper process, alive since Sep 29, had no live child when the hub came back.

## Hypothesis (to confirm)

1. `bin/cluster-down` removed the user-owned logs folder when it deleted the hub; it "removes local launchd agents and their state".
2. The 07:34 `make up` then bootstrapped root LaunchDaemons. Their log paths were under that folder, so **launchd, running as root, recreated the missing folder as root**.

To confirm:
- read the `StandardOutPath` values in the three daemon plist templates in `bin/cluster-up` (around lines 599, 707 and 1371), and how `_ACG_STATE_DIR` / the log variables resolve for a `k3s-aws` run;
- check whether `cluster-down` removes `~/.local/share/k3d-manager/logs`.

## Fix direction (brief after confirming)

- **Create the folder as the user first.** Before any `launchctl bootstrap system ...`, make every log folder a root daemon writes into with `mkdir -p` as the user. launchd then creates only the *files* as root, inside a user-owned folder.
- **Repair the existing state.** If a log folder under `~/.local/share/k3d-manager` is root-owned, `cluster-up` should say so and give the exact `sudo chown` command; it must not run sudo silently.
- **The Grafana wrapper must not die silently** when its log cannot be opened. Make that a loud, visible failure, for example a `make status` check for a loaded-but-exited port-forward agent.

## Operator workaround (now)

```
sudo chown -R cliang:staff ~/.local/share/k3d-manager/logs
```
```
launchctl kickstart -k gui/$(id -u)/com.k3d-manager.grafana-port-forward
```

## Investigation update (2026-10-03, about 17:00, Claude, read-only)

- **The flat-state migration is not the cause.** `_acg_migrate_flat_state` moves `${base}/logs`
  only when the provider's scoped folder is missing. `k3s-hostinger/logs` is dated Sep 29 and was
  not moved.
- **What happened at 07:34:** at 07:34 the `k3s-hostinger/` folder and its `run/` were touched,
  and root's `k3s-hostinger/logs/argocd-browser-https.log` (357 MB) stopped growing. The root-owned
  top-level `logs/` folder was created at the same minute. From 08:06 to 08:38, root daemons wrote
  `keycloak-`, `frontend-` and `argocd-browser` logs into it.
- **Confirmed defect: the ArgoCD browser log falls back to the shared folder.**
  `scripts/plugins/argocd.sh:83` sets the default
  `ARGOCD_BROWSER_LISTENER_LOG:=${HOME}/.local/share/k3d-manager/logs/argocd-browser-https.log`.
  `bin/cluster-up` sources `argocd.sh` early, so its own fallback
  `${ARGOCD_BROWSER_LISTENER_LOG:-${_ACG_STATE_DIR}/logs/...}` (`:673`) is dead code. The **root**
  ArgoCD browser daemon therefore logs into the shared top-level `logs/` folder. That is the same
  folder the **user** Grafana agent writes `grafana-pf.log` into.
- **Still unexplained:** the folder mode is `drwxr--r--` (744), not the user's umask 755. The
  `mkdir -p` at `bin/cluster-up:681`, which runs as the user, would have made it user-owned. So
  something running as root created the folder first. No `sudo mkdir` of a log path exists in
  `bin/` or `scripts/`. The remaining candidate is launchd itself, opening `StandardOutPath` for a
  root daemon whose folder was missing.
- **Fix direction, refined:**
  1. Remove the `argocd.sh:83` default, or point it at a per-provider folder, so root daemons
     never share a log folder with user agents.
  2. Keep the `bin/hub-restore` root-owned preflight. It already reports this case with the
     exact `chown`.

## Fix spec (Claude, 2026-10-04)

Two changes. The first stops the root ArgoCD browser daemon from logging into the shared folder.
The second makes `cluster-up` stop, loudly, before it installs anything when a root-owned folder
already sits in the state tree. It never runs sudo to repair it.

### File 1 — `scripts/plugins/argocd.sh`

Delete these two lines (currently :82 and :83):

```bash
: "${ARGOCD_BROWSER_LISTENER_WRAPPER:=${HOME}/.local/share/k3d-manager/bin/argocd-browser-https.sh}"
: "${ARGOCD_BROWSER_LISTENER_LOG:=${HOME}/.local/share/k3d-manager/logs/argocd-browser-https.log}"
```

Nothing inside `argocd.sh` reads either variable. Every consumer already has a per-provider
fallback that these defaults shadow: `bin/cluster-up:690/692`, `bin/cluster-refresh:510/511`,
`bin/cluster-down:230` and `scripts/lib/providers/k3s-hostinger.sh:581/582`. Do not edit those.

### File 2 — `bin/cluster-up`

Insert this block directly after the line
`_dry_guard "create local state directories" mkdir -p "${_ACG_STATE_DIR}/bin" "${_ACG_STATE_DIR}/run" "${_ACG_STATE_DIR}/logs"`
(currently :100). It is the same check `bin/hub-restore:48-58` already runs, with the
`[acg-up]` prefix:

```bash
_acg_state_root="${_ACG_STATE_BASE:-${HOME}/.local/share/k3d-manager}"
_acg_root_owned_dirs="$(find "${_acg_state_root}" -maxdepth 3 -type d -user root ! -name '*.lock' 2>/dev/null || true)"
if [[ -n "${_acg_root_owned_dirs}" ]]; then
  printf 'ERROR: [acg-up] root-owned state folders found; user launchd agents cannot write their logs there:\n' >&2
  while IFS= read -r _acg_root_dir; do
    [[ -n "${_acg_root_dir}" ]] || continue
    printf 'ERROR: %s\n' "${_acg_root_dir}" >&2
    printf 'ERROR: sudo chown -R "%s":staff %s\n' "$(id -un)" "${_acg_root_dir}" >&2
  done <<< "${_acg_root_owned_dirs}"
  exit 2
fi
```

It must sit before the first `_run_command --interactive-sudo` in the file (currently :708).

### File 3 — `scripts/tests/bin/cluster_up.bats` (append) and a new `scripts/tests/plugins/argocd_browser_listener_defaults.bats`

1. `argocd_browser_listener_defaults.bats`: `argocd.sh` contains neither
   `ARGOCD_BROWSER_LISTENER_LOG:=` nor `ARGOCD_BROWSER_LISTENER_WRAPPER:=` (use `run grep -F` and
   assert `status -eq 1`, never a bare `! grep`).
2. Same file: `bin/cluster-up` still contains the fallback
   `${ARGOCD_BROWSER_LISTENER_LOG:-${_ACG_STATE_DIR}/logs/argocd-browser-https.log}`.
3. `cluster_up.bats`: the line number of `-user root` in `bin/cluster-up` is lower than the line
   number of the first `--interactive-sudo`, and higher than the `create local state directories`
   line.
4. `cluster_up.bats`: functional. Extract the block (from `_acg_state_root=` through its closing
   `fi`) with `sed -n`, run it in `bash` with `_ACG_STATE_BASE` set to a `$BATS_TEST_TMPDIR`
   folder that holds no root-owned dirs, and assert exit 0 with no output. Root ownership cannot
   be faked without sudo, so for the failing case put a stub `find` on `PATH` that prints
   `$BATS_TEST_TMPDIR/state/logs`, and assert exit 2, `root-owned state folders found` and
   `sudo chown -R` in the output.

## Rules

- Modify only Files 1–3. Do not touch `scripts/lib/foundation/`, `bin/hub-restore`,
  `bin/cluster-refresh`, `bin/cluster-down` or `scripts/lib/providers/`.
- Do not commit or push; `.git` writes are denied in your sandbox. Leave changes unstaged.
- Run and paste: `shellcheck bin/cluster-up scripts/plugins/argocd.sh` (no new warnings: compare the
  count against `git show HEAD:<file> | shellcheck -`),
  `bats scripts/tests/bin/cluster_up.bats scripts/tests/plugins/argocd_browser_listener_defaults.bats`,
  `bats scripts/tests/lib/bats_negation_lint.bats`.
- Mutations (snapshot each file to `$TMPDIR` first, restore, prove with `cmp`):
  1. Put the `ARGOCD_BROWSER_LISTENER_LOG:=` line back → test 1 red.
  2. Delete the `exit 2` in the preflight → test 4 red.
- Do not run `make test`.

## Done when

Both defaults are gone, `cluster-up` stops with the exact `chown` command before any sudo step
when a root-owned folder exists, the new tests pass, both mutations go red and are restored.
