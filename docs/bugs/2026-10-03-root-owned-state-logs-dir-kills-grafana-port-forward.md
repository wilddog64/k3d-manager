# Bug: a root-owned `~/.local/share/k3d-manager/logs` stops the Grafana port-forward agent

**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude (found during the hub-loss recovery)
**Status:** OPEN — the root cause is a hypothesis; confirm it before writing the fix brief
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
