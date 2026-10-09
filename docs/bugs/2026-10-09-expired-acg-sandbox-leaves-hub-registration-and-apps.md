# An expired ACG sandbox leaves its hub ArgoCD registration and 10 apps behind

**Filed:** 2026-10-09, Claude (operator: "can we automatically clean up these after acg sandbox tear down")
**Branch:** k3d-manager-v1.42.0 (bug docs are exempt from the 5-plan cap)
**Status:** IMPLEMENTED — the reaper is on k3d-manager-v1.42.0. The operator installed it 2026-10-09: `com.k3d-manager.sandbox-reaper` is loaded, the first run exited 0, and PATH is set in the plist. The live reap waits for the next sandbox to expire. Release decision 2026-10-09: ships in v1.42.0 as **verify on next occurrence** (an ACG sandbox expires every 4–8h, so the next lapse is the test; simulating it would delete real hub registrations).
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

---

## Design — automatic cleanup after expiry (Claude, 2026-10-09; not yet specced for Codex)

### Drop the watcher path

`acg_watch` / `acg_watch_start` are never started by k3d-manager (`git grep` over `bin/`,
`scripts/plugins/`, `scripts/lib/providers/` and the `Makefile` finds no caller), and the launchd
wrapper only runs the Playwright extend; it never checks whether the sandbox is gone. Hooking a
deregister into it would hook a loop that does not run. No lib-foundation change is needed.

### Reaper (k3d-manager only)

A new `bin/k3dm-sandbox-reaper` run by a launchd agent `com.k3d-manager.sandbox-reaper`
(`StartInterval` 600, `RunAtLoad`), installed with `make install-sandbox-reaper` (operator).
Each run:

1. List hub registration Secrets in `cicd` for provider `k3s-aws`. None → exit 0.
2. For each, collect the Applications that target it by destination name **or** server (the same
   selector as `_k3s_aws_deregister_cluster`). Require at least one, and all `sync.status == Unknown`.
3. Keep a first-seen timestamp in `~/.local/share/k3d-manager/sandbox-reaper/<secret-uid>`.
   Keying on the Secret **UID** means a fresh `make up` that re-registers the same name starts a
   new clock. Remove the file as soon as any app is not `Unknown`.
4. Gone signal, only once the clock is ≥ 30 min:
   `aws cloudformation describe-stacks --stack-name "${_ACG_CF_STACK_NAME}"`.
   - stderr `does not exist` → gone
   - `InvalidClientTokenId` / `ExpiredToken` / `UnrecognizedClientException` → gone (ACG allows one
     sandbox; dead creds mean that sandbox ended)
   - anything else (network, throttling, success) → **not** gone; do nothing
5. Both hold → `bin/cleanup-stale-registration --cluster=<name> --confirm` (Secret first, then apps),
   and one log line per action in `~/.local/share/k3d-manager/logs/sandbox-reaper.log`.

**Rollout:** ship with `K3DM_SANDBOX_REAPER_DRYRUN=1` as the plist default, so it logs
"would deregister" only. Flip it after one real expiry shows the log line at the right time.

**Tests (BATS, stubbed `kubectl`/`aws`, RED first):** stack gone + Unknown ≥ 30 min → deregisters;
Unknown only (aws network error) → no action; Unknown < 30 min → no action; new Secret UID →
clock resets; one app `Synced` → clock file removed; never selects `ubuntu-k3s-app-cluster`.

**Open question for the operator:** this reaper deletes without asking. The alternative is a Hermes
sensor that proposes the same cleanup through the Slack approval flow (Hermes already runs every
5 min). Recommended: the reaper as above, because the two-signal gate makes a wrong delete
unlikely and the action is cheap to redo (`make argocd-registration`).

## Operator decision (2026-10-09)

> "expired-sandbox cleanup should happen automatically without approval. this typically happen
> during ACG sandbox up and down unless there a debug session initial by cloud agent. even that
> happen that's would be initial by me ... but notification should happen so I am aware of activities"

- **Automatic, no approval.** The Hermes-approval alternative is dropped.
- **No dry-run soak.** The two-signal gate is the safety. The plist ships live
  (`K3DM_SANDBOX_REAPER_DRYRUN=0`); the variable stays for manual runs.
- **Notify every action to Slack** through the relay Hermes already uses (Keychain item
  `k3dm-slack-webhook`, account `k3dm`). Debug sessions need no exemption: the operator starts them.

## Implementation spec (Codex)

**Repo / branch:** k3d-manager, `k3d-manager-v1.42.0` (already checked out; do not switch).

**Files (nothing else):**

| File | Change |
|---|---|
| `bin/k3dm-sandbox-reaper` | new, executable |
| `bin/k3dm-slack-notify` | new, executable |
| `scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl` | new |
| `Makefile` | `install-sandbox-reaper` / `uninstall-sandbox-reaper` targets + `.PHONY` |
| `scripts/tests/bin/k3dm_sandbox_reaper.bats` | new |
| `scripts/tests/bin/k3dm_slack_notify.bats` | new |
| `docs/howto/launchd-daemons.md` | row in "Daemons at a Glance" + a `## Sandbox reaper` section |
| `CHANGELOG.md` | `[Unreleased]` → `### Added`, one bullet |
| this doc | `**Status:**` → `IMPLEMENTED — reaper on k3d-manager-v1.42.0; operator install pending (make install-sandbox-reaper)` |

### 1. `bin/k3dm-slack-notify`

A small bash wrapper: reads the message from **stdin**, posts it with the existing
`scripts/lib/hermes/slack.py` `post_summary`, URL read from Keychain by the existing
`scripts/lib/hermes/sensors.py` `_keychain_secret("k3dm-slack-webhook")`. The URL must never be on
argv, in an env var exported to children, or in a log.

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
message="$(cat)"
[[ -n "${message}" ]] || { printf '%s\n' 'k3dm-slack-notify: empty message' >&2; exit 2; }
K3DM_NOTIFY_MESSAGE="${message}" PYTHONPATH="${repo_root}/scripts/lib" python3 - <<'PY'
import os, sys
from hermes.sensors import _keychain_secret
from hermes.slack import post_summary
sys.exit(0 if post_summary(_keychain_secret("k3dm-slack-webhook"), os.environ["K3DM_NOTIFY_MESSAGE"]) else 1)
PY
```

Before writing it, confirm `hermes.sensors` imports cleanly with only `PYTHONPATH=scripts/lib`
(no side effects at import). If it does not, copy the 10-line `_keychain_secret` body inline instead
and say so in the report.

BATS (`k3dm_slack_notify.bats`): stub `security` and `python3` is NOT stubbed; instead put a fake
`security` on `PATH` that prints `http://127.0.0.1:9/never` and assert: empty stdin → exit 2;
non-empty stdin → exit 1 (post fails to the closed port) and the URL never appears in the output.

### 2. `bin/k3dm-sandbox-reaper`

`#!/usr/bin/env bash`, `set -euo pipefail`, `export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"`.
**Always exits 0** after a run (launchd must not throttle it); errors are logged.

Configuration (env, with defaults):

| Variable | Default |
|---|---|
| `ARGOCD_HUB_CONTEXT` | `k3d-k3d-cluster` |
| `ARGOCD_NAMESPACE` | `cicd` |
| `K3DM_SANDBOX_REAPER_PROVIDER` | `k3s-aws` |
| `K3DM_SANDBOX_REAPER_GRACE` | `1800` (seconds) |
| `K3DM_SANDBOX_REAPER_DRYRUN` | `0` |
| `K3DM_SANDBOX_REAPER_STATE_DIR` | `${HOME}/.local/share/k3d-manager/sandbox-reaper` |
| `K3DM_SANDBOX_REAPER_LOG` | `${HOME}/.local/share/k3d-manager/logs/sandbox-reaper.log` |
| `K3DM_SANDBOX_REAPER_CLEANUP_BIN` | `<repo>/bin/cleanup-stale-registration` |
| `K3DM_SANDBOX_REAPER_NOTIFY_BIN` | `<repo>/bin/k3dm-slack-notify` |
| `K3DM_SANDBOX_REAPER_NOW` | unset → `date +%s` (tests set it) |
| `ACG_REGION` | `us-west-2` |
| `K3DM_SANDBOX_REAPER_STACK` | `k3d-manager-cluster` (matches lib `_ACG_CF_STACK_NAME`) |

Each run:

1. If `pgrep -f 'bin/cluster-up|bin/cluster-down'` finds a process, log `skip: lifecycle command running` and exit 0.
2. `kubectl --context "$ARGOCD_HUB_CONTEXT" -n "$ARGOCD_NAMESPACE" get secrets -l "argocd.argoproj.io/secret-type=cluster,k3d-manager/provider=${K3DM_SANDBOX_REAPER_PROVIDER}" -o json`.
   kubectl failure → log `skip: hub unreachable`, exit 0. No items → remove every file in the state dir, exit 0.
3. For each Secret: `uid`, cluster name (label `argocd.argoproj.io/cluster-name`), and decoded `.data.server`.
   Skip a Secret whose cluster name fails `^[A-Za-z0-9._-]+$`.
4. Applications: one `get applications -o json`; select with the **same predicate as
   `bin/cleanup-stale-registration`** (destination name, label `k3d-manager/cluster`, or server match).
   Healthy-sandbox condition = zero matching apps **or** any app whose `.status.sync.status != "Unknown"`
   → delete `${STATE_DIR}/${uid}` if present and continue.
5. All matching apps `Unknown`: if `${STATE_DIR}/${uid}` is missing, write `NOW` into it, log
   `first-seen <cluster> uid=<uid> apps=<n>`, continue. Otherwise `age = NOW - first_seen`;
   `age < GRACE` → continue.
6. Gone signal: `aws cloudformation describe-stacks --region "$ACG_REGION" --stack-name "$STACK"`,
   stdout to `/dev/null`, stderr captured.
   - rc 0 → **alive**, log `skip: stack exists`, continue.
   - stderr matches `does not exist` → gone (`stack-deleted`).
   - stderr matches `InvalidClientTokenId|ExpiredToken|UnrecognizedClientException` → gone (`credentials-dead`).
   - anything else (incl. `Unable to locate credentials`, network) → log `skip: aws inconclusive`, continue.
7. Gone and `DRYRUN=1` → log `would-deregister …` only, no notify.
8. Gone and `DRYRUN=0` → run `"$CLEANUP_BIN" --cluster="<cluster>" --confirm`, capturing output.
   - success → log `deregistered <cluster> reason=<reason> unknown_for=<age>s`, delete the state file,
     notify: `k3dm sandbox reaper: removed hub registration <cluster> and <n> apps — sandbox gone (<reason>), apps Unknown for <minutes> min.`
   - failure → log `cleanup failed <cluster> rc=<rc>`, keep the state file, notify:
     `k3dm sandbox reaper: FAILED to remove hub registration <cluster> (rc=<rc>); see sandbox-reaper.log`.
     To avoid a Slack message every 10 minutes, write `${STATE_DIR}/${uid}.failed-notified` and do not
     notify the failure again while it exists.
9. Notification failure (notify bin non-zero) is logged as `notify failed` and never changes the outcome.
10. Remove state files whose uid is not among the current Secrets.

Log line format: `[<ISO-8601 time>] <message>` (same as `bin/k3dm-node-health-watch`). Never log Secret data.

### 3. `scripts/etc/launchd/com.k3d-manager.sandbox-reaper.plist.tmpl`

Model on `com.k3d-manager.node-health-watch.plist.tmpl`, with:
`ProgramArguments` = `{{REPO_ROOT}}/bin/k3dm-sandbox-reaper`; `EnvironmentVariables`:
`KUBECONFIG={{HOME}}/.kube/config`, `K3DM_SANDBOX_REAPER_DRYRUN=0`; `StartInterval` 600;
`RunAtLoad` true; **no** `KeepAlive`; stdout/stderr → `{{HOME}}/.local/share/k3d-manager/logs/sandbox-reaper.log`.

### 4. Makefile

Copy the `install-node-health-watch` / `uninstall-node-health-watch` recipes (sed `{{REPO_ROOT}}` and
`{{HOME}}`, `launchctl bootout` then `bootstrap`), label `com.k3d-manager.sandbox-reaper`, with a
`##` help comment: `Install the expired-ACG-sandbox reaper (every 10 min; removes the hub registration once the sandbox is gone; Slack notice)`.
Add both targets to `.PHONY`. Do not run them.

### 5. BATS — `scripts/tests/bin/k3dm_sandbox_reaper.bats`

Stub `kubectl`, `aws`, `pgrep` and the cleanup/notify bins on `PATH` / via the env overrides (pattern:
`scripts/tests/bin/cleanup_stale_registration.bats`). Fixtures: one `k3s-aws` Secret
`cluster-ubuntu-k3s` (uid `u1`, cluster `ubuntu-k3s`), apps targeting it, plus a `ubuntu-hostinger`
app that must never count. Cases:

1. All apps Unknown, no state file → writes the clock file, no aws call, no cleanup.
2. Clock 1799 s old → no aws call, no cleanup.
3. Clock ≥ 1800 s, aws `does not exist` → cleanup called once with `--cluster=ubuntu-k3s --confirm`;
   notify called once with a message containing `removed hub registration ubuntu-k3s`; state file removed.
4. Same with aws `InvalidClientTokenId` → cleanup called; message contains `credentials-dead`.
5. aws rc 0 → no cleanup, no notify.
6. aws `Could not connect to the endpoint URL` → no cleanup, no notify.
7. One app `Synced` → no cleanup, existing state file removed.
8. Zero matching apps → no cleanup.
9. `DRYRUN=1` past grace with stack gone → no cleanup, no notify, log contains `would-deregister`.
10. Cleanup bin exits 1 → failure notified once; a second run notifies nothing more; state file kept.
11. Notify bin exits 1 → cleanup still recorded as `deregistered`, log contains `notify failed`, exit 0.
12. `pgrep` finds `bin/cluster-up` → no kubectl call at all.
13. kubectl label selector passed for Secrets contains `k3d-manager/provider=k3s-aws` (assert the stub's argv log).
14. Stale state file for an unknown uid is removed.

**RED:** every case must fail with the reaper absent (it is a new file — show the run against an empty stub).
**Gates (paste output):** `shellcheck bin/k3dm-sandbox-reaper bin/k3dm-slack-notify` (0 findings);
`bats scripts/tests/bin/k3dm_sandbox_reaper.bats scripts/tests/bin/k3dm_slack_notify.bats`;
`bats scripts/tests/bin/cleanup_stale_registration.bats` (unchanged, still green);
`plutil -lint` on the plist rendered to a temp file with the Makefile's sed; `make check-doc-links`.

### 6. Docs

`docs/howto/launchd-daemons.md`: table row
`| com.k3d-manager.sandbox-reaper | Removes the hub registration + apps of an expired ACG sandbox; Slack notice | ❌ (timer: 10m) | make install-sandbox-reaper | ~/.local/share/k3d-manager/logs/sandbox-reaper.log |`
and a `## Sandbox reaper (bin/k3dm-sandbox-reaper)` section: the two-signal gate, the 30-minute grace,
what is notified, how to dry-run by hand (`K3DM_SANDBOX_REAPER_DRYRUN=1 bin/k3dm-sandbox-reaper; tail ~/.local/share/k3d-manager/logs/sandbox-reaper.log`),
and how to redo a wrongful removal (`make argocd-registration`).

CHANGELOG `[Unreleased]` → `### Added` (create it above `### Fixed` if missing):
`**Expired ACG sandboxes are cleaned off the hub automatically.** A new launchd agent (`make install-sandbox-reaper`) checks every 10 minutes; once every app of a `k3s-aws` registration has been Unknown for 30 minutes and AWS confirms the sandbox is gone (stack deleted or credentials dead), it removes the registration and its Applications with `bin/cleanup-stale-registration` and posts a Slack notice. Covers expiries that `make down` never saw.`

### Commit

```
feat(acg): reap expired-sandbox hub registrations automatically with Slack notice

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
Push `git push origin k3d-manager-v1.42.0`; confirm `git ls-remote origin k3d-manager-v1.42.0` == `git rev-parse HEAD`.

### What NOT to do

No PR, no merge, no `main`, no `--no-verify`. Do not run `make install-sandbox-reaper`, any `make`
lifecycle target, `make -n`, `launchctl`, real `aws` or real `kubectl`. Do not read the Keychain or any
credential. Do not touch `scripts/lib/foundation/`, `scripts/lib/hermes/`, `bin/cleanup-stale-registration`,
or memory-bank.
